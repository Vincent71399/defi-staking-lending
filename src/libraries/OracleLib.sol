// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function getPrice(address chainlinkFeedAddress)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80, uint8)
    {
        AggregatorV3Interface chainlinkFeed = AggregatorV3Interface(chainlinkFeedAddress);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            chainlinkFeed.latestRoundData();

        uint8 decimals = chainlinkFeed.decimals();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound, decimals);
    }

    function getSimplePrice(address chainlinkFeedAddress) public view returns (int256) {
        (, int256 answer,,,,) = getPrice(chainlinkFeedAddress);
        return answer;
    }

    function getActualPrice(address chainlinkFeedAddress) public view returns (uint256) {
        (, int256 answer,,,, uint8 decimals) = getPrice(chainlinkFeedAddress);
        return uint256(answer) / (10 ** decimals);
    }
}
