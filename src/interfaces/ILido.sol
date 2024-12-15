// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ILido is IERC20 {
    function submit(address _referral) external payable returns (uint256);
}

interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

interface ILidoWithdrawalQueue {
    /// @notice output format struct for `_getWithdrawalStatus()` method
    struct WithdrawalRequestStatus {
        /// @notice stETH token amount that was locked on withdrawal queue for this request
        uint256 amountOfStETH;
        /// @notice amount of stETH shares locked on withdrawal queue for this request
        uint256 amountOfShares;
        /// @notice address that can claim or transfer this request
        address owner;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    function requestWithdrawals(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);
    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function getLastCheckpointIndex() external view returns (uint256);
    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds);
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
}
