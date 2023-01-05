//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../VotePowerQueue.sol";
import "../ICrossSpaceCall.sol";
interface IERC20crossInCore{
    function crossFromEvm(address _evmToken, address _evmAccount,uint256 _amount) external;
    function withdrawToEvm(address _evmToken, address _evmAccount,uint256 _amount)  external;
}
///
///  @title Core Exchange is deployed in core;
///  @dev This contract exchange CFX and xCFX in core, 
///  @dev This contract use the espace exchangeroom methods to do the work  
///  @notice Users can use this contract to participate Conflux PoS stake.
///
contract CoreExchange is Ownable, Initializable {
  using SafeMath for uint256;
  using VotePowerQueue for VotePowerQueue.InOutQueue;
  uint256 private constant ONE_DAY_BLOCK_COUNT = 3600 * 24 * 2; //172800

  CrossSpaceCall internal crossSpaceCall;
  address eSpaceroomAddr;         //espace address
  address xCFXeSpaceAddr;         //espace address
  address bridgeeSpacesideaddr;   //espace address
  address bridgeCoresideaddr;     //Core address
  address xCFXCoreAddr;           //Core address
  address storagebridge;          //espace address
  bool started;

  uint256 public _poolLockPeriod_slow = ONE_DAY_BLOCK_COUNT * 15;
  uint256 public _poolLockPeriod_fast = ONE_DAY_BLOCK_COUNT * 2;
  string public poolName; // = "UNCLEON HUB";
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
    uint256 unlockingCFX;
  }

  /// @title UserSummary
  /// @custom:field unlocking
  /// @custom:field unlocked
  struct UserSummary {
    uint256 unlocking;
    uint256 unlocked;
  }
  // ======================== Contract states ===========================
  ExchangeSummary private _exchangeSummary;
  VotePowerQueue.InOutQueue private Inqueues;
  mapping(address => UserSummary) private userSummaries;
  mapping(address => VotePowerQueue.InOutQueue) private userOutqueues;
  //--------------------------------------Modifiers-----------------------------------------------
  modifier Only_after_started() {
    require(started==true,'started must be true');
    _;
  }
  // ======================== Helpers ===================================
  function _selfBalance() internal view virtual returns (uint256) {
    return address(this).balance;
  }

  function _blockNumber() internal view virtual returns (uint256) {
    return block.number;
  }
    // ======================== Events ====================================
  
  event IncreasePoSStake(address indexed user, uint256 votePower);

  event DecreasePoSStake(address indexed user, uint256 votePower);

  event WithdrawStake(address indexed user, uint256 votePower);

  event SetPoolName(address indexed user, string name);

  event SetLockPeriod(address indexed user, uint256 slow, uint256 fast);

  event Setstart(address indexed user);

  event SeteSpaceroomAddr(address indexed user, address eSpaceroomAddr);

  event SetxCFXeSpaceAddr(address indexed user, address xCFXeSpaceAddr);

  event SetstorageBridge(address indexed user, address s_addr);

  event SetXCFXaddr(address indexed user, address xcfx_addr);

  event SetSystemBridgeeSpacesideaddr(address indexed user, address bridgeeSpacesideaddr);

  event SetSystemBridgeCoresideaddr(address indexed user, address bridgeCoresideaddr);

  //--------------------------------------settings-----------------------------------------------
  function initialize() public initializer{
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
    _poolLockPeriod_slow = ONE_DAY_BLOCK_COUNT * 15;
    _poolLockPeriod_fast = ONE_DAY_BLOCK_COUNT * 2;
    poolName = "UNCLEON HUB Core";
  }
  function _setPoolName(string memory name) public onlyOwner {
    poolName = name;
    emit SetPoolName(msg.sender, name);
  }
  function _setLockPeriod() public onlyOwner returns(uint256,uint256){
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("getLockPeriod()"));
    uint256 _slow;
    uint256 _fast;
    (_slow, _fast) = abi.decode(rawdatas, (uint256,uint256));
    _poolLockPeriod_slow = _slow*21/10;
    _poolLockPeriod_fast = _fast*21/10;
    emit SetLockPeriod(msg.sender, _poolLockPeriod_slow, _poolLockPeriod_fast);
    return(_poolLockPeriod_slow,_poolLockPeriod_fast);
  }

  function _setstart() external onlyOwner {
    started = true;
    emit Setstart(msg.sender);
  }
  function _seteSpaceroomAddr(address _eSpaceroomAddr) external onlyOwner {
    eSpaceroomAddr = _eSpaceroomAddr;
    emit SeteSpaceroomAddr(msg.sender, eSpaceroomAddr);
  }
  function _setxCFXeSpaceAddr(address _xCFXeSpaceAddr) external onlyOwner {
    xCFXeSpaceAddr = _xCFXeSpaceAddr;
    emit SetxCFXeSpaceAddr(msg.sender, xCFXeSpaceAddr);
  } 
  function _setstoragebridgeAddr(address _storagebridgeAddr) external onlyOwner {
    storagebridge = _storagebridgeAddr;
    emit SetstorageBridge(msg.sender, storagebridge);
  } 
  function _setxCFXCoreAddr(address _xCFXCoreAddr) external onlyOwner {
    xCFXCoreAddr = _xCFXCoreAddr;
    emit  SetXCFXaddr(msg.sender, xCFXCoreAddr);
  }
  function _setSystemBridgeeSpacesideAddr(address _bridgeeSpacesideaddr) external onlyOwner {
    bridgeeSpacesideaddr = _bridgeeSpacesideaddr;
    emit SetSystemBridgeeSpacesideaddr(msg.sender, bridgeeSpacesideaddr);
  }
  function _setSystemBridgeCoresideAddr(address _bridgeCoresideaddr) external onlyOwner {
    bridgeCoresideaddr = _bridgeCoresideaddr;
    emit SetSystemBridgeCoresideaddr(msg.sender, bridgeCoresideaddr);
  }
  
  //--------------------------------------functions-----------------------------------------------
  //  function CFX_exchange_estim(uint256 _amount) public view returns(uint256);
  //  function CFX_exchange_XCFX() external payable returns(uint256)   return xcfx_exchange;
  //  function XCFX_burn_estim(uint256 _amount) public view returns(uint256);
  //  function XCFX_burn(uint256 _amount) public virtual onlyRegisted returns(uint256);
  //  function getback_CFX(uint256 _amount) public virtual onlyRegisted ;
  function CFX_exchange_estim(uint256 _amount) public view returns(uint256){
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("CFX_exchange_estim(uint256)", _amount));
    uint256 estimReturn = abi.decode(rawdatas, (uint256));
    return estimReturn;
  }

  function CFX_exchange_XCFX() external payable Only_after_started returns(uint256){
    bytes memory rawdatas = crossSpaceCall.callEVM{value: msg.value}(bytes20(eSpaceroomAddr), abi.encodeWithSignature("handleCFXexchangeXCFX()"));
    uint256 Amount = abi.decode(rawdatas, (uint256));
    rawdatas = crossSpaceCall.callEVM(bytes20(storagebridge), 
                            abi.encodeWithSignature("handlelock(uint256)", Amount));
    Amount = abi.decode(rawdatas, (uint256));
    collectOutqueuesFinishedVotes();
    IERC20crossInCore(bridgeCoresideaddr).crossFromEvm(xCFXeSpaceAddr, storagebridge, Amount);
    IERC20(xCFXCoreAddr).transfer(msg.sender, Amount);
    _exchangeSummary.totalxcfxs = IERC20(xCFXCoreAddr).totalSupply();
    emit IncreasePoSStake(msg.sender, Amount);
    return _exchangeSummary.totalxcfxs;
  }

  function XCFX_burn_estim(uint256 _amount) public view returns(uint256,uint256){
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("XCFX_burn_estim(uint256,uint256)", _amount));
    uint256 estimReturn1;
    uint256 estimReturn2;
    (estimReturn1,estimReturn2) = abi.decode(rawdatas, (uint256,uint256));
    return (estimReturn1,estimReturn2);
  }
  
  function XCFX_burn(uint256 _amount) external Only_after_started returns(uint256, uint256){
    IERC20(xCFXCoreAddr).transferFrom(msg.sender, address(this),_amount);
    IERC20(xCFXCoreAddr).approve(bridgeCoresideaddr,_amount);
    IERC20crossInCore(bridgeCoresideaddr).withdrawToEvm(xCFXeSpaceAddr, storagebridge, _amount);
    bytes memory rawdatas = crossSpaceCall.callEVM(bytes20(storagebridge), abi.encodeWithSignature("handlexCFXburn(uint256)",_amount));
    uint256 withdrawCFXs;
    uint256 withdrawtimes;
    (withdrawCFXs,withdrawtimes) = abi.decode(rawdatas, (uint256,uint256));
    _exchangeSummary.totalxcfxs = IERC20(xCFXCoreAddr).totalSupply();
    _exchangeSummary.unlockingCFX += withdrawCFXs;

    if(withdrawtimes == 101109){
      userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(withdrawCFXs, _blockNumber() + _poolLockPeriod_fast));
      _amount = _blockNumber() + _poolLockPeriod_fast;
      }
    else{
      userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(withdrawCFXs, _blockNumber() + _poolLockPeriod_slow));
      _amount = _blockNumber() + _poolLockPeriod_slow;
    }
    userSummaries[msg.sender].unlocking += withdrawCFXs;
    collectOutqueuesFinishedVotes();
    emit DecreasePoSStake(msg.sender, withdrawCFXs);
    return (withdrawCFXs,withdrawtimes);
  }

  function getback_CFX(uint256 _amount) public virtual Only_after_started {
    collectOutqueuesFinishedVotes();
    _exchangeSummary.totalxcfxs = IERC20(xCFXCoreAddr).totalSupply();
    _exchangeSummary.unlockingCFX -= _amount;
    require(userSummaries[msg.sender].unlocked>=_amount,'_amount exceed available');
    userSummaries[msg.sender].unlocked -= _amount;
    crossSpaceCall.callEVM(bytes20(storagebridge), abi.encodeWithSignature("handlegetbackCFX(uint256)",_amount));
    crossSpaceCall.withdrawFromMapped(_amount);
    (bool success, ) = msg.sender.call{value:_amount}("");
    require(success,"CFX Transfer Failed");
    emit WithdrawStake(msg.sender, _amount);
  }

  // 
  // @notice Get user's pool summary
  // @param _user The address of user to query
  // @return User's summary
  //
  function userSummary(address _user) public view returns (UserSummary memory) {
    UserSummary memory summary = userSummaries[_user];
    uint256 temp_amount =userOutqueues[_user].sumEndedVotes();
    summary.unlocked += temp_amount;
    summary.unlocking -= temp_amount;
    return summary;
  }
  // @title Summary() 
  // @dev get the pos pool Summary
  function Summary() public view returns (ExchangeSummary memory) {
    return _exchangeSummary;
  }
  // @title userOutQueue(address account)
  // @dev get the user's OutQueue
  function userOutQueue(address account) public view returns (VotePowerQueue.QueueNode[] memory) {
    return userOutqueues[account].queueItems();
  }

  function collectOutqueuesFinishedVotes() private {
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;
  }

  fallback() external payable {}
  receive() external payable {}
  
}