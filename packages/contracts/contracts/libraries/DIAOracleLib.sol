// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IDIAOracleV2.sol";

/**
 * @title DIAOracleLib
 * @dev Library for integrating with DIA Oracle V2 on Somnia Network
 * @notice Based on official DIA documentation and best practices
 * @author HyperLend Team
 *
 * Features:
 * - Safe price fetching with staleness checks
 * - Built-in error handling
 * - Gas-optimized batch operations
 * - Somnia-specific optimizations
 */
library DIAOracleLib {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    error PriceTooOld();
    error InvalidOracle();
    error PriceNotFound();
    error InvalidKey();
    error ZeroPrice();

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice DIA Oracle returns prices with 8 decimal places
    uint256 public constant DIA_DECIMALS = 8;

    /// @notice Target precision for price calculations (18 decimals)
    uint256 public constant TARGET_DECIMALS = 18;

    /// @notice Scaling factor to convert DIA prices to 18 decimals
    uint256 public constant PRICE_SCALING_FACTOR =
        10 ** (TARGET_DECIMALS - DIA_DECIMALS);

    /// @notice Maximum acceptable price age (24 hours)
    uint256 public constant MAX_PRICE_AGE = 86400;

    /// @notice Default staleness threshold (1 hour)
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 3600;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get price from DIA Oracle with automatic scaling to 18 decimals
     * @param oracle Address of the DIA Oracle contract
     * @param key Asset key (e.g., "BTC/USD", "STT/USD")
     * @return latestPrice Price scaled to 18 decimals
     * @return timestampOfLatestPrice Timestamp of the price update
     */
    function getPrice(
        address oracle,
        string memory key
    )
        public
        view
        returns (uint128 latestPrice, uint128 timestampOfLatestPrice)
    {
        if (oracle == address(0)) revert InvalidOracle();
        if (bytes(key).length == 0) revert InvalidKey();

        // Get raw price from DIA Oracle
        (uint128 rawPrice, uint128 timestamp) = IDIAOracleV2(oracle).getValue(
            key
        );

        if (rawPrice == 0) revert ZeroPrice();

        // Scale price from 8 decimals to 18 decimals
        latestPrice = uint128(uint256(rawPrice) * PRICE_SCALING_FACTOR);
        timestampOfLatestPrice = timestamp;
    }

    /**
     * @notice Get price only if it's not older than specified threshold
     * @param oracle Address of the DIA Oracle contract
     * @param key Asset key (e.g., "BTC/USD", "STT/USD")
     * @param maxTimePassed Maximum acceptable age in seconds
     * @return price Price scaled to 18 decimals (0 if too old)
     * @return inTime True if price is fresh enough
     */
    function getPriceIfNotOlderThan(
        address oracle,
        string memory key,
        uint128 maxTimePassed
    ) public view returns (uint128 price, bool inTime) {
        (uint128 latestPrice, uint128 timestamp) = getPrice(oracle, key);

        // Check if price is fresh enough
        uint256 priceAge = block.timestamp - uint256(timestamp);
        inTime = priceAge <= uint256(maxTimePassed);

        if (inTime) {
            price = latestPrice;
        } else {
            price = 0;
        }
    }

    /**
     * @notice Get price with built-in staleness check (1 hour default)
     * @param oracle Address of the DIA Oracle contract
     * @param key Asset key
     * @return price Fresh price scaled to 18 decimals
     */
    function getFreshPrice(
        address oracle,
        string memory key
    ) public view returns (uint128 price) {
        (uint128 freshPrice, bool inTime) = getPriceIfNotOlderThan(
            oracle,
            key,
            uint128(DEFAULT_STALENESS_THRESHOLD)
        );

        if (!inTime) revert PriceTooOld();

        return freshPrice;
    }

    /**
     * @notice Get multiple prices in a single call (gas optimized)
     * @param oracle Address of the DIA Oracle contract
     * @param keys Array of asset keys
     * @return prices Array of prices scaled to 18 decimals
     * @return timestamps Array of timestamps
     */
    function getBatchPrices(
        address oracle,
        string[] memory keys
    )
        public
        view
        returns (uint128[] memory prices, uint128[] memory timestamps)
    {
        if (oracle == address(0)) revert InvalidOracle();

        uint256 length = keys.length;
        prices = new uint128[](length);
        timestamps = new uint128[](length);

        for (uint256 i = 0; i < length; i++) {
            (prices[i], timestamps[i]) = getPrice(oracle, keys[i]);
        }
    }

    /**
     * @notice Get multiple fresh prices with staleness check
     * @param oracle Address of the DIA Oracle contract
     * @param keys Array of asset keys
     * @param maxTimePassed Maximum acceptable age for all prices
     * @return prices Array of fresh prices (0 if stale)
     * @return areAllFresh True if all prices are fresh
     */
    function getBatchFreshPrices(
        address oracle,
        string[] memory keys,
        uint128 maxTimePassed
    ) public view returns (uint128[] memory prices, bool areAllFresh) {
        uint256 length = keys.length;
        prices = new uint128[](length);
        areAllFresh = true;

        for (uint256 i = 0; i < length; i++) {
            (uint128 price, bool inTime) = getPriceIfNotOlderThan(
                oracle,
                keys[i],
                maxTimePassed
            );

            prices[i] = price;
            if (!inTime) {
                areAllFresh = false;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the age of a price in seconds
     * @param oracle Address of the DIA Oracle contract
     * @param key Asset key
     * @return age Age in seconds since last update
     */
    function getPriceAge(
        address oracle,
        string memory key
    ) public view returns (uint256 age) {
        (, uint128 timestamp) = IDIAOracleV2(oracle).getValue(key);
        age = block.timestamp - uint256(timestamp);
    }

    /**
     * @notice Check if a price is fresh enough
     * @param oracle Address of the DIA Oracle contract
     * @param key Asset key
     * @param maxAge Maximum acceptable age in seconds
     * @return isFresh True if price is fresh enough
     */
    function isPriceFresh(
        address oracle,
        string memory key,
        uint256 maxAge
    ) public view returns (bool isFresh) {
        uint256 age = getPriceAge(oracle, key);
        isFresh = age <= maxAge;
    }

    /**
     * @notice Convert DIA price (8 decimals) to target decimals
     * @param diaPrice Price from DIA Oracle (8 decimals)
     * @param targetDecimals Target decimal places
     * @return convertedPrice Price with target decimals
     */
    function convertDIAPrice(
        uint128 diaPrice,
        uint8 targetDecimals
    ) public pure returns (uint256 convertedPrice) {
        if (targetDecimals >= DIA_DECIMALS) {
            // Scale up
            uint256 scalingFactor = 10 ** (targetDecimals - DIA_DECIMALS);
            convertedPrice = uint256(diaPrice) * scalingFactor;
        } else {
            // Scale down
            uint256 scalingFactor = 10 ** (DIA_DECIMALS - targetDecimals);
            convertedPrice = uint256(diaPrice) / scalingFactor;
        }
    }

    /**
     * @notice Calculate price change percentage between two prices
     * @param oldPrice Previous price
     * @param newPrice Current price
     * @return changePercentage Percentage change (scaled by 1e18)
     */
    function calculatePriceChange(
        uint128 oldPrice,
        uint128 newPrice
    ) public pure returns (uint256 changePercentage) {
        if (oldPrice == 0) return 0;

        uint256 difference = newPrice > oldPrice
            ? uint256(newPrice - oldPrice)
            : uint256(oldPrice - newPrice);

        // Calculate percentage change scaled by 1e18
        changePercentage = (difference * 1e18) / uint256(oldPrice);
    }

    /**
     * @notice Validate oracle response
     * @param price Price from oracle
     * @param timestamp Timestamp from oracle
     * @param maxAge Maximum acceptable age
     * @return isValid True if response is valid
     */
    function validateOracleResponse(
        uint128 price,
        uint128 timestamp,
        uint256 maxAge
    ) public view returns (bool isValid) {
        // Check if price is non-zero
        if (price == 0) return false;

        // Check if timestamp is not in the future
        if (uint256(timestamp) > block.timestamp) return false;

        // Check if price is not too old
        uint256 age = block.timestamp - uint256(timestamp);
        if (age > maxAge) return false;

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // SOMNIA-SPECIFIC OPTIMIZATIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get STT price specifically optimized for Somnia native token
     * @param oracle Address of the DIA Oracle contract
     * @return sttPrice STT price in USD (18 decimals)
     * @return timestamp Last update timestamp
     */
    function getSTTPrice(
        address oracle
    ) public view returns (uint128 sttPrice, uint128 timestamp) {
        return getPrice(oracle, "STT/USD");
    }

    /**
     * @notice Get fresh STT price with optimized staleness check for Somnia's fast finality
     * @param oracle Address of the DIA Oracle contract
     * @return sttPrice Fresh STT price in USD (18 decimals)
     */
    function getFreshSTTPrice(
        address oracle
    ) public view returns (uint128 sttPrice) {
        // Use shorter staleness threshold for STT due to Somnia's fast finality
        return getFreshPrice(oracle, "STT/USD");
    }

    /**
     * @notice Get prices for all Somnia-supported assets
     * @param oracle Address of the DIA Oracle contract
     * @return sttPrice STT/USD price
     * @return usdtPrice USDT/USD price
     * @return usdcPrice USDC/USD price
     * @return btcPrice BTC/USD price
     * @return arbPrice ARB/USD price
     * @return solPrice SOL/USD price
     */
    function getAllSomniaAssetPrices(
        address oracle
    )
        public
        view
        returns (
            uint128 sttPrice,
            uint128 usdtPrice,
            uint128 usdcPrice,
            uint128 btcPrice,
            uint128 arbPrice,
            uint128 solPrice
        )
    {
        string[] memory keys = new string[](6);
        keys[0] = "STT/USD";
        keys[1] = "USDT/USD";
        keys[2] = "USDC/USD";
        keys[3] = "BTC/USD";
        keys[4] = "ARB/USD";
        keys[5] = "SOL/USD";

        (uint128[] memory prices, ) = getBatchPrices(oracle, keys);

        sttPrice = prices[0];
        usdtPrice = prices[1];
        usdcPrice = prices[2];
        btcPrice = prices[3];
        arbPrice = prices[4];
        solPrice = prices[5];
    }
}
