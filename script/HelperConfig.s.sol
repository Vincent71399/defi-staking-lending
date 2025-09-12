// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockToken} from "../test/mocks/MockToken.sol";
import {MockTokenD8} from "../test/mocks/MockTokenD8.sol";

contract HelperConfig is Script {
    error HelperConfig__UnSupportedChain();

    NetworkConfig private activeNetworkConfig;

    struct NetworkConfig {
        string[] tokenNames;
        address[] priceFeedAddresses;
        address[] tokenAddresses;
    }

    uint256 private constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 private constant ANVIL_CHAIN_ID = 31337;

    address private constant ETH_USD_PRICE_FEED_SEPOLIA = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address private constant BTC_USD_PRICE_FEED_SEPOLIA = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address private constant LINK_USD_PRICE_FEED_SEPOLIA = 0xc59E3633BAAC79493d908e63626716e204A45EdF;

    address private constant WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address private constant WBTC_SEPOLIA = 0x29f2D40B0605204364af54EC677bD022dA425d03;
    address private constant LINK_SEPOLIA = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__UnSupportedChain();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        string[] memory names = new string[](3);
        names[0] = "WETH/USD";
        names[1] = "WBTC/USD";
        names[2] = "LINK/USD";

        address[] memory priceFeedAddresses = new address[](3);
        priceFeedAddresses[0] = ETH_USD_PRICE_FEED_SEPOLIA;
        priceFeedAddresses[1] = BTC_USD_PRICE_FEED_SEPOLIA;
        priceFeedAddresses[2] = LINK_USD_PRICE_FEED_SEPOLIA;

        address[] memory tokenAddresses = new address[](3);
        tokenAddresses[0] = WETH_SEPOLIA;
        tokenAddresses[1] = WBTC_SEPOLIA;
        tokenAddresses[2] = LINK_SEPOLIA;

        sepoliaNetworkConfig =
            NetworkConfig({tokenNames: names, priceFeedAddresses: priceFeedAddresses, tokenAddresses: tokenAddresses});
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.priceFeedAddresses.length != 0 && activeNetworkConfig.tokenAddresses.length != 0) {
            anvilNetworkConfig = activeNetworkConfig;
        } else {
            vm.startBroadcast();
            MockToken weth = new MockToken("WETH", "WETH");
            MockTokenD8 wbtc = new MockTokenD8("WBTC", "WBTC");
            MockToken link = new MockToken("LINK", "LINK");

            MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(8, 438893980000);
            MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(8, 10792500000000);
            MockV3Aggregator linkUsdPriceFeed = new MockV3Aggregator(8, 2289298851);
            vm.stopBroadcast();

            string[] memory tokenNames = new string[](3);
            tokenNames[0] = "WETH/USD";
            tokenNames[1] = "WBTC/USD";
            tokenNames[2] = "LINK/USD";

            address[] memory priceFeedAddresses = new address[](3);
            priceFeedAddresses[0] = address(ethUsdPriceFeed);
            priceFeedAddresses[1] = address(btcUsdPriceFeed);
            priceFeedAddresses[2] = address(linkUsdPriceFeed);

            address[] memory tokenAddresses = new address[](3);
            tokenAddresses[0] = address(weth);
            tokenAddresses[1] = address(wbtc);
            tokenAddresses[2] = address(link);

            anvilNetworkConfig = NetworkConfig({
                tokenNames: tokenNames,
                priceFeedAddresses: priceFeedAddresses,
                tokenAddresses: tokenAddresses
            });
        }
    }

    // Price Feeds && Tokens getters
    function getTokenNames() external view returns (string[] memory) {
        return activeNetworkConfig.tokenNames;
    }

    function getPriceFeeds() external view returns (address[] memory) {
        return activeNetworkConfig.priceFeedAddresses;
    }

    function getTokens() external view returns (address[] memory) {
        return activeNetworkConfig.tokenAddresses;
    }
}
