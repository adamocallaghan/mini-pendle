// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/MiniPendleMarketFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployScript is Script {
    function run() external {

        vm.createSelectFork("monad-testnet");

        vm.startBroadcast();

        // Deploy Factory
        MiniPendleMarketFactory factory = new MiniPendleMarketFactory();
        console.log("Factory deployed at: ", address(factory));

        // Example params for first market
        address underlying = 0x0000000000000000000000000000000000000000; // replace with real aUSDC/lending receipt token
        uint256 maturity = block.timestamp + 90 days;

        address market = factory.createMarket(IERC20(underlying), maturity);
        console.log("First market deployed at:", market);

        vm.stopBroadcast();
    }
}
