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
//import "../IExchange.sol";
///
///  @title Core Exchange is deployed in core;
///  @dev This contract exchange CFX and xCFX in core, 
///  @dev  
///  @notice Users can direct use this contract to participate Conflux PoS stake.
///
contract CoreExchange is Ownable, Initializable {
  using SafeMath for uint256;
  using VotePowerQueue for VotePowerQueue.InOutQueue;
  uint256 private constant ONE_DAY_BLOCK_COUNT = 3600 * 24 * 2;

  CrossSpaceCall internal crossSpaceCall;
  address eSpaceroomAddr; //espace address
  address xCFXeSpaceAddr; //espace address
  address CoreExchangeeSpaceaddr; //espace address
  address bridgeeSpacesideaddr; //espace address
  address bridgeCoresideaddr; //Core address
  address xCFXCoreAddr; //Core address
  address storagebridge; //espace address
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
    require(started==true,'trigers must be trusted');
    _;
  }
  // ======================== Helpers ===================================
  function _selfBalance() internal view virtual returns (uint256) {
    return address(this).balance;
  }

  function _blockNumber() internal view virtual returns (uint256) {
    return block.number;
  }
  //--------------------------------------settings-----------------------------------------------
  function initialize() public initializer{
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
    _poolLockPeriod_slow = ONE_DAY_BLOCK_COUNT * 15;
    _poolLockPeriod_fast = ONE_DAY_BLOCK_COUNT * 2;
    _poolLockPeriod_slow = ONE_DAY_BLOCK_COUNT * 15;
    _poolLockPeriod_fast = ONE_DAY_BLOCK_COUNT * 2;
    poolName = "UNCLEON HUB Core";
  }

  function _setLockPeriod(uint64 _slow,uint64 _fast) public onlyOwner {
    _poolLockPeriod_slow = _slow;
    _poolLockPeriod_fast = _fast;
  }
  function _seteSpaceroomAddr(address _eSpaceroomAddr) external onlyOwner {
        eSpaceroomAddr = _eSpaceroomAddr;
  }
  function _setxCFXeSpaceAddr(address _xCFXeSpaceAddr) external onlyOwner {
        xCFXeSpaceAddr = _xCFXeSpaceAddr;
  } 
  function _setstoragebridgeAddr(address _storagebridgeAddr) external onlyOwner {
        storagebridge = _storagebridgeAddr;
  } 
  function _setCoreExchangeeSpaceaddr(address _CoreExchangeeSpaceaddr) external onlyOwner {
        CoreExchangeeSpaceaddr = _CoreExchangeeSpaceaddr;
  }
  function _setbridgeeSpacesideaddr(address _bridgeeSpacesideaddr) external onlyOwner {
        bridgeeSpacesideaddr = _bridgeeSpacesideaddr;
  }
  function _setbridgeCoresideaddr(address _bridgeCoresideaddr) external onlyOwner {
        bridgeCoresideaddr = _bridgeCoresideaddr;
  }
  function _setxCFXCoreAddr(address _xCFXCoreAddr) external onlyOwner {
        xCFXCoreAddr = _xCFXCoreAddr;
  }
  

  //--------------------------------------functions-----------------------------------------------
  //  function CFX_exchange_estim(uint256 _amount) public view returns(uint256);
  //  function CFX_exchange_XCFX() external payable returns(uint256)   return xcfx_exchange;
  //  function XCFX_burn_estim(uint256 _amount) public view returns(uint256);
  //  function XCFX_burn(uint256 _amount) public virtual onlyRegisted returns(uint256);
  //  function getback_CFX(uint256 _amount) public virtual onlyRegisted ;
  function CFX_exchange_estim(uint256 _amount) public view returns(uint256){
    
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("CFX_exchange_estim(uint256 _amount)", _amount));
    uint256 estimReturn = abi.decode(rawdatas, (uint256));
    return estimReturn;
  }
  function CFX_exchange_XCFX() external payable Only_after_started returns(uint256){
    bytes memory rawdatas = crossSpaceCall.callEVM{value: msg.value}(bytes20(eSpaceroomAddr), abi.encodeWithSignature("handleCFXexchangeXCFX()"));
    uint256 xCFXAmount = abi.decode(rawdatas, (uint256));

    crossSpaceCall.callEVM(bytes20(storagebridge), abi.encodeWithSignature(" handlelocktoCoreExchange(address _token, uint256 _amount)", xCFXeSpaceAddr,xCFXAmount)) ;
    IERC20crossInCore(bridgeCoresideaddr).crossFromEvm(xCFXeSpaceAddr, CoreExchangeeSpaceaddr, xCFXAmount);
    IERC20(xCFXCoreAddr).transfer(msg.sender, xCFXAmount);
    _exchangeSummary.totalxcfxs += xCFXAmount;
    return xCFXAmount;
  }
  function XCFX_burn_estim(uint256 _amount) public view returns(uint256){
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("XCFX_burn_estim(uint256 _amount)", _amount));
    uint256 estimReturn = abi.decode(rawdatas, (uint256));
    return estimReturn;
  }
  function XCFX_burn(uint256 _amount) external Only_after_started returns(uint256,uint256){
    IERC20(xCFXCoreAddr).transferFrom(msg.sender, address(this),_amount);
    IERC20crossInCore(bridgeCoresideaddr).withdrawToEvm(xCFXeSpaceAddr, eSpaceroomAddr, _amount);
    bytes memory rawdatas = crossSpaceCall.callEVM(bytes20(storagebridge), abi.encodeWithSignature("handlexCFXburn(uint256 _amount)",_amount));
    uint256 withdrawCFXs;
    uint256 withdrawtimes;
    (withdrawCFXs,withdrawtimes) = abi.decode(rawdatas, (uint256,uint256));
    _exchangeSummary.totalxcfxs -= _amount;
    _exchangeSummary.unlockingCFX += withdrawCFXs;
    uint256 _mode = 0;
    if(withdrawCFXs<=_exchangeSummary.alloflockedvotes.mul(1000 ether)){
      _mode=1;
    }
    else {
      require(_amount<=_exchangeSummary.totalxcfxs,"Exceed exchange limit");
      _mode=0;
    }

    if(_mode == 1){
      userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(withdrawCFXs, _blockNumber() + _poolLockPeriod_fast));
      _amount = _blockNumber() + _poolLockPeriod_fast;
      }
    else{
      userOutqueues[msg.sender].enqueue(VotePowerQueue.QueueNode(withdrawCFXs, _blockNumber() + _poolLockPeriod_slow));
      _amount = _blockNumber() + _poolLockPeriod_slow;
    }
    
    userSummaries[msg.sender].unlocking += withdrawCFXs;
    
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;
    return (withdrawCFXs,withdrawtimes);
  }

  function getback_CFX(uint256 _amount) public virtual Only_after_started {
    uint256 temp_amount = userOutqueues[msg.sender].collectEndedVotes();
    userSummaries[msg.sender].unlocked += temp_amount;
    userSummaries[msg.sender].unlocking -= temp_amount;
    _exchangeSummary.unlockingCFX -= _amount;
    crossSpaceCall.callEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("getback_CFX(uint256 _amount)",_amount));
    crossSpaceCall.withdrawFromMapped(_amount);
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


  //--------------------------------------internal-----------------------------------------------
  // function callEVM(address addr, bytes20 data) internal {
  //   crossSpaceCall.callEVM(bytes20(addr), data);
  // }
  // function staticCallEVM(address addr, bytes20 data) internal view  returns (uint256){
  //   bytes20 rawdatas = crossSpaceCall.staticCallEVM(bytes20(addr), data);
  //   uint256 outputdata = abi.decode(rawdatas, (uint256));
  //   return outputdata;
  // }

  fallback() external payable {}
  receive() external payable {}
  uint256 identifier;
  //--------------------------------------temp-----------------------------------------------
   //function identifier_test(uint256 _identifier) public onlyOwner {identifier=_identifier; }
   //function systemCFXInterestsTemp_set(uint256 _i) public onlyOwner {systemCFXInterestsTemp=_i; }
  
}