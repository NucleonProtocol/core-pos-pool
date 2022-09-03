//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
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
  uint256 public poolUserShareRatio = 9000;
  uint256 CFX_COUNT_OF_ONE_VOTE = 1000;
  uint256 CFX_VALUE_OF_ONE_VOTE = 1000 ether;

  address[] public poolAddress;               // can use many pools, so here is an array
  uint256   public PosIDinuse;             // pos pool in use
  //eSpace address
  address   public xCFXAddress;               // xCFX addr in espace 
  address   public eSpaceExroomAddress;       //Exchange room Address in espace
  address   public bridgeeSpaceAddress;       //address of bridge in espace
  //Core Space address
  address   public CoreExroomAddress;         //Exchange room Address in core
  address   public ServicetreasuryAddress;    //Service treasury Address in core
  uint256   public systemCFXInterestsTemp; //pools cfx interests in temporary
  //
  //uint256   public identifier;                //Execution number , should be private when use in main net
  mapping(address=>bool) trusted_node_trigers;//     
  // ======================== Struct definitions =========================
  struct PoolSummary {
    uint256 xCFXSUM;             // xCFX SUM (1 ether xCFX === 1 e18)
    uint256 totalInterest;       // PoS pool interests for all xCFX
    uint256 CFXbalances;         // CFX balances in bridge
    uint256 historical_Interest ;// total historical interest of whole pools
  }

  constructor () {
    initialize();
  }
  // ======================== Modifiers =========================

  // modifier Only_in_order() {
  //   identifier += 1;
  //   _;
  //   if(identifier==5) identifier = 0;
  // }
  modifier Only_trusted_trigers() {
    require(trusted_node_trigers[msg.sender]==true,'trigers must be trusted');
    _;
  }
  // ======================== Methods for core pos pools settings =========================

  function initialize() public initializer{
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
    poolUserShareRatio = 9000;
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  }

  function _addPoolAddress(address _poolAddress) public onlyOwner {
    poolAddress.push(_poolAddress);
  }

  function _changePoolAddress(address _oldpoolAddress,address _newpoolAddress) public onlyOwner {
    uint256 pool_sum = poolAddress.length;
    for(uint256 i=0;i<pool_sum;i++)
    {
        if(poolAddress[i]==_oldpoolAddress)
        {
            poolAddress[i]=_newpoolAddress;
        }
    }
  }
  function _delePoolAddress(address _oldpoolAddress) public onlyOwner {
    uint256 pool_sum = poolAddress.length;
    for(uint256 i=0;i<pool_sum;i++)
    {
        if(poolAddress[i]==_oldpoolAddress)
        {
            poolAddress[i]= poolAddress[pool_sum-1];
            poolAddress.pop();
        }
    }
  }

  function _seteSpaceExroomAddress(address _eSpaceExroomAddress) public onlyOwner {
    eSpaceExroomAddress = _eSpaceExroomAddress;
  }
  function _seteSpacexCFXAddress(address _eSpacexCFXaddr) public onlyOwner {
    xCFXAddress = _eSpacexCFXaddr;
  }
  function _seteSpacebridgeAddress(address _bridgeeSpaceAddress) public onlyOwner {
    bridgeeSpaceAddress = _bridgeeSpaceAddress;
  }
  function _settrustedtrigers(address _Address,bool state) public onlyOwner {
    trusted_node_trigers[_Address] = state;
  }

  function gettrigerstate(address _Address) public view returns(bool){
    return trusted_node_trigers[_Address];
  }
  function getPoolAddress() public view returns (address[] memory ) {
    return poolAddress;
  }

  /// @param count Vote cfx count, unit is cfx
  function _setCfxCountOfOneVote(uint256 count) public onlyOwner {
    CFX_COUNT_OF_ONE_VOTE = count;
    CFX_VALUE_OF_ONE_VOTE = count * 1 ether;
  }

  function _setPoolUserShareRatio(uint64 ratio) public onlyOwner {
    require(ratio > 0 && ratio <= RATIO_BASE, "ratio should be 1-10000");
    poolUserShareRatio = ratio;
  }

  //-----------------espace method-------------------------------------------------------------------------------------

  function queryespacexCFXincrease() public returns (uint256) {
    bytes memory rawCrossingVotes = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("crossingVotes()"));
    return abi.decode(rawCrossingVotes, (uint256));
  }

  function queryUnstakeLen() public returns (uint256) {
    bytes memory rawUnstakeLen = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("unstakeLen()"));
    return abi.decode(rawUnstakeLen, (uint256));
  }

  //-----------------core pool method-------------------------------------------------------------------------------------
  function queryInterest(uint256 _num) public view returns (uint256) {
    IExchange posPool = IExchange(poolAddress[_num]);
    uint256 interest = posPool.temp_Interest();
    return interest;
  }

  //-----------------bridge method-------------------------------------------------------------------------------------
  function syncALLwork() public Only_trusted_trigers {
    claimInterests();

    campounds();
    SyncValue();

    handleUnstake();
    withdrawVotes();
  }

  function claimInterests() public Only_trusted_trigers returns(uint256){
    //require(identifier==1,"identifier is not right, need be 1");
    require(systemCFXInterestsTemp==0,'system_cfxinterests not cleaned');
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
    systemCFXInterestsTemp = interest.mul(RATIO_BASE-poolUserShareRatio).div(RATIO_BASE);
    //require(systemCFXInterestsTemp > 0,"interests in all pool is zero");
    return systemCFXInterestsTemp;
  }
  function campounds() public Only_trusted_trigers  returns(uint256){
    require(identifier==0,"identifier is not right, need be 0");
    identifier=1;
    // if(systemCFXInterestsTemp==0){return 0;}
    //require(systemCFXInterestsTemp!=0,'system_cfxinterests is cleaned');
    uint256 toxCFX = systemCFXInterestsTemp;
    systemCFXInterestsTemp = 0;
    if(toxCFX>0){
      crossSpaceCall.callEVM{value: toxCFX}(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("CFX_exchange_XCFX()"));
    }
    
    bytes memory rawbalance = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("espacebalanceof(address)", bridgeeSpaceAddress));
    uint256 balanceinpool =  abi.decode(rawbalance, (uint256));
    crossSpaceCall.withdrawFromMapped(balanceinpool);
    uint64 votePower = uint64(address(this).balance.div(CFX_VALUE_OF_ONE_VOTE));
    if (votePower > 0){
      IExchange(poolAddress[PosIDinuse]).increaseStake{value: votePower*CFX_VALUE_OF_ONE_VOTE}(votePower);
    }
    return votePower;
  }

  function SyncValue() public Only_trusted_trigers returns(uint256){
    require(identifier==1,"identifier is not right, need be 1");
    identifier=0;
    
    bytes memory rawsum = crossSpaceCall.callEVM(bytes20(xCFXAddress), abi.encodeWithSignature("totalSupply()"));
    uint256 sum = abi.decode(rawsum, (uint256));
    uint256 balanceinbridge =  address(this).balance;
    uint256 pool_sum = poolAddress.length;
    uint256 poolvotes_sum;
    //uint256 poolLockedvotesSUM;
    for(uint256 i=0;i<pool_sum;i++)
    {
        poolvotes_sum += IExchange(poolAddress[i]).poolSummary().totalvotes
                      +  IExchange(poolAddress[i]).poolSummary().unlocking
                      +  IExchange(poolAddress[i]).poolSummary().unlocked;
        //poolLockedvotesSUM += IExchange(poolAddress[i]).poolSummary().locked;
    }
    uint256 xCFXvalues =((balanceinbridge+poolvotes_sum.mul(CFX_VALUE_OF_ONE_VOTE)) * 1 ether ).div(sum);
    crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("setxCFXValue(uint256)", xCFXvalues));
    crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("handlexCFXadd()"));
    //crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("setlockedvotes(uint256)", poolLockedvotesSUM));
    return xCFXvalues;
  }
  uint256 Unstakebalanceinbridge;
  function handleUnstake() public Only_trusted_trigers {
    //require(identifier==4,"identifier is not right, need be 4");
    uint256 unstakeLen = queryUnstakeLen();
    if (unstakeLen == 0) return;
    if (unstakeLen > 5000) unstakeLen = 5000; // max 1000 unstakes per call
    IExchange posPool = IExchange(poolAddress[PosIDinuse]);
    IExchange.PoolSummary memory poolSummary = posPool.poolSummary();
    uint256 available = poolSummary.totalvotes.mul(CFX_VALUE_OF_ONE_VOTE);
    bytes memory rawFirstUnstakeVotes ;
    uint256 firstUnstakeVotes;
    if (available == 0) return;
    for(uint256 i = 0; i < unstakeLen; i++) {
      rawFirstUnstakeVotes = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("firstUnstakeVotes()"));
      firstUnstakeVotes = abi.decode(rawFirstUnstakeVotes, (uint256));
      if (firstUnstakeVotes == 0) break;
      if (firstUnstakeVotes > available) break;
      Unstakebalanceinbridge += firstUnstakeVotes;

      //posPool.decreaseStake(uint64(firstUnstakeVotes));
      crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("handleUnstakeTask()"));
      //available -= firstUnstakeVotes;
    }
    if(Unstakebalanceinbridge > CFX_VALUE_OF_ONE_VOTE){
      posPool.decreaseStake(uint64(Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE)));
      available -= Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE);
      Unstakebalanceinbridge -= Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE).mul(CFX_VALUE_OF_ONE_VOTE);
    }
    uint256 pool_sum = poolAddress.length;
    uint256 poolLockedvotesSUM;
    for(uint256 i=0;i<pool_sum;i++)
    {
        poolLockedvotesSUM += IExchange(poolAddress[i]).poolSummary().locked;
    }
    crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("setlockedvotes(uint256)", poolLockedvotesSUM));
  }

  function withdrawVotes() public Only_trusted_trigers {
    //require(identifier==5,"identifier is not right, need be 5");
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
        // crossSpaceCall.callEVM{value: transferValue}(ePoolAddrB20(), abi.encodeWithSignature("handleUnlockedIncrease(uint256)", userSummary.unlocked));
      }
    }
  }

  function callEVM(address addr, bytes calldata data) internal Only_trusted_trigers {
    crossSpaceCall.callEVM(bytes20(addr), data);
  }

  fallback() external payable {}
  receive() external payable {}
  uint256 identifier;
  //--------------------------------------temp-----------------------------------------------
   //function identifier_test(uint256 _identifier) public onlyOwner {identifier=_identifier; }
   //function systemCFXInterestsTemp_set(uint256 _i) public onlyOwner {systemCFXInterestsTemp=_i; }
  
}