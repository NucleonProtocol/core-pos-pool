//SPDX-License-Identifier: BUSL-1.1
// Licensor:            X-Dao.
// Licensed Work:       NUCLEON 1.0

pragma solidity 0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./PoolContext.sol";
import "./VotePowerQueue.sol";

///
///  @title PoSPoolmini is a small Conflux POS pool cantract with the basic usages 
///  @dev This is Conflux PoS pool contract, the contract only be used by the bridge
///  @notice bridge use this contract to participate Conflux PoS.
///
contract PoSPoolmini is PoolContext, Ownable, Initializable {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  using VotePowerQueue for VotePowerQueue.InOutQueue;

  uint256 private CFX_COUNT_OF_ONE_VOTE = 1000;
  uint256 private CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  uint256 private ONE_DAY_BLOCK_COUNT = 2 * 3600 * 24;
  
  // ======================== Pool config =========================

  string public poolName;
  // wheter this poolContract registed in PoS
  bool public _poolRegisted;

  address bridge_contract;
  address bridge_withdraw;
  address bridge_storage;

  // lock period: 14 days + 1 day + 25520
  uint256 public _poolLockPeriod_in = ONE_DAY_BLOCK_COUNT * 14; 
  uint256 public _poolLockPeriod_out = ONE_DAY_BLOCK_COUNT * 1 + 25520; 

  // ======================== Struct definitions =========================

  /// @title PoolSummary
  /// @custom:field totalvotes Pool's total votes in use
  /// @custom:field locking Pool's locking votes
  /// @custom:field locked
  /// @custom:field unlocking votes
  /// @custom:field unlocked votes
  /// @custom:field unclaimedInterests,total interest of whole pools
  /// @custom:field claimedInterest

  struct PoolSummary {
    uint256 totalvotes;
    uint256 locking;
    uint256 locked;
    uint256 unlocking;
    uint256 unlocked;
    uint256 unclaimedInterests; 
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
  VotePowerQueue.InOutQueue private OutqueuesFast;

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

  // ======================== Events ==============================

  event IncreasePoSStake(address indexed user, uint256 votePower);

  event DecreasePoSStake(address indexed user, uint256 votePower);

  event WithdrawStake(address indexed user, uint256 votePower);

  event ClaimInterest(address indexed user, uint256 amount);

  event Setbridges(address indexed user, address bridgeaddr, address withdrawaddr, address storageAddr);

  event SetLockPeriod(address indexed user, uint256 inPeriod,uint256 outPeriod);

  event SetPoolName(address indexed user, string name);

  event SetCfxCountOfOneVote(address indexed user, uint256 count);

  event ReStake(address indexed user, uint64 votePower);

  event ClaimAllInterest(address indexed user, uint256 claimableInterest);
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
    require(msg.value == CFX_VALUE_OF_ONE_VOTE, "msg.value should be 1000 CFX");
    // update pool info
    _poolRegisted = true;
    _poolSummary.totalvotes += votePower;
    _poolSummary.locking += votePower;
    
    _stakingDeposit(msg.value);
    _posRegisterRegister(indentifier, votePower, blsPubKey, vrfPubKey, blsPubKeyProof);
  }

  // ======================== Contract methods , Only bridge can use =========================

  ///
  /// @notice Increase PoS vote power
  /// @param votePower The number of vote power to increase
  ///
  function increaseStake(uint64 votePower) public virtual payable onlyRegisted onlybridge{
    require(votePower > 0, "Minimal votePower is 1");
    require(msg.value == votePower * CFX_VALUE_OF_ONE_VOTE, "msg.value should be votePower * 1000 ether");
    collectStateFinishedVotes();
    require(Inqueues.queueLength()<1000,"TOO long Inqueues!");
    // update pool info
    _poolSummary.totalvotes += votePower;
    _poolSummary.locking += votePower;
    Inqueues.enqueue(VotePowerQueue.QueueNode(votePower, block.number + _poolLockPeriod_in));
    collectStateFinishedVotes();

    _stakingDeposit(msg.value);
    _posRegisterIncreaseStake(votePower);
    emit IncreasePoSStake(msg.sender, votePower);
  }

  ///
  /// @notice Decrease PoS vote power
  /// @param votePower The number of vote power to decrease
  ///
  function decreaseStake(uint64 votePower) public virtual onlyRegisted onlybridge{
    uint256 tempvotes;
    collectStateFinishedVotes();
    require(_poolSummary.totalvotes >= votePower, "Votes is not enough");
    require(Outqueues.queueLength()+OutqueuesFast.queueLength()<500,"TOO long queues!");
    // update pool info
    _poolSummary.totalvotes -= votePower;
    _poolSummary.unlocking += votePower;
    if(votePower<=_poolSummary.locked){
      _poolSummary.locked -= votePower;
      OutqueuesFast.enqueue(VotePowerQueue.QueueNode(votePower, block.number + _poolLockPeriod_out));
    }else {
      tempvotes = votePower - _poolSummary.locked;
      _poolSummary.locked = 0;
      _poolSummary.locking -= tempvotes;
      Outqueues.enqueue(VotePowerQueue.QueueNode(votePower, block.number + _poolLockPeriod_in + _poolLockPeriod_out));
    }
    
    _posRegisterRetire(votePower);
    emit DecreasePoSStake(msg.sender, votePower);
  }

  ///
  /// @notice Withdraw PoS vote power
  /// @dev  The number of vote power to withdraw
  ///
  function withdrawStake() public onlyRegisted onlybridge{
    collectStateFinishedVotes();
    uint256 temp_unlocked = _poolSummary.unlocked;
    _poolSummary.unlocked = 0;

    _stakingWithdraw(temp_unlocked * CFX_VALUE_OF_ONE_VOTE);
    address payable receiver = payable(bridge_withdraw);// withdraw CFX to bridgecoreaddr
    (bool success, ) = receiver.call{value: temp_unlocked * CFX_VALUE_OF_ONE_VOTE}("");
    require(success,"CFX Transfer Failed");
    emit WithdrawStake(msg.sender, temp_unlocked);
  }

  ///
  /// @notice Claim all interest in pool
  ///
  function claimAllInterest() public onlyRegisted onlybridge returns (uint256){
    collectStateFinishedVotes();
    uint claimableInterest = _selfBalance();
    require(claimableInterest > 0, "No claimable interest");
    _poolSummary.claimedInterest += claimableInterest;
    address payable receiver = payable(bridge_storage);
    (bool success, ) = receiver.call{value: claimableInterest}("");
    require(success,"CFX Transfer Failed");
    emit ClaimAllInterest(msg.sender, claimableInterest);
    return claimableInterest;
  }

  function temp_Interest() public view returns (uint256){
    return _selfBalance() ;
  }
  function collectStateFinishedVotes() public {
    _poolSummary.locked += Inqueues.collectEndedVotes();
    uint256 tempvotes = Outqueues.collectEndedVotes()+OutqueuesFast.collectEndedVotes();
    _poolSummary.unlocking -= tempvotes;
    _poolSummary.unlocked += tempvotes;
  }
  // ======================== Contract view methods interface use =========================
  /// 
  /// @notice Get  pool summary
  /// @return pool's summary
  ///
  function poolSummary() public view returns (PoolSummary memory) {
    PoolSummary memory summary = _poolSummary;
    summary.unclaimedInterests = _selfBalance();
    return summary;
  }

  function getInQueue() public view returns (VotePowerQueue.QueueNode[] memory) {
    return Inqueues.queueItems();
  }

  function getOutQueue() public view returns (VotePowerQueue.QueueNode[] memory) {
    return Outqueues.queueItems();
  }
  function getOutQueueFast() public view returns (VotePowerQueue.QueueNode[] memory) {
    return OutqueuesFast.queueItems();
  }

  // ======================== admin methods =====================

  ///
  /// @notice Enable admin to set the user share ratio
  /// @dev description
  ///
  function _setbridges(address bridgeaddr, address withdrawaddr, address storageaddr) public onlyOwner {
    bridge_contract = bridgeaddr;
    bridge_withdraw = withdrawaddr;
    bridge_storage = storageaddr;
    emit Setbridges(msg.sender, bridgeaddr, withdrawaddr, storageaddr);
  }

  /// 
  /// @notice Enable admin to set the lock and unlock period
  /// @dev Only admin can do this
  /// @param inPeriod The lock period in in block number, default is seven day's block count
  /// @param outPeriod The lock period out in block number, default is seven day's block count
  ///
  function _setLockPeriod(uint64 inPeriod,uint64 outPeriod) public onlyOwner {
    _poolLockPeriod_in = inPeriod;
    _poolLockPeriod_out = outPeriod;
    emit SetLockPeriod(msg.sender, inPeriod, outPeriod);
  }

  /// 
  /// @notice Enable admin to set the pool name
  ///
  function _setPoolName(string memory name) public onlyOwner {
    poolName = name;
    emit SetPoolName(msg.sender, poolName);
  }

  /// @param count Vote cfx count, unit is cfx
  function _setCfxCountOfOneVote(uint256 count) public onlyOwner {
    CFX_COUNT_OF_ONE_VOTE = count;
    CFX_VALUE_OF_ONE_VOTE = count * 1 ether;
    emit SetCfxCountOfOneVote(msg.sender, count);
  }

  // Used to bring account's retired votes back to work
  // reStake _poolSummary.available
  function _reStake(uint64 votePower) public onlyOwner {
    _posRegisterIncreaseStake(votePower);
    emit ReStake(msg.sender, votePower);
  }

  // ======================== contract base methods =====================
  fallback() external payable {}
  receive() external payable {}

}