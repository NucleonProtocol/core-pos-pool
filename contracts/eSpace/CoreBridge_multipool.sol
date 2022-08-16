//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../ICrossSpaceCall.sol";
import "../IExchange.sol";
///
///  @title CoreBridge_multipool is a bridge to connect Conflux POS pools and Exchange rooms ,deployed in core;
///  @dev This contract set the user share ratio, system share ratio, 
///  @dev compound the interests
///  @notice Users cann't direct use this contract to participate Conflux PoS stake.
///
contract CoreBridge_multipool is Ownable {
  using SafeMath for uint256;
  CrossSpaceCall internal crossSpaceCall;

  uint256 private constant RATIO_BASE = 10000;
  // ratio shared by user: 1-10000
  uint256 public poolUserShareRatio = 9000;
  uint256 CFX_COUNT_OF_ONE_VOTE = 1000;
  uint256 CFX_VALUE_OF_ONE_VOTE = 1000 ether;

  address[] public poolAddress;               // can use many pools, so here is an array
  uint256   public pos_id_in_use;             // pos pool in use
  address   public xCFXAddress;               // xCFX addr in espace 
  address   public eSpaceExroomAddress;       //Exchange room Address in espace
  address   public CoreExroomAddress;         //Exchange room Address in core
  address   public ServicetreasuryAddress;    //Service treasury Address in core
  uint256   private system_cfxinterests_temp; //pools cfx interests in temporary
  uint256   public identifier;                //Execution number , should be private when use in main net
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

  modifier Only_in_order() {
    identifier += 1;
    _;
    if(identifier==5) identifier = 0;
  }
  modifier Only_trusted_trigers() {
    require(trusted_node_trigers[msg.sender]==true,'trigers must be trusted');
    _;
  }
  // ======================== Methods for core pos pools settings =========================

  function initialize() public {
    crossSpaceCall = CrossSpaceCall(0x0888000000000000000000000000000000000006);
  }

  function addPoolAddress(address _poolAddress) public onlyOwner {
    poolAddress.push(_poolAddress);
  }

  function changePoolAddress(address _oldpoolAddress,address _newpoolAddress) public onlyOwner {
    uint256 pool_sum = poolAddress.length;
    for(uint256 i=0;i<pool_sum;i++)
    {
        if(poolAddress[i]==_oldpoolAddress)
        {
            poolAddress[i]=_newpoolAddress;
        }
    }
  }
  function delePoolAddress(address _oldpoolAddress) public onlyOwner {
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

  function seteSpaceExroomAddress(address _eSpaceExroomAddress) public onlyOwner {
    eSpaceExroomAddress = _eSpaceExroomAddress;
  }
  function settrusted_trigers(address _eSpaceExroomAddress,bool state) public onlyOwner {
    trusted_node_trigers[_eSpaceExroomAddress] = state;
  }

  function get_triger_state(address _eSpaceExroomAddress) public view onlyOwner returns(bool){
    return trusted_node_trigers[_eSpaceExroomAddress];
  }
  function getPoolAddress() public view returns (address[] memory ) {
    return poolAddress;
  }
  
  function ePoolAddrB20() public view returns (bytes20) {
    return bytes20(eSpaceExroomAddress);
  }
  //-----------------espace method-------------------------------------------------------------------------------------

  function queryespacexCFXincrease() public returns (uint256) {
    bytes memory rawCrossingVotes = crossSpaceCall.callEVM(ePoolAddrB20(), abi.encodeWithSignature("crossingVotes()"));
    return abi.decode(rawCrossingVotes, (uint256));
  }

  function queryUnstakeLen() public returns (uint256) {
    bytes memory rawUnstakeLen = crossSpaceCall.callEVM(ePoolAddrB20(), abi.encodeWithSignature("unstakeLen()"));
    return abi.decode(rawUnstakeLen, (uint256));
  }

  //-----------------core pool method-------------------------------------------------------------------------------------
  function queryInterest(uint256 _num) public view returns (uint256) {
    IExchange posPool = IExchange(poolAddress[_num]);
    uint256 interest = posPool.temp_Interest();
    return interest;
  }

  //-----------------bridge method-------------------------------------------------------------------------------------
  function syncALLwork() public onlyOwner Only_trusted_trigers {
    claimInterests();

    campounds();
    SyncValue();

    handleUnstake();
    withdrawVotes();
  }

  function claimInterests() public Only_in_order Only_trusted_trigers {
    require(identifier==1,"identifier is not right, need be 1");
    require(system_cfxinterests_temp==0,'system_cfxinterests not cleaned');
    uint256 pool_sum = poolAddress.length;
    IExchange posPool;
    uint256 interest;
    for(uint256 i=0;i<pool_sum;i++)
    {
      posPool = IExchange(poolAddress[i]);
      //interest = posPool.userInterest(address(this));
      if (interest > 0) {
        interest = posPool.claimAllInterest();
        system_cfxinterests_temp += interest.mul(poolUserShareRatio).div(RATIO_BASE);
        crossSpaceCall.transferEVM{value: interest}(ePoolAddrB20());
      }
    }
  }
  function campounds() public Only_in_order Only_trusted_trigers {
    require(identifier==2,"identifier is not right, need be 2");
    require(system_cfxinterests_temp!=0,'system_cfxinterests is cleaned');
    uint256 toxCFX = system_cfxinterests_temp;
    system_cfxinterests_temp == 0;
    crossSpaceCall.callEVM{value: toxCFX}(ePoolAddrB20(), abi.encodeWithSignature("CFX_exchange_XCFX()"));
    uint256 balanceinpool = crossSpaceCall.mappedBalance(eSpaceExroomAddress);
    uint64 votePower = uint64(balanceinpool.div(CFX_VALUE_OF_ONE_VOTE));
    if (votePower > 0){
      IExchange(poolAddress[pos_id_in_use]).increaseStake(votePower);
    }
  }

  function SyncValue() public Only_in_order Only_trusted_trigers {
    require(identifier==3,"identifier is not right, need be 3");
    uint256 sum = IERC20(xCFXAddress).totalSupply() ; 
    uint256 balanceinpool = crossSpaceCall.mappedBalance(eSpaceExroomAddress);
    uint256 pool_sum = poolAddress.length;
    uint256 SUMvotes;
    for(uint256 i=0;i<pool_sum;i++)
    {
        SUMvotes += IExchange(poolAddress[i]).poolSummary().totalvotes;
    }
    uint256 xCFXvalues =balanceinpool.add(SUMvotes.mul(CFX_VALUE_OF_ONE_VOTE)).div(sum);
    crossSpaceCall.callEVM(ePoolAddrB20(), abi.encodeWithSignature("setxCFXValue(uint256)", xCFXvalues));
  }

  function handleUnstake() public Only_in_order Only_trusted_trigers {
    require(identifier==4,"identifier is not right, need be 4");
    uint256 unstakeLen = queryUnstakeLen();
    if (unstakeLen == 0) return;
    if (unstakeLen > 50) unstakeLen = 50; // max 50 unstakes per call
    IExchange posPool = IExchange(poolAddress[pos_id_in_use]);
    IExchange.PoolSummary memory poolSummary = posPool.poolSummary();
    uint256 available = poolSummary.totalvotes;
    bytes memory rawFirstUnstakeVotes ;
    uint256 firstUnstakeVotes;
    if (available == 0) return;
    for(uint256 i = 0; i < unstakeLen; i++) {
      rawFirstUnstakeVotes = crossSpaceCall.callEVM(ePoolAddrB20(), abi.encodeWithSignature("firstUnstakeVotes()"));
      firstUnstakeVotes = abi.decode(rawFirstUnstakeVotes, (uint256));
      if (firstUnstakeVotes == 0) break;
      if (firstUnstakeVotes > available) break;
      posPool.decreaseStake(uint64(firstUnstakeVotes));
      crossSpaceCall.callEVM(ePoolAddrB20(), abi.encodeWithSignature("handleUnstakeTask()"));
      available -= firstUnstakeVotes;
    }
  }

  function withdrawVotes() public Only_in_order Only_trusted_trigers {
    require(identifier==5,"identifier is not right, need be 5");
    uint256 pool_sum = poolAddress.length;
    IExchange posPool;
    uint256 temp_unlocked;
    //uint256 transferValue;
    for(uint256 i=0;i<pool_sum;i++)
    {
      posPool = IExchange(poolAddress[i]);
      IExchange.PoolSummary memory poolSummary = posPool.poolSummary();
      temp_unlocked = poolSummary.unlocked;
      if (temp_unlocked > 0) 
      {
        posPool.withdrawStake();
        // transfer to eSpacePool and call method
        //transferValue = temp_unlocked * 1000 ether;
        //crossSpaceCall.callEVM{value: transferValue}(ePoolAddrB20(), abi.encodeWithSignature("handleUnlockedIncrease(uint256)", userSummary.unlocked));
      }
    }
  }

  function callEVM(address addr, bytes calldata data) public Only_trusted_trigers {
    crossSpaceCall.callEVM(bytes20(addr), data);
  }

  fallback() external payable {}
  receive() external payable {}
}