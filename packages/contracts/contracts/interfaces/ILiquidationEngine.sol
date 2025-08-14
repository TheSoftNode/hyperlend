// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidationEngine
 * @dev Interface for the liquidation engine handling ultra-fast liquidations
 */
interface ILiquidationEngine {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct LiquidationParams {
        address user;
        address debtAsset;
        address collateralAsset;
        uint256 debtAmount;
        uint256 maxCollateralAmount;
        uint256 healthFactorThreshold;
        uint256 liquidationBonus;
    }

    struct LiquidationResult {
        uint256 debtRepaid;
        uint256 collateralSeized;
        uint256 liquidationBonus;
        uint256 protocolFee;
        bool isPartialLiquidation;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event LiquidationExecuted(
        address indexed liquidator,
        address indexed user,
        address indexed debtAsset,
        address collateralAsset,
        uint256 debtRepaid,
        uint256 collateralSeized,
        uint256 liquidationBonus
    );

    event MicroLiquidationExecuted(
        address indexed liquidator,
        address indexed user,
        address indexed debtAsset,
        uint256 debtRepaid,
        uint256 timestamp
    );

    event LiquidationParametersUpdated(
        address indexed asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute liquidation for an unhealthy position
     * @param user The user being liquidated
     * @param debtAsset The debt asset to repay
     * @param debtAmount The amount of debt to repay
     * @param collateralAsset The collateral asset to seize
     * @return collateralAmount Amount of collateral seized
     * @return liquidationBonus Bonus amount for liquidator
     */
    function executeLiquidation(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    ) external returns (uint256 collateralAmount, uint256 liquidationBonus);

    /**
     * @notice Calculate optimal liquidation amount for micro-liquidations
     * @param user The user to liquidate
     * @param debtAsset The debt asset
     * @param maxDebtAmount Maximum debt amount to liquidate
     * @return optimalAmount Optimal liquidation amount
     */
    function calculateOptimalLiquidation(
        address user,
        address debtAsset,
        uint256 maxDebtAmount
    ) external view returns (uint256 optimalAmount);

    /**
     * @notice Execute micro-liquidation for real-time risk management
     * @param params Liquidation parameters
     * @return result Liquidation result
     */
    function executeMicroLiquidation(
        LiquidationParams calldata params
    ) external returns (LiquidationResult memory result);

    /**
     * @notice Calculate liquidation amounts and bonuses
     * @param user The user being liquidated
     * @param debtAsset The debt asset to repay
     * @param debtAmount The amount of debt to repay
     * @param collateralAsset The collateral asset to seize
     * @return collateralAmount Amount of collateral to seize
     * @return liquidationBonus Bonus for liquidator
     * @return protocolFee Fee for protocol
     */
    function calculateLiquidationAmounts(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    )
        external
        view
        returns (
            uint256 collateralAmount,
            uint256 liquidationBonus,
            uint256 protocolFee
        );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if a position is liquidatable
     * @param user The user to check
     * @return isLiquidatable True if position can be liquidated
     * @return healthFactor Current health factor
     * @return liquidationThreshold Threshold for liquidation
     */
    function isPositionLiquidatable(
        address user
    )
        external
        view
        returns (
            bool isLiquidatable,
            uint256 healthFactor,
            uint256 liquidationThreshold
        );

    /**
     * @notice Validate liquidation parameters
     * @param user The user being liquidated
     * @param debtAsset The debt asset
     * @param debtAmount The debt amount
     * @param collateralAsset The collateral asset
     * @return isValid True if liquidation is valid
     * @return reason Reason if invalid
     */
    function validateLiquidation(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    ) external view returns (bool isValid, string memory reason);

    /**
     * @notice Get maximum liquidatable debt amount
     * @param user The user being liquidated
     * @param debtAsset The debt asset
     * @return maxDebtAmount Maximum debt that can be liquidated
     */
    function getMaxLiquidatableDebt(
        address user,
        address debtAsset
    ) external view returns (uint256 maxDebtAmount);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME MONITORING
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get list of positions eligible for liquidation
     * @param maxPositions Maximum number of positions to return
     * @return users Array of user addresses
     * @return healthFactors Array of health factors
     * @return totalDebts Array of total debt values
     */
    function getLiquidatablePositions(
        uint256 maxPositions
    )
        external
        view
        returns (
            address[] memory users,
            uint256[] memory healthFactors,
            uint256[] memory totalDebts
        );

    /**
     * @notice Get liquidation statistics
     * @return totalLiquidations Total number of liquidations
     * @return totalVolumeUSD Total liquidation volume in USD
     * @return averageLiquidationSize Average liquidation size
     * @return last24hLiquidations Liquidations in last 24 hours
     */
    function getLiquidationStats()
        external
        view
        returns (
            uint256 totalLiquidations,
            uint256 totalVolumeUSD,
            uint256 averageLiquidationSize,
            uint256 last24hLiquidations
        );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set liquidation parameters for an asset
     * @param asset The market asset
     * @param liquidationThreshold Health factor threshold for liquidation
     * @param liquidationBonus Bonus percentage for liquidators
     * @param maxLiquidationRatio Maximum portion of debt that can be liquidated
     */
    function setLiquidationParams(
        address asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio
    ) external;

    /**
     * @notice Enable or disable micro-liquidations
     * @param enabled True to enable micro-liquidations
     */
    function setMicroLiquidationEnabled(bool enabled) external;

    /**
     * @notice Set minimum liquidation amount
     * @param asset The market asset
     * @param minAmount Minimum liquidation amount
     */
    function setMinLiquidationAmount(address asset, uint256 minAmount) external;

    /**
     * @notice Emergency pause liquidations
     */
    function pauseLiquidations() external;

    /**
     * @notice Resume liquidations
     */
    function resumeLiquidations() external;
}
