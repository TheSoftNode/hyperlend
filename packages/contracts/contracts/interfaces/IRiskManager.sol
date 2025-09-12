// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRiskManager
 * @dev Interface for risk management and health factor calculations
 */
interface IRiskManager {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct RiskParameters {
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 borrowFactor;
        uint256 supplyCap;
        uint256 borrowCap;
        bool isActive;
        bool isFrozen;
    }

    struct UserRiskData {
        uint256 totalCollateralValue;
        uint256 totalBorrowValue;
        uint256 healthFactor;
        uint256 liquidationThreshold;
        uint256 maxBorrowValue;
        bool isLiquidatable;
    }

    struct AssetRisk {
        address asset;
        uint256 collateralValue;
        uint256 borrowValue;
        uint256 utilizationRate;
        uint256 volatilityScore;
        uint256 liquidityScore;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event RiskParametersUpdated(
        address indexed asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 borrowFactor
    );

    event HealthFactorUpdated(
        address indexed user,
        uint256 oldHealthFactor,
        uint256 newHealthFactor
    );

    event RiskLevelChanged(
        address indexed user,
        uint8 oldRiskLevel,
        uint8 newRiskLevel
    );

    event LiquidationTriggered(
        address indexed user,
        uint256 healthFactor,
        uint256 timestamp
    );

    event EmergencyAction(
        string indexed action,
        address indexed admin,
        uint256 timestamp
    );

    event SystemParametersUpdated(
        string indexed parameter,
        address indexed admin
    );

    event RiskTrackingUpdated(
        address indexed user,
        bool isTracked,
        uint256 timestamp
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate user's health factor
     * @param user The user address
     * @return healthFactor Current health factor (scaled by 1e18)
     */
    function calculateHealthFactor(
        address user
    ) external view returns (uint256 healthFactor);

    /**
     * @notice Get comprehensive user risk data
     * @param user The user address
     * @return riskData Complete risk information
     */
    function getUserRiskData(
        address user
    ) external view returns (UserRiskData memory riskData);

    /**
     * @notice Calculate maximum borrowing capacity
     * @param user The user address
     * @param asset The asset to borrow
     * @return maxBorrowAmount Maximum amount that can be borrowed
     */
    function getMaxBorrowAmount(
        address user,
        address asset
    ) external view returns (uint256 maxBorrowAmount);

    /**
     * @notice Calculate maximum withdrawal amount
     * @param user The user address
     * @param asset The asset to withdraw
     * @return maxWithdrawAmount Maximum amount that can be withdrawn
     */
    function getMaxWithdrawAmount(
        address user,
        address asset
    ) external view returns (uint256 maxWithdrawAmount);

    /**
     * @notice Calculate liquidation amounts
     * @param user The user being liquidated
     * @param debtAsset The debt asset to repay
     * @param collateralAsset The collateral asset to seize
     * @param debtAmount The amount of debt to repay
     * @return collateralAmount Amount of collateral to seize
     * @return liquidationBonus Bonus for liquidator
     */
    function calculateLiquidationAmounts(
        address user,
        address debtAsset,
        address collateralAsset,
        uint256 debtAmount
    )
        external
        view
        returns (uint256 collateralAmount, uint256 liquidationBonus);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if borrow operation is allowed
     * @param user The user address
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     * @return isAllowed True if borrow is allowed
     * @return reason Reason if not allowed
     */
    function isBorrowAllowed(
        address user,
        address asset,
        uint256 amount
    ) external view returns (bool isAllowed, string memory reason);

    /**
     * @notice Check if withdrawal is allowed
     * @param user The user address
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @return isAllowed True if withdrawal is allowed
     * @return reason Reason if not allowed
     */
    function isWithdrawAllowed(
        address user,
        address asset,
        uint256 amount
    ) external view returns (bool isAllowed, string memory reason);

    /**
     * @notice Check if liquidation is allowed
     * @param user The user to liquidate
     * @return isAllowed True if liquidation is allowed
     * @return healthFactor Current health factor
     */
    function isLiquidationAllowed(
        address user
    ) external view returns (bool isAllowed, uint256 healthFactor);

    /**
     * @notice Validate supply operation
     * @param user The user address
     * @param asset The asset to supply
     * @param amount The amount to supply
     * @return isValid True if supply is valid
     * @return reason Reason if invalid
     */
    function validateSupply(
        address user,
        address asset,
        uint256 amount
    ) external view returns (bool isValid, string memory reason);

    /**
     * @notice Validate repay operation
     * @param user The user address
     * @param asset The asset to repay
     * @param amount The amount to repay
     * @return isValid True if repay is valid
     * @return reason Reason if invalid
     */
    function validateRepay(
        address user,
        address asset,
        uint256 amount
    ) external view returns (bool isValid, string memory reason);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // RISK ASSESSMENT
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user's risk level (1-5 scale)
     * @param user The user address
     * @return riskLevel Risk level from 1 (low) to 5 (very high)
     */
    function getUserRiskLevel(
        address user
    ) external view returns (uint8 riskLevel);

    /**
     * @notice Get asset risk metrics
     * @param asset The asset address
     * @return assetRisk Asset risk information
     */
    function getAssetRisk(
        address asset
    ) external view returns (AssetRisk memory assetRisk);

    /**
     * @notice Get portfolio diversification score
     * @param user The user address
     * @return diversificationScore Score from 0-100
     */
    function getPortfolioDiversification(
        address user
    ) external view returns (uint256 diversificationScore);

    /**
     * @notice Calculate value at risk (VaR)
     * @param user The user address
     * @param confidenceLevel Confidence level (e.g., 95 for 95%)
     * @param timeHorizon Time horizon in days
     * @return valueAtRisk VaR amount in USD
     */
    function calculateValueAtRisk(
        address user,
        uint256 confidenceLevel,
        uint256 timeHorizon
    ) external view returns (uint256 valueAtRisk);

    /**
     * @notice Get stress test results
     * @param user The user address
     * @param priceShocks Array of price shock percentages
     * @return healthFactors Resulting health factors
     * @return wouldBeLiquidated Whether position would be liquidated
     */
    function stressTest(
        address user,
        int256[] calldata priceShocks
    )
        external
        view
        returns (
            uint256[] memory healthFactors,
            bool[] memory wouldBeLiquidated
        );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME MONITORING
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get positions at risk of liquidation
     * @param healthFactorThreshold Health factor threshold
     * @param maxPositions Maximum positions to return
     * @return users Array of user addresses
     * @return healthFactors Array of health factors
     * @return riskLevels Array of risk levels
     */
    function getPositionsAtRisk(
        uint256 healthFactorThreshold,
        uint256 maxPositions
    )
        external
        view
        returns (
            address[] memory users,
            uint256[] memory healthFactors,
            uint8[] memory riskLevels
        );

    /**
     * @notice Get system-wide risk metrics
     * @return totalCollateral Total collateral in USD
     * @return totalDebt Total debt in USD
     * @return averageHealthFactor Average health factor
     * @return positionsAtRisk Number of positions at risk
     */
    function getSystemRiskMetrics()
        external
        view
        returns (
            uint256 totalCollateral,
            uint256 totalDebt,
            uint256 averageHealthFactor,
            uint256 positionsAtRisk
        );

    /**
     * @notice Get real-time risk score for the protocol
     * @return riskScore Overall protocol risk score (0-100)
     * @return riskFactors Array of contributing risk factors
     */
    function getProtocolRiskScore()
        external
        view
        returns (uint256 riskScore, string[] memory riskFactors);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONFIGURATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get risk parameters for an asset
     * @param asset The asset address
     * @return params Risk parameters
     */
    function getRiskParameters(
        address asset
    ) external view returns (RiskParameters memory params);

    /**
     * @notice Get liquidation threshold for an asset
     * @param asset The asset address
     * @return threshold Liquidation threshold (scaled by 1e18)
     */
    function getLiquidationThreshold(
        address asset
    ) external view returns (uint256 threshold);

    /**
     * @notice Get liquidation bonus for an asset
     * @param asset The asset address
     * @return bonus Liquidation bonus (scaled by 1e18)
     */
    function getLiquidationBonus(
        address asset
    ) external view returns (uint256 bonus);

    /**
     * @notice Get borrow factor for an asset
     * @param asset The asset address
     * @return factor Borrow factor (scaled by 1e18)
     */
    function getBorrowFactor(
        address asset
    ) external view returns (uint256 factor);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set risk parameters for an asset
     * @param asset The asset address
     * @param liquidationThreshold Liquidation threshold
     * @param liquidationBonus Liquidation bonus
     * @param borrowFactor Borrow factor
     */
    function setRiskParameters(
        address asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 borrowFactor
    ) external;

    /**
     * @notice Set supply and borrow caps
     * @param asset The asset address
     * @param supplyCap Maximum supply amount
     * @param borrowCap Maximum borrow amount
     */
    function setCaps(
        address asset,
        uint256 supplyCap,
        uint256 borrowCap
    ) external;

    /**
     * @notice Freeze or unfreeze an asset
     * @param asset The asset address
     * @param frozen True to freeze, false to unfreeze
     */
    function setAssetFrozen(address asset, bool frozen) external;

    /**
     * @notice Set global risk parameters
     * @param maxHealthFactorForLiquidation Maximum health factor for liquidation
     * @param minHealthFactorForBorrow Minimum health factor for borrowing
     * @param maxLiquidationRatio Maximum liquidation ratio
     */
    function setGlobalRiskParameters(
        uint256 maxHealthFactorForLiquidation,
        uint256 minHealthFactorForBorrow,
        uint256 maxLiquidationRatio
    ) external;

    /**
     * @notice Emergency pause all operations
     */
    function emergencyPause() external;

    /**
     * @notice Resume operations after emergency pause
     */
    function emergencyResume() external;
}
