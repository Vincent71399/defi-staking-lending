// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DSPool} from "../src/DSPool.sol";
import {DSCoin} from "../src/DSCoin.sol";

contract DeployDSPool is Script {
    function run() external returns (DSPool dsPool, DSCoin dsc, HelperConfig helperConfig) {
        helperConfig = new HelperConfig(); // This comes with our mocks!

        vm.startBroadcast();
        dsc = new DSCoin();
        dsPool = new DSPool(helperConfig.getTokens(), helperConfig.getPriceFeeds(), address(dsc));
        dsc.transferOwnership(address(dsPool));
        vm.stopBroadcast();
    }
}
