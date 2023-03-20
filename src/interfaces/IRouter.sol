// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IParam} from './IParam.sol';

interface IRouter {
    event SignerAdded(address indexed signer, uint256 referral);

    event SignerRemoved(address indexed signer);

    error Reentrancy();

    error AgentCreated();

    error InvalidReferral(uint256 referral);

    error SignatureExpired(uint256 deadline);

    error InvalidSigner(address signer);

    error InvalidSignature();

    error LengthMismatch();

    function agentImplementation() external view returns (address);

    function signerReferrals(address signer) external view returns (uint256);

    function owner() external view returns (address);

    function user() external view returns (address);

    function domainSeparator() external view returns (bytes32);

    function getAgent() external view returns (address);

    function getAgent(address user) external view returns (address);

    function getUserAgent() external view returns (address, address);

    function calcAgent(address user) external view returns (address);

    function addSigner(address newSigner, uint256 referral) external;

    function removeSigner(address signer) external;

    function executeWithSignature(
        IParam.LogicBatch calldata logicBatch,
        address signer,
        bytes calldata signature,
        address[] calldata tokensReturn
    ) external payable;

    function execute(IParam.Logic[] calldata logics, address[] calldata tokensReturn) external payable;

    function feeDecoder(bytes4 sig) external view returns (address);

    function feeCollector() external view returns (address);

    function nativeFeeRate() external view returns (uint256);

    function newAgent() external returns (address payable);

    function newAgent(address user) external returns (address payable);
}
