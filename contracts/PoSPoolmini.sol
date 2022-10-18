//SPDX-License-Identifier: BUSL-1.1
// Licensor:            X-Dao.
// Licensed Work:       NUCLEON 1.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./PoolContext.sol";
import "./VotePowerQueue.sol";
import "./PoolAPY.sol";

///
///  @title PoSPoolmini is a small Conflux POS pool cantract with the basic usages 
///  @dev This is Conflux PoS pool contract, the contract only be used by the bridge
///  @notice bridge use this contract to participate Conflux PoS.
///
contract PoSPoolmini is PoolContext, Ownable, Initializable {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  using VotePowerQueue for VotePowerQueue.InOutQueue;
  using PoolAPY for PoolAPY.ApyQueue;

  uint256 private CFX_COUNT_OF_ONE_VOTE = 1000;
  uint256 private CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  uint256 private ONE_DAY_BLOCK_COUNT = 2 * 3600 * 24;
  
  // ======================== Pool config =========================

  string public poolName;
  // wheter this poolContract registed in PoS
  bool public _poolRegisted;
  // ratio shared by user: 1-10000
  address bridge_contract;
  address bridge_withdraw;
  address bridge_storage;

  // lock period: 13 days + 1 day
  uint256 public _poolLockPeriod_in = ONE_DAY_BLOCK_COUNT * 14; 
  uint256 public _poolLockPeriod_out = ONE_DAY_BLOCK_COUNT * 1 + 12520; 

  // ======================== Struct definitions =========================

  /// @title PoolSummary
  /// @custom:field totalvotes Pool's total votes in use
  /// @custom:field locking Pool's locking votes
  /// @custom:field locked
  /// @custom:field unlocking votes
  /// @custom:field unlocked votes
  /// @custom:field totalInterest,total interest of whole pools
  /// @custom:field claimedInterest

  struct PoolSummary {
    uint256 totalvotes;
    uint256 locking;
    uint256 locked;
    uint256 unlocking;
    uint256 unlocked;
    uint256 totalInterest; 
    uint256 claimedInterest;
  }

  struct PoolShot {
    uint256 available;
    uint256 balance;
    uint256 blockNumber;
  } 

  // ======================== Contract states ====================

  PoolSummary private _poolSummary;
  VotePowerQueue.InOutQueue private Inqueues;
  VotePowerQueue.InOutQueue private Outqueues;

  PoolShot internal lastPoolShot;

  // ======================== Modifiers ==========================
  modifier onlyRegisted() {
    require(_poolRegisted, "Pool is not registed");
    _;
  }
  modifier onlybridge() {
    require(msg.sender==bridge_contract, "msg.sender is not bridge");
    _;
  }
  // ======================== Helpers ============================

  // used to update lastPoolShot after _poolSummary.available changed 
  function _updatePoolShot() private {
    lastPoolShot.available = _poolSummary.totalvotes;
    lastPoolShot.balance = _selfBalance();
    lastPoolShot.blockNumber = _blockNumber();
  }

  // ======================== Events ==============================

  event IncreasePoSStake(address indexed user, uint256 votePower);

  event DecreasePoSStake(address indexed user, uint256 votePower);

  event WithdrawStake(address indexed user, uint256 votePower);

  event ClaimInterest(address indexed user, uint256 amount);

  // ======================== Init methods =========================
  // call this method when depoly the 1967 proxy contract
  function initialize() public initializer {
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
    ONE_DAY_BLOCK_COUNT = 2 * 3600 * 24;
    _poolLockPeriod_in = ONE_DAY_BLOCK_COUNT * 14; 
    _poolLockPeriod_out = ONE_DAY_BLOCK_COUNT * 1 + 12520;
    poolName = "Nucleon Conflux Pos Pool 01";
  }
  
  ///
  /// @notice Regist the pool contract in PoS internal contract 
  /// @dev Only admin can do this
  /// @param indentifier The identifier of PoS node
  /// @param votePower The vote power when register
  /// @param blsPubKey The bls public key of PoS node
  /// @param vrfPubKey The vrf public key of PoS node
  /// @param blsPubKeyProof The bls public key proof of PoS node
  ///
  function register(
    bytes32 indentifier,
    uint64 votePower,
    bytes calldata blsPubKey,
    bytes calldata vrfPubKey,
    bytes[2] calldata blsPubKeyProof
  ) public virtual payable onlyOwner {
    require(!_poolRegisted, "Pool is already registed");
    require(votePower == 1, "votePower should be 1");
    require(msg.value == votePower * CFX_VALUE_OF_ONE_VOTE, "msg.value should be 1000 CFX");
    _stakingDeposit(msg.value);
    _posRegisterRegister(indentifier, votePower, blsPubKey, vrfPubKey, blsPubKeyProof);
    _poolRegisted = true;

    // update pool info
    _poolSummary.totalvotes += votePower;
    _poolSummary.locking += votePower;
    Inqueues.enqueue(VotePowerQueue.QueueNode(votePower, _blockNumber() + _poolLockPeriod_in));
    _poolSummary.locked += Inqueues.collectEndedVotes();
    _updatePoolShot();
  }

  // ======================== Contract methods , Only bridge can use =========================

  ///
  /// @notice Increase PoS vote power
  /// @param votePower The number of vote power to increase
  ///
  function increaseStake(uint64 votePower) public virtual payable onlyRegisted onlybridge{
    require(votePower > 0, "Minimal votePower is 1");
    require(msg.value == votePower * CFX_VALUE_OF_ONE_VOTE, "msg.value should be votePower * 1000 ether");
    _stakingDeposit(msg.value);
    _posRegisterIncreaseStake(votePower);
    emit IncreasePoSStake(msg.sender, votePower);
    uint256 tempvotes;
    // update pool info
    _poolSummary.totalvotes += votePower;
    _poolSummary.locking += votePower;
    Inqueues.enqueue(VotePowerQueue.QueueNode(votePower, _blockNumber() + _poolLockPeriod_in));
    tempvotes = Outqueues.collectEndedVotes();
    _poolSummary.unlocking -= tempvotes;
    _poolSummary.unlocked += tempvotes;
    _updatePoolShot();
  }

  ///
  /// @notice Decrease PoS vote power
  /// @param votePower The number of vote power to decrease
  ///
  function decreaseStake(uint64 votePower) public virtual onlyRegisted onlybridge{
    uint256 tempvotes;
    _poolSummary.locked += Inqueues.collectEndedVotes();
    require(_poolSummary.totalvotes >= votePower, "Votes is not enough");
    _posRegisterRetire(votePower);
    emit DecreasePoSStake(msg.sender, votePower);

    // update pool info
    _poolSummary.totalvotes -= votePower;
    _poolSummary.unlocking += votePower;
    if(votePower<=_poolSummary.locked){
      _poolSummary.locked -= votePower;
      Outqueues.enqueue(VotePowerQueue.QueueNode(votePower, _blockNumber() + _poolLockPeriod_out));
    }else {
      tempvotes = votePower - _poolSummary.locked;
      _poolSummary.locked = 0;
      _poolSummary.locking -= tempvotes;
      Outqueues.enqueue(VotePowerQueue.QueueNode(votePower, _blockNumber() + _poolLockPeriod_in + _poolLockPeriod_out));
    }
    tempvotes = Outqueues.collectEndedVotes();
    _poolSummary.unlocking -= tempvotes;
    _poolSummary.unlocked += tempvotes;
    _updatePoolShot();
  }

  ///
  /// @notice Withdraw PoS vote power
  /// @dev  The number of vote power to withdraw
  ///
  function withdrawStake() public onlyRegisted onlybridge{
    uint256 temp_out_cEndVotes = Outqueues.collectEndedVotes();
    _poolSummary.unlocking -= temp_out_cEndVotes;
    _poolSummary.unlocked += temp_out_cEndVotes;
    // require(_poolSummary.unlocked >= 0, "Unlocked is not enough");

    _stakingWithdraw(_poolSummary.unlocked * CFX_VALUE_OF_ONE_VOTE);
    address payable receiver = payable(bridge_withdraw);// withdraw CFX to bridgecoreaddr
    receiver.transfer(_poolSummary.unlocked * CFX_VALUE_OF_ONE_VOTE);
    _poolSummary.unlocked = 0;
    emit WithdrawStake(msg.sender, temp_out_cEndVotes);
  }

  ///
  /// @notice Claim all interest in pool
  ///
  function claimAllInterest() public onlyRegisted onlybridge returns (uint256){
    uint claimableInterest = _selfBalance();
    require(claimableInterest > 0, "No claimable interest");
    address payable receiver = payable(bridge_storage);
    receiver.transfer(claimableInterest);
    return claimableInterest;
  }

  function temp_Interest() public view onlyRegisted returns (uint256){
    return _selfBalance() ;
  }
  // ======================== Contract view methods interface use =========================
  /// 
  /// @notice Get  pool summary
  /// @return pool's summary
  ///
  function poolSummary() public view returns (PoolSummary memory) {
    PoolSummary memory summary = _poolSummary;
    uint256 _latestReward = _selfBalance().sub(lastPoolShot.balance);
    summary.totalInterest = summary.totalInterest.add(_latestReward);
    return summary;
  }

  function getInQueue() public view returns (VotePowerQueue.QueueNode[] memory) {
    return Inqueues.queueItems();
  }

  function getOutQueue() public view returns (VotePowerQueue.QueueNode[] memory) {
    return Outqueues.queueItems();
  }

  // ======================== admin methods =====================

  ///
  /// @notice Enable admin to set the user share ratio
  /// @dev description
  /// @param _withdraw  description
  /// @param _storage description
  ///
  function _set_bridges(address _bridge, address _withdraw, address _storage) public onlyOwner {
    bridge_contract = _bridge;
    bridge_withdraw = _withdraw;
    bridge_storage = _storage;
  }

  /// 
  /// @notice Enable admin to set the lock and unlock period
  /// @dev Only admin can do this
  /// @param _in The lock period in in block number, default is seven day's block count
  /// @param _out The lock period out in block number, default is seven day's block count
  ///
  function _setLockPeriod(uint64 _in,uint64 _out) public onlyOwner {
    _poolLockPeriod_in = _in;
    _poolLockPeriod_out = _out;
  }

  /// 
  /// @notice Enable admin to set the pool name
  ///
  function _setPoolName(string memory name) public onlyOwner {
    poolName = name;
  }

  /// @param count Vote cfx count, unit is cfx
  function _setCfxCountOfOneVote(uint256 count) public onlyOwner {
    CFX_COUNT_OF_ONE_VOTE = count;
    CFX_VALUE_OF_ONE_VOTE = count * 1 ether;
  }

  // Used to bring account's retired votes back to work
  // reStake _poolSummary.available
  function _reStake(uint64 votePower) public onlyOwner {
    _posRegisterIncreaseStake(votePower);
  }

  // ======================== contract base methods =====================
  fallback() external payable {}
  receive() external payable {}

}