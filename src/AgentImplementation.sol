// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IAgent} from './interfaces/IAgent.sol';
import {IParam} from './interfaces/IParam.sol';
import {IRouter} from './interfaces/IRouter.sol';
import {ApproveHelper} from './libraries/ApproveHelper.sol';

/// @title Router executes arbitrary logics
contract AgentImplementation is IAgent {
    using SafeERC20 for IERC20;
    using Address for address;
    using Address for address payable;

    address private constant _NATIVE = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 private constant _BPS_BASE = 10_000;
    uint256 private constant _SKIP = type(uint256).max;

    address public immutable router;

    address private _caller;

    constructor() {
        router = msg.sender;
    }

    modifier checkCaller() {
        if (_caller != msg.sender) revert InvalidCallback();
        else if (_caller != router) _caller = router;
        _;
    }

    function initialize() external {
        require(_caller == address(0));
        _caller = router;
    }

    /// @notice Execute logics and return tokens to user
    function execute(IParam.Logic[] calldata logics, address[] calldata tokensReturn) external payable checkCaller {
        _execute(logics, tokensReturn);
    }

    /// @notice Router executes logics and calls Spenders to consume user's approval, e.g. erc20 and debt tokens
    function _execute(IParam.Logic[] calldata logics, address[] calldata tokensReturn) private {
        // Execute each logic
        uint256 logicsLength = logics.length;
        for (uint256 i = 0; i < logicsLength; ) {
            address to = logics[i].to;
            bytes memory data = logics[i].data;
            IParam.Input[] memory inputs = logics[i].inputs;
            address callback = logics[i].callback;

            // Execute each input if need to modify the amount or do approve
            uint256 value;
            uint256 inputsLength = inputs.length;
            for (uint256 j = 0; j < inputsLength; ) {
                address token = inputs[j].token;
                uint256 amountBps = inputs[j].amountBps;

                // Calculate native or token amount
                // 1. if amountBps is skip: read amountOrOffset as amount
                // 2. if amountBps isn't skip: balance multiplied by amountBps as amount
                // 3. if amountBps isn't skip and amountOrOffset isn't skip:
                //    => replace the amount at offset equal to amountOrOffset with the calculated amount
                uint256 amount;
                if (amountBps == _SKIP) {
                    amount = inputs[j].amountOrOffset;
                } else {
                    if (amountBps == 0 || amountBps > _BPS_BASE) revert InvalidBps();
                    amount = (_getBalance(token) * amountBps) / _BPS_BASE;

                    // Skip if don't need to replace, e.g., most protocols set native amount in call value
                    uint256 offset = inputs[j].amountOrOffset;
                    if (offset != _SKIP) {
                        assembly {
                            let loc := add(add(data, 0x24), offset) // 0x24 = 0x20(data_length) + 0x4(sig)
                            mstore(loc, amount)
                        }
                    }
                }

                // Set native token value or approve ERC20 if `to` isn't the token self
                if (token == _NATIVE) {
                    value = amount;
                }

                unchecked {
                    j++;
                }
            }

            // Set _callback who should enter one-time execute
            if (callback != address(0)) _caller = callback;

            // Execute
            to.functionCallWithValue(data, value, 'ERROR_ROUTER_EXECUTE');

            // Revert if the previous call didn't enter execute
            if (_caller != router) revert UnresetCallback();

            unchecked {
                i++;
            }
        }

        // Push tokensReturn if any balance
        uint256 tokensReturnLength = tokensReturn.length;
        for (uint256 i = 0; i < tokensReturnLength; ) {
            address token = tokensReturn[i];
            uint256 balance = _getBalance(token);
            address user = IRouter(router).user();
            if (token == _NATIVE) {
                payable(user).sendValue(balance);
            } else {
                IERC20(token).safeTransfer(user, balance);
            }

            unchecked {
                i++;
            }
        }
    }

    function _getBalance(address token) private view returns (uint256 balance) {
        if (token == _NATIVE) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }
    }
}
