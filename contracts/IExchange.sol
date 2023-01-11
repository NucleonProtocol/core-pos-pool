//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./VotePowerQueue.sol";

interface IExchange {
  struct PoolSummary {
    uint256 totalvotes;
    uint256 locking;
    uint256 locked;
    uint256 unlocking;
    uint256 unlocked;
    uint256 totalInterest; // total interest of whole pools
    uint256 claimedInterest;
  }

  struct PoolShot {
    uint256 available;
    uint256 balance;
    uint256 blockNumber;
  } 

  // user functions
  function poolSummary() external view returns (PoolSummary memory);
  function increaseStake(uint64 votePower) external payable;
  function decreaseStake(uint64 votePower) external;
  function withdrawStake() external;
  function temp_Interest() external view returns (uint256);
  function claimAllInterest() external returns (uint256);
  function setxCFXValue(uint256 _cfxvalue) external  returns (uint256);
}