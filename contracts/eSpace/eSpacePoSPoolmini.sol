//SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../VotePowerQueue.sol";
import "./UnstakeQueueCFX.sol";
interface XCFXExchange{
    function addTokens(address _to, uint256 _value) external;
    function burnTokens(address account, uint256 amount) external;
    function balanceOf(address account) external view returns(uint256);
    function totalSupply() external view returns(uint256);
}

///
///  @title Exchange room
///
contract Exchangeroom is Ownable,Initializable {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  using VotePowerQueue for VotePowerQueue.InOutQueue;
  using UnstakeQueueCFX for UnstakeQueueCFX.Queue;

  uint256 private constant RATIO_BASE = 10000;
  uint256 private constant ONE_DAY_BLOCK_COUNT = 3600 * 24;
  uint256 private CFX_COUNT_OF_ONE_VOTE = 1000;
  uint256 private CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  
  
  // ======================== Pool config =========================
  // wheter this poolContract registed in PoS
  bool public birdgeAddrSetted;
  address private _bridgeAddress;

  // lock period: 14 days
  uint256 public _poolLockPeriod_slow = ONE_DAY_BLOCK_COUNT * 14;
  uint256 public _poolLockPeriod_fast = ONE_DAY_BLOCK_COUNT * 2;
  string public poolName; // = "UNCLEON HUB";
   // ======================== xCFX use ===================================
  address public owner_addr;
  address public admin_addr;

  address XCFX_address;
  address Storage_addr;

  address zero_addr=address(0x0000000000000000000000000000000000000000);

  // ======================== Struct definitions =========================

  /// @title ExchangeSummary
  /// @custom:field totalxcfxs
  /// @custom:field totalinterests
  /// @custom:field cfxstillinstore
  /// @custom:field remainedcfx
  struct ExchangeSummary {
    uint256 totalxcfxs;
    uint256 xcfxvalues;
    uint256 alloflockedvotes;
    uint256 xCFXincrease;
    uint256 unlockingCFX;
  }

  /// @title UserSummary
  /// @custom:field unlocking
  /// @custom:field unlocked
  struct UserSummary {
    uint256 unlocking;
    uint256 unlocked;
  }

  // ======================== Contract states =========================
  ExchangeSummary private _exchangeSummary;
  //PoolAccounts private _poolAccounts;
  mapping(address => UserSummary) private userSummaries;
  
  VotePowerQueue.InOutQueue private Inqueues;
  //VotePowerQueue.InOutQueue private Outqueues;
  // Unstake votes queue
  UnstakeQueueCFX.Queue public unstakeQueue;  //private--debug

  mapping(address => VotePowerQueue.InOutQueue) private userOutqueues;

  // ======================== Modifiers =========================
  modifier onlyRegisted() {
    require(birdgeAddrSetted, "Pool is not setted");
    _;
  }
  modifier onlyBridge() {
    //require(isContract(msg.sender),"bridge is contracts");
    require(msg.sender == _bridgeAddress, "Only bridge is allowed");
    _;
  }
  // ======================== Helpers =========================
  function _selfBalance() internal view virtual returns (uint256) {
    return address(this).balance;
  }

  function _blockNumber() internal view virtual returns (uint256) {
    return block.number;
  }
  // ======================== Events =========================

  event IncreasePoSStake(address indexed user, uint256 votePower);

  event DecreasePoSStake(address indexed user, uint256 votePower);

  event WithdrawStake(address indexed user, uint256 votePower);

  // ======================== Init methods =========================

  // call this method when depoly the 1967 proxy contract
  function initialize() public initializer {
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
    //poolUserShareRatio = 9000;
    owner_addr = msg.sender;
    _exchangeSummary.xcfxvalues = 1;
    _poolLockPeriod_slow = ONE_DAY_BLOCK_COUNT * 14;
    _poolLockPeriod_fast = ONE_DAY_BLOCK_COUNT * 2;
  }

  // ======================== Contract methods =========================

  function set_Settings(address _XCFX_addr,address _S_addr) external onlyOwner {
        XCFX_address = _XCFX_addr;
        Storage_addr = _S_addr;
    }  

  function get_Settings() external view returns(address,address){
    return (XCFX_address,Storage_addr);
    }

  //
  // @title CFX_exchange_estim
  // @dev _amount The amount of CFX to stake
  // return xCFX numbers can get
  function CFX_exchange_estim(uint256 _amount) public view returns(uint256){
    return _amount.div(_exchangeSummary.xcfxvalues);
    }

  function CFX_exchange_XCFX() external payable {
    require(msg.value>0 , 'must > 0');
    _exchangeSummary.totalxcfxs = XCFXExchange(XCFX_address).totalSupply();

    address payable receiver = payable(_bridgeAddress);
    receiver.transfer(msg.value);
    uint256 xcfx_exchange = CFX_exchange_estim(msg.value);
    XCFXExchange(XCFX_address).addTokens(msg.sender, xcfx_exchange);

    _exchangeSummary.totalxcfxs += xcfx_exchange;
    _exchangeSummary.xCFXincrease += xcfx_exchange;
    emit IncreasePoSStake(msg.sender, msg.value);
  }

  function XCFX_burn_estim(uint256 _amount) public view returns(uint256){
    return _amount.mul(_exchangeSummary.xcfxvalues);
    }

  function XCFX_burn(uint256 _amount) public virtual onlyRegisted returns(uint256){
    require(_amount<=XCFXExchange(XCFX_address).balanceOf(msg.sender),"Exceed your xCFX balance");
    _exchangeSummary.totalxcfxs = XCFXExchange(XCFX_address).totalSupply();
    uint256 _mode = 0;
    uint256 cfx_back = XCFX_burn_estim(_amount);
    if(cfx_back<=_exchangeSummary.alloflockedvotes.mul(1000 ether).div(2*_exchangeSummary.unlockingCFX)){
      _mode=1;
    }
    else {
      require(cfx_back<=_exchangeSummary.totalxcfxs.mul(1000 ether),"Exceed exchange limit");
    }
    _exchangeSummary.totalxcfxs -= _amount;
    _exchangeSummary.unlockingCFX += cfx_back;
    unstakeQueue.enqueue(UnstakeQueueCFX.Node(cfx_back));
    XCFXExchange(XCFX_address).burnTokens(msg.sender, _amount);

    //uint256 unstakeVotePowers;
    if(_mode == 1){
      userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(cfx_back, _blockNumber() + _poolLockPeriod_fast));
      //Outqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(_amount, _blockNumber() + _poolLockPeriod_fast));
      }
    else{
      userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(cfx_back, _blockNumber() + _poolLockPeriod_slow));
      //Outqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(_amount, _blockNumber() + _poolLockPeriod_slow));
    }
    
    userSummaries[msg.sender].unlocking += cfx_back;
    
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;

    emit DecreasePoSStake(msg.sender, _amount);
  }

  function getback_CFX(uint256 _amount) public virtual onlyRegisted {
     withdraw(_amount);
  }

  ///
  /// @notice Withdraw CFX
  /// @param _amount The amount of CFX to withdraw
  ///
  function withdraw(uint256 _amount) private onlyRegisted {
    require(address(this).balance>=_amount,"pool Unlocked CFX is not enough");
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;

    require(userSummaries[msg.sender].unlocked >= _amount, "your Unlocked CFX is not enough");
    
    address payable receiver = payable(msg.sender);
    receiver.transfer(_amount);
    emit WithdrawStake(msg.sender, _amount);
  }

  /// 
  /// @notice Get user's pool summary
  /// @param _user The address of user to query
  /// @return User's summary
  ///
  function userSummary(address _user) public view returns (UserSummary memory) {
    UserSummary memory summary = userSummaries[_user];
    uint256 temp_amount =userOutqueues[_user].sumEndedVotes();
    summary.unlocked += temp_amount;
    summary.unlocking -= temp_amount;
    return summary;
  }

  function Summary() public view returns (ExchangeSummary memory) {
    return _exchangeSummary;
  }

  function userOutQueue(address account) public view returns (VotePowerQueue.QueueNode[] memory) {
    return userOutqueues[account].queueItems();
  }

  // ======================== admin methods =====================

  /// 
  /// @notice Enable admin to set the lock and unlock period
  /// @dev Only admin can do this
  ///
  function setLockPeriod(uint64 _a,uint64 _b) public onlyOwner {
    _poolLockPeriod_slow = _a;
    _poolLockPeriod_fast = _b;
  }

  /// @param count Vote cfx count, unit is cfx
  function setCfxCountOfOneVote(uint256 count) public onlyOwner {
    CFX_COUNT_OF_ONE_VOTE = count;
    CFX_VALUE_OF_ONE_VOTE = count * 1 ether;
  }

  function setBridge(address bridgeAddress) public onlyOwner {
    _bridgeAddress = bridgeAddress;
    birdgeAddrSetted = true;
  }
  function getBridge() public view returns(address){
    return _bridgeAddress;
  }

  function setPoolName(string memory name) public onlyOwner {
    poolName = name;
  }

  // ======================== cross space bridge methods =====================
  
  function handlexCFXadd() public onlyBridge returns(uint256 ){
    uint256 temp_stake = _exchangeSummary.xCFXincrease ;
    require( temp_stake > 0, "xCFX have not increase");
     _exchangeSummary.xCFXincrease = 0;
     return temp_stake;
  }

  function handleUnstake() public onlyBridge returns (uint256) {
    uint256 temp_unstake = _exchangeSummary.unlockingCFX;
    require( temp_unstake > 0, "CFX have not decrease");
     _exchangeSummary.unlockingCFX = 0;
     return temp_unstake;
  }

  function unstakeLen() public view returns (uint256) {
    return unstakeQueue.end - unstakeQueue.start;
  }

  function firstUnstakeVotes() public view returns (uint256) {
    if (unstakeQueue.end == unstakeQueue.start) {
      return 0;
    }
    return unstakeQueue.items[unstakeQueue.start].CFXs;
  }

  function setxCFXValue(uint256 _cfxvalue) public onlyBridge returns (uint256){
    _exchangeSummary.xcfxvalues = _cfxvalue;
    // struct ExchangeSummary {
    // uint256 totalxcfxs;
    // uint256 xcfxvalues;
    // uint256 alloflockedvotes;
    // uint256 xCFXincrease;
    // uint256 unlockingCFX;
    // }
    return  _exchangeSummary.xcfxvalues;
  }

  function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
  }

  // receive interest
  function receiveInterest() public payable onlyBridge {}

  fallback() external payable {}
  receive() external payable {}

}