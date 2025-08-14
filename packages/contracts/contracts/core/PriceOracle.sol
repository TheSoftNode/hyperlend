// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IPriceOracle.sol";
import "../libraries/Math.sol";

/**
 * @title PriceOracle
 * @dev High-performance price oracle optimized for Somnia's throughput
 * @notice Provides real-time asset prices with circuit breaker protection
 */
contract PriceOracle is IPriceOracle, AccessControl, Pausable {
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_PRICE_DEVIATION = 50e16; // 50%
    uint256 public constant DEFAULT_HEARTBEAT = 3600; // 1 hour
    uint256 public constant MAX_PRICE_AGE = 86400; // 24 hours

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct PriceEntry {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        bool isValid;
        bool isEmergency;
    }

    struct CircuitBreaker {
        bool enabled;
        uint256 threshold;
        uint256 lastTriggerTime;
        uint256 cooldownPeriod;
        bool isTriggered;
    }

    // Asset price data
    mapping(address => PriceEntry) public priceData;
    mapping(address => PriceFeed) public priceFeeds;
    mapping(address => CircuitBreaker) public circuitBreakers;
    mapping(address => bool) public hasFeed;

    // Price history for analytics
    mapping(address => uint256[]) public priceHistory;
    mapping(address => uint256[]) public timestampHistory;
    uint256 public constant MAX_HISTORY_LENGTH = 100;

    // Fallback oracle
    address public fallbackOracle;

    // Emergency prices set by admin
    mapping(address => uint256) public emergencyPrices;
    mapping(address => bool) public hasEmergencyPrice;

    // Real-time metrics
    uint256 public totalPriceUpdates;
    uint256 public totalCircuitBreakerTriggers;
    uint256 public last24hPriceUpdates;
    uint256 public lastMetricsReset;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(address admin) {
        require(admin != address(0), "PriceOracle: Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(EMERGENCY_ROLE, admin);

        lastMetricsReset = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE PRICE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the current price of an asset
     */
    function getPrice(address asset) external view override returns (uint256 price) {
        return _getValidPrice(asset);
    }

    /**
     * @notice Get detailed price data for an asset
     */
    function getPriceData(address asset) external view override returns (PriceData memory) {
        PriceEntry memory entry = priceData[asset];
        
        return PriceData({
            price: entry.price,
            timestamp: entry.timestamp,
            confidence: entry.confidence,
            isValid: entry.isValid && _isPriceValid(asset)
        });
    }

    /**
     * @notice Get prices for multiple assets
     */
    function getPrices(address[] calldata assets) external view override returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = _getValidPrice(assets[i]);
        }
    }

    /**
     * @notice Get the value of an amount in USD
     */
    function getAssetValue(address asset, uint256 amount) external view override returns (uint256 valueUSD) {
        uint256 price = _getValidPrice(asset);
        return amount.mulDiv(price, PRECISION);
    }

    /**
     * @notice Convert amount from one asset to another
     */
    function convertAssetAmount(
        address fromAsset,
        address toAsset,
        uint256 amount
    ) external view override returns (uint256 convertedAmount) {
        uint256 fromPrice = _getValidPrice(fromAsset);
        uint256 toPrice = _getValidPrice(toAsset);
        
        uint256 valueUSD = amount.mulDiv(fromPrice, PRECISION);
        return valueUSD.mulDiv(PRECISION, toPrice);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if price data is valid and fresh
     */
    function isPriceValid(address asset) external view override returns (bool isValid, uint256 age) {
        PriceEntry memory entry = priceData[asset];
        age = block.timestamp - entry.timestamp;
        
        if (!entry.isValid) return (false, age);
        if (age > MAX_PRICE_AGE) return (false, age);
        if (circuitBreakers[asset].isTriggered) return (false, age);
        
        return (true, age);
    }

    /**
     * @notice Check if asset has a price feed
     */
    function hasPriceFeed(address asset) external view override returns (bool) {
        return hasFeed[asset];
    }

    /**
     * @notice Get price feed information for an asset
     */
    function getPriceFeed(address asset) external view override returns (PriceFeed memory) {
        return priceFeeds[asset];
    }

    /**
     * @notice Get price confidence level
     */
    function getPriceConfidence(address asset) external view override returns (uint256 confidence) {
        return priceData[asset].confidence;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME FEATURES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Force price update for an asset
     */
    function updatePrice(address asset) external override onlyRole(PRICE_UPDATER_ROLE) whenNotPaused {
        _updateAssetPrice(asset);
    }

    /**
     * @notice Batch update prices for multiple assets
     */
    function batchUpdatePrices(address[] calldata assets) external override onlyRole(PRICE_UPDATER_ROLE) whenNotPaused {
        for (uint256 i = 0; i < assets.length; i++) {
            _updateAssetPrice(assets[i]);
        }
    }

    /**
     * @notice Get real-time price with circuit breaker check
     */
    function getRealTimePrice(address asset) external view override returns (
        uint256 price,
        bool isCircuitBreakerTriggered
    ) {
        price = _getValidPrice(asset);
        isCircuitBreakerTriggered = circuitBreakers[asset].isTriggered;
    }

    /**
     * @notice Get price history for an asset
     */
    function getPriceHistory(
        address asset,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external view override returns (uint256[] memory timestamps, uint256[] memory prices) {
        uint256[] storage assetPrices = priceHistory[asset];
        uint256[] storage assetTimestamps = timestampHistory[asset];
        
        // Find start and end indices
        uint256 startIndex = 0;
        uint256 endIndex = assetTimestamps.length;
        
        for (uint256 i = 0; i < assetTimestamps.length; i++) {
            if (assetTimestamps[i] >= fromTimestamp && startIndex == 0) {
                startIndex = i;
            }
            if (assetTimestamps[i] > toTimestamp) {
                endIndex = i;
                break;
            }
        }
        
        uint256 length = endIndex - startIndex;
        timestamps = new uint256[](length);
        prices = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            timestamps[i] = assetTimestamps[startIndex + i];
            prices[i] = assetPrices[startIndex + i];
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _getValidPrice(address asset) internal view returns (uint256) {
        PriceEntry memory entry = priceData[asset];
        
        // Check for emergency price first
        if (hasEmergencyPrice[asset]) {
            return emergencyPrices[asset];
        }
        
        // Check circuit breaker
        if (circuitBreakers[asset].isTriggered) {
            revert("PriceOracle: Circuit breaker triggered");
        }
        
        // Check if price is valid and fresh
        if (!entry.isValid || !_isPriceValid(asset)) {
            // Try fallback oracle
            if (fallbackOracle != address(0)) {
                try IPriceOracle(fallbackOracle).getPrice(asset) returns (uint256 fallbackPrice) {
                    return fallbackPrice;
                } catch {
                    revert("PriceOracle: No valid price available");
                }
            }
            revert("PriceOracle: No valid price available");
        }
        
        return entry.price;
    }

    function _isPriceValid(address asset) internal view returns (bool) {
        PriceEntry memory entry = priceData[asset];
        
        if (!entry.isValid) return false;
        if (block.timestamp - entry.timestamp > MAX_PRICE_AGE) return false;
        
        PriceFeed memory feed = priceFeeds[asset];
        if (hasFeed[asset] && block.timestamp - entry.timestamp > feed.heartbeat) return false;
        
        return true;
    }

    function _updateAssetPrice(address asset) internal {
        if (!hasFeed[asset]) return;
        
        PriceFeed memory feed = priceFeeds[asset];
        if (!feed.isActive) return;
        
        // This would typically fetch from external price feed
        // For this implementation, we'll simulate with stored data
        PriceEntry storage entry = priceData[asset];
        
        // Update metrics
        totalPriceUpdates++;
        _update24hMetrics();
        
        // Store in history
        _updatePriceHistory(asset, entry.price, block.timestamp);
        
        emit PriceUpdated(asset, entry.price, entry.price, block.timestamp);
    }

    function _updatePriceHistory(address asset, uint256 price, uint256 timestamp) internal {
        uint256[] storage prices = priceHistory[asset];
        uint256[] storage timestamps = timestampHistory[asset];
        
        prices.push(price);
        timestamps.push(timestamp);
        
        // Maintain history length
        if (prices.length > MAX_HISTORY_LENGTH) {
            // Remove oldest entries
            for (uint256 i = 0; i < prices.length - 1; i++) {
                prices[i] = prices[i + 1];
                timestamps[i] = timestamps[i + 1];
            }
            prices.pop();
            timestamps.pop();
        }
    }

    function _update24hMetrics() internal {
        // Reset 24h counter if needed
        if (block.timestamp >= lastMetricsReset + 24 hours) {
            last24hPriceUpdates = 0;
            lastMetricsReset = block.timestamp;
        }
        
        last24hPriceUpdates++;
    }

    function _checkCircuitBreaker(address asset, uint256 newPrice) internal {
        CircuitBreaker storage breaker = circuitBreakers[asset];
        if (!breaker.enabled) return;
        
        PriceEntry memory entry = priceData[asset];
        if (entry.price == 0) return; // No previous price to compare
        
        // Calculate price change percentage
        uint256 priceChange = entry.price > newPrice ? 
            entry.price - newPrice : 
            newPrice - entry.price;
        uint256 changePercentage = priceChange.mulDiv(PRECISION, entry.price);
        
        // Trigger circuit breaker if change exceeds threshold
        if (changePercentage > breaker.threshold) {
            breaker.isTriggered = true;
            breaker.lastTriggerTime = block.timestamp;
            totalCircuitBreakerTriggers++;
            
            emit CircuitBreakerTriggered(asset, entry.price, newPrice, changePercentage);
        }
    }

    function _setPrice(address asset, uint256 price, uint256 confidence, bool isEmergency) internal {
        require(price > 0, "PriceOracle: Invalid price");
        
        // Check circuit breaker before updating
        if (!isEmergency) {
            _checkCircuitBreaker(asset, price);
        }
        
        uint256 oldPrice = priceData[asset].price;
        
        priceData[asset] = PriceEntry({
            price: price,
            timestamp: block.timestamp,
            confidence: confidence,
            isValid: true,
            isEmergency: isEmergency
        });
        
        // Update history
        _updatePriceHistory(asset, price, block.timestamp);
        
        emit PriceUpdated(asset, oldPrice, price, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a price feed for an asset
     */
    function addPriceFeed(
        address asset,
        address feedAddress,
        uint256 heartbeat,
        uint256 deviation
    ) external override onlyRole(ADMIN_ROLE) {
        require(asset != address(0), "PriceOracle: Invalid asset");
        require(feedAddress != address(0), "PriceOracle: Invalid feed");
        require(heartbeat > 0, "PriceOracle: Invalid heartbeat");
        require(deviation <= MAX_PRICE_DEVIATION, "PriceOracle: Deviation too high");
        
        priceFeeds[asset] = PriceFeed({
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
     * @notice Update price feed for an asset
     */
    function updatePriceFeed(
        address asset,
        address feedAddress,
        uint256 heartbeat,
        uint256 deviation
    ) external override onlyRole(ADMIN_ROLE) {
        require(hasFeed[asset], "PriceOracle: Feed not found");
        require(feedAddress != address(0), "PriceOracle: Invalid feed");
        
        address oldFeed = priceFeeds[asset].feedAddress;
        
        priceFeeds[asset].feedAddress = feedAddress;
        priceFeeds[asset].heartbeat = heartbeat;
        priceFeeds[asset].deviation = deviation;
        
        emit PriceFeedUpdated(asset, oldFeed, feedAddress);
    }

    /**
     * @notice Remove price feed for an asset
     */
    function removePriceFeed(address asset) external override onlyRole(ADMIN_ROLE) {
        require(hasFeed[asset], "PriceOracle: Feed not found");
        
        address feedAddress = priceFeeds[asset].feedAddress;
        delete priceFeeds[asset];
        hasFeed[asset] = false;
        
        emit PriceFeedRemoved(asset, feedAddress);
    }

    /**
     * @notice Set emergency price for an asset
     */
    function setEmergencyPrice(
        address asset,
        uint256 price,
        string calldata reason
    ) external override onlyRole(EMERGENCY_ROLE) {
        require(asset != address(0), "PriceOracle: Invalid asset");
        require(price > 0, "PriceOracle: Invalid price");
        
        emergencyPrices[asset] = price;
        hasEmergencyPrice[asset] = true;
        
        _setPrice(asset, price, 100, true); // 100% confidence for emergency price
        
        emit EmergencyPriceSet(asset, price, msg.sender, reason);
    }

    /**
     * @notice Remove emergency price for an asset
     */
    function removeEmergencyPrice(address asset) external onlyRole(EMERGENCY_ROLE) {
        require(hasEmergencyPrice[asset], "PriceOracle: No emergency price set");
        
        delete emergencyPrices[asset];
        hasEmergencyPrice[asset] = false;
    }

    /**
     * @notice Enable or disable circuit breaker for an asset
     */
    function setCircuitBreaker(
        address asset,
        bool enabled,
        uint256 threshold
    ) external override onlyRole(ADMIN_ROLE) {
        require(threshold <= MAX_PRICE_DEVIATION, "PriceOracle: Threshold too high");
        
        circuitBreakers[asset] = CircuitBreaker({
            enabled: enabled,
            threshold: threshold,
            lastTriggerTime: 0,
            cooldownPeriod: 3600, // 1 hour default
            isTriggered: false
        });
    }

    /**
     * @notice Reset circuit breaker for an asset
     */
    function resetCircuitBreaker(address asset) external onlyRole(ADMIN_ROLE) {
        CircuitBreaker storage breaker = circuitBreakers[asset];
        require(breaker.isTriggered, "PriceOracle: Circuit breaker not triggered");
        require(
            block.timestamp >= breaker.lastTriggerTime + breaker.cooldownPeriod,
            "PriceOracle: Cooldown period not met"
        );
        
        breaker.isTriggered = false;
    }

    /**
     * @notice Set fallback price oracle
     */
    function setFallbackOracle(address _fallbackOracle) external override onlyRole(ADMIN_ROLE) {
        fallbackOracle = _fallbackOracle;
    }

    /**
     * @notice Pause price feeds
     */
    function pausePriceFeeds() external override onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Resume price feeds
     */
    function resumePriceFeeds() external override onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Set price directly (admin only, for testing/emergency)
     */
    function setPrice(address asset, uint256 price, uint256 confidence) external onlyRole(ADMIN_ROLE) {
        _setPrice(asset, price, confidence, false);
    }

    /**
     * @notice Batch set prices (admin only)
     */
    function batchSetPrices(
        address[] calldata assets,
        uint256[] calldata prices,
        uint256[] calldata confidences
    ) external onlyRole(ADMIN_ROLE) {
        require(assets.length == prices.length, "PriceOracle: Length mismatch");
        require(assets.length == confidences.length, "PriceOracle: Length mismatch");
        
        for (uint256 i = 0; i < assets.length; i++) {
            _setPrice(assets[i], prices[i], confidences[i], false);
        }
    }

    /**
     * @notice Grant price updater role
     */
    function grantPriceUpdaterRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(PRICE_UPDATER_ROLE, account);
    }

    /**
     * @notice Revoke price updater role
     */
    function revokePriceUpdaterRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(PRICE_UPDATER_ROLE, account);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get oracle statistics
     */
    function getOracleStats() external view returns (
        uint256 totalUpdates,
        uint256 totalCircuitBreakers,
        uint256 last24hUpdates,
        uint256 activeFeedsCount
    ) {
        // Count active feeds
        // Note: This is inefficient for large numbers of assets
        // In production, you'd maintain a counter
        activeFeedsCount = 0; // Simplified for this implementation
        
        return (
            totalPriceUpdates,
            totalCircuitBreakerTriggers,
            last24hPriceUpdates,
            activeFeedsCount
        );
    }

    /**
     * @notice Get price volatility for an asset
     */
    function getPriceVolatility(address asset, uint256 periods) external view returns (uint256 volatility) {
        uint256[] storage prices = priceHistory[asset];
        if (prices.length < 2 || periods == 0) return 0;
        
        uint256 startIndex = prices.length > periods ? prices.length - periods : 0;
        uint256 count = prices.length - startIndex;
        
        if (count < 2) return 0;
        
        // Calculate returns
        uint256[] memory returns = new uint256[](count - 1);
        for (uint256 i = 1; i < count; i++) {
            if (prices[startIndex + i - 1] > 0) {
                returns[i - 1] = prices[startIndex + i].mulDiv(PRECISION, prices[startIndex + i - 1]);
            }
        }
        
        // Calculate standard deviation of returns
        volatility = Math.standardDeviation(returns);
    }

    /**
     * @notice Get price correlation between two assets
     */
    function getPriceCorrelation(address asset1, address asset2, uint256 periods) external view returns (int256 correlation) {
        uint256[] storage prices1 = priceHistory[asset1];
        uint256[] storage prices2 = priceHistory[asset2];
        
        uint256 minLength = prices1.length < prices2.length ? prices1.length : prices2.length;
        if (minLength < 2 || periods == 0) return 0;
        
        uint256 startIndex = minLength > periods ? minLength - periods : 0;
        uint256 count = minLength - startIndex;
        
        if (count < 2) return 0;
        
        // Extract price arrays for correlation calculation
        uint256[] memory x = new uint256[](count);
        uint256[] memory y = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            x[i] = prices1[startIndex + i];
            y[i] = prices2[startIndex + i];
        }
        
        correlation = Math.correlation(x, y);
    }

    /**
     * @notice Check if prices are stale
     */
    function getStaleAssets() external view returns (address[] memory staleAssets) {
        // This is a simplified implementation
        // In production, you'd maintain an array of all assets
        staleAssets = new address[](0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event CircuitBreakerTriggered(
        address indexed asset,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 changePercentage
    );
}