// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IRouter} from './interfaces/IRouter.sol';
import {IFlashLoanCallbackAaveV2} from './interfaces/IFlashLoanCallbackAaveV2.sol';
import {IAaveV2Provider} from './interfaces/aaveV2/IAaveV2Provider.sol';
import {ApproveHelper} from './libraries/ApproveHelper.sol';

/// @title Aave V2 flash loan callback
contract FlashLoanCallbackAaveV2 is IFlashLoanCallbackAaveV2 {
    using SafeERC20 for IERC20;
    using Address for address;

    address public immutable router;
    address public immutable aaveV2Provider;

    constructor(address router_, address aaveV2Provider_) {
        router = router_;
        aaveV2Provider = aaveV2Provider_;
    }

    /// @dev No need to check whether `initiator` is Router as it's certain when the below conditions are satisfied:
    ///      1. `to` in Router is Aave Pool, i.e, user signed a correct `to`
    ///      2. `_callback` in Router is set to this callback, i.e, user signed a correct `callback`
    ///      3. `msg.sender` of this callback is Aave Pool
    ///      4. Aave Pool contract is benign
    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address, // initiator
        bytes memory params
    ) external returns (bool) {
        address pool = IAaveV2Provider(aaveV2Provider).getLendingPool();

        if (msg.sender != pool) revert InvalidCaller();

        // Transfer assets to Router
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; ) {
            IERC20(assets[i]).safeTransfer(router, amounts[i]);

            unchecked {
                i++;
            }
        }

        // Call Router::execute
        router.functionCall(params, 'ERROR_AAVE_V2_FLASH_LOAN_CALLBACK');

        // Approve assets for pulling from Aave Pool
        for (uint256 i = 0; i < assetsLength; ) {
            uint256 amountOwing = amounts[i] + premiums[i];

            // Save gas by only the first user does approve. It's safe since this callback don't hold any asset
            ApproveHelper._approveMax(assets[i], pool, amountOwing);

            unchecked {
                i++;
            }
        }

        return true;
    }
}
