// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {OracleLib} from "../src/libraries/OracleLib.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract HelperConfigAndOracleLib is Test {
    HelperConfig internal helperConfig;

    constructor() {
        helperConfig = new HelperConfig();
    }

    function testReadPrice() public view {
        address[] memory priceFeeds = helperConfig.getPriceFeeds();
        string[] memory names = helperConfig.getTokenNames();
        for (uint256 i = 0; i < priceFeeds.length; i++) {
            (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound,
                uint8 decimals
            ) = OracleLib.getPrice(priceFeeds[i]);
            assertGt(answer, 0);
            console.log("name", names[i]);
            console.log("Price feed address: ", priceFeeds[i]);
            console.log("Price is ", answer);
            console.log("Updated at ", updatedAt);
            console.log("Round ID ", roundId);
            console.log("Started at ", startedAt);
            console.log("Answered in round ", answeredInRound);
            console.log("Decimals ", decimals);
            console.log("--------------------------------------------------");
        }
    }
}
