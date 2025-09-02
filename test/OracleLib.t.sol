// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { Test, console } from "forge-std/Test.sol";
import { OracleLib } from "../src/libraries/OracleLib.sol";
import { HelperConfig } from "../script/HelperConfig.s.sol";


contract OracleLibTest is Test {

    HelperConfig internal helperConfig;

    constructor() {
        helperConfig = new HelperConfig();
    }

    function testReadPrice() public view {
        address[] memory priceFeeds = helperConfig.getPriceFeeds();
        string[] memory names = helperConfig.getTokenNames();
        for (uint i = 0; i < priceFeeds.length; i++) {
            (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = OracleLib.getPrice(priceFeeds[i]);
            console.log("name", names[i]);
            console.log("Price feed address: ", priceFeeds[i]);
            console.log("Price is ", answer);
            console.log("Updated at ", updatedAt);
            console.log("Round ID ", roundId);
            console.log("Started at ", startedAt);
            console.log("Answered in round ", answeredInRound);
            console.log("--------------------------------------------------");
        }
    }

    function testGetPrice() public view {
        // for Sepolia testnet
        // ETH / USD
        address ethUsdPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = OracleLib.getPrice(ethUsdPriceFeed);
        console.log("ETH / USD price is ", answer);
        console.log("Updated at ", updatedAt);
        console.log("Round ID ", roundId);
        console.log("Started at ", startedAt);
        console.log("Answered in round ", answeredInRound);

        // BTC / USD
        address btcUsdPriceFeed = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        (roundId, answer, startedAt, updatedAt, answeredInRound) = OracleLib.getPrice(btcUsdPriceFeed);
        console.log("BTC / USD price is ", answer);
        console.log("Updated at ", updatedAt);
        console.log("Round ID ", roundId);
        console.log("Started at ", startedAt);
        console.log("Answered in round ", answeredInRound);

        // LINK / USD
        address linkUsdPriceFeed = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
        (roundId, answer, startedAt, updatedAt, answeredInRound) = OracleLib.getPrice(linkUsdPriceFeed);
        console.log("LINK / USD price is ", answer);
        console.log("Updated at ", updatedAt);
        console.log("Round ID ", roundId);
        console.log("Started at ", startedAt);
        console.log("Answered in round ", answeredInRound);
    }
}