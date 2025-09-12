// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IDIAOracleV2.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title PriceOracle
 * @dev Somnia-optimized price oracle with DIA Oracle integration
 * @notice Features:
 * - DIA Oracle integration for secure, decentralized price feeds
 * - Native STT pricing support
 * - Real-time price updates leveraging Somnia's speed
 * - Circuit breaker protection against price manipulation
 * - Multi-source price validation
 * - Sub-second price propagation
 */
contract PriceOracle is IPriceOracle, AccessControl, Pausable {
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE =
        keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_PRICE_DEVIATION = 50e16; // 50%
    uint256 public constant DEFAULT_HEARTBEAT = 3600; // 1 hour
    uint256 public constant MAX_PRICE_AGE = 86400; // 24 hours

    // Somnia-specific constants
    address public constant NATIVE_STT = address(0);
    string public constant STT_PRICE_KEY = "STT/USD";
    uint256 public constant DIA_ORACLE_DECIMALS = 8;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    // DIA Oracle integration
    IDIAOracleV2 public immutable diaOracle;

    // Asset to DIA Oracle key mapping
    mapping(address => string) public assetToDIAKey;
    mapping(address => uint256) public assetDecimals;

    // Native STT price feeds and validation
    mapping(address => PriceFeed) public priceFeeds;

    // Price data structures

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

    constructor(address admin, address _diaOracle) {
        require(admin != address(0), "PriceOracle: Invalid admin");
        require(_diaOracle != address(0), "PriceOracle: Invalid DIA oracle");

        diaOracle = IDIAOracleV2(_diaOracle);

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
    function getPrice(
        address asset
    ) external view override returns (uint256 price) {
        return _getValidPrice(asset);
    }

    /**
     * @notice Get detailed price data for an asset
     */
    function getPriceData(
        address asset
    ) external view override returns (PriceData memory) {
        PriceEntry memory entry = priceData[asset];

        return
            PriceData({
                price: entry.price,
                timestamp: entry.timestamp,
                confidence: entry.confidence,
                isValid: entry.isValid && _isPriceValid(asset)
            });
    }

    /**
     * @notice Maps an asset to its DIA Oracle price feed key
     * @param asset The address of the asset (use address(0) for native STT)
     * @param diaKey The DIA Oracle key (e.g., "STT/USD", "BTC/USD")
     * @param decimals The number of decimals the asset has (e.g., 18 for ETH, 6 for USDC)
     */
    function setAssetDIAKey(
        address asset,
        string calldata diaKey,
        uint256 decimals
    ) external onlyRole(ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        require(bytes(diaKey).length > 0, "Invalid DIA key");
        require(decimals <= 18, "Decimals too high");

        assetToDIAKey[asset] = diaKey;
        assetDecimals[asset] = decimals;

        // This will now work because the event is declared
        emit DIAKeySet(asset, diaKey, decimals);
    }

    /**
     * @notice Get prices for multiple assets
     */
    function getPrices(
        address[] calldata assets
    ) external view override returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = _getValidPrice(assets[i]);
        }
    }

    /**
     * @notice Get the value of an amount in USD
     */
    function getAssetValue(
        address asset,
        uint256 amount
    ) external view override returns (uint256 valueUSD) {
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
    function isPriceValid(
        address asset
    ) external view override returns (bool isValid, uint256 age) {
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
    function getPriceFeed(
        address asset
    ) external view override returns (PriceFeed memory) {
        return priceFeeds[asset];
    }

    /**
     * @notice Get price confidence level
     */
    function getPriceConfidence(
        address asset
    ) external view override returns (uint256 confidence) {
        return priceData[asset].confidence;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME FEATURES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Force price update for an asset
     */
    function updatePrice(
        address asset
    ) external override onlyRole(PRICE_UPDATER_ROLE) whenNotPaused {
        _updateAssetPrice(asset);
    }

    /**
     * @notice Batch update prices for multiple assets
     */
    function batchUpdatePrices(
        address[] calldata assets
    ) external override onlyRole(PRICE_UPDATER_ROLE) whenNotPaused {
        for (uint256 i = 0; i < assets.length; i++) {
            _updateAssetPrice(assets[i]);
        }
    }

    /**
     * @notice Get real-time price with circuit breaker check
     */
    function getRealTimePrice(
        address asset
    )
        external
        view
        override
        returns (uint256 price, bool isCircuitBreakerTriggered)
    {
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
    )
        external
        view
        override
        returns (uint256[] memory timestamps, uint256[] memory prices)
    {
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
                try IPriceOracle(fallbackOracle).getPrice(asset) returns (
                    uint256 fallbackPrice
                ) {
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
        if (
            hasFeed[asset] && block.timestamp - entry.timestamp > feed.heartbeat
        ) return false;

        return true;
    }

    function _updateAssetPrice(address asset) internal {
        if (!hasFeed[asset]) revert("PriceOracle: No feed for asset");

        PriceFeed memory feed = priceFeeds[asset];
        if (!feed.isActive) revert("PriceOracle: Feed inactive");

        // 1. Get the DIA key for this asset
        string memory diaKey = assetToDIAKey[asset];
        require(
            bytes(diaKey).length > 0,
            "PriceOracle: DIA key not set for asset"
        );

        // 2. FETCH THE PRICE FROM DIA ORACLE
        (uint256 price, uint256 timestamp) = diaOracle.getValue(diaKey); // <-- THE CRITICAL LINE

        // 3. Validate the price is fresh
        require(
            block.timestamp - timestamp <= feed.heartbeat,
            "PriceOracle: Price too stale"
        );

        // 4. Convert DIA's 8-decimals to internal 18-decimals
        // Example: If DIA returns 1e8 (1.00000000), we need to make it 1e18
        uint256 convertedPrice = price * (10 ** (18 - DIA_ORACLE_DECIMALS));

        // 5. Check for circuit breaker
        _checkCircuitBreaker(asset, convertedPrice);

        // 6. Get the old price for the event
        uint256 oldPrice = priceData[asset].price;

        // 7. Update storage with the NEW, FRESH price
        priceData[asset] = PriceEntry({
            price: convertedPrice,
            timestamp: timestamp, // Use the timestamp from DIA, not block.timestamp!
            confidence: 100, // Or calculate this based on deviation
            isValid: true,
            isEmergency: false
        });

        // 8. Update history and metrics
        _updatePriceHistory(asset, convertedPrice, block.timestamp);
        totalPriceUpdates++;
        _update24hMetrics();

        // 9. Emit event with the actual change
        emit PriceUpdated(asset, oldPrice, convertedPrice, timestamp);
    }

    function _updatePriceHistory(
        address asset,
        uint256 price,
        uint256 timestamp
    ) internal {
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
        uint256 priceChange = entry.price > newPrice
            ? entry.price - newPrice
            : newPrice - entry.price;
        uint256 changePercentage = priceChange.mulDiv(PRECISION, entry.price);

        // Trigger circuit breaker if change exceeds threshold
        if (changePercentage > breaker.threshold) {
            breaker.isTriggered = true;
            breaker.lastTriggerTime = block.timestamp;
            totalCircuitBreakerTriggers++;

            emit CircuitBreakerTriggered(
                asset,
                entry.price,
                newPrice,
                changePercentage
            );
        }
    }

    function _setPrice(
        address asset,
        uint256 price,
        uint256 confidence,
        bool isEmergency
    ) internal {
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
        require(
            deviation <= MAX_PRICE_DEVIATION,
            "PriceOracle: Deviation too high"
        );

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
    function removePriceFeed(
        address asset
    ) external override onlyRole(ADMIN_ROLE) {
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
    function removeEmergencyPrice(
        address asset
    ) external onlyRole(EMERGENCY_ROLE) {
        require(
            hasEmergencyPrice[asset],
            "PriceOracle: No emergency price set"
        );

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
        require(
            threshold <= MAX_PRICE_DEVIATION,
            "PriceOracle: Threshold too high"
        );

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
        require(
            breaker.isTriggered,
            "PriceOracle: Circuit breaker not triggered"
        );
        require(
            block.timestamp >= breaker.lastTriggerTime + breaker.cooldownPeriod,
            "PriceOracle: Cooldown period not met"
        );

        breaker.isTriggered = false;
    }

    /**
     * @notice Set fallback price oracle
     */
    function setFallbackOracle(
        address _fallbackOracle
    ) external override onlyRole(ADMIN_ROLE) {
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
    function setPrice(
        address asset,
        uint256 price,
        uint256 confidence
    ) external onlyRole(ADMIN_ROLE) {
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
        require(
            assets.length == confidences.length,
            "PriceOracle: Length mismatch"
        );

        for (uint256 i = 0; i < assets.length; i++) {
            _setPrice(assets[i], prices[i], confidences[i], false);
        }
    }

    /**
     * @notice Grant price updater role
     */
    function grantPriceUpdaterRole(
        address account
    ) external onlyRole(ADMIN_ROLE) {
        _grantRole(PRICE_UPDATER_ROLE, account);
    }

    /**
     * @notice Revoke price updater role
     */
    function revokePriceUpdaterRole(
        address account
    ) external onlyRole(ADMIN_ROLE) {
        _revokeRole(PRICE_UPDATER_ROLE, account);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get oracle statistics
     */
    function getOracleStats()
        external
        view
        returns (
            uint256 totalUpdates,
            uint256 totalCircuitBreakers,
            uint256 last24hUpdates,
            uint256 activeFeedsCount
        )
    {
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
    function getPriceVolatility(
        address asset,
        uint256 periods
    ) external view returns (uint256 volatility) {
        uint256[] storage prices = priceHistory[asset];
        if (prices.length < 2 || periods == 0) return 0;

        uint256 startIndex = prices.length > periods
            ? prices.length - periods
            : 0;
        uint256 count = prices.length - startIndex;

        if (count < 2) return 0;

        // Calculate price returns
        uint256[] memory priceReturns = new uint256[](count - 1);
        for (uint256 i = 1; i < count; i++) {
            if (prices[startIndex + i - 1] > 0) {
                priceReturns[i - 1] = prices[startIndex + i].mulDiv(
                    PRECISION,
                    prices[startIndex + i - 1]
                );
            }
        }

        // Calculate standard deviation of price returns
        volatility = _calculateStandardDeviation(priceReturns);
    }

    /**
     * @notice Get price correlation between two assets
     */
    function getPriceCorrelation(
        address asset1,
        address asset2,
        uint256 periods
    ) external view returns (int256 correlation) {
        uint256[] storage prices1 = priceHistory[asset1];
        uint256[] storage prices2 = priceHistory[asset2];

        uint256 minLength = prices1.length < prices2.length
            ? prices1.length
            : prices2.length;
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

        correlation = _calculateCorrelation(x, y);
    }

    /**
     * @notice Check if prices are stale
     */
    function getStaleAssets()
        external
        pure
        returns (address[] memory staleAssets)
    {
        // This is a simplified implementation
        // In production, you'd maintain an array of all assets
        staleAssets = new address[](0);
    }

    /**
     * @notice Calculate standard deviation of an array
     * @param values Array of values
     * @return stdDev Standard deviation
     */
    function _calculateStandardDeviation(
        uint256[] memory values
    ) private pure returns (uint256 stdDev) {
        if (values.length < 2) return 0;

        // Calculate mean
        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }
        uint256 mean = sum / values.length;

        // Calculate variance
        uint256 variance = 0;
        for (uint256 i = 0; i < values.length; i++) {
            uint256 diff = values[i] > mean
                ? values[i] - mean
                : mean - values[i];
            variance += (diff * diff) / values.length;
        }

        // Calculate standard deviation (simple square root approximation)
        stdDev = Math.sqrt(variance);
    }

    /**
     * @notice Calculate correlation between two arrays
     * @param x First array
     * @param y Second array
     * @return correlation Correlation coefficient (scaled by 1e18)
     */
    function _calculateCorrelation(
        uint256[] memory x,
        uint256[] memory y
    ) private pure returns (int256 correlation) {
        if (x.length != y.length || x.length < 2) return 0;

        // Calculate means
        uint256 sumX = 0;
        uint256 sumY = 0;
        for (uint256 i = 0; i < x.length; i++) {
            sumX += x[i];
            sumY += y[i];
        }
        uint256 meanX = sumX / x.length;
        uint256 meanY = sumY / y.length;

        // Calculate correlation numerator and denominators
        int256 numerator = 0;
        uint256 sumXSquared = 0;
        uint256 sumYSquared = 0;

        for (uint256 i = 0; i < x.length; i++) {
            int256 diffX = int256(x[i]) - int256(meanX);
            int256 diffY = int256(y[i]) - int256(meanY);

            numerator += (diffX * diffY) / int256(x.length);
            sumXSquared += uint256((diffX * diffX)) / x.length;
            sumYSquared += uint256((diffY * diffY)) / x.length;
        }

        // Calculate correlation (simplified)
        uint256 denominator = Math.sqrt(sumXSquared * sumYSquared);
        correlation = denominator > 0
            ? (numerator * int256(PRECISION)) / int256(denominator)
            : int256(0);
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
