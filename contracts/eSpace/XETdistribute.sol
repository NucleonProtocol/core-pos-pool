//SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.2;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract XETdistribute is Ownable{
    address xpool_addr;
    address XET_address;
    address Storage_room_addr;
    using SafeMath for uint256;

    modifier only_xpool() {
        require(msg.sender == xpool_addr, "Only xpool use");
        _;
    }

    function set_useful_addrs(address _xpool,address _XET, address _Sto) public onlyOwner returns (address) {
        xpool_addr = _xpool;
        XET_address = _XET;
        Storage_room_addr = _Sto;
    }
    function get_useful_addrs() external view returns (address,address,address) {
        //require(_address==msg.sender,'1');
        return (xpool_addr,XET_address,Storage_room_addr);
    }

    function estimate_in(uint256 _msgvalue) public view returns(uint256){
        uint256 temp_XET_num = ERC20(XET_address).balanceOf(address(this));
        if (temp_XET_num > 200000 ether) {
            temp_XET_num = 200000 ether;
            //ERC20(XET_address).transfer(Storage_room_addr, temp_XET_num - 200000 ether);
        }
        uint256 temp_XET_stage = temp_XET_num-temp_XET_num.div(10000 ether).mul(10000 ether);
        uint256 totalstage = (temp_XET_stage + _msgvalue).div(10000 ether);
        uint256 XET_num_out;
        uint256 temp_value;
        uint256 temp_value2;
        if(totalstage>0) {
            temp_value = 10000 ether - temp_XET_stage.mul(10000 ether);
            XET_num_out += temp_value.div(10**((200000 ether - temp_XET_num - XET_num_out).div(10000 ether)));
        }
        else{
            XET_num_out += _msgvalue.div(10**((200000 ether - temp_XET_num - XET_num_out).div(10000 ether)));
            return XET_num_out;
        }
        for (uint256 i = 0; i <= totalstage; i++) {
            if(i<totalstage) {
                temp_value2 = 10000 ether;
                XET_num_out += temp_value2.div(10**((200000 ether - temp_XET_num - XET_num_out).div(10000 ether)));
                }
            if(i==totalstage) {
                temp_value2 = _msgvalue - temp_XET_stage - (totalstage-1).mul(10000 ether);
                XET_num_out += temp_value2.div(10**((200000 ether - temp_XET_num - XET_num_out).div(10000 ether)));
                }
        }
        if (temp_XET_num > XET_num_out) {
            return XET_num_out;
            //ERC20(XET_address).transfer(_address, XET_num_out);
        } else if (temp_XET_num > 0) {
            return temp_XET_num;
            //ERC20(XET_address).transfer(_address, temp_XET_num);
        }
    }

    function distribute_in(address _address, uint256 _msgvalue)
        external
        only_xpool
    {
        uint256 temp_XET_num = ERC20(XET_address).balanceOf(address(this));
        if (temp_XET_num > 200000 ether) {
            ERC20(XET_address).transfer(Storage_room_addr, temp_XET_num - 200000 ether);
        }
        ERC20(XET_address).transfer(_address, estimate_in(_msgvalue));
    }

    function estimate_out(uint256 _msgvalue) public view returns(uint256)
    {
        uint256 temp_XET_num = ERC20(XET_address).balanceOf(address(this));
        uint256 XET_num_out = _msgvalue.div(100);
        if (temp_XET_num > XET_num_out) {
            return XET_num_out;
            //ERC20(XET_address).transfer(_address, XET_num_out);
        } else if (temp_XET_num > 0) {
            return temp_XET_num;
            //ERC20(XET_address).transfer(_address, temp_XET_num);
        }
    }
    function distribute_out(address _address, uint256 _msgvalue)
        external
        only_xpool
    {
        ERC20(XET_address).transfer(_address, estimate_out(_msgvalue));
    }
}
