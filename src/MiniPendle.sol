// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PTToken} from "./PTToken.sol";
import {YTToken} from "./YTToken.sol";

contract MiniPendleMarket {
    IERC20 public underlying;
    PTToken public pt;
    YTToken public yt;
    uint256 public expiry;

    constructor(IERC20 _underlying, uint256 _expiry) {
        underlying = _underlying;
        expiry = _expiry;

        // Deploy fresh PT and YT tokens tied to THIS market
        pt = new PTToken("Principal Token", "PT", address(this));
        yt = new YTToken("Yield Token", "YT", address(this));
    }

    // Then you just call pt.mint(), yt.mint() inside your logic
}
