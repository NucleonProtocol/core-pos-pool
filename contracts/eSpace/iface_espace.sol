pragma solidity ^0.8.2;

interface XCFXExchange{
    function addTokens(address _to, uint256 _value) external;
    function burnTokens(address account, uint256 amount) external;
    function balanceOf(address account) external view returns(uint256);
    function totalSupply() external view returns(uint256);
}
interface XVIPI{
    function tokensOf(address account) external view returns (uint256[] memory _tokens);
    function Maxlevelof(address account) external view returns (uint256 level);
}
