// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YTToken is ERC20 {
    address public market;
    constructor(string memory name, string memory symbol, address _market)
        ERC20(name, symbol)
    {
        market = _market;
    }

    function mint(address to, uint256 amt) external {
        require(msg.sender == market, "not market");
        _mint(to, amt);
    }

    function burn(address from, uint256 amt) external {
        require(msg.sender == market, "not market");
        _burn(from, amt);
    }
}