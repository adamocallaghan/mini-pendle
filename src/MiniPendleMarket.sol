// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PTToken} from "./PTToken.sol";
import {YTToken} from "./YTToken.sol";

contract MiniPendleMarket {
    IERC20 public immutable underlying; // e.g. aUSDC
    uint256 public immutable expiry;

    PTToken public immutable pt;
    YTToken public immutable yt;

    uint256 public requiredPrincipal; // face value owed to PT holders
    uint256 public yieldPerYTStored; // reward accounting accumulator

    mapping(address => uint256) public userYieldPerYTPaid;
    mapping(address => uint256) public userClaimable;

    constructor(IERC20 _underlying, uint256 _expiry) {
        underlying = _underlying;
        expiry = _expiry;

        // Deploy PT + YT tokens owned by THIS market
        pt = new PTToken("Principal Token", "PT", address(this));
        yt = new YTToken("Yield Token", "YT", address(this));
    }

    // ---- Core flow ----

    function deposit(uint256 amount, address to) external update {
        underlying.transferFrom(msg.sender, address(this), amount);

        // Assume 1 underlying = 1 USDC unit (if aUSDC, it's ~1:1)
        uint256 principalUnits = amount;
        requiredPrincipal += principalUnits;

        pt.mint(to, principalUnits);
        yt.mint(to, principalUnits);

        _settleUser(to);
    }

    function claimYield(address to) external update {
        _settleUser(msg.sender);
        uint256 amount = userClaimable[msg.sender];
        userClaimable[msg.sender] = 0;
        _payUnderlyingAsUSDC(to, amount);
    }

    function redeemPT(uint256 ptAmount, address to) external {
        require(block.timestamp >= expiry, "not matured");
        pt.burn(msg.sender, ptAmount);
        requiredPrincipal -= ptAmount;
        _payUnderlyingAsUSDC(to, ptAmount);
    }

    // ---- Accounting ----

    // update:
    // - checks if yield has accrued & updates 'yieldPerYTStored' if it has
    //
    // example:
    // - 100 aUSDC is deposited (aUSDC.balanceOf(this) == 100)
    // - 10 aUSDC yield has accrued
    // - 110 aUSDC in total assets (aUSDC.balanceOf(this) == 110)
    // - aUSDC is always 1:1 with USDC
    // 
    // claims:
    // - PT (100 minted): $100 (we always hold onto this to make sure PT holders can claim at expiry)
    // - YT (100 minted): $10 / 100 = $0.1 yieldPerYTStored
    //
    modifier update() {
        uint256 assets = totalAssetsInUSDC();
        uint256 principal = requiredPrincipal;
        if (assets > principal) {
            uint256 newYield = assets - principal;
            uint256 supplyYT = yt.totalSupply();
            if (supplyYT > 0 && newYield > 0) {
                yieldPerYTStored += (newYield * 1e18) / supplyYT;
            }
        }
        _;
    }

    // _settleUser:
    // - checks if the user has any outstanding yield
    // - allows them to claim outstanding (via claim func)
    // - resets their yield paid out to the current yield per YT
    // - that way any delta next _settleUser call will be settled too
    function _settleUser(address u) internal {
        uint256 delta = yieldPerYTStored - userYieldPerYTPaid[u];
        if (delta > 0) {
            uint256 owed = (yt.balanceOf(u) * delta) / 1e18;
            userClaimable[u] += owed;
            userYieldPerYTPaid[u] = yieldPerYTStored;
        }
    }

    // ---- Helpers ----

    function totalAssetsInUSDC() public view returns (uint256) {
        // For aUSDC, 1 aUSDC ≈ 1 USDC redeemable
        return underlying.balanceOf(address(this));
    }

    function _payUnderlyingAsUSDC(address to, uint256 amount) internal {
        // For demo: just transfer aUSDC directly
        // For realism: redeem aUSDC -> USDC and send that
        underlying.transfer(to, amount);
    }
}
