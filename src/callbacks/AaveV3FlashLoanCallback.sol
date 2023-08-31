// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IAgent} from '../interfaces/IAgent.sol';
import {IParam} from '../interfaces/IParam.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import {IAaveV3FlashLoanCallback} from '../interfaces/callbacks/IAaveV3FlashLoanCallback.sol';
import {IAaveV3Provider} from '../interfaces/aaveV3/IAaveV3Provider.sol';
import {ApproveHelper} from '../libraries/ApproveHelper.sol';
import {FeeLogic} from '../libraries/FeeLogic.sol';
import {CallbackFeeBase} from './CallbackFeeBase.sol';

/// @title Aave V3 flash loan callback
/// @notice Invoked by Aave V3 pool to call the current user's agent
contract AaveV3FlashLoanCallback is IAaveV3FlashLoanCallback, CallbackFeeBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using FeeLogic for IParam.Fee;

    address public immutable router;
    address public immutable aaveV3Provider;
    bytes32 internal constant _META_DATA = bytes32(bytes('aave-v3:flash-loan'));

    constructor(address router_, address aaveV3Provider_, uint256 feeRate_) CallbackFeeBase(feeRate_, _META_DATA) {
        router = router_;
        aaveV3Provider = aaveV3Provider_;
    }

    /// @dev No need to check if `initiator` is the agent as it's certain when the below conditions are satisfied:
    ///      1. The `to` address used in agent is Aave Pool, i.e, the user signed a correct `to`
    ///      2. The callback address set in agent is this callback, i.e, the user signed a correct `callback`
    ///      3. The `msg.sender` of this callback is Aave Pool
    ///      4. The Aave pool is benign
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address, // initiator
        bytes calldata params
    ) external returns (bool) {
        if (msg.sender != IAaveV3Provider(aaveV3Provider).getPool()) revert InvalidCaller();
        uint256[] memory initBalances;
        IParam.Fee[] memory fees;
        {
            (, address agent) = IRouter(router).getCurrentUserAgent();

            // Transfer assets to the agent and record initial balances
            initBalances = new uint256[](assets.length);
            if (feeRate > 0 && IAgent(agent).isCharging()) {
                fees = new IParam.Fee[](assets.length);
            }
            for (uint256 i; i < assets.length; ) {
                address asset = assets[i];
                uint256 amount = amounts[i];
                if (fees.length > 0) {
                    fees[i] = FeeLogic.calculateFee(asset, amount, feeRate, metadata);
                }
                IERC20(asset).safeTransfer(agent, amount);
                initBalances[i] = IERC20(asset).balanceOf(address(this));

                unchecked {
                    ++i;
                }
            }

            agent.functionCall(
                abi.encodePacked(IAgent.executeByCallback.selector, params),
                'ERROR_AAVE_V3_FLASH_LOAN_CALLBACK'
            );
        }

        // Approve assets for pulling from Aave Pool
        {
            address pool = IAaveV3Provider(aaveV3Provider).getPool();
            address feeCollector = IRouter(router).feeCollector();
            for (uint256 i; i < assets.length; ) {
                address asset = assets[i];
                uint256 amountOwing = amounts[i] + premiums[i];
                if (fees.length > 0) {
                    fees[i].charge(feeCollector);
                }

                // Check balance is valid
                if (IERC20(asset).balanceOf(address(this)) != initBalances[i] + amountOwing)
                    revert InvalidBalance(asset);

                // Save gas by only the first user does approve. It's safe since this callback don't hold any asset
                ApproveHelper._approveMax(asset, pool, amountOwing);

                unchecked {
                    ++i;
                }
            }
        }

        return true;
    }
}
