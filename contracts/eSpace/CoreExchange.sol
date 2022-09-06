//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../ICrossSpaceCall.sol";
interface IERC20crosstoCore{
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
  address bridgeCoresideaddr; //espace address
  //--------------------------------------Modifiers-----------------------------------------------
  // modifier Only_trusted_trigers() {
  //   require(trusted_node_trigers[msg.sender]==true,'trigers must be trusted');
  //   _;
  // }

  //--------------------------------------settings-----------------------------------------------
  function initialize() public initializer{
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  }

  //--------------------------------------functions-----------------------------------------------
  //  function CFX_exchange_estim(uint256 _amount) public view returns(uint256);
  //  function CFX_exchange_XCFX() external payable returns(uint256)   return xcfx_exchange;
  //  function XCFX_burn_estim(uint256 _amount) public view returns(uint256);
  //  function XCFX_burn(uint256 _amount) public virtual onlyRegisted returns(uint256);
  //  function getback_CFX(uint256 _amount) public virtual onlyRegisted ;
  function CFX_exchange_estim(uint256 _amount) public view returns(uint256){
    return staticCallEVM(eSpaceroomAddr, abi.encodeWithSignature("CFX_exchange_estim(uint256 _amount)", _amount));
  }
  function CFX_exchange_XCFX() external payable returns(uint256){
    uint256 xCFXAmount = abi.decode(crossSpaceCall.callEVM {value: msg.value}
           (bytes20(eSpaceroomAddr), abi.encodeWithSignature("CFX_exchange_XCFX()")), (uint256));
    callEVM(xCFXeSpace, abi.encodeWithSignature("approve(address spender,uint256 amount)"), (CoreExchangeeSpaceaddr,xCFXAmount)) ;
    callEVM(bridgeeSpacesideaddr, abi.encodeWithSignature("lockToken(address _token,address _cfxAccount,uint256 _amount)"), 
                                                                       (xCFXeSpaceAddr,msg.sender,xCFXAmount)) ;
    IERC20crosstoCore(bridgeCoresideaddr).crossFromEvm(xCFXeSpaceAddr, CoreExchangeeSpaceaddr, _amount);
    return xCFXAmount;
  }


  //--------------------------------------internal-----------------------------------------------
  function callEVM(address addr, bytes calldata data) internal {
    crossSpaceCall.callEVM(bytes20(addr), data);
  }
  function staticCallEVM(address addr, bytes calldata data) internal view  returns (uint256){
    bytes20 rawdatas = crossSpaceCall.staticCallEVM(bytes20(addr), data);
    uint256 outputdata = abi.decode(rawFirstUnstakeVotes, (uint256));
    return outputdata;
  }

  fallback() external payable {}
  receive() external payable {}
  uint256 identifier;
  //--------------------------------------temp-----------------------------------------------
   //function identifier_test(uint256 _identifier) public onlyOwner {identifier=_identifier; }
   //function systemCFXInterestsTemp_set(uint256 _i) public onlyOwner {systemCFXInterestsTemp=_i; }
  
}