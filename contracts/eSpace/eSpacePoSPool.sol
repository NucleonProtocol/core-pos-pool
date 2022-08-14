//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../VotePowerQueue.sol";
import "./iface_espace.sol";
import "./UnstakeQueue.sol";
import "./XETdistribute.sol";
import "./contractpoolerc20.sol";

// interface XCFXExchange{
//     function addTokens(address _to, uint256 _value) external;
//     function burnTokens(address account, uint256 amount) external;
//     function balanceOf(address account) external view returns(uint256);
//     function totalSupply() external view returns(uint256);
// }
// interface XVIPI{
//     function tokensOf(address account) external view returns (uint256[] memory _tokens);
//     function Maxlevelof(address account) external view returns (uint256 level);
// }
///
///  @title eSpace PoSPool
///
contract ESpacePoSPool is Ownable,Initializable {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  using VotePowerQueue for VotePowerQueue.InOutQueue;
  using UnstakeQueue for UnstakeQueue.Queue;

  uint256 private constant RATIO_BASE = 10000;
  uint256 private constant ONE_DAY_BLOCK_COUNT = 3600 * 24;
  uint256 private CFX_COUNT_OF_ONE_VOTE = 1000;
  uint256 private CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  
  
  // ======================== Pool config =========================
  // wheter this poolContract registed in PoS
  bool public birdgeAddrSetted;
  address private _bridgeAddress;
  // ratio shared by user: 1-10000
  uint256 public poolUserShareRatio = 9000;
  // lock period: 7 days + half hour
  uint256 public _poolLockPeriod = ONE_DAY_BLOCK_COUNT * 14;
  string public poolName; // = "eSpacePool";
  uint256 private _poolAPY = 0;

  // ======================== Contract states =========================
  // global pool accumulative reward for each cfx
  uint256 public accRewardPerCfx;  // start from 0

  PoolSummary private _poolSummary;
  mapping(address => UserSummary) private userSummaries;
  //mapping(address => VotePowerQueue.InOutQueue) private userInqueues;
  mapping(address => VotePowerQueue.InOutQueue) private userOutqueues;

  PoolShot internal lastPoolShot;
  mapping(address => UserShot) internal lastUserShots;
  
  EnumerableSet.AddressSet private stakers;
  // Unstake votes queue
  UnstakeQueue.Queue public unstakeQueue;  //private--debug

  // Currently withdrawable CFX
  //uint256 public withdrawableCfx;
  // Votes need to cross from eSpace to Core
  uint256 public crossingVotes;

  // ======================== XCFX use ===================================
  address public owner_addr;
  address public admin_addr;

  uint256 public total_minted;
  uint256 public total_minted_inpool;//total_minted >= total_minted_inpool
  uint256 public total_burned;
  uint256 public total_burned_inpool;//total_burned_inpool >= total_burned
  address XCFX_address;
  address XET_address;
  address XVIP_address;
  address Storage_room_addr;
  address XET_Distribute_addr;
  address zero_addr=address(0x0000000000000000000000000000000000000000);
  mapping(address => address) contract_erc20_addr;


  // ======================== Struct definitions =========================
  struct PoolSummary {
    uint256 available;  //available is XCFX SUM (1 ether XCFX === 1 e18)
    uint256 interest; // PoS pool current interest
    uint256 totalInterest; // total historical interest of whole pools
  }

  /// @title UserSummary
  /// @custom:field votes User's total votes
  /// @custom:field available User's avaliable votes
  /// @custom:field locked
  /// @custom:field unlocked
  /// @custom:field claimedInterest
  /// @custom:field currentInterest
  struct UserSummary {
    //uint256 votes;  // Total votes in PoS system, including locking, locked, unlocking, unlocked
    uint256 available; // XCFX SUM (1 ether XCFX === 1e18)
    uint256 unlocking;
    uint256 unlocked;
    uint256 claimedInterest; // total historical claimed interest
    uint256 currentInterest; // current claimable interest
  }

  struct PoolShot {
    uint256 available; // XCFX SUM (1 ether XCFX === 1)
    uint256 balance;
    uint256 blockNumber;
  } 

  struct UserShot {
    uint256 available; // XCFX SUM (1 ether XCFX === 1)
    uint256 accRewardPerCfx;
    uint256 blockNumber;
  }

  // ======================== Modifiers =========================
  modifier onlyRegisted() {
    require(birdgeAddrSetted, "Pool is not setted");
    _;
  }

  modifier onlyBridge() {
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

  function _userShareRatio(address _user) public view returns (uint256) {
    if (XVIP_address==owner_addr) return poolUserShareRatio;
    if (XVIPI(XVIP_address).Maxlevelof(_user)==1) return RATIO_BASE-((RATIO_BASE-poolUserShareRatio)*50/100);
    if (XVIPI(XVIP_address).Maxlevelof(_user)==2) return RATIO_BASE-((RATIO_BASE-poolUserShareRatio)*25/100);
    if (XVIPI(XVIP_address).Maxlevelof(_user)==3) return RATIO_BASE;
    return poolUserShareRatio;
  }

  function _calUserShare(uint256 reward, address _stakerAddress) private view returns (uint256) {
    return reward.mul(_userShareRatio(_stakerAddress)).div(RATIO_BASE);
  }

  function _userInputRatio(address _user) public view returns (uint256) {
    return 9000 + _userShareRatio(_user).div(10);
  }

  // used to update lastPoolShot after _poolSummary.available changed 
  function _updatePoolShot() private {
    lastPoolShot.available = _poolSummary.available;
    lastPoolShot.balance = _selfBalance();
    lastPoolShot.blockNumber = _blockNumber();
  }

  // used to update lastUserShot after userSummary.available and accRewardPerCfx changed
  function _updateUserShot(address _user) private {
    lastUserShots[_user].available = userSummaries[_user].available;
    lastUserShots[_user].accRewardPerCfx = accRewardPerCfx;
    lastUserShots[_user].blockNumber = _blockNumber();
  }

  // used to update accRewardPerCfx after _poolSummary.available changed or user claimed interest
  // depend on: lastPoolShot.available and lastPoolShot.balance
  function _updateAccRewardPerCfx() private {
    uint256 reward = _selfBalance() - lastPoolShot.balance;
    if (reward == 0 || lastPoolShot.available == 0) return;
    // update global accRewardPerCfx
    uint256 cfxCount = lastPoolShot.available.div(0.01 ether);//.mul(CFX_COUNT_OF_ONE_VOTE);
    accRewardPerCfx = accRewardPerCfx.add(reward.div(cfxCount));
    // update pool interest info
    _poolSummary.totalInterest = _poolSummary.totalInterest.add(reward);
  }

  // depend on: accRewardPerCfx and lastUserShot
  function _updateUserInterest(address _user) private {
    UserShot memory uShot = lastUserShots[_user];
    if (uShot.available == 0) return;
    uint256 latestInterest = accRewardPerCfx.sub(uShot.accRewardPerCfx).mul(uShot.available).div(0.01 ether); //.mul(CFX_COUNT_OF_ONE_VOTE)
    uint256 _userInterest = _calUserShare(latestInterest, _user);
    userSummaries[_user].currentInterest = userSummaries[_user].currentInterest.add(_userInterest);
    _poolSummary.interest = _poolSummary.interest.add(latestInterest.sub(_userInterest));
  }


  // ======================== Events =========================

  event IncreasePoSStake(address indexed user, uint256 votePower);

  event DecreasePoSStake(address indexed user, uint256 votePower);

  event WithdrawStake(address indexed user, uint256 votePower);

  event ClaimInterest(address indexed user, uint256 amount);

  //event RatioChanged(uint256 ratio);

  // ======================== Init methods =========================

  // call this method when depoly the 1967 proxy contract
  function initialize() public initializer {
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
    _poolLockPeriod = ONE_DAY_BLOCK_COUNT * 14;
    poolUserShareRatio = 9000;
    owner_addr = msg.sender;
    XVIP_address = msg.sender;
  }

  // ======================== Contract methods =========================

  //--------------------------------------------------------------------all new function for XCFX  ↓
  // modifier onlyOwner() {
  //       require(msg.sender == owner_addr, 'Must Owner');
  //       _;
  //   }
  modifier only_admin() {
        require(msg.sender == admin_addr, 'Must admin');
        _;
    }
  function set_admin(address _admin_addr) external onlyOwner {
        admin_addr=_admin_addr;
    } 
  function get_admin() external view returns(address){
    //require(_address==msg.sender,'1');
    return(admin_addr);
    }
  function set_Settings(address _XVIP_addr,address _XET_addr,address _XCFX_addr,address _S_addr,address _distr) external onlyOwner {
        XVIP_address = _XVIP_addr;
        XET_address = _XET_addr;
        XCFX_address = _XCFX_addr;
        Storage_room_addr = _S_addr;
        XET_Distribute_addr = _distr;
    }  

  function get_Settings() external view returns(address,address,address,address,address){
    //require(_address==msg.sender,'1');
    return (XCFX_address,XET_address,Storage_room_addr,XVIP_address,XET_Distribute_addr);
    }
  function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }
  //
  // @notice CFX_to_XCFX
  //
  function CFX_to_XCFX_estim(uint256 _amount, address _addr) public view returns(uint256,uint256){
    return (_amount.mul(_userInputRatio(_addr)).div(RATIO_BASE),
             XETdistribute(XET_Distribute_addr).estimate_in(_amount));//XCFX,XET
    }

  function CFX_to_XCFX() public payable {
    require(msg.value>0 , 'must > 0');
    address payable receiver = payable(_bridgeAddress);
    receiver.transfer(msg.value);
    total_minted += msg.value;
    XCFXExchange(XCFX_address).addTokens(msg.sender, msg.value.mul(_userInputRatio(msg.sender)).div(RATIO_BASE));
    XCFXExchange(XCFX_address).addTokens(Storage_room_addr, msg.value-msg.value.mul(_userInputRatio(msg.sender)).div(RATIO_BASE));
    
    //receiver_storge.transfer(msg.value-msg.value.mul(_userInputRatio(msg.sender)).div(RATIO_BASE));
    if(total_minted-total_minted_inpool>=1000 ether){
      uint256 votePower = (total_minted.sub(total_minted_inpool)).div(1000 ether);

      crossingVotes += votePower;

      total_minted_inpool += votePower*CFX_VALUE_OF_ONE_VOTE;
    }
    // uint256 temp_XET_num = ERC20(XET_address).balanceOf(address(this));
    // // if(temp_XET_num>200000 ether){
    // //   ERC20(XET_address).transfer(Storage_room_addr,temp_XET_num - 200000 ether);
    // // }
    // uint256 XET_num_out = msg.value.div(10**((200000 ether - temp_XET_num).div(10000 ether)));
    // if (temp_XET_num > XET_num_out) {
    //   ERC20(XET_address).transfer(msg.sender,XET_num_out);
    // }
    // else if(temp_XET_num > 0){
    //   ERC20(XET_address).transfer(msg.sender,temp_XET_num);
    // }
    ERC20(XET_address).transfer(msg.sender,XETdistribute(XET_Distribute_addr).estimate_in(msg.value));
    emit IncreasePoSStake(msg.sender, msg.value);
    //update user
    _updateAccRewardPerCfx();
    _updateUserInterest(msg.sender);
    _updateUserShot(msg.sender);

    //userSummaries update
    //userSummaries[msg.sender].available += msg.value;

    //update pool
    _poolSummary.available += msg.value;
    _updatePoolShot();

    stakers.add(msg.sender);
  }

  function XCFX_burn(uint256 _amount) public virtual onlyRegisted {
    require(_amount<=XCFXExchange(XCFX_address).balanceOf(msg.sender),"Exceed balance");
    XCFXExchange(XCFX_address).burnTokens(msg.sender, _amount);
    total_burned+=_amount;
    if(total_burned>total_burned_inpool){
      decreaseStake(uint64((total_burned.sub(total_burned_inpool)).div(1000 ether))+1);
      total_burned_inpool+=((total_burned.sub(total_burned_inpool)).div(1000 ether)+1).mul(1000 ether);
    }
    //userSummaries[msg.sender].available -= _amount;//XCFXExchange(XCFX_address).balanceOf(msg.sender);
    userSummaries[msg.sender].unlocking += _amount;
    userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(_amount, _blockNumber() + _poolLockPeriod));
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;

    emit DecreasePoSStake(msg.sender, _amount);

    //update user
    _updateAccRewardPerCfx();
    _updateUserInterest(msg.sender);
    _updateUserShot(msg.sender);

    _poolSummary.available -= _amount;
    _updatePoolShot();
  }  
  function getback_CFX(uint256 _amount) public virtual onlyRegisted {
     withdrawStake(_amount);
  }  

  function update_after_trans_by_outer_func(address _from,address _to) external virtual onlyRegisted {
    if(isContract(_to) && (contract_erc20_addr[_to] != zero_addr)){
      contractpool_erc20(contract_erc20_addr[_to]).start_cal(_to);
    }
    if(isContract(_from) && (contract_erc20_addr[_from] != zero_addr)){
      contractpool_erc20(contract_erc20_addr[_from]).start_cal(_from);
    }
    _updateAccRewardPerCfx();
    //_updateAPY();
    // update user interest
    _updateUserInterest(_from);
    _updateUserShot(_from);
    _updateUserInterest(_to);
    _updateUserShot(_to);
    userSummaries[_from].available = XCFXExchange(XCFX_address).balanceOf(_from);
    userSummaries[_to  ].available = XCFXExchange(XCFX_address).balanceOf(_to  );
    stakers.add(_to);
    if (userSummaries[_from].available == 0) {
      stakers.remove(_from);
    }
    _updatePoolShot();
  }

  function claimContractInterest(uint _amount,address _contract) public onlyRegisted only_admin{
    uint claimableInterest;
    uint temp_useless;
    (claimableInterest,temp_useless) = userInterest(_contract);
    require(claimableInterest >= _amount, "Interest not enough");
    require(isContract(_contract)==true,'Must be Contract');
    _updateAccRewardPerCfx();
    _updateUserInterest(_contract);
    //
    userSummaries[_contract].claimedInterest = userSummaries[_contract].claimedInterest.add(_amount);
    userSummaries[_contract].currentInterest = userSummaries[_contract].currentInterest.sub(_amount);
    // update userShot's accRewardPerCfx
    _updateUserShot(_contract);
    // send interest to user
    address payable receiver = payable(msg.sender);
    receiver.transfer(_amount);
    emit ClaimInterest(_contract, _amount);
    // update blockNumber and balance
    _updatePoolShot();
  }

  function claimAllContractInterest(address _contract) public onlyRegisted only_admin{
    uint claimableInterest;
    uint temp_useless;
    (claimableInterest,temp_useless) = userInterest(_contract);
    require(claimableInterest > 0, "No claimable interest");
    claimContractInterest(claimableInterest, _contract);
  }

  //--------------------------------------------------------------------all new function for XCFX  ↑

  ///
  /// @notice Increase PoS vote power
  /// @param votePower The number of vote power to increase
  ///
  // function increaseStake(uint64 votePower) public virtual payable onlyRegisted {
  //   require(votePower > 0, "Minimal votePower is 1");
  //   require(msg.value == votePower * CFX_VALUE_OF_ONE_VOTE, "msg.value should be votePower * 1000 ether");
    
  //   // transfer to bridge address
  //   address payable receiver = payable(_bridgeAddress);
  //   receiver.transfer(msg.value);
  //   //XCFXExchange(ACFX_address).addTokens(msg.sender, votePower*CFX_VALUE_OF_ONE_VOTE);----------------------------will use
  //   crossingVotes += votePower;
  //   // emit IncreasePoSStake(msg.sender, votePower);

    
  //   // put stake info in queue
  //   //userInqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(votePower, _blockNumber() + _poolLockPeriod));
  //   //userSummaries[msg.sender].locked += userInqueues[msg.sender].collectEndedVotes();
  //   //userSummaries[msg.sender].votes += votePower;
  //   //userSummaries[msg.sender].available += votePower;
    
  // }

  ///
  /// @notice Decrease PoS vote power
  /// @param votePower The number of vote power to decrease
  ///
  function decreaseStake(uint64 votePower) public virtual onlyRegisted {
    //userSummaries[msg.sender].locked += userInqueues[msg.sender].collectEndedVotes();
    //require(userSummaries[msg.sender].locked >= votePower, "Locked is not enough");
    // record the decrease request
    unstakeQueue.enqueue(UnstakeQueue.Node(votePower));
    // emit DecreasePoSStake(msg.sender, votePower);

    //_updateAccRewardPerCfx();

    // update user interest
    //_updateUserInterest(msg.sender);
    //

    // userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(votePower, _blockNumber() + _poolLockPeriod));
    // userSummaries[msg.sender].unlocked += userOutqueues[msg.sender].collectEndedVotes();
    // userSummaries[msg.sender].available -= votePower;
    // userSummaries[msg.sender].locked -= votePower;
    //_updateUserShot(msg.sender);

    //
    // _poolSummary.available -= votePower;
    // _updatePoolShot();
  }

  ///
  /// @notice Withdraw PoS vote power
  /// @param _amount The amount of CFX to withdraw
  ///
  function withdrawStake(uint256 _amount) public onlyRegisted {
    //userSummaries[msg.sender].unlocked += userOutqueues[msg.sender].collectEndedVotes();
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;

    require(userSummaries[msg.sender].unlocked >= _amount, "Unlocked is not enough");
    uint256 _withdrawAmount = _amount;
    require( userSummaries[msg.sender].unlocked >= _withdrawAmount, "Withdrawable CFX is not enough");
    // update amount of withdrawable CFX
    //withdrawableCfx -= _withdrawAmount;
    userSummaries[msg.sender].unlocked -= _amount;
    //userSummaries[msg.sender].votes -= votePower;
    
    address payable receiver = payable(msg.sender);
    receiver.transfer(_withdrawAmount);
    emit WithdrawStake(msg.sender, _amount);

    _updatePoolShot();

    if (userSummaries[msg.sender].available == 0) {
      stakers.remove(msg.sender);
    }
  }

  ///
  /// @notice User's interest from participate PoS
  /// @param _address The address of user to query
  /// @return CFX interest in Drip
  ///
  function userInterest(address _address) public view returns (uint256,uint256) {
    
    uint256 _interest = userSummaries[_address].currentInterest;

    uint256 _latestAccRewardPerCfx = accRewardPerCfx;
    // add latest profit
    uint256 _latestReward = _selfBalance() - lastPoolShot.balance;
    UserShot memory uShot = lastUserShots[_address];
    if (_latestReward > 0) {
      uint256 _deltaAcc = _latestReward.mul(0.01 ether).div(lastPoolShot.available);
      _latestAccRewardPerCfx = _latestAccRewardPerCfx.add(_deltaAcc);
    }

    if (uShot.available > 0) {
      uint256 _latestInterest = _latestAccRewardPerCfx.sub(uShot.accRewardPerCfx).mul(uShot.available).div(0.01 ether);
      _interest = _interest.add(_calUserShare(_latestInterest, _address));
    }
    // uint256 temp_XET_num = ERC20(XET_address).balanceOf(address(this));
    // uint256 XET_num_out = _interest.div(100);
    // if (temp_XET_num < XET_num_out) {
    //     XET_num_out=temp_XET_num;
    //   }
    return (_interest,XETdistribute(XET_Distribute_addr).estimate_out( _interest));
  }

  ///
  /// @notice Claim specific amount user interest
  /// @param amount The amount of interest to claim
  ///
  function claimInterest(uint amount) public onlyRegisted {
    uint claimableInterest;
    uint temp_useless;
    (claimableInterest,temp_useless) = userInterest(msg.sender);
    require(claimableInterest >= amount, "Interest not enough");
    require(isContract(msg.sender)==false,'cant be Contract');
    _updateAccRewardPerCfx();
    _updateUserInterest(msg.sender);
    //
    userSummaries[msg.sender].claimedInterest = userSummaries[msg.sender].claimedInterest.add(amount);
    userSummaries[msg.sender].currentInterest = userSummaries[msg.sender].currentInterest.sub(amount);
    // update userShot's accRewardPerCfx
    _updateUserShot(msg.sender);

    // send interest to user
    address payable receiver = payable(msg.sender);
    receiver.transfer(amount);
    emit ClaimInterest(msg.sender, amount);
    // uint256 temp_XET_num = ERC20(XET_address).balanceOf(address(this));
    // uint256 XET_num_out = amount.div(100);
    // if (temp_XET_num > XET_num_out) {
    //   ERC20(XET_address).transfer(msg.sender,XET_num_out);
    // }
    // else if(temp_XET_num > 0){
    //   ERC20(XET_address).transfer(msg.sender,temp_XET_num);
    // }
    ERC20(XET_address).transfer(msg.sender,XETdistribute(XET_Distribute_addr).estimate_out( amount));

    // update blockNumber and balance
    _updatePoolShot();
  }

  ///
  /// @notice Claim one user's all interest
  ///
  function claimAllInterest() public onlyRegisted {
    uint claimableInterest;
    uint temp_useless;
    (claimableInterest,temp_useless) = userInterest(msg.sender);
    require(claimableInterest > 0, "No claimable interest");
    claimInterest(claimableInterest);
  }

  /// 
  /// @notice Get user's pool summary
  /// @param _user The address of user to query
  /// @return User's summary
  ///
  function userSummary(address _user) public view returns (UserSummary memory) {
    UserSummary memory summary = userSummaries[_user];
    uint256 temp_amount =userOutqueues[_user].sumEndedVotes();
    //summary.locked += userInqueues[_user].sumEndedVotes();
    summary.unlocked += temp_amount;
    summary.unlocking -= temp_amount;
    return summary;
  }

  function poolSummary() public view returns (PoolSummary memory) {
    PoolSummary memory summary = _poolSummary;
    uint256 _latestReward = _selfBalance().sub(lastPoolShot.balance);
    summary.totalInterest = summary.totalInterest.add(_latestReward);
    return summary;
  }

  function poolAPY() public view returns (uint256) {
    return _poolAPY;
  }

  // function userInQueue(address account) public view returns (VotePowerQueue.QueueNode[] memory) {
  //   return userInqueues[account].queueItems();
  // }

  function userOutQueue(address account) public view returns (VotePowerQueue.QueueNode[] memory) {
    return userOutqueues[account].queueItems();
  }

  // function userInQueue(address account, uint64 offset, uint64 limit) public view returns (VotePowerQueue.QueueNode[] memory) {
  //   return userInqueues[account].queueItems(offset, limit);
  // }

  function userOutQueueoffset(address account, uint64 offset, uint64 limit) public view returns (VotePowerQueue.QueueNode[] memory) {
    return userOutqueues[account].queueItems(offset, limit);
  }

  function stakerNumber() public view returns (uint) {
    return stakers.length();
  }

  function stakerAddress(uint256 i) public view returns (address) {
    return stakers.at(i);
  }

  function unstakeLen() public view returns (uint256) {
    return unstakeQueue.end - unstakeQueue.start;
  }

  function firstUnstakeVotes() public view returns (uint256) {
    if (unstakeQueue.end == unstakeQueue.start) {
      return 0;
    }
    return unstakeQueue.items[unstakeQueue.start].votes;
  }

  // ======================== admin methods =====================

  ///
  /// @notice Enable admin to set the user share ratio
  /// @dev The ratio base is 10000, only admin can do this
  /// @param ratio The interest user share ratio (1-10000), default is 9000
  ///
  function setPoolUserShareRatio(uint64 ratio) public onlyOwner {
    require(ratio > 0 && ratio <= RATIO_BASE, "ratio should be 1-10000");
    poolUserShareRatio = ratio;
    //emit RatioChanged(ratio);
  }

  /// 
  /// @notice Enable admin to set the lock and unlock period
  /// @dev Only admin can do this
  /// @param period The lock period in block number, default is seven day's block count
  ///
  function setLockPeriod(uint64 period) public onlyOwner {
    _poolLockPeriod = period;
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
  function getBridge() public  returns(address){
    return _bridgeAddress;
  }

  function setPoolName(string memory name) public onlyOwner {
    poolName = name;
  }

  function _retireUserStake(address _addr, uint64 endBlockNumber) public onlyOwner {
    uint256 amount = userSummaries[_addr].available;
    if (amount == 0) return;

    _updateUserInterest(_addr);
    userSummaries[_addr].available = 0;
    userSummaries[_addr].unlocking = 0;
    // clear user inqueue
    // userInqueues[_addr].clear();
    userOutqueues[_addr].enqueue(VotePowerQueue.QueueNode(amount, endBlockNumber));
    _updateUserShot(_addr);

    _poolSummary.available -= amount;
  }

  // When pool node is force retired, use this method to make all user's available stake to unlocking
  function _retireUserStakes(uint256 offset, uint256 limit, uint64 endBlockNumber) public onlyOwner {
    uint256 len = stakers.length();
    if (len == 0) return;

    _updateAccRewardPerCfx();

    uint256 end = offset + limit;
    if (end > len) {
      end = len;
    }
    for (uint256 i = offset; i < end; i++) {
      _retireUserStake(stakers.at(i), endBlockNumber);
    }

    _updatePoolShot();
  }

  // ======================== bridge methods =====================

  function setPoolAPY(uint256 apy) public onlyBridge {
    _poolAPY = apy;
  }

  function handleUnlockedIncrease(uint256 votePower) public payable onlyBridge {
    require(msg.value == votePower * CFX_VALUE_OF_ONE_VOTE, "msg.value should be votePower * 1000 ether");
    //withdrawableCfx += msg.value;
    _updatePoolShot();
  }

  function handleCrossingVotes(uint256 votePower) public onlyBridge {
    require(crossingVotes >= votePower, "crossingVotes should be greater than votePower");
    crossingVotes -= votePower;
  }

  function handleUnstakeTask() public onlyBridge returns (uint256) {
    UnstakeQueue.Node memory node = unstakeQueue.dequeue();
    return node.votes;
  }

  // receive interest
  function receiveInterest() public payable onlyBridge {}

  fallback() external payable {}
  receive() external payable {}

}