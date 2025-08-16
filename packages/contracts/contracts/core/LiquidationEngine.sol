// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/ILiquidationEngine.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRiskManager.sol";
import {Math as HyperMath} from "../libraries/Math.sol";

/**
 * @title LiquidationEngine
 * @dev Ultra-fast liquidation engine optimized for Somnia's high throughput
 * @notice Handles micro-liquidations and real-time position monitoring
 */
contract LiquidationEngine is
    ILiquidationEngine,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using HyperMath for uint256;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_LIQUIDATION_RATIO = 50e16; // 50%
    uint256 public constant MIN_LIQUIDATION_AMOUNT = 1e6; // $1 minimum
    uint256 public constant MAX_LIQUIDATION_BONUS = 20e16; // 20% maximum

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct LiquidationConfig {
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 maxLiquidationRatio;
        uint256 minLiquidationAmount;
        bool isActive;
    }

    struct LiquidationStats {
        uint256 totalLiquidations;
        uint256 totalVolumeUSD;
        uint256 last24hLiquidations;
        uint256 last24hVolumeUSD;
        uint256 lastResetTimestamp;
    }

    IPriceOracle public immutable priceOracle;
    IRiskManager public immutable riskManager;

    mapping(address => LiquidationConfig) public liquidationConfigs;
    mapping(address => uint256) public userLiquidationCount;
    mapping(address => uint256) public userLiquidationVolume;

    LiquidationStats public stats;

    // Micro-liquidation settings
    bool public microLiquidationEnabled = true;
    uint256 public microLiquidationThreshold = 1e16; // 1% below liquidation threshold
    uint256 public maxMicroLiquidationSize = 1000e18; // $1000 maximum per micro-liquidation

    // Liquidatable positions tracking
    address[] public liquidatablePositions;
    mapping(address => uint256) public liquidatablePositionIndex;
    mapping(address => bool) public isPositionTracked;

    // Emergency settings
    bool public emergencyPaused = false;
    uint256 public emergencyLiquidationBonus = 10e16; // 10% bonus during emergency

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event LiquidationConfigUpdated(
        address indexed asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio
    );

    event PositionAddedToTracking(address indexed user, uint256 healthFactor);
    event PositionRemovedFromTracking(
        address indexed user,
        uint256 healthFactor
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(address _priceOracle, address _riskManager) {
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_riskManager != address(0), "Invalid risk manager");

        priceOracle = IPriceOracle(_priceOracle);
        riskManager = IRiskManager(_riskManager);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        stats.lastResetTimestamp = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE LIQUIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute liquidation for an unhealthy position
     */
    function executeLiquidation(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 collateralAmount, uint256 liquidationBonus)
    {
        require(!emergencyPaused, "Emergency paused");
        require(user != msg.sender, "Cannot liquidate self");

        // Validate liquidation
        (bool isValid, string memory reason) = validateLiquidation(
            user,
            debtAsset,
            debtAmount,
            collateralAsset
        );
        require(isValid, reason);

        // Get liquidation parameters
        LiquidationConfig memory config = liquidationConfigs[debtAsset];

        // Calculate liquidation amounts
        (collateralAmount, liquidationBonus, ) = calculateLiquidationAmounts(
            user,
            debtAsset,
            debtAmount,
            collateralAsset
        );

        // Update statistics
        _updateLiquidationStats(debtAmount);
        userLiquidationCount[user]++;

        uint256 debtValueUSD = priceOracle.getAssetValue(debtAsset, debtAmount);
        userLiquidationVolume[user] += debtValueUSD;

        // Remove from tracking if health factor improves significantly
        _updatePositionTracking(user);

        emit LiquidationExecuted(
            msg.sender,
            user,
            debtAsset,
            collateralAsset,
            debtAmount,
            collateralAmount,
            liquidationBonus
        );

        return (collateralAmount, liquidationBonus);
    }

    /**
     * @notice Calculate optimal liquidation amount for micro-liquidations
     */
    function calculateOptimalLiquidation(
        address user,
        address debtAsset,
        uint256 maxDebtAmount
    ) public view override returns (uint256 optimalAmount) {
        if (!microLiquidationEnabled) return 0;

        // Get user's current health factor
        uint256 healthFactor = riskManager.calculateHealthFactor(user);
        LiquidationConfig memory config = liquidationConfigs[debtAsset];

        // Check if micro-liquidation is needed
        uint256 microThreshold = config.liquidationThreshold +
            microLiquidationThreshold;
        if (healthFactor >= microThreshold) return 0;

        // Calculate how much debt to liquidate to bring health factor to safe level
        uint256 targetHealthFactor = microThreshold +
            (microLiquidationThreshold / 2);

        // Get user's positions
        (uint256 totalCollateral, uint256 totalDebt) = _getUserPositionValues(
            user
        );

        if (totalDebt == 0) return 0;

        // Calculate required debt reduction
        uint256 requiredDebtReduction = totalDebt -
            totalCollateral.mulDiv(PRECISION, targetHealthFactor);

        // Limit to maximum micro-liquidation size
        uint256 maxMicroAmount = maxMicroLiquidationSize.mulDiv(
            PRECISION,
            priceOracle.getPrice(debtAsset)
        );

        optimalAmount = requiredDebtReduction > maxMicroAmount
            ? maxMicroAmount
            : requiredDebtReduction;

        // Limit to user's actual debt and provided maximum
        if (optimalAmount > maxDebtAmount) {
            optimalAmount = maxDebtAmount;
        }

        return optimalAmount;
    }

    /**
     * @notice Execute micro-liquidation for real-time risk management
     */
    function executeMicroLiquidation(
        LiquidationParams calldata params
    )
        external
        override
        onlyRole(KEEPER_ROLE)
        nonReentrant
        whenNotPaused
        returns (LiquidationResult memory result)
    {
        require(microLiquidationEnabled, "Micro-liquidations disabled");
        require(!emergencyPaused, "Emergency paused");

        // Calculate optimal liquidation amount
        uint256 optimalAmount = calculateOptimalLiquidation(
            params.user,
            params.debtAsset,
            params.debtAmount
        );

        if (optimalAmount == 0) {
            return
                LiquidationResult({
                    debtRepaid: 0,
                    collateralSeized: 0,
                    liquidationBonus: 0,
                    protocolFee: 0,
                    isPartialLiquidation: false
                });
        }

        // Execute micro-liquidation
        (
            uint256 collateralAmount,
            uint256 bonus,
            uint256 protocolFee
        ) = calculateLiquidationAmounts(
                params.user,
                params.debtAsset,
                optimalAmount,
                params.collateralAsset
            );

        // Update statistics
        _updateLiquidationStats(optimalAmount);

        result = LiquidationResult({
            debtRepaid: optimalAmount,
            collateralSeized: collateralAmount,
            liquidationBonus: bonus,
            protocolFee: protocolFee,
            isPartialLiquidation: true
        });

        emit MicroLiquidationExecuted(
            msg.sender,
            params.user,
            params.debtAsset,
            optimalAmount,
            block.timestamp
        );

        return result;
    }

    /**
     * @notice Calculate liquidation amounts and bonuses
     */
    function calculateLiquidationAmounts(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    )
        public
        view
        override
        returns (
            uint256 collateralAmount,
            uint256 liquidationBonus,
            uint256 protocolFee
        )
    {
        // Get prices
        uint256 debtPrice = priceOracle.getPrice(debtAsset);
        uint256 collateralPrice = priceOracle.getPrice(collateralAsset);

        // Get liquidation configuration
        LiquidationConfig memory config = liquidationConfigs[debtAsset];
        uint256 bonusRate = emergencyPaused
            ? emergencyLiquidationBonus
            : config.liquidationBonus;

        // Calculate debt value in USD
        uint256 debtValueUSD = debtAmount.mulDiv(debtPrice, PRECISION);

        // Calculate collateral amount to seize (including bonus)
        uint256 collateralValueUSD = debtValueUSD.mulDiv(
            PRECISION + bonusRate,
            PRECISION
        );
        collateralAmount = collateralValueUSD.mulDiv(
            PRECISION,
            collateralPrice
        );

        // Calculate liquidation bonus
        liquidationBonus = debtValueUSD.mulDiv(bonusRate, PRECISION).mulDiv(
            PRECISION,
            collateralPrice
        );

        // Calculate protocol fee (1% of liquidation bonus)
        protocolFee = liquidationBonus.mulDiv(1e16, PRECISION);
        liquidationBonus -= protocolFee;

        return (collateralAmount, liquidationBonus, protocolFee);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if a position is liquidatable
     */
    function isPositionLiquidatable(
        address user
    )
        public
        view
        override
        returns (
            bool isLiquidatable,
            uint256 healthFactor,
            uint256 liquidationThreshold
        )
    {
        healthFactor = riskManager.calculateHealthFactor(user);

        // Get the lowest liquidation threshold among user's debt assets
        liquidationThreshold = _getUserLiquidationThreshold(user);

        isLiquidatable = healthFactor < liquidationThreshold;

        return (isLiquidatable, healthFactor, liquidationThreshold);
    }

    /**
     * @notice Validate liquidation parameters
     */
    function validateLiquidation(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    ) public view override returns (bool isValid, string memory reason) {
        // Check if user position is liquidatable
        (bool liquidatable, uint256 healthFactor, ) = isPositionLiquidatable(
            user
        );
        if (!liquidatable) {
            return (false, "Position not liquidatable");
        }

        // Check liquidation configuration
        LiquidationConfig memory config = liquidationConfigs[debtAsset];
        if (!config.isActive) {
            return (false, "Liquidation not active for asset");
        }

        // Check minimum liquidation amount
        uint256 debtValueUSD = priceOracle.getAssetValue(debtAsset, debtAmount);
        if (debtValueUSD < config.minLiquidationAmount) {
            return (false, "Below minimum liquidation amount");
        }

        // Check maximum liquidation ratio
        uint256 userTotalDebt = _getUserTotalDebt(user);
        uint256 maxLiquidationAmount = userTotalDebt.mulDiv(
            config.maxLiquidationRatio,
            PRECISION
        );
        if (debtValueUSD > maxLiquidationAmount) {
            return (false, "Exceeds maximum liquidation ratio");
        }

        return (true, "");
    }

    /**
     * @notice Get maximum liquidatable debt amount
     */
    function getMaxLiquidatableDebt(
        address user,
        address debtAsset
    ) external view override returns (uint256 maxDebtAmount) {
        // Check if position is liquidatable
        (bool liquidatable, , ) = isPositionLiquidatable(user);
        if (!liquidatable) return 0;

        LiquidationConfig memory config = liquidationConfigs[debtAsset];
        if (!config.isActive) return 0;

        // Calculate maximum based on liquidation ratio
        uint256 userTotalDebt = _getUserTotalDebt(user);
        uint256 maxLiquidationValueUSD = userTotalDebt.mulDiv(
            config.maxLiquidationRatio,
            PRECISION
        );

        // Convert to debt asset amount
        uint256 debtPrice = priceOracle.getPrice(debtAsset);
        maxDebtAmount = maxLiquidationValueUSD.mulDiv(PRECISION, debtPrice);

        return maxDebtAmount;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME MONITORING
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get list of positions eligible for liquidation
     */
    function getLiquidatablePositions(
        uint256 maxPositions
    )
        external
        view
        override
        returns (
            address[] memory users,
            uint256[] memory healthFactors,
            uint256[] memory totalDebts
        )
    {
        uint256 count = liquidatablePositions.length > maxPositions
            ? maxPositions
            : liquidatablePositions.length;

        users = new address[](count);
        healthFactors = new uint256[](count);
        totalDebts = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            address user = liquidatablePositions[i];
            users[i] = user;
            healthFactors[i] = riskManager.calculateHealthFactor(user);
            totalDebts[i] = _getUserTotalDebt(user);
        }

        return (users, healthFactors, totalDebts);
    }

    /**
     * @notice Get liquidation statistics
     */
    function getLiquidationStats()
        external
        view
        override
        returns (
            uint256 totalLiquidations,
            uint256 totalVolumeUSD,
            uint256 averageLiquidationSize,
            uint256 last24hLiquidations
        )
    {
        totalLiquidations = stats.totalLiquidations;
        totalVolumeUSD = stats.totalVolumeUSD;
        averageLiquidationSize = totalLiquidations > 0
            ? totalVolumeUSD / totalLiquidations
            : 0;
        last24hLiquidations = stats.last24hLiquidations;

        return (
            totalLiquidations,
            totalVolumeUSD,
            averageLiquidationSize,
            last24hLiquidations
        );
    }

    /**
     * @notice Update position tracking for real-time monitoring
     */
    function updatePositionTracking(address user) external {
        _updatePositionTracking(user);
    }

    /**
     * @notice Batch update position tracking
     */
    function batchUpdatePositionTracking(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            _updatePositionTracking(users[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _updateLiquidationStats(uint256 debtAmount) internal {
        // Reset 24h stats if needed
        if (block.timestamp >= stats.lastResetTimestamp + 24 hours) {
            stats.last24hLiquidations = 0;
            stats.last24hVolumeUSD = 0;
            stats.lastResetTimestamp = block.timestamp;
        }

        stats.totalLiquidations++;
        stats.last24hLiquidations++;

        // Add to volume (assuming debtAmount is already in USD terms)
        stats.totalVolumeUSD += debtAmount;
        stats.last24hVolumeUSD += debtAmount;
    }

    function _updatePositionTracking(address user) internal {
        (bool isLiquidatable, uint256 healthFactor, ) = isPositionLiquidatable(
            user
        );

        if (isLiquidatable && !isPositionTracked[user]) {
            // Add to tracking
            liquidatablePositions.push(user);
            liquidatablePositionIndex[user] = liquidatablePositions.length - 1;
            isPositionTracked[user] = true;

            emit PositionAddedToTracking(user, healthFactor);
        } else if (!isLiquidatable && isPositionTracked[user]) {
            // Remove from tracking
            uint256 index = liquidatablePositionIndex[user];
            uint256 lastIndex = liquidatablePositions.length - 1;

            if (index != lastIndex) {
                address lastUser = liquidatablePositions[lastIndex];
                liquidatablePositions[index] = lastUser;
                liquidatablePositionIndex[lastUser] = index;
            }

            liquidatablePositions.pop();
            delete liquidatablePositionIndex[user];
            isPositionTracked[user] = false;

            emit PositionRemovedFromTracking(user, healthFactor);
        }
    }

    function _getUserPositionValues(
        address user
    ) internal view returns (uint256 totalCollateral, uint256 totalDebt) {
        // This would typically call the main pool contract to get user positions
        // For now, we'll use the risk manager
        IRiskManager.UserRiskData memory riskData = riskManager.getUserRiskData(
            user
        );
        return (riskData.totalCollateralValue, riskData.totalBorrowValue);
    }

    function _getUserTotalDebt(
        address user
    ) internal view returns (uint256 totalDebt) {
        IRiskManager.UserRiskData memory riskData = riskManager.getUserRiskData(
            user
        );
        return riskData.totalBorrowValue;
    }

    function _getUserLiquidationThreshold(
        address user
    ) internal view returns (uint256 threshold) {
        // Get the minimum liquidation threshold among user's debt positions
        // This is a simplified implementation
        return 85e16; // 85% default threshold
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function setLiquidationParams(
        address asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio
    ) external override onlyRole(ADMIN_ROLE) {
        require(
            liquidationThreshold > 0 && liquidationThreshold <= PRECISION,
            "Invalid threshold"
        );
        require(liquidationBonus <= MAX_LIQUIDATION_BONUS, "Bonus too high");
        require(maxLiquidationRatio <= MAX_LIQUIDATION_RATIO, "Ratio too high");

        liquidationConfigs[asset] = LiquidationConfig({
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            maxLiquidationRatio: maxLiquidationRatio,
            minLiquidationAmount: MIN_LIQUIDATION_AMOUNT,
            isActive: true
        });

        emit LiquidationConfigUpdated(
            asset,
            liquidationThreshold,
            liquidationBonus,
            maxLiquidationRatio
        );
    }

    function setMicroLiquidationEnabled(
        bool enabled
    ) external override onlyRole(ADMIN_ROLE) {
        microLiquidationEnabled = enabled;
    }

    function setMinLiquidationAmount(
        address asset,
        uint256 minAmount
    ) external override onlyRole(ADMIN_ROLE) {
        liquidationConfigs[asset].minLiquidationAmount = minAmount;
    }

    function pauseLiquidations() external override onlyRole(ADMIN_ROLE) {
        emergencyPaused = true;
    }

    function resumeLiquidations() external override onlyRole(ADMIN_ROLE) {
        emergencyPaused = false;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
