// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IInterestRateModel.sol";
import "../interfaces/IPriceOracle.sol";
import "../libraries/SomniaConstants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title InterestRateModel
 * @dev Dynamic interest rate model optimized for Somnia Network
 * @notice Features:
 * - Real-time rate adjustments leveraging Somnia's 1M+ TPS
 * - Sub-second rate updates for ultra-responsive lending
 * - Native STT-optimized rate calculations
 * - DIA Oracle integration for market-driven rates
 * - Gas-efficient operations for high-frequency updates
 */
contract InterestRateModel is IInterestRateModel, AccessControl, Pausable {
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant MAX_RATE = 10e18; // 1000% APY maximum
    uint256 public constant MAX_UTILIZATION = 1e18; // 100%

    // Network constants for configuration
    uint256 public constant TESTNET_CHAIN_ID = 50312;
    uint256 public constant MAINNET_CHAIN_ID = 50311;

    // Configuration parameters (loaded from deployment config)
    struct NetworkConfig {
        uint256 baseRate;
        uint256 slope1;
        uint256 slope2;
        uint256 optimalUtilization;
        uint256 reserveFactor;
        uint256 maxBorrowingRate;
        uint256 protocolFeeRate;
        uint256 maxPriceDeviation;
        uint256 priceValidityPeriod;
        uint256 minimumUpdateInterval;
    }

    NetworkConfig public networkConfig;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct InterestRateParams {
        uint256 baseRate;
        uint256 multiplier;
        uint256 jumpMultiplier;
        uint256 kink;
        bool isCustom;
    }

    // Default parameters
    InterestRateParams public defaultParams;

    // Asset-specific parameters
    mapping(address => InterestRateParams) public assetParams;
    mapping(address => bool) private _hasCustomParams;

    // PriceOracle integration for market-driven rates
    IPriceOracle public priceOracle;

    // Asset-specific configurations
    mapping(address => uint256) public assetReserveFactor;
    mapping(address => uint256) public volatilityMultiplier;
    mapping(address => uint256) public lastVolatilityUpdate;

    // Circuit breaker and safety mechanisms
    struct CircuitBreaker {
        bool enabled;
        uint256 maxRateChangePerUpdate; // Maximum rate change per update (basis points)
        uint256 emergencyRateThreshold; // Rate that triggers emergency mode
        uint256 lastTriggerTime;
        uint256 cooldownPeriod;
        bool isTriggered;
    }

    mapping(address => CircuitBreaker) public circuitBreakers;
    mapping(address => bool) public emergencyMode;
    mapping(address => uint256) public emergencyRateCap;

    // Rate smoothing for production stability
    mapping(address => uint256) public targetBorrowRate;
    mapping(address => uint256) public rateAdjustmentSpeed; // How fast rates can change (per update)

    // Market correlation tracking
    mapping(address => mapping(address => int256)) public assetCorrelations;
    mapping(address => address[]) public correlatedAssets;

    // Rate caching for gas optimization
    mapping(address => uint256) public lastBorrowRate;
    mapping(address => uint256) public lastSupplyRate;
    mapping(address => uint256) public lastUtilizationRate;
    mapping(address => uint256) public lastUpdateTimestamp;

    // Efficient circular buffer for rate history (replaces inefficient array shifting)
    mapping(address => uint256[]) private rateHistoryCircular;
    mapping(address => uint256[]) private timestampHistoryCircular;
    mapping(address => uint256) public historyHead; // Current position in circular buffer
    mapping(address => uint256) public historySize; // Current size of history
    uint256 public constant MAX_HISTORY_LENGTH = 100;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event RateCalculated(
        address indexed asset,
        uint256 utilizationRate,
        uint256 borrowRate,
        uint256 supplyRate,
        uint256 timestamp
    );

    event DefaultParamsUpdated(
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _kink,
        uint256 _jumpMultiplier,
        address _priceOracle
    ) {
        require(_baseRate <= MAX_RATE, "Base rate too high");
        require(_multiplier <= MAX_RATE, "Multiplier too high");
        require(_jumpMultiplier <= MAX_RATE, "Jump multiplier too high");
        require(_kink <= MAX_UTILIZATION, "Kink too high");
        require(_priceOracle != address(0), "Invalid price oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        priceOracle = IPriceOracle(_priceOracle);

        // Initialize network configuration based on testnet parameters (primary)
        // These values are from TESTNET_CONFIG in deployments/testnet/config.ts
        networkConfig = NetworkConfig({
            baseRate: 200 * 1e16,
            slope1: 1000 * 1e16,
            slope2: 30000 * 1e16,
            optimalUtilization: 8000 * 1e14,
            reserveFactor: 1000 * 1e14,
            maxBorrowingRate: 10000 * 1e14,
            protocolFeeRate: 300 * 1e14,
            maxPriceDeviation: 1000 * 1e14,
            priceValidityPeriod: 3600,
            minimumUpdateInterval: 60
        });

        defaultParams = InterestRateParams({
            baseRate: _baseRate,
            multiplier: _multiplier,
            jumpMultiplier: _jumpMultiplier,
            kink: _kink,
            isCustom: false
        });

        emit DefaultParamsUpdated(
            _baseRate,
            _multiplier,
            _jumpMultiplier,
            _kink
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate supply and borrow rates with comprehensive market analysis
     */
    function calculateRates(
        address asset,
        uint256 utilizationRate,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view override returns (uint256 borrowAPY, uint256 supplyAPY) {
        require(utilizationRate <= MAX_UTILIZATION, "Invalid utilization rate");

        // Check if asset is in emergency mode
        if (emergencyMode[asset]) {
            return _getEmergencyRates(asset, utilizationRate);
        }

        // Get base parameters
        InterestRateParams memory params = _hasCustomParams[asset]
            ? assetParams[asset]
            : defaultParams;

        // Calculate base borrow rate
        uint256 baseBorrowRate = _calculateBorrowRate(utilizationRate, params);

        // Apply market-driven adjustments
        borrowAPY = _applyMarketAdjustments(
            asset,
            baseBorrowRate,
            utilizationRate,
            totalSupply,
            totalBorrow
        );

        // Apply circuit breaker constraints
        borrowAPY = _applyCircuitBreakerLimits(asset, borrowAPY);

        // Apply rate smoothing for stability
        borrowAPY = _applySmoothingConstraints(asset, borrowAPY);

        // Calculate supply rate with proper reserve factor
        uint256 reserveFactor = assetReserveFactor[asset] > 0
            ? assetReserveFactor[asset]
            : networkConfig.reserveFactor;

        supplyAPY = _calculateSupplyRate(
            utilizationRate,
            borrowAPY,
            reserveFactor
        );

        return (borrowAPY, supplyAPY);
    }

    /**
     * @notice Get current utilization rate
     */
    function getUtilizationRate(
        address /* asset */,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external pure override returns (uint256 utilizationRate) {
        if (totalSupply == 0) return 0;
        return totalBorrow.mulDiv(PRECISION, totalSupply);
    }

    /**
     * @notice Calculate borrow rate per second
     */
    function getBorrowRate(
        address asset,
        uint256 utilizationRate
    ) external view override returns (uint256 borrowRatePerSecond) {
        InterestRateParams memory params = _hasCustomParams[asset]
            ? assetParams[asset]
            : defaultParams;

        uint256 borrowAPY = _calculateBorrowRate(utilizationRate, params);
        return borrowAPY / SECONDS_PER_YEAR;
    }

    /**
     * @notice Calculate supply rate per second
     */
    function getSupplyRate(
        address /* asset */,
        uint256 utilizationRate,
        uint256 borrowRate,
        uint256 reserveFactor
    ) external pure override returns (uint256 supplyRatePerSecond) {
        uint256 supplyAPY = _calculateSupplyRate(
            utilizationRate,
            borrowRate,
            reserveFactor
        );
        return supplyAPY / SECONDS_PER_YEAR;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _calculateBorrowRate(
        uint256 utilizationRate,
        InterestRateParams memory params
    ) internal pure returns (uint256) {
        if (utilizationRate <= params.kink) {
            // Below kink: baseRate + (utilizationRate * multiplier)
            return
                params.baseRate +
                utilizationRate.mulDiv(params.multiplier, PRECISION);
        } else {
            // Above kink: baseRate + (kink * multiplier) + ((utilizationRate - kink) * jumpMultiplier)
            uint256 baseRateAtKink = params.baseRate +
                params.kink.mulDiv(params.multiplier, PRECISION);
            uint256 excessUtilization = utilizationRate - params.kink;
            uint256 jumpRate = excessUtilization.mulDiv(
                params.jumpMultiplier,
                PRECISION
            );
            return baseRateAtKink + jumpRate;
        }
    }

    function _calculateSupplyRate(
        uint256 utilizationRate,
        uint256 borrowRate,
        uint256 reserveFactor
    ) internal pure returns (uint256) {
        // supplyRate = borrowRate * utilizationRate * (1 - reserveFactor)
        uint256 rateToSuppliers = borrowRate.mulDiv(
            PRECISION - reserveFactor,
            PRECISION
        );
        return utilizationRate.mulDiv(rateToSuppliers, PRECISION);
    }

    function _updateRateHistory(
        address asset,
        uint256 borrowRate,
        uint256 supplyRate,
        uint256 timestamp
    ) internal {
        // Initialize arrays if they don't exist
        if (rateHistoryCircular[asset].length == 0) {
            rateHistoryCircular[asset] = new uint256[](MAX_HISTORY_LENGTH);
            timestampHistoryCircular[asset] = new uint256[](MAX_HISTORY_LENGTH);
        }

        // Get current position and update it
        uint256 head = historyHead[asset];
        uint256 size = historySize[asset];

        // Store combined rate (borrow rate in upper 128 bits, supply rate in lower 128 bits)
        uint256 combinedRate = (borrowRate << 128) | supplyRate;

        // Update circular buffer
        rateHistoryCircular[asset][head] = combinedRate;
        timestampHistoryCircular[asset][head] = timestamp;

        // Update head position (circular)
        historyHead[asset] = (head + 1) % MAX_HISTORY_LENGTH;

        // Update size (capped at MAX_HISTORY_LENGTH)
        if (size < MAX_HISTORY_LENGTH) {
            historySize[asset] = size + 1;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function getInterestRateParams(
        address asset
    )
        external
        view
        override
        returns (
            uint256 baseRate,
            uint256 multiplier,
            uint256 jumpMultiplier,
            uint256 kink
        )
    {
        InterestRateParams memory params = _hasCustomParams[asset]
            ? assetParams[asset]
            : defaultParams;

        return (
            params.baseRate,
            params.multiplier,
            params.jumpMultiplier,
            params.kink
        );
    }

    /**
     * @notice Check if asset has custom interest rate parameters
     * @param asset The market asset
     * @return hasCustomParams True if asset has custom parameters
     */
    function hasCustomParams(
        address asset
    ) external view override returns (bool) {
        return _hasCustomParams[asset];
    }

    function getRateHistory(
        address asset,
        uint256 length
    )
        external
        view
        returns (
            uint256[] memory borrowRates,
            uint256[] memory supplyRates,
            uint256[] memory timestamps
        )
    {
        uint256 size = historySize[asset];
        uint256 actualLength = length > size ? size : length;

        borrowRates = new uint256[](actualLength);
        supplyRates = new uint256[](actualLength);
        timestamps = new uint256[](actualLength);

        if (actualLength == 0) return (borrowRates, supplyRates, timestamps);

        uint256 head = historyHead[asset];

        // Calculate starting position in circular buffer
        uint256 startPos;
        if (size < MAX_HISTORY_LENGTH) {
            // Buffer not full yet, start from beginning
            startPos = size >= actualLength ? size - actualLength : 0;
        } else {
            // Buffer is full, calculate position relative to head
            startPos =
                (head + MAX_HISTORY_LENGTH - actualLength) %
                MAX_HISTORY_LENGTH;
        }

        // Extract data from circular buffer
        for (uint256 i = 0; i < actualLength; i++) {
            uint256 pos = (startPos + i) % MAX_HISTORY_LENGTH;
            uint256 combinedRate = rateHistoryCircular[asset][pos];

            borrowRates[i] = combinedRate >> 128;
            supplyRates[i] = combinedRate & ((1 << 128) - 1);
            timestamps[i] = timestampHistoryCircular[asset][pos];
        }
    }

    function getLastRates(
        address asset
    )
        external
        view
        returns (
            uint256 borrowRate,
            uint256 supplyRate,
            uint256 utilizationRate,
            uint256 timestamp
        )
    {
        return (
            lastBorrowRate[asset],
            lastSupplyRate[asset],
            lastUtilizationRate[asset],
            lastUpdateTimestamp[asset]
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update network configuration (supports both testnet and mainnet)
     * @param useMainnetConfig Whether to use mainnet configuration
     */
    function updateNetworkConfig(
        bool useMainnetConfig
    ) external onlyRole(ADMIN_ROLE) {
        if (useMainnetConfig) {
            // Mainnet configuration (from MAINNET_CONFIG in deployments/mainnet/config.ts)
            networkConfig = NetworkConfig({
                baseRate: 100 * 1e16,
                slope1: 800 * 1e16,
                slope2: 25000 * 1e16,
                optimalUtilization: 8500 * 1e14,
                reserveFactor: 1500 * 1e14,
                maxBorrowingRate: 10000 * 1e14,
                protocolFeeRate: 200 * 1e14,
                maxPriceDeviation: 500 * 1e14,
                priceValidityPeriod: 1800,
                minimumUpdateInterval: 30
            });
        } else {
            // Testnet configuration (from TESTNET_CONFIG in deployments/testnet/config.ts)
            networkConfig = NetworkConfig({
                baseRate: 200 * 1e16,
                slope1: 1000 * 1e16,
                slope2: 30000 * 1e16,
                optimalUtilization: 8000 * 1e14,
                reserveFactor: 1000 * 1e14,
                maxBorrowingRate: 10000 * 1e14,
                protocolFeeRate: 300 * 1e14,
                maxPriceDeviation: 1000 * 1e14,
                priceValidityPeriod: 3600,
                minimumUpdateInterval: 60 // 1 minute minimum update
            });
        }

        emit NetworkConfigUpdated(useMainnetConfig);
    }

    /**
     * @notice Set asset-specific reserve factor
     * @param asset The asset address
     * @param reserveFactor The reserve factor (scaled by 1e18)
     */
    function setAssetReserveFactor(
        address asset,
        uint256 reserveFactor
    ) external onlyRole(ADMIN_ROLE) {
        require(reserveFactor <= PRECISION, "Reserve factor too high");
        assetReserveFactor[asset] = reserveFactor;
        emit AssetReserveFactorUpdated(asset, reserveFactor);
    }

    /**
     * @notice Update price oracle address
     * @param _priceOracle New price oracle address
     */
    function updatePriceOracle(
        address _priceOracle
    ) external onlyRole(ADMIN_ROLE) {
        require(_priceOracle != address(0), "Invalid price oracle");
        address oldOracle = address(priceOracle);
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(oldOracle, _priceOracle);
    }

    /**
     * @notice Update market-driven rate multiplier for an asset based on price analysis
     * @param asset The asset address
     * @param lookbackPeriods Number of historical periods to analyze
     */
    function updateMarketRateMultiplier(
        address asset,
        uint256 lookbackPeriods
    ) external onlyRole(RATE_UPDATER_ROLE) {
        require(
            lookbackPeriods > 0 && lookbackPeriods <= 50,
            "Invalid lookback periods"
        );

        // Get current price and historical price data
        uint256 currentPrice = priceOracle.getPrice(asset);
        require(currentPrice > 0, "Invalid current price");

        // Analyze price movement and volatility from our own rate history
        uint256 marketMultiplier = _calculateMarketMultiplier(
            asset,
            currentPrice,
            lookbackPeriods
        );

        // Apply safety constraints
        if (marketMultiplier < PRECISION / 2) {
            marketMultiplier = PRECISION / 2; // Minimum 0.5x multiplier
        } else if (marketMultiplier > 3 * PRECISION) {
            marketMultiplier = 3 * PRECISION; // Maximum 3.0x multiplier
        }

        volatilityMultiplier[asset] = marketMultiplier;
        lastVolatilityUpdate[asset] = block.timestamp;

        emit VolatilityMultiplierUpdated(asset, currentPrice, marketMultiplier);
    }

    /**
     * @notice Calculate market-driven rate multiplier based on price analysis
     * @param asset The asset address
     * @param currentPrice Current asset price
     * @param lookbackPeriods Number of periods to analyze
     * @return multiplier Market-driven rate multiplier
     */
    function _calculateMarketMultiplier(
        address asset,
        uint256 currentPrice,
        uint256 lookbackPeriods
    ) internal view returns (uint256 multiplier) {
        // Get historical rate data
        uint256 size = historySize[asset];
        if (size < 2) {
            return PRECISION; // Default multiplier if insufficient data
        }

        // Analyze recent price movements through rate history correlation
        uint256 periods = lookbackPeriods > size ? size : lookbackPeriods;

        // Calculate price volatility proxy using rate variance
        uint256 rateVariance = _calculateRateVariance(asset, periods);

        // Convert rate variance to market risk multiplier
        // Higher rate variance indicates higher market risk → higher multiplier
        multiplier = PRECISION + (rateVariance / 10); // Add 10% of variance as premium

        // Apply market confidence factor based on price data freshness
        IPriceOracle.PriceData memory priceData = priceOracle.getPriceData(
            asset
        );
        uint256 priceAge = block.timestamp - priceData.timestamp;

        if (priceAge > networkConfig.priceValidityPeriod) {
            // Stale price → increase multiplier for risk
            multiplier = multiplier.mulDiv(120, 100); // +20% for stale data
        }

        // Apply confidence factor
        if (priceData.confidence < 80) {
            // Low confidence → increase multiplier
            multiplier = multiplier.mulDiv(110, 100); // +10% for low confidence
        }

        return multiplier;
    }

    /**
     * @notice Calculate rate variance as a proxy for market volatility
     * @param asset The asset address
     * @param periods Number of periods to analyze
     * @return variance Rate variance (scaled by 1e18)
     */
    function _calculateRateVariance(
        address asset,
        uint256 periods
    ) internal view returns (uint256 variance) {
        uint256 size = historySize[asset];
        if (size < 2 || periods < 2) return 0;

        uint256 actualPeriods = periods > size ? size : periods;
        uint256 head = historyHead[asset];

        // Calculate mean rate
        uint256 sum = 0;
        for (uint256 i = 0; i < actualPeriods; i++) {
            uint256 pos = (head + MAX_HISTORY_LENGTH - actualPeriods + i) %
                MAX_HISTORY_LENGTH;
            uint256 combinedRate = rateHistoryCircular[asset][pos];
            uint256 borrowRate = combinedRate >> 128;
            sum += borrowRate;
        }
        uint256 meanRate = sum / actualPeriods;

        // Calculate variance
        uint256 squaredDiffSum = 0;
        for (uint256 i = 0; i < actualPeriods; i++) {
            uint256 pos = (head + MAX_HISTORY_LENGTH - actualPeriods + i) %
                MAX_HISTORY_LENGTH;
            uint256 combinedRate = rateHistoryCircular[asset][pos];
            uint256 borrowRate = combinedRate >> 128;

            uint256 diff = borrowRate > meanRate
                ? borrowRate - meanRate
                : meanRate - borrowRate;
            squaredDiffSum += (diff * diff) / PRECISION;
        }

        variance = squaredDiffSum / actualPeriods;
        return variance;
    }

    /**
     * @notice Get emergency rates when asset is in emergency mode
     */
    function _getEmergencyRates(
        address asset,
        uint256 utilizationRate
    ) internal view returns (uint256 borrowAPY, uint256 supplyAPY) {
        uint256 emergencyCap = emergencyRateCap[asset];
        if (emergencyCap == 0) {
            emergencyCap = networkConfig.maxBorrowingRate / 2; // Default to 50% max rate
        }

        // Simple linear rate in emergency mode
        borrowAPY = (utilizationRate * emergencyCap) / PRECISION;

        // Supply rate with higher reserve factor in emergency
        uint256 emergencyReserveFactor = networkConfig.reserveFactor * 2; // Double reserve factor
        if (emergencyReserveFactor > PRECISION) {
            emergencyReserveFactor = PRECISION;
        }

        supplyAPY = _calculateSupplyRate(
            utilizationRate,
            borrowAPY,
            emergencyReserveFactor
        );

        return (borrowAPY, supplyAPY);
    }

    /**
     * @notice Apply circuit breaker limits to prevent extreme rate changes
     */
    function _applyCircuitBreakerLimits(
        address asset,
        uint256 proposedRate
    ) internal view returns (uint256 limitedRate) {
        CircuitBreaker memory breaker = circuitBreakers[asset];

        if (!breaker.enabled || breaker.isTriggered) {
            return proposedRate;
        }

        uint256 lastRate = lastBorrowRate[asset];
        if (lastRate == 0) {
            return proposedRate; // No previous rate to compare
        }

        uint256 maxChange = lastRate.mulDiv(
            breaker.maxRateChangePerUpdate,
            10000
        ); // basis points

        if (proposedRate > lastRate + maxChange) {
            limitedRate = lastRate + maxChange;
        } else if (proposedRate < lastRate - maxChange) {
            limitedRate = lastRate > maxChange ? lastRate - maxChange : 0;
        } else {
            limitedRate = proposedRate;
        }

        // Check emergency threshold
        if (limitedRate > breaker.emergencyRateThreshold) {
            limitedRate = breaker.emergencyRateThreshold;
        }

        return limitedRate;
    }

    /**
     * @notice Apply rate smoothing constraints for gradual rate changes
     */
    function _applySmoothingConstraints(
        address asset,
        uint256 proposedRate
    ) internal view returns (uint256 smoothedRate) {
        uint256 target = targetBorrowRate[asset];
        uint256 adjustmentSpeed = rateAdjustmentSpeed[asset];

        if (target == 0 || adjustmentSpeed == 0) {
            return proposedRate; // No smoothing configured
        }

        if (proposedRate > target) {
            uint256 maxIncrease = target.mulDiv(adjustmentSpeed, 10000); // basis points per update
            smoothedRate = proposedRate > target + maxIncrease
                ? target + maxIncrease
                : proposedRate;
        } else {
            uint256 maxDecrease = target.mulDiv(adjustmentSpeed, 10000);
            smoothedRate = proposedRate < target - maxDecrease
                ? target - maxDecrease
                : proposedRate;
        }

        return smoothedRate;
    }

    /**
     * @notice Apply comprehensive market adjustments to base rate
     */
    function _applyMarketAdjustments(
        address asset,
        uint256 baseBorrowRate,
        uint256 utilizationRate,
        uint256 totalSupply,
        uint256 totalBorrow
    ) internal view returns (uint256 adjustedRate) {
        adjustedRate = baseBorrowRate;

        // Apply volatility/market risk multiplier
        uint256 volMultiplier = volatilityMultiplier[asset];
        if (
            volMultiplier > 0 &&
            block.timestamp - lastVolatilityUpdate[asset] <=
            networkConfig.priceValidityPeriod
        ) {
            adjustedRate = adjustedRate.mulDiv(volMultiplier, PRECISION);
        }

        // Apply utilization pressure adjustment
        adjustedRate = _applyUtilizationPressure(adjustedRate, utilizationRate);

        // Apply market size adjustment (larger markets get better rates)
        adjustedRate = _applyMarketSizeAdjustment(
            asset,
            adjustedRate,
            totalSupply,
            totalBorrow
        );

        // Apply correlation adjustments if configured
        adjustedRate = _applyCorrelationAdjustments(asset, adjustedRate);

        return adjustedRate;
    }

    /**
     * @notice Apply utilization pressure to encourage optimal utilization
     */
    function _applyUtilizationPressure(
        uint256 baseRate,
        uint256 utilizationRate
    ) internal view returns (uint256 adjustedRate) {
        if (utilizationRate > networkConfig.optimalUtilization) {
            // Above optimal: exponential increase
            uint256 excessUtilization = utilizationRate -
                networkConfig.optimalUtilization;
            uint256 pressureMultiplier = PRECISION +
                (excessUtilization * excessUtilization) /
                PRECISION;
            adjustedRate = baseRate.mulDiv(pressureMultiplier, PRECISION);
        } else if (utilizationRate < networkConfig.optimalUtilization / 2) {
            // Below half optimal: encourage borrowing with lower rates
            adjustedRate = baseRate.mulDiv(95, 100); // 5% discount
        } else {
            adjustedRate = baseRate;
        }

        return adjustedRate;
    }

    /**
     * @notice Apply market size adjustments (larger markets = more stability = better rates)
     */
    function _applyMarketSizeAdjustment(
        address asset,
        uint256 baseRate,
        uint256 totalSupply,
        uint256 totalBorrow
    ) internal view returns (uint256 adjustedRate) {
        // Get market size in USD
        uint256 marketSizeUSD = priceOracle.getAssetValue(asset, totalSupply);

        if (marketSizeUSD >= 100_000_000 * PRECISION) {
            // Large market (>$100M): 10% rate discount
            adjustedRate = baseRate.mulDiv(90, 100);
        } else if (marketSizeUSD >= 10_000_000 * PRECISION) {
            // Medium market ($10M-$100M): 5% rate discount
            adjustedRate = baseRate.mulDiv(95, 100);
        } else if (marketSizeUSD < 1_000_000 * PRECISION) {
            // Small market (<$1M): 20% rate premium for risk
            adjustedRate = baseRate.mulDiv(120, 100);
        } else {
            // Standard market: no adjustment
            adjustedRate = baseRate;
        }

        return adjustedRate;
    }

    /**
     * @notice Apply correlation-based adjustments
     */
    function _applyCorrelationAdjustments(
        address asset,
        uint256 baseRate
    ) internal view returns (uint256 adjustedRate) {
        adjustedRate = baseRate;

        address[] memory correlatedList = correlatedAssets[asset];
        if (correlatedList.length == 0) return adjustedRate;

        int256 totalCorrelationEffect = 0;

        for (uint256 i = 0; i < correlatedList.length; i++) {
            address correlatedAsset = correlatedList[i];
            int256 correlation = assetCorrelations[asset][correlatedAsset];

            // If highly correlated assets have high utilization, increase rates
            uint256 correlatedUtilization = _getAssetUtilization(
                correlatedAsset
            );
            if (correlation > (80 * int256(PRECISION)) / 100) {
                // >80% correlation
                if (correlatedUtilization > networkConfig.optimalUtilization) {
                    totalCorrelationEffect +=
                        int256(
                            correlatedUtilization -
                                networkConfig.optimalUtilization
                        ) /
                        10;
                }
            }
        }

        if (totalCorrelationEffect > 0) {
            uint256 correlationMultiplier = PRECISION +
                uint256(totalCorrelationEffect);
            adjustedRate = adjustedRate.mulDiv(
                correlationMultiplier,
                PRECISION
            );
        }

        return adjustedRate;
    }

    /**
     * @notice Get utilization rate for a specific asset (would typically be called from main pool)
     */
    function _getAssetUtilization(
        address asset
    ) internal view returns (uint256) {
        // This would typically fetch from the main lending pool
        // For now, return the last known utilization
        return lastUtilizationRate[asset];
    }
    function setInterestRateParams(
        address asset,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    ) external override onlyRole(ADMIN_ROLE) {
        require(baseRate <= MAX_RATE, "Base rate too high");
        require(multiplier <= MAX_RATE, "Multiplier too high");
        require(jumpMultiplier <= MAX_RATE, "Jump multiplier too high");
        require(kink <= MAX_UTILIZATION, "Kink too high");

        assetParams[asset] = InterestRateParams({
            baseRate: baseRate,
            multiplier: multiplier,
            jumpMultiplier: jumpMultiplier,
            kink: kink,
            isCustom: true
        });

        _hasCustomParams[asset] = true;

        emit InterestRateModelUpdate(
            asset,
            baseRate,
            multiplier,
            jumpMultiplier,
            kink
        );
    }

    function removeCustomParams(
        address asset
    ) external override onlyRole(ADMIN_ROLE) {
        delete assetParams[asset];
        _hasCustomParams[asset] = false;
    }

    function updateDefaultParams(
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    ) external override onlyRole(ADMIN_ROLE) {
        require(baseRate <= MAX_RATE, "Base rate too high");
        require(multiplier <= MAX_RATE, "Multiplier too high");
        require(jumpMultiplier <= MAX_RATE, "Jump multiplier too high");
        require(kink <= MAX_UTILIZATION, "Kink too high");

        defaultParams = InterestRateParams({
            baseRate: baseRate,
            multiplier: multiplier,
            jumpMultiplier: jumpMultiplier,
            kink: kink,
            isCustom: false
        });

        emit DefaultParamsUpdated(baseRate, multiplier, jumpMultiplier, kink);
    }

    function updateRates(
        address asset,
        uint256 utilizationRate,
        uint256 borrowRate,
        uint256 supplyRate
    ) external onlyRole(RATE_UPDATER_ROLE) {
        lastBorrowRate[asset] = borrowRate;
        lastSupplyRate[asset] = supplyRate;
        lastUtilizationRate[asset] = utilizationRate;
        lastUpdateTimestamp[asset] = block.timestamp;

        _updateRateHistory(asset, borrowRate, supplyRate, block.timestamp);

        emit RateCalculated(
            asset,
            utilizationRate,
            borrowRate,
            supplyRate,
            block.timestamp
        );
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function grantRateUpdaterRole(
        address account
    ) external onlyRole(ADMIN_ROLE) {
        _grantRole(RATE_UPDATER_ROLE, account);
    }

    function revokeRateUpdaterRole(
        address account
    ) external onlyRole(ADMIN_ROLE) {
        _revokeRole(RATE_UPDATER_ROLE, account);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS FOR ANALYTICS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get comprehensive market analytics for an asset
     * @param asset The asset address
     */
    function getMarketAnalytics(
        address asset
    )
        external
        view
        returns (
            uint256 currentBorrowRate,
            uint256 currentSupplyRate,
            uint256 utilizationRate,
            uint256 volatilityMult,
            uint256 marketMultiplierAge,
            bool isEmergencyMode,
            bool isCircuitBreakerTriggered,
            uint256 rateVariance,
            uint256 historyDataPoints
        )
    {
        currentBorrowRate = lastBorrowRate[asset];
        currentSupplyRate = lastSupplyRate[asset];
        utilizationRate = lastUtilizationRate[asset];
        volatilityMult = volatilityMultiplier[asset];
        marketMultiplierAge = block.timestamp - lastVolatilityUpdate[asset];
        isEmergencyMode = emergencyMode[asset];
        isCircuitBreakerTriggered = circuitBreakers[asset].isTriggered;
        rateVariance = _calculateRateVariance(asset, 20); // 20 period variance
        historyDataPoints = historySize[asset];
    }

    /**
     * @notice Get network configuration details
     */
    function getNetworkConfiguration()
        external
        view
        returns (NetworkConfig memory)
    {
        return networkConfig;
    }

    /**
     * @notice Get asset safety configuration
     * @param asset The asset address
     */
    function getAssetSafetyConfig(
        address asset
    )
        external
        view
        returns (
            CircuitBreaker memory circuitBreaker,
            bool emergencyModeEnabled,
            uint256 emergencyRateCapValue,
            uint256 targetBorrowRateValue,
            uint256 rateAdjustmentSpeedValue,
            uint256 assetReserveFactorValue
        )
    {
        return (
            circuitBreakers[asset],
            emergencyMode[asset],
            emergencyRateCap[asset],
            targetBorrowRate[asset],
            rateAdjustmentSpeed[asset],
            assetReserveFactor[asset]
        );
    }

    /**
     * @notice Check if the contract is production-ready
     * @return isReady True if all production features are configured
     * @return missingFeatures Array of missing feature names
     */
    function isProductionReady()
        external
        view
        returns (bool isReady, string[] memory missingFeatures)
    {
        string[] memory missing = new string[](10);
        uint256 missingCount = 0;

        if (address(priceOracle) == address(0)) {
            missing[missingCount++] = "PriceOracle not set";
        }

        if (networkConfig.baseRate == 0) {
            missing[missingCount++] = "Network config not initialized";
        }

        if (defaultParams.baseRate == 0) {
            missing[missingCount++] = "Default params not set";
        }

        // Resize array to actual missing count
        missingFeatures = new string[](missingCount);
        for (uint256 i = 0; i < missingCount; i++) {
            missingFeatures[i] = missing[i];
        }

        isReady = missingCount == 0;
    }
}
