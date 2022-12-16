//SPDX-License-Identifier: BUSL-1.1
// Licensor:            X-Dao.
// Licensed Work:       NUCLEON 1.0

pragma solidity 0.8.2;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../ICrossSpaceCall.sol";
import "../IExchange.sol";

///  @title CoreBridge_multipool is a bridge to connect Conflux POS pools and Exchange rooms 
///  @dev Contract should be deployed in conflux core space;
///  @dev This contract can set the user share ratio, system share ratio, 
///  @dev compound the interests
///  @notice Users cann't direct use this contract to participate Conflux PoS stake.
contract CoreBridge_multipool is Ownable, Initializable, ReentrancyGuard {
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

  // ============================ Modifiers ===============================

  modifier Only_trusted_trigers() {
    require(trusted_node_trigers[msg.sender],'trigers must be trusted');
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
  /// @notice Call this method when depoly the 1967 proxy contract
  function initialize(address crossSpaceCallAddress) public initializer{
    crossSpaceCall = CrossSpaceCall(crossSpaceCallAddress);
    poolUserShareRatio = 9000;
    CFX_COUNT_OF_ONE_VOTE = 1000;
    CFX_VALUE_OF_ONE_VOTE = 1000 ether;
  }
  /// @notice Add POS Pool Address
  /// @notice Only used by Owner
  /// @param poolAddr The address of POS Pool to be added
  function _addPoolAddress(address poolAddr) public onlyOwner {
    require(poolAddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    poolAddress.push(poolAddr);
    emit AddPoolAddress(msg.sender, poolAddr);
  }
  /// @notice Change POS Pool Address
  /// @notice Only used by Owner
  /// @param oldpoolAddress The address of POS Pool to be del
  /// @param newpoolAddress The address of POS Pool to be added
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
  /// @notice Del POS Pool Address
  /// @notice Only used by Owner
  /// @param oldpoolAddress The address of POS Pool to be del
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
  /// @notice Set eSpace Exchangeroom contract Address
  /// @notice Only used by Owner
  /// @param eSpaceExroomAddr The address of Exchangeroom contract, espace address 
  function _seteSpaceExroomAddress(address eSpaceExroomAddr) public onlyOwner {
    require(eSpaceExroomAddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    eSpaceExroomAddress = eSpaceExroomAddr;
    emit SeteSpaceExroomAddress(msg.sender, eSpaceExroomAddr);
  }
  /// @notice Set eSpace xCFX contract Address
  /// @notice Only used by Owner
  /// @param eSpacexCFXaddr The address of xCFX contract, espace address 
  function _seteSpacexCFXAddress(address eSpacexCFXaddr) public onlyOwner {
    require(eSpacexCFXaddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    xCFXAddress = eSpacexCFXaddr;
    emit SeteSpacexCFXAddress(msg.sender, eSpacexCFXaddr);
  }
  /// @notice Set eSpace bridge contract Address
  /// @notice Only used by Owner
  /// @param bridgeeSpaceAddr The address of bridge contract, espace address 
  function _seteSpacebridgeAddress(address bridgeeSpaceAddr) public onlyOwner {
    require(bridgeeSpaceAddr!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    bridgeeSpaceAddress = bridgeeSpaceAddr;
    emit SeteSpacebridgeAddress(msg.sender, bridgeeSpaceAddr);
  }
  /// @notice Set eSpace Service treasury contract Address
  /// @notice Only used by Owner
  /// @param servicetreasury The address of Service treasury contract, espace address 
  function _seteServicetreasuryAddress(address servicetreasury) public onlyOwner {
    require(servicetreasury!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    ServicetreasuryAddress = servicetreasury;
    emit SeteServicetreasuryAddress(msg.sender, servicetreasury);
  }
  /// @notice Set trustedtrigers Address
  /// @notice Only used by Owner
  /// @param triggersAddress The address of Service treasury contract, nomal address 
  /// @param state True or False
  function _settrustedtrigers(address triggersAddress,bool state) public onlyOwner {
    require(triggersAddress!=address(0x0000000000000000000000000000000000000000),'Can not be Zero adress');
    trusted_node_trigers[triggersAddress] = state;
    emit Settrustedtrigers(msg.sender, triggersAddress, state);
  }
  /// @notice Set Cfx Count Of One Vote
  /// @notice Only used by Owner
  /// @param count Vote cfx count, unit is cfx
  function _setCfxCountOfOneVote(uint256 count) public onlyOwner {
    CFX_COUNT_OF_ONE_VOTE = count;
    CFX_VALUE_OF_ONE_VOTE = count * 1 ether;
    emit SetCfxCountOfOneVote(msg.sender, CFX_COUNT_OF_ONE_VOTE);
  }
  /// @notice Set Pool User ShareRatio
  /// @notice Only used by Owner
  /// @param ratio ratio should be 1-10000
  function _setPoolUserShareRatio(uint256 ratio) public onlyOwner {
    require(ratio > 0 && ratio <= RATIO_BASE, "ratio should be 1-10000");
    poolUserShareRatio = ratio;
    emit SetPoolUserShareRatio(msg.sender, ratio);
  }
  /// @notice Get triger state
  /// @param _Address the triger address to be query
  function gettrigerstate(address _Address) public view returns(bool){
    return trusted_node_trigers[_Address];
  }
  /// @notice Get Pool Address array
  function getPoolAddress() public view returns (address[] memory ) {
    return poolAddress;
  }
  /// @notice clear the states
  /// @notice Only used by Owner
  function _clearTheStates() public onlyOwner {
    identifier = 0;
    emit ClearTheStates(msg.sender, identifier);
  }

  //---------------------bridge method-------------------------------------
  /// @notice syncALLwork is triggered regularly by triger
  /// @notice Only used by trusted triger
  /// @return infos all needed infos, uint256[11]
  function syncALLwork() public Only_trusted_trigers returns(uint256[11] memory infos){
    infos[0] = claimInterests();
    (infos[1],infos[2]) = campounds();
    (infos[3],infos[4]) = handleUnstake();
    infos[5] = handleLockedvotesSUM();
    (infos[6],infos[7],infos[8]) = SyncValue();
    (infos[9],infos[10]) = withdrawVotes();
    return infos;
  }
  /// @notice Used to claim POS pool interests
  /// @notice Only used by trusted triger
  /// @return systemCFXInterestsTemp The interests need be distribute to system now
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
  /// @notice Used to campounds and get the platform interests
  /// @notice Only used by trusted triger
  /// @return xCFXminted all of the xCFX minted this time
  /// @return votePower all of the votePower added this time
  function campounds() internal Only_trusted_trigers  returns(uint256,uint256){
    require(identifier==0,"identifier is not right, need be 0");
    identifier=1;

    uint256 toxCFX = systemCFXInterestsTemp;
    uint256 xCFXminted;
    systemCFXInterestsTemp = 0;
    if(toxCFX > 0){
      bytes memory rawxCFX = crossSpaceCall.callEVM{value: toxCFX}(bytes20(eSpaceExroomAddress), 
                                            abi.encodeWithSignature("handleCFXexchangeXCFX()"));
      xCFXminted =  abi.decode(rawxCFX, (uint256));
    }
    
    bytes memory rawbalance = crossSpaceCall.callEVM(bytes20(eSpaceExroomAddress), abi.encodeWithSignature("espacebalanceof(address)", bridgeeSpaceAddress));
    uint256 balanceinpool =  abi.decode(rawbalance, (uint256));
    if(balanceinpool > 0){
      crossSpaceCall.withdrawFromMapped(balanceinpool);
    }
    uint64 votePower = uint64(address(this).balance.div(CFX_VALUE_OF_ONE_VOTE));
    if (votePower > 0){
      IExchange(poolAddress[PosIDinuse]).increaseStake{value: votePower*CFX_VALUE_OF_ONE_VOTE}(votePower);
    }
    return (xCFXminted, votePower);
  }
  /// @notice Used to handle Unstake CFXs
  /// @notice Only used by trusted triger
  /// @return available poolSummary.totalvotes
  /// @return Unstakebalanceinbridge a para to balance unstake votes and CFXs
  function handleUnstake() internal Only_trusted_trigers nonReentrant returns(uint256,uint256){
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
    Unstakebalanceinbridge += receivedUnstakeCFXs;
    uint256 unstakeSubVotes;
    if(Unstakebalanceinbridge > CFX_VALUE_OF_ONE_VOTE){
      available -= Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE);
      unstakeSubVotes = Unstakebalanceinbridge.div(CFX_VALUE_OF_ONE_VOTE);
      Unstakebalanceinbridge -= unstakeSubVotes.mul(CFX_VALUE_OF_ONE_VOTE);
      posPool.decreaseStake(uint64(unstakeSubVotes));
    }

    return (available,Unstakebalanceinbridge);
  }
  /// @notice Used to handle Locked votes SUM
  /// @notice Only used by trusted triger
  /// @return poolLockedvotesSUM current POS pool locked votes SUM
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
  /// @notice Used to Sync xCFX Value
  /// @notice Only used by trusted triger
  /// @return balanceinbridge balance in this bridge
  /// @return poolvotes_sum pool votes sum
  /// @return xCFXvalues New xCFX values
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
  /// @notice Used to withdraw Votes to eSpace Exchangeroom, Convenient for users to extract
  /// @notice Only used by trusted triger
  /// @return temp_unlocked temp_unlocked in POS pool
  /// @return transferValue Values transfer to Exchangeroom
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