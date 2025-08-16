// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title MockPriceOracle
 * @dev Mock price oracle for testing purposes
 * @notice Provides controllable price feeds for testing scenarios
 */
contract MockPriceOracle is IPriceOracle, Ownable {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    mapping(address => PriceData) public assetPrices;
    mapping(address => PriceFeed) public assetFeeds;
    mapping(address => bool) public hasFeed;

    // Price history for testing
    mapping(address => uint256[]) public priceHistory;
    mapping(address => uint256[]) public timestampHistory;

    // Testing features
    bool public oracleEnabled = true;
    bool public shouldRevert = false;
    uint256 public priceDelay = 0;
    uint256 public volatilityFactor = 0; // Basis points for random price changes

    // Round data for Chainlink-style interface
    mapping(address => uint80) public latestRoundId;
    mapping(address => mapping(uint80 => int256)) public roundPrices;
    mapping(address => mapping(uint80 => uint256)) public roundTimestamps;

    // Fallback oracle
    address public fallbackOracle;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event PriceSet(address indexed asset, uint256 price, uint256 timestamp);
    event OracleToggled(bool enabled);
    event VolatilityFactorSet(uint256 factor);
    event PriceDelaySet(uint256 delay);
    event ShouldRevertSet(bool shouldRevert);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor() Ownable() {}

    // ═══════════════════════════════════════════════════════════════════════════════════
    // PRICE ORACLE INTERFACE IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════════════

    function getPrice(
        address asset
    ) external view override returns (uint256 price) {
        if (shouldRevert) {
            revert("MockPriceOracle: Forced revert");
        }

        if (!oracleEnabled) {
            revert("MockPriceOracle: Oracle disabled");
        }

        PriceData memory data = assetPrices[asset];

        if (!data.isValid) {
            revert("MockPriceOracle: No price set");
        }

        // Apply price delay if set
        if (priceDelay > 0 && block.timestamp < data.timestamp + priceDelay) {
            revert("MockPriceOracle: Price not ready");
        }

        // Apply volatility if set
        if (volatilityFactor > 0) {
            uint256 variation = (data.price * volatilityFactor) / 10000;
            uint256 randomness = uint256(
                keccak256(abi.encodePacked(block.timestamp, asset))
            ) % 200;
            if (randomness < 100) {
                // Decrease price
                uint256 decrease = (variation * randomness) / 100;
                return
                    data.price > decrease
                        ? data.price - decrease
                        : data.price / 2;
            } else {
                // Increase price
                uint256 increase = (variation * (randomness - 100)) / 100;
                return data.price + increase;
            }
        }

        return data.price;
    }

    function getPriceData(
        address asset
    ) external view override returns (PriceData memory) {
        return assetPrices[asset];
    }

    function getPrices(
        address[] calldata assets
    ) external view override returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = this.getPrice(assets[i]);
        }
    }

    function getAssetValue(
        address asset,
        uint256 amount
    ) external view override returns (uint256 valueUSD) {
        uint256 price = this.getPrice(asset);
        return (amount * price) / 1e18;
    }

    function convertAssetAmount(
        address fromAsset,
        address toAsset,
        uint256 amount
    ) external view override returns (uint256 convertedAmount) {
        uint256 fromPrice = this.getPrice(fromAsset);
        uint256 toPrice = this.getPrice(toAsset);

        uint256 valueUSD = (amount * fromPrice) / 1e18;
        return (valueUSD * 1e18) / toPrice;
    }

    function isPriceValid(
        address asset
    ) external view override returns (bool isValid, uint256 age) {
        PriceData memory data = assetPrices[asset];
        age = block.timestamp - data.timestamp;
        isValid = data.isValid && age <= 86400; // Valid for 24 hours
    }

    function hasPriceFeed(address asset) external view override returns (bool) {
        return hasFeed[asset];
    }

    function getPriceFeed(
        address asset
    ) external view override returns (PriceFeed memory) {
        return assetFeeds[asset];
    }

    function getPriceConfidence(
        address asset
    ) external view override returns (uint256 confidence) {
        return assetPrices[asset].confidence;
    }

    function getRealTimePrice(
        address asset
    )
        external
        view
        override
        returns (uint256 price, bool isCircuitBreakerTriggered)
    {
        price = this.getPrice(asset);
        isCircuitBreakerTriggered = false; // Mock doesn't have circuit breakers
    }

    function getPriceHistory(
        address asset,
        uint256 /* fromTimestamp */,
        uint256 /* toTimestamp */
    )
        external
        view
        override
        returns (uint256[] memory timestamps, uint256[] memory prices)
    {
        uint256[] storage assetTimestamps = timestampHistory[asset];
        uint256[] storage assetPriceHistory = priceHistory[asset];

        // Simple implementation - return all history
        timestamps = assetTimestamps;
        prices = assetPriceHistory;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // MOCK-SPECIFIC FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set price for an asset
     * @param asset Asset address
     * @param price Price in USD (scaled by 1e18)
     */
    function setPrice(address asset, uint256 price) external onlyOwner {
        setPrice(asset, price, 100); // 100% confidence
    }

    /**
     * @notice Set price with confidence level
     * @param asset Asset address
     * @param price Price in USD (scaled by 1e18)
     * @param confidence Confidence level (0-100)
     */
    function setPrice(
        address asset,
        uint256 price,
        uint256 confidence
    ) public onlyOwner {
        require(confidence <= 100, "MockPriceOracle: Invalid confidence");

        assetPrices[asset] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: confidence,
            isValid: true
        });

        // Add to history
        priceHistory[asset].push(price);
        timestampHistory[asset].push(block.timestamp);

        // Update round data
        latestRoundId[asset]++;
        roundPrices[asset][latestRoundId[asset]] = int256(price);
        roundTimestamps[asset][latestRoundId[asset]] = block.timestamp;

        emit PriceSet(asset, price, block.timestamp);
    }

    /**
     * @notice Set prices for multiple assets
     * @param assets Array of asset addresses
     * @param prices Array of prices
     */
    function setPrices(
        address[] calldata assets,
        uint256[] calldata prices
    ) external onlyOwner {
        require(
            assets.length == prices.length,
            "MockPriceOracle: Length mismatch"
        );

        for (uint256 i = 0; i < assets.length; i++) {
            setPrice(assets[i], prices[i], 100);
        }
    }

    /**
     * @notice Set price with custom timestamp (for testing historical data)
     * @param asset Asset address
     * @param price Price in USD
     * @param timestamp Custom timestamp
     */
    function setPriceWithTimestamp(
        address asset,
        uint256 price,
        uint256 timestamp
    ) external onlyOwner {
        assetPrices[asset] = PriceData({
            price: price,
            timestamp: timestamp,
            confidence: 100,
            isValid: true
        });

        emit PriceSet(asset, price, timestamp);
    }

    /**
     * @notice Simulate price movement
     * @param asset Asset address
     * @param changePercent Percentage change (positive or negative, in basis points)
     */
    function simulatePriceChange(
        address asset,
        int256 changePercent
    ) external onlyOwner {
        PriceData storage data = assetPrices[asset];
        require(data.isValid, "MockPriceOracle: Price not set");

        uint256 currentPrice = data.price;
        uint256 change = (currentPrice *
            uint256(changePercent >= 0 ? changePercent : -changePercent)) /
            10000;

        uint256 newPrice;
        if (changePercent >= 0) {
            newPrice = currentPrice + change;
        } else {
            newPrice = currentPrice > change
                ? currentPrice - change
                : currentPrice / 2;
        }

        setPrice(asset, newPrice, 100);
    }

    /**
     * @notice Set volatility factor for random price changes
     * @param factor Volatility factor in basis points (100 = 1%)
     */
    function setVolatilityFactor(uint256 factor) external onlyOwner {
        require(factor <= 5000, "MockPriceOracle: Volatility too high"); // Max 50%
        volatilityFactor = factor;
        emit VolatilityFactorSet(factor);
    }

    /**
     * @notice Set price delay for testing time-sensitive operations
     * @param delay Delay in seconds before price becomes available
     */
    function setPriceDelay(uint256 delay) external onlyOwner {
        require(delay <= 1 hours, "MockPriceOracle: Delay too long");
        priceDelay = delay;
        emit PriceDelaySet(delay);
    }

    /**
     * @notice Toggle oracle on/off
     * @param enabled Whether oracle should be enabled
     */
    function setOracleEnabled(bool enabled) external onlyOwner {
        oracleEnabled = enabled;
        emit OracleToggled(enabled);
    }

    /**
     * @notice Set whether oracle should revert (for testing error handling)
     * @param _shouldRevert Whether oracle should revert
     */
    function setShouldRevert(bool _shouldRevert) external onlyOwner {
        shouldRevert = _shouldRevert;
        emit ShouldRevertSet(_shouldRevert);
    }

    /**
     * @notice Invalidate price for an asset
     * @param asset Asset address
     */
    function invalidatePrice(address asset) external onlyOwner {
        assetPrices[asset].isValid = false;
    }

    /**
     * @notice Add price feed for an asset
     * @param asset Asset address
     * @param feedAddress Feed address (can be mock)
     * @param heartbeat Heartbeat in seconds
     * @param deviation Deviation threshold
     */
    function addPriceFeed(
        address asset,
        address feedAddress,
        uint256 heartbeat,
        uint256 deviation
    ) external override onlyOwner {
        assetFeeds[asset] = PriceFeed({
            feedAddress: feedAddress,
            heartbeat: heartbeat,
            deviation: deviation,
            isActive: true,
            isInverse: false
        });

        hasFeed[asset] = true;
        emit PriceFeedAdded(asset, feedAddress, heartbeat, deviation);
    }

    /**
     * @notice Update price feed
     */
    function updatePriceFeed(
        address asset,
        address feedAddress,
        uint256 heartbeat,
        uint256 deviation
    ) external override onlyOwner {
        require(hasFeed[asset], "MockPriceOracle: Feed not found");

        address oldFeed = assetFeeds[asset].feedAddress;
        assetFeeds[asset].feedAddress = feedAddress;
        assetFeeds[asset].heartbeat = heartbeat;
        assetFeeds[asset].deviation = deviation;

        emit PriceFeedUpdated(asset, oldFeed, feedAddress);
    }

    /**
     * @notice Remove price feed
     */
    function removePriceFeed(address asset) external override onlyOwner {
        require(hasFeed[asset], "MockPriceOracle: Feed not found");

        address feedAddress = assetFeeds[asset].feedAddress;
        delete assetFeeds[asset];
        hasFeed[asset] = false;

        emit PriceFeedRemoved(asset, feedAddress);
    }

    /**
     * @notice Set emergency price
     */
    function setEmergencyPrice(
        address asset,
        uint256 price,
        string calldata reason
    ) external override onlyOwner {
        setPrice(asset, price, 50); // Lower confidence for emergency price
        emit EmergencyPriceSet(asset, price, msg.sender, reason);
    }

    /**
     * @notice Set circuit breaker (mock implementation)
     */
    function setCircuitBreaker(
        address asset,
        bool enabled,
        uint256 threshold
    ) external override onlyOwner {
        // Mock implementation - just emit event
        // Real implementation would store circuit breaker state
    }

    /**
     * @notice Set fallback oracle
     */
    function setFallbackOracle(
        address _fallbackOracle
    ) external override onlyOwner {
        fallbackOracle = _fallbackOracle;
    }

    /**
     * @notice Pause price feeds (mock implementation)
     */
    function pausePriceFeeds() external override onlyOwner {
        oracleEnabled = false;
    }

    /**
     * @notice Resume price feeds (mock implementation)
     */
    function resumePriceFeeds() external override onlyOwner {
        oracleEnabled = true;
    }

    /**
     * @notice Update price (for real-time testing)
     */
    function updatePrice(address asset) external override {
        // Mock implementation - just emit event
        PriceData memory data = assetPrices[asset];
        if (data.isValid) {
            emit PriceUpdated(asset, data.price, data.price, block.timestamp);
        }
    }

    /**
     * @notice Batch update prices
     */
    function batchUpdatePrices(address[] calldata assets) external override {
        for (uint256 i = 0; i < assets.length; i++) {
            this.updatePrice(assets[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CHAINLINK-STYLE INTERFACE (for compatibility testing)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get latest round data (Chainlink style)
     * @param asset Asset address
     */
    function latestRoundData(
        address asset
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = latestRoundId[asset];
        answer = roundPrices[asset][roundId];
        startedAt = roundTimestamps[asset][roundId];
        updatedAt = roundTimestamps[asset][roundId];
        answeredInRound = roundId;
    }

    /**
     * @notice Get round data for specific round
     * @param asset Asset address
     * @param _roundId Round ID
     */
    function getRoundData(
        address asset,
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = _roundId;
        answer = roundPrices[asset][_roundId];
        startedAt = roundTimestamps[asset][_roundId];
        updatedAt = roundTimestamps[asset][_roundId];
        answeredInRound = _roundId;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // TESTING UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get all configuration for testing
     */
    function getConfig()
        external
        view
        returns (
            bool _oracleEnabled,
            bool _shouldRevert,
            uint256 _priceDelay,
            uint256 _volatilityFactor,
            address _fallbackOracle
        )
    {
        return (
            oracleEnabled,
            shouldRevert,
            priceDelay,
            volatilityFactor,
            fallbackOracle
        );
    }

    /**
     * @notice Clear price history for an asset
     * @param asset Asset address
     */
    function clearPriceHistory(address asset) external onlyOwner {
        delete priceHistory[asset];
        delete timestampHistory[asset];
    }

    /**
     * @notice Reset oracle to default state
     */
    function resetOracle() external onlyOwner {
        oracleEnabled = true;
        shouldRevert = false;
        priceDelay = 0;
        volatilityFactor = 0;
        fallbackOracle = address(0);
    }

    /**
     * @notice Simulate network congestion (delay all responses)
     * @param delay Delay in seconds
     */
    function simulateNetworkCongestion(uint256 delay) external onlyOwner {
        priceDelay = delay;
        emit PriceDelaySet(delay);
    }

    /**
     * @notice Simulate oracle outage
     */
    function simulateOutage(uint256 /* duration */) external onlyOwner {
        oracleEnabled = false;
        emit OracleToggled(false);
        // In a real scenario, you'd set a timer to re-enable after duration
        // For testing, manual re-enable is expected
    }

    /**
     * @notice Add multiple historical prices at once
     * @param asset Asset address
     * @param prices Array of historical prices
     * @param timestamps Array of timestamps
     */
    function addHistoricalPrices(
        address asset,
        uint256[] calldata prices,
        uint256[] calldata timestamps
    ) external onlyOwner {
        require(
            prices.length == timestamps.length,
            "MockPriceOracle: Length mismatch"
        );

        for (uint256 i = 0; i < prices.length; i++) {
            priceHistory[asset].push(prices[i]);
            timestampHistory[asset].push(timestamps[i]);
        }
    }

    /**
     * @notice Simulate price flash crash
     * @param asset Asset address
     * @param crashPercent Percentage to crash (in basis points)
     */
    function simulateFlashCrash(
        address asset,
        uint256 crashPercent,
        uint256 /* recoveryTime */
    ) external onlyOwner {
        PriceData storage data = assetPrices[asset];
        uint256 originalPrice = data.price;

        // Crash the price
        uint256 crashAmount = (originalPrice * crashPercent) / 10000;
        uint256 crashedPrice = originalPrice - crashAmount;

        setPrice(asset, crashedPrice, 100);

        // Note: In a real implementation, you'd set up a timer to recover the price
        // For testing, manual recovery is expected
    }
}
