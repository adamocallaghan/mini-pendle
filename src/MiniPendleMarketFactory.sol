// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MiniPendleMarket} from "./MiniPendleMarket.sol";

contract MiniPendleMarketFactory {
    event MarketCreated(address market, address pt, address yt, address underlying, uint256 expiry);

    mapping(address => mapping(uint256 => address)) public getMarket; 
    // underlying => expiry => market

    function createMarket(IERC20 underlying, uint256 expiry) external returns (address market) {
        require(getMarket[address(underlying)][expiry] == address(0), "exists");

        MiniPendleMarket m = new MiniPendleMarket(underlying, expiry);
        market = address(m);

        getMarket[address(underlying)][expiry] = market;

        emit MarketCreated(market, address(m.pt()), address(m.yt()), address(underlying), expiry);
    }
}