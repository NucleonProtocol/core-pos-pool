//SPDX-License-Identifier: BUSL-1.1
// Licensor:            X-Dao.
// Licensed Work:       NUCLEON 1.0

pragma solidity 0.8.2;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../ICrossSpaceCall.sol";
import "../IExchange.sol";
///
///  @title CoreBridge_multipool is a bridge to connect Conflux POS pools and Exchange rooms ,deployed in core;
///  @dev This contract set the user share ratio, system share ratio, 
///  @dev compound the interests
///  @notice Users cann't direct use this contract to participate Conflux PoS stake.
///
contract CoreBridge_multipool is Ownable, Initializable {
  using SafeMath for uint256;
  CrossSpaceCall internal crossSpaceCall;

  uint256 private constant RATIO_BASE = 10000;
  // ratio shared by user: 1-10000
  uint256 public poolUserShareRatio;
  uint256 private CFX_COUNT_OF_ONE_VOTE;
  uint256 private CFX_VALUE_OF_ONE_VOTE;

  address[] public poolAddress;               //can use many pools, so here is an array
  uint256   public PosIDinuse;                //pos pool in use
  //eSpace address
  address   public xCFXAddress;               //xCFX addr in espace 
  address   public eSpaceExroomAddress;       //Exchange room Address in espace
  address   public bridgeeSpaceAddress;       //address of bridge in espace
  address   public ServicetreasuryAddress;    //Service treasury Address in espace
  //Core Space address
  address   public CoreExroomAddress;         //Exchange room Address in core
  uint256   private systemCFXInterestsTemp;    //pools cfx interests in temporary

  uint256 private Unstakebalanceinbridge;             //Unstaked balance
  uint256 private identifier;                         //compound and update order identifier

  mapping(address=>bool) private trusted_node_trigers;//     
  // ======================== Struct definitions =========================
  struct PoolSummary {
    uint256 xCFXSUM;             // xCFX SUM (1 ether xCFX === 1 e18)
    uint256 totalInterest;       // PoS pool interests for all xCFX
    uint256 CFXbalances;         // CFX balances in bridge
    uint256 historical_Interest ;// total historical interest of whole pools
  }

  // constructor () {
  //   initialize();
  // }
  // ============================ Modifiers ===============================

  modifier Only_trusted_trigers() {
    require(trusted_node_trigers[msg.sender]==true,'trigers must be trusted');
    _;
  }
    // ======================== Events ==============================

  event AddPoolAddress(address indexed user, address poolAddress);

  event ChangePoolAddress(address indexed user, address oldpoolAddress,address newpoolAddress);

  event DelePoolAddress(address indexed user, address oldpoolAddress);

  event SeteSpaceExroomAddress(address indexed user, address eSpaceExroomAddr);

  event SeteSpacexCFXAddress(address indexed user, address eSpacexCFXaddr);

  event SeteSpacebridgeAddress(address indexed user, address bridgeeSpaceAddr);

  event SeteServicetreasuryAddress(address indexed user, address servicetreasuryAddress);

  event Settrustedtrigers(address indexed user, address triggersAddress,bool state);

  event SetCfxCountOfOneVote(address indexed user, uint256 count);

  event SetPoolUserShareRatio(address indexed user, uint256 ratio);

  event ClearTheStates(address indexed user, uint256 idclear);

  // ================== Methods for core pos pools settings ===============

  function initialize() public initializer{
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
    poolUserShareRatio = 9000;
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  }

  function _addPoolAddress(address poolAddr) public onlyOwner {
    require(poolAddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    poolAddress.push(poolAddr);
    emit AddPoolAddress(msg.sender, poolAddr);
  }

  function _changePoolAddress(address oldpoolAddress,address newpoolAddress) public onlyOwner {
    require(newpoolAddress!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    uint256 poolsum = poolAddress.length;
    for(uint256 i=0;i<poolsum;i++)
    {
        if(poolAddress[i]==oldpoolAddress)
        {
            poolAddress[i]=newpoolAddress;
            break;
        }
    }
    emit ChangePoolAddress(msg.sender, oldpoolAddress, newpoolAddress);
  }
  function _delePoolAddress(address oldpoolAddress) public onlyOwner {
    uint256 pool_sum = poolAddress.length;
    for(uint256 i=0;i<pool_sum;i++)
    {
        if(poolAddress[i]==oldpoolAddress)
        {
            poolAddress[i]= poolAddress[pool_sum-1];
            poolAddress.pop();
            break;
        }
    }
    emit DelePoolAddress(msg.sender, oldpoolAddress);
  }

  function _seteSpaceExroomAddress(address eSpaceExroomAddr) public onlyOwner {
    require(eSpaceExroomAddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    eSpaceExroomAddress = eSpaceExroomAddr;
    emit SeteSpaceExroomAddress(msg.sender, eSpaceExroomAddr);
  }
  function _seteSpacexCFXAddress(address eSpacexCFXaddr) public onlyOwner {
    require(eSpacexCFXaddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    xCFXAddress = eSpacexCFXaddr;
    emit SeteSpacexCFXAddress(msg.sender, eSpacexCFXaddr);
  }
  function _seteSpacebridgeAddress(address bridgeeSpaceAddr) public onlyOwner {
    require(bridgeeSpaceAddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    bridgeeSpaceAddress = bridgeeSpaceAddr;
    emit SeteSpacebridgeAddress(msg.sender, bridgeeSpaceAddr);
  }
  function _seteServicetreasuryAddress(address servicetreasury) public onlyOwner {
    require(servicetreasury!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    ServicetreasuryAddress = servicetreasury;
    emit SeteServicetreasuryAddress(msg.sender, servicetreasury);
  }
  
  function _settrustedtrigers(address triggersAddress,bool state) public onlyOwner {
    require(triggersAddress!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    trusted_node_trigers[triggersAddress] = state;
    emit Settrustedtrigers(msg.sender, triggersAddress, state);
  }

  /// @param count Vote cfx count, unit is cfx
  function _setCfxCountOfOneVote(uint256 count) public onlyOwner {
    CFX_COUNT_OF_ONE_VOTE = count;
    CFX_VALUE_OF_ONE_VOTE = count * 1 ether;
    emit SetCfxCountOfOneVote(msg.sender, CFX_COUNT_OF_ONE_VOTE);
  }

  function _setPoolUserShareRatio(uint256 ratio) public onlyOwner {
    require(ratio > 0 && ratio <= RATIO_BASE, "ratio should be 1-10000");
    poolUserShareRatio = ratio;
    emit SetPoolUserShareRatio(msg.sender, ratio);
  }
  function gettrigerstate(address _Address) public view returns(bool){
    return trusted_node_trigers[_Address];
  }
  function getPoolAddress() public view returns (address[] memory ) {
    return poolAddress;
  }
  function _clearTheStates() public onlyOwner {
    identifier = 0;
    emit ClearTheStates(msg.sender, identifier);
  }

  //------------------------espace method---------------------------------

  function queryespacexCFXincrease() internal returns (uint256) {
    bytes memory rawCrossingVotes = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("crossingVotes()"));
    return abi.decode(rawCrossingVotes, (uint256));
  }

  // function queryUnstakeLen() public view returns (uint256) {
  //   bytes memory rawUnstakeLen = crossSpaceCall.staticCallEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("unstakeLen()"));
  //   return abi.decode(rawUnstakeLen, (uint256));
  // }

  //-------------------core pool method------------------------------------
  function queryInterest(uint256 _num) internal view returns (uint256) {
    IExchange posPool = IExchange(poolAddress[_num]);
    uint256 interest = posPool.temp_Interest();
    return interest;
  }

  //---------------------bridge method-------------------------------------
  function syncALLwork() public Only_trusted_trigers returns(uint256[11] memory infos){
    infos[0] = claimInterests();
    (infos[1],infos[2]) = campounds();
    (infos[3],infos[4]) = handleUnstake();
    infos[5] = handleLockedvotesSUM();
    (infos[6],infos[7],infos[8]) = SyncValue();
    (infos[9],infos[10]) = withdrawVotes();
    return infos;
  }

  function claimInterests() internal Only_trusted_trigers returns(uint256){
    uint256 pool_sum = poolAddress.length;
    IExchange posPool;
    uint256 interest;
    uint256 allinterest;
    for(uint256 i=0;i<pool_sum;i++)
    {
      posPool = IExchange(poolAddress[i]);
      interest = posPool.temp_Interest();
      if (interest > 0) {
        allinterest += posPool.claimAllInterest(); 
      }
    }
    systemCFXInterestsTemp += allinterest.mul(RATIO_BASE-poolUserShareRatio).div(RATIO_BASE);
    return systemCFXInterestsTemp;
  }
  
  function campounds() internal Only_trusted_trigers  returns(uint256,uint256){
    require(identifier==0,"identifier is not right, need be 0");
    identifier=1;

    uint256 toxCFX = systemCFXInterestsTemp;
    uint256 xCFXminted;
    systemCFXInterestsTemp = 0;
    if(toxCFX>0){
      bytes memory rawxCFX = crossSpaceCall.callEVM{value: toxCFX}(bytes20(eSpaceExroomAddress), 
                                            abi.encodeWithSignature("handleCFXexchangeXCFX()"));
      xCFXminted =  abi.decode(rawxCFX, (uint256));
    }
    
    bytes memory rawbalance = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("espacebalanceof(address)", bridgeeSpaceAddress));
    uint256 balanceinpool =  abi.decode(rawbalance, (uint256));
    crossSpaceCall.withdrawFromMapped(balanceinpool);
    uint64 votePower = uint64(address(this).balance.div(CFX_VALUE_OF_ONE_VOTE));
    if (votePower > 0){
      IExchange(poolAddress[PosIDinuse]).increaseStake{value: votePower*CFX_VALUE_OF_ONE_VOTE}(votePower);
    }
    return (xCFXminted, votePower);
  }

  function handleUnstake() internal Only_trusted_trigers  returns(uint256,uint256){
    require(identifier==1,"identifier is not right, need be 1");
    identifier=2;

    IExchange posPool = IExchange(poolAddress[PosIDinuse]);
    IExchange.PoolSummary memory poolSummary = posPool.poolSummary();
    uint256 available = poolSummary.totalvotes;
    if (available == 0) return (0,Unstakebalanceinbridge);

    bytes memory rawUnstakeCFXs ;
    uint256 receivedUnstakeCFXs;
    rawUnstakeCFXs = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("handleUnstake()"));
    receivedUnstakeCFXs = abi.decode(rawUnstakeCFXs, (uint256));
    if (receivedUnstakeCFXs == 0) return (0,0);
    require(receivedUnstakeCFXs <= available.mul(CFX_VALUE_OF_ONE_VOTE),'handleUnstake error, receivedUnstakeCFXs > availableCFX in POS');
    //if (receivedUnstakeCFXs > available) return (0,0);
    Unstakebalanceinbridge += receivedUnstakeCFXs;

    if(Unstakebalanceinbridge > CFX_VALUE_OF_ONE_VOTE){
      available -= Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE);
      posPool.decreaseStake(uint64(Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE)));
      Unstakebalanceinbridge -= Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE).mul(CFX_VALUE_OF_ONE_VOTE);
    }

    return (available,Unstakebalanceinbridge);
  }

  function handleLockedvotesSUM() internal Only_trusted_trigers  returns(uint256){
    uint256 pool_sum = poolAddress.length;
    uint256 poolLockedvotesSUM;
    for(uint256 i=0;i<pool_sum;i++)
    {
        poolLockedvotesSUM += IExchange(poolAddress[i]).poolSummary().locked;
    }
    crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("setlockedvotes(uint256)", poolLockedvotesSUM));
    return poolLockedvotesSUM;
  }

  function SyncValue() internal Only_trusted_trigers returns(uint256,uint256,uint256){
    require(identifier==2,"identifier is not right, need be 2");
    identifier=0;
    bytes memory rawbalance = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("espacebalanceof(address)", bridgeeSpaceAddress));
    uint256 balanceinpool =  abi.decode(rawbalance, (uint256));
    bytes memory rawsum = crossSpaceCall.callEVM(bytes20(xCFXAddress), abi.encodeWithSignature("totalSupply()"));
    uint256 sum = abi.decode(rawsum, (uint256));
    uint256 balanceinbridge = balanceinpool + address(this).balance; //crossSpaceCall.mappedBalance(bridgeeSpaceAddress)
    uint256 pool_sum = poolAddress.length;
    uint256 poolvotes_sum;
    for(uint256 i=0;i<pool_sum;i++)
    {
        poolvotes_sum += IExchange(poolAddress[i]).poolSummary().totalvotes;
    }
    uint256 xCFXvalues =((balanceinbridge + poolvotes_sum.mul(CFX_VALUE_OF_ONE_VOTE) - Unstakebalanceinbridge) * 1 ether).div(sum);
    crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("setxCFXValue(uint256)", xCFXvalues));
    crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("handlexCFXadd()"));
    return (balanceinbridge,poolvotes_sum,xCFXvalues);
  }

  function withdrawVotes() internal Only_trusted_trigers returns(uint256,uint256){
    uint256 pool_sum = poolAddress.length;
    IExchange posPool;
    uint256 temp_unlocked;
    uint256 transferValue;
    for(uint256 i=0;i<pool_sum;i++)
    {
      posPool = IExchange(poolAddress[i]);
      IExchange.PoolSummary memory poolSummary = posPool.poolSummary();
      temp_unlocked = poolSummary.unlocked;
      if (temp_unlocked > 0) 
      {
        posPool.withdrawStake();
        // transfer to eSpacePool and call method
        transferValue = temp_unlocked * 1000 ether;
        crossSpaceCall.transferEVM{value: transferValue}(bytes20(eSpaceExroomAddress));
      }
    }
    return (temp_unlocked,transferValue);
  }

  fallback() external payable {}
  receive() external payable {}
  
}