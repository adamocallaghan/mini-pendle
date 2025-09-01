// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PTToken} from "./PTToken.sol";
import {YTToken} from "./YTToken.sol";

/// @notice Minimal Pendle-like market: splits an underlying yield-bearing token
/// into PT (principal) and YT (yield) per-expiry. This is a small, audit-unfriendly
/// example for dev/testing — do NOT use in production without hardening.
contract MiniPendleMarket {
    IERC20 public immutable underlying; // e.g. aUSDC
    uint256 public immutable expiry;

    PTToken public immutable pt;
    YTToken public immutable yt;

    // total principal outstanding (face value owed to PT holders)
    uint256 public requiredPrincipal;

    // yield accounting accumulator (USDC units per 1 YT, fixed point 1e18)
    uint256 public yieldPerYTStored;

    // snapshot of underlying assets in USDC-equivalent at last accounting update
    uint256 public lastAssets;

    // per-user accounting for yield-per-YT already paid
    mapping(address => uint256) public userYieldPerYTPaid;
    // per-user claimable amount (in USDC underlying units)
    mapping(address => uint256) public userClaimable;

    constructor(IERC20 _underlying, uint256 _expiry) {
        underlying = _underlying;
        expiry = _expiry;

        // Deploy PT + YT tokens owned by THIS market
        pt = new PTToken("Principal Token", "PT", address(this));
        yt = new YTToken("Yield Token", "YT", address(this));

        // initialize lastAssets to current balance (likely 0)
        lastAssets = totalAssetsInUSDC();
    }

    // ---- Core flow ----
    //
    // NOTE: we explicitly call _updateAccounting() at the START of public actions
    // so we capture yield accrued up to that moment. We then do state changes
    // (transferIn, mint, burn, etc.) and adjust lastAssets to not treat deposits
    // as yield.

    /// @notice Deposit `amount` of the underlying (e.g., aUSDC) and receive PT+YT.
    /// @param amount underlying token units (e.g., aUSDC units)
    /// @param to recipient of PT & YT
    function deposit(uint256 amount, address to) external {
        // 1) capture yield up to now
        _updateAccounting();

        // 2) pull underlying from depositor into the market
        underlying.transferFrom(msg.sender, address(this), amount);

        // 3) record principal and mint PT+YT (1:1 face units)
        uint256 principalUnits = amount;
        requiredPrincipal += principalUnits;

        pt.mint(to, principalUnits);
        yt.mint(to, principalUnits);

        // 4) settle user's claimable state so they don't miss earned yield
        _settleUser(to);

        // 5) update lastAssets to include the new deposit so deposit isn't counted as yield
        lastAssets = totalAssetsInUSDC();
    }

    /// @notice Claim any accrued yield the caller has earned.
    /// @param to address to receive the underlying (USDC/aUSDC depending on implementation)
    function claimYield(address to) external {
        // capture yield up to now and update yieldPerYTStored
        _updateAccounting();

        // settle the caller to move new yield into userClaimable
        _settleUser(msg.sender);

        uint256 amount = userClaimable[msg.sender];
        require(amount > 0, "no yield");

        userClaimable[msg.sender] = 0;

        // pay out underlying (demo: transfer underlying token).
        // Note: in a real integration you'd redeem aUSDC -> USDC here.
        _payUnderlyingAsUSDC(to, amount);

        // update lastAssets to reflect funds removed (withdrawal reduces underlying balance)
        lastAssets = totalAssetsInUSDC();
    }

    /// @notice Redeem PT for principal after expiry.
    /// Burns PT and pays face-value principal.
    function redeemPT(uint256 ptAmount, address to) external {
        require(block.timestamp >= expiry, "not matured");

        // capture yield up to now (so YT holders can still claim accrued yield before PT redemption)
        _updateAccounting();

        // settle redeemer (in case they also hold YT)
        _settleUser(msg.sender);

        // burn PT and reduce required principal
        pt.burn(msg.sender, ptAmount);
        requiredPrincipal -= ptAmount;

        // pay the principal to redeemer
        _payUnderlyingAsUSDC(to, ptAmount);

        // update lastAssets to reflect assets outflow
        lastAssets = totalAssetsInUSDC();
    }

    /// @notice Optional: allow a holder to burn equal PT+YT to retrieve the underlying (recombine)
    function recombineAndWithdraw(uint256 faceAmount, address to) external {
        // capture yield up to now
        _updateAccounting();

        // settle sender for any pending yield before burning
        _settleUser(msg.sender);

        // burn both tokens
        pt.burn(msg.sender, faceAmount);
        yt.burn(msg.sender, faceAmount);

        // reduce required principal
        requiredPrincipal -= faceAmount;

        // transfer underlying equivalent (we assume 1 underlying unit per faceAmount)
        _payUnderlyingAsUSDC(to, faceAmount);

        // update lastAssets snapshot
        lastAssets = totalAssetsInUSDC();
    }

    // ---- Accounting helpers ----

    /// @dev Update accounting to capture asset growth since last snapshot.
    /// This only distributes the *new* accrued yield since lastAssets.
    function _updateAccounting() internal {
        uint256 assets = totalAssetsInUSDC();

        // if assets have grown since last snapshot, that's new yield to distribute
        if (assets > lastAssets) {
            uint256 accrued = assets - lastAssets;

            uint256 supplyYT = yt.totalSupply();
            if (supplyYT > 0 && accrued > 0) {
                // convert to per-YT accumulator (1e18 fixed point)
                yieldPerYTStored += (accrued * 1e18) / supplyYT;
            }
        }

        // always refresh snapshot (even on no-change)
        lastAssets = assets;
    }

    /// @dev Move accumulated yield from global accumulator into per-user claimable.
    /// Caller should run `_updateAccounting()` beforehand to ensure `yieldPerYTStored` is current.
    function _settleUser(address u) internal {
        uint256 paid = userYieldPerYTPaid[u];
        uint256 delta = yieldPerYTStored - paid;
        if (delta > 0) {
            uint256 balYT = yt.balanceOf(u);
            if (balYT > 0) {
                uint256 owed = (balYT * delta) / 1e18;
                userClaimable[u] += owed;
            }
            userYieldPerYTPaid[u] = yieldPerYTStored;
        }
    }

    // ---- View / low-level helpers ----

    /// @notice How much the contract's underlying holdings are worth in USDC-equivalent.
    /// For Aave aTokens this is simply balanceOf (aTokens rebalance their balances).
    function totalAssetsInUSDC() public view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    /// @dev Minimal payout helper. In a real system redeem aUSDC->USDC here if desired.
    function _payUnderlyingAsUSDC(address to, uint256 amount) internal {
        // For demo: transfer the underlying token directly.
        // Production: call Aave lendingPool.withdraw(USDC, amount, to) then transfer USDC.
        underlying.transfer(to, amount);
    }

    // ---- Admin / informational getters (optional) ----

    /// @notice Convenience: get current accrued yield (assets - requiredPrincipal).
    function accruedYield() external view returns (uint256) {
        uint256 assets = totalAssetsInUSDC();
        if (assets <= requiredPrincipal) return 0;
        return assets - requiredPrincipal;
    }
}
