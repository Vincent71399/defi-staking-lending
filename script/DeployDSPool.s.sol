// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
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

        console.log("Deployed to ", block.chainid);
        console.log("DSPool at ", address(dsPool));
        console.log("DSCoin at ", address(dsc));

        for(uint i = 0; i < helperConfig.getTokens().length; i++) {
            console.log("Token", i, "at", helperConfig.getTokens()[i]);
            console.log("Price Feed", i, "at", helperConfig.getPriceFeeds()[i]);
        }
    }
}
