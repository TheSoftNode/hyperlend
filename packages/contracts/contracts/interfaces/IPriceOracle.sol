// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @dev Interface for price oracle providing real-time asset prices
 */
interface IPriceOracle {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        bool isValid;
    }

    struct PriceFeed {
        address feedAddress;
        uint256 heartbeat;
        uint256 deviation;
        bool isActive;
        bool isInverse;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event PriceUpdated(
        address indexed asset,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );

    event PriceFeedAdded(
        address indexed asset,
        address indexed feedAddress,
        uint256 heartbeat,
        uint256 deviation
    );

    event PriceFeedUpdated(
        address indexed asset,
        address indexed oldFeed,
        address indexed newFeed
    );

    event PriceFeedRemoved(address indexed asset, address indexed feedAddress);

    event EmergencyPriceSet(
        address indexed asset,
        uint256 price,
        address indexed setter,
        string reason
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the current price of an asset
     * @param asset The asset address
     * @return price The price in USD (scaled by 1e18)
     */
    function getPrice(address asset) external view returns (uint256 price);

    /**
     * @notice Get detailed price data for an asset
     * @param asset The asset address
     * @return priceData Detailed price information
     */
    function getPriceData(
        address asset
    ) external view returns (PriceData memory priceData);

    /**
     * @notice Get prices for multiple assets
     * @param assets Array of asset addresses
     * @return prices Array of prices in USD (scaled by 1e18)
     */
    function getPrices(
        address[] calldata assets
    ) external view returns (uint256[] memory prices);

    /**
     * @notice Get the value of an amount in USD
     * @param asset The asset address
     * @param amount The amount of the asset
     * @return valueUSD The USD value (scaled by 1e18)
     */
    function getAssetValue(
        address asset,
        uint256 amount
    ) external view returns (uint256 valueUSD);

    /**
     * @notice Convert amount from one asset to another
     * @param fromAsset Source asset address
     * @param toAsset Target asset address
     * @param amount Amount of source asset
     * @return convertedAmount Amount in target asset
     */
    function convertAssetAmount(
        address fromAsset,
        address toAsset,
        uint256 amount
    ) external view returns (uint256 convertedAmount);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if price data is valid and fresh
     * @param asset The asset address
     * @return isValid True if price is valid
     * @return age Age of price data in seconds
     */
    function isPriceValid(
        address asset
    ) external view returns (bool isValid, uint256 age);

    /**
     * @notice Check if asset has a price feed
     * @param asset The asset address
     * @return hasFeed True if asset has a price feed
     */
    function hasPriceFeed(address asset) external view returns (bool hasFeed);

    /**
     * @notice Get price feed information for an asset
     * @param asset The asset address
     * @return feed Price feed information
     */
    function getPriceFeed(
        address asset
    ) external view returns (PriceFeed memory feed);

    /**
     * @notice Get price confidence level
     * @param asset The asset address
     * @return confidence Confidence level (0-100)
     */
    function getPriceConfidence(
        address asset
    ) external view returns (uint256 confidence);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME FEATURES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Force price update for an asset
     * @param asset The asset address
     */
    function updatePrice(address asset) external;

    /**
     * @notice Batch update prices for multiple assets
     * @param assets Array of asset addresses
     */
    function batchUpdatePrices(address[] calldata assets) external;

    /**
     * @notice Get real-time price with circuit breaker check
     * @param asset The asset address
     * @return price Current price
     * @return isCircuitBreakerTriggered True if circuit breaker is active
     */
    function getRealTimePrice(
        address asset
    ) external view returns (uint256 price, bool isCircuitBreakerTriggered);

    /**
     * @notice Get price history for an asset
     * @param asset The asset address
     * @param fromTimestamp Start timestamp
     * @param toTimestamp End timestamp
     * @return timestamps Array of timestamps
     * @return prices Array of prices
     */
    function getPriceHistory(
        address asset,
        uint256 fromTimestamp,
        uint256 toTimestamp
    )
        external
        view
        returns (uint256[] memory timestamps, uint256[] memory prices);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a price feed for an asset
     * @param asset The asset address
     * @param feedAddress The price feed address
     * @param heartbeat Maximum age of price data in seconds
     * @param deviation Maximum allowed price deviation percentage
     */
    function addPriceFeed(
        address asset,
        address feedAddress,
        uint256 heartbeat,
        uint256 deviation
    ) external;

    /**
     * @notice Update price feed for an asset
     * @param asset The asset address
     * @param feedAddress The new price feed address
     * @param heartbeat New heartbeat value
     * @param deviation New deviation threshold
     */
    function updatePriceFeed(
        address asset,
        address feedAddress,
        uint256 heartbeat,
        uint256 deviation
    ) external;

    /**
     * @notice Remove price feed for an asset
     * @param asset The asset address
     */
    function removePriceFeed(address asset) external;

    /**
     * @notice Set emergency price for an asset
     * @param asset The asset address
     * @param price Emergency price
     * @param reason Reason for emergency price
     */
    function setEmergencyPrice(
        address asset,
        uint256 price,
        string calldata reason
    ) external;

    /**
     * @notice Enable or disable circuit breaker for an asset
     * @param asset The asset address
     * @param enabled True to enable circuit breaker
     * @param threshold Price change threshold to trigger circuit breaker
     */
    function setCircuitBreaker(
        address asset,
        bool enabled,
        uint256 threshold
    ) external;

    /**
     * @notice Pause price feeds
     */
    function pausePriceFeeds() external;

    /**
     * @notice Resume price feeds
     */
    function resumePriceFeeds() external;

    /**
     * @notice Set fallback price oracle
     * @param fallbackOracle Address of fallback oracle
     */
    function setFallbackOracle(address fallbackOracle) external;
}
