// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Rahul Dindigala
 * @notice This library is used to check the chainlink Oracle for stale data.
 * If the price is stale, the function will revert, and render the DSCEngine unusable, i.e We want the DSCEngine to freeze if  prices become stale.
 *
 * So if the Chainlink network explodes and you have a lot of money locked in protocol
 */
library OracleLib {
    uint256 private constant TIMEOUT = 3 hours;

    error OracleLib__StalePrice();

    function staleCheckLatestRound(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answerInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answerInRound);
    }
}

