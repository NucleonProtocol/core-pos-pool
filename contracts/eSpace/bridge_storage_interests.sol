//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
//import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../ICrossSpaceCall.sol";
import "../IPoSPool.sol";

contract interests_storage is Ownable {
  address _bridgeAddress;
  address _interestAddress;
  modifier onlyBridge() {
    require(msg.sender == _bridgeAddress, "Only bridge is allowed");
    _;
  }
  
  function tranferto(address _addr) payable external onlyBridge{
    address payable receiver = payable(_interestAddress);
    receiver.transfer(msg.value);

  }
  function setbridge(address _addr) public onlyOwner{
    _bridgeAddress = _addr;
  }
  function setinterest(address _addr) public onlyOwner{
    _interestAddress = _addr;
  }
  fallback() external payable {}
  receive() external payable {}
}