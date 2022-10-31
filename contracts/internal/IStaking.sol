// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStaking {
  function getStakingBalance(address user) external view returns (uint256);
  function deposit(uint256 amount) external payable;
  function withdraw(uint256 amount) external;
}