//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
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
  CrossSpaceCall internal crossSpaceCall;
  address eSpaceroomAddr; //espace address
  address xCFXeSpaceAddr; //espace address
  address CoreExchangeeSpaceaddr; //espace address
  address bridgeeSpacesideaddr; //espace address
  address bridgeCoresideaddr; //Core address
  address xCFXCoreAddr; //Core address

  bool started;
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
  //--------------------------------------Modifiers-----------------------------------------------
  modifier Only_after_started() {
    require(started==true,'trigers must be trusted');
    _;
  }

  //--------------------------------------settings-----------------------------------------------
  function initialize() public initializer{
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
  }

  function _seteSpaceroomAddr(address _eSpaceroomAddr) external onlyOwner {
        eSpaceroomAddr = _eSpaceroomAddr;
  }
  function _setxCFXeSpaceAddr(address _xCFXeSpaceAddr) external onlyOwner {
        xCFXeSpaceAddr = _xCFXeSpaceAddr;
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
    bytes memory rawdatas = crossSpaceCall.callEVM{value: msg.value}(bytes20(eSpaceroomAddr), abi.encodeWithSignature("CFX_exchange_XCFX()"));
    uint256 xCFXAmount = abi.decode(rawdatas, (uint256));
    crossSpaceCall.callEVM(bytes20(xCFXeSpaceAddr), abi.encodeWithSignature("approve(address spender,uint256 amount)", CoreExchangeeSpaceaddr,xCFXAmount)) ;
    crossSpaceCall.callEVM(bytes20(bridgeeSpacesideaddr), abi.encodeWithSignature("lockToken(address _token,address _cfxAccount,uint256 _amount)", 
                                                                       xCFXeSpaceAddr,CoreExchangeeSpaceaddr,xCFXAmount)) ;
    IERC20crossInCore(bridgeCoresideaddr).crossFromEvm(xCFXeSpaceAddr, CoreExchangeeSpaceaddr, xCFXAmount);
    IERC20(xCFXCoreAddr).transfer(msg.sender, xCFXAmount);
    return xCFXAmount;
  }
  function XCFX_burn_estim(uint256 _amount) public view returns(uint256){
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("XCFX_burn_estim(uint256 _amount)", _amount));
    uint256 estimReturn = abi.decode(rawdatas, (uint256));
    return estimReturn;
  }
  function XCFX_burn(uint256 _amount) external Only_after_started returns(uint256){
    IERC20(xCFXCoreAddr).transferFrom(msg.sender, address(this),_amount);
    IERC20crossInCore(bridgeCoresideaddr).withdrawToEvm(xCFXeSpaceAddr, CoreExchangeeSpaceaddr, _amount);
    bytes memory rawdatas = crossSpaceCall.callEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("XCFX_burn(uint256 _amount)",_amount));
    uint256 withdrawtimes = abi.decode(rawdatas, (uint256));

    return withdrawtimes;
  }

  function getback_CFX(uint256 _amount) public virtual Only_after_started {
    crossSpaceCall.callEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("getback_CFX(uint256 _amount)",_amount));
    crossSpaceCall.withdrawFromMapped(_amount);
  }

  // 
  // @notice Get user's pool summary
  // @param _user The address of user to query
  // @return User's summary
  //
  function userSummary(address _user) public view returns (UserSummary memory) {
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("userSummary(address _user)", _user));
    UserSummary memory summary = abi.decode(rawdatas, (UserSummary));
    return summary;
  }
  // @title Summary() 
  // @dev get the pos pool Summary
  function Summary() public view returns (ExchangeSummary memory) {
    bytes memory rawdatas = crossSpaceCall.staticCallEVM(bytes20(eSpaceroomAddr), abi.encodeWithSignature("Summary()"));
    ExchangeSummary memory summary = abi.decode(rawdatas, (ExchangeSummary));
    return summary;
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