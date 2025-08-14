// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../libraries/Math.sol";

/**
 * @title RiskManager
 * @dev Advanced risk management system with real-time health factor calculations
 * @notice Handles position risk assessment and liquidation parameters
 */
contract RiskManager is IRiskManager, AccessControl, Pausable {
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME MONITORING
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get positions at risk of liquidation
     */
    function getPositionsAtRisk(
        uint256 healthFactorThreshold,
        uint256 maxPositions
    ) external view override returns (
        address[] memory users,
        uint256[] memory healthFactors,
        uint8[] memory riskLevels
    ) {
        uint256 count = 0;
        uint256 totalUsers = riskUsers.length;
        
        // Count qualifying users
        for (uint256 i = 0; i < totalUsers && count < maxPositions; i++) {
            uint256 healthFactor = _calculateHealthFactor(riskUsers[i]);
            if (healthFactor <= healthFactorThreshold) {
                count++;
            }
        }
        
        users = new address[](count);
        healthFactors = new uint256[](count);
        riskLevels = new uint8[](count);
        
        uint256 index = 0;
        for (uint256 i = 0; i < totalUsers && index < count; i++) {
            address user = riskUsers[i];
            uint256 healthFactor = _calculateHealthFactor(user);
            if (healthFactor <= healthFactorThreshold) {
                users[index] = user;
                healthFactors[index] = healthFactor;
                riskLevels[index] = _getUserRiskLevel(user);
                index++;
            }
        }
        
        return (users, healthFactors, riskLevels);
    }

    /**
     * @notice Get system-wide risk metrics
     */
    function getSystemRiskMetrics() external view override returns (
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 avgHealthFactor,
        uint256 positionsAtRiskCount
    ) {
        return (
            totalCollateralValue,
            totalBorrowValue,
            averageHealthFactor,
            positionsAtRisk
        );
    }

    /**
     * @notice Get real-time risk score for the protocol
     */
    function getProtocolRiskScore() external view override returns (
        uint256 riskScore,
        string[] memory riskFactors
    ) {
        riskFactors = new string[](5);
        uint256 factorCount = 0;
        uint256 totalScore = 0;
        
        // Factor 1: Overall utilization
        uint256 utilizationRate = totalCollateralValue > 0 ? 
            totalBorrowValue.mulDiv(PRECISION, totalCollateralValue) : 0;
        uint256 utilizationScore = utilizationRate > 80e16 ? 20 : utilizationRate / 4e16;
        totalScore += utilizationScore;
        
        if (utilizationRate > 80e16) {
            riskFactors[factorCount] = "High utilization rate";
            factorCount++;
        }
        
        // Factor 2: Positions at risk
        uint256 riskPositionScore = positionsAtRisk > 100 ? 25 : positionsAtRisk / 4;
        totalScore += riskPositionScore;
        
        if (positionsAtRisk > 50) {
            riskFactors[factorCount] = "Many positions at risk";
            factorCount++;
        }
        
        // Factor 3: Average health factor
        uint256 healthScore = averageHealthFactor < 120e16 ? 25 : 0;
        totalScore += healthScore;
        
        if (averageHealthFactor < 120e16) {
            riskFactors[factorCount] = "Low average health factor";
            factorCount++;
        }
        
        // Factor 4: Asset concentration
        uint256 concentrationScore = _calculateAssetConcentrationRisk();
        totalScore += concentrationScore;
        
        if (concentrationScore > 15) {
            riskFactors[factorCount] = "High asset concentration";
            factorCount++;
        }
        
        // Factor 5: Market volatility
        uint256 volatilityScore = _calculateMarketVolatilityRisk();
        totalScore += volatilityScore;
        
        if (volatilityScore > 15) {
            riskFactors[factorCount] = "High market volatility";
            factorCount++;
        }
        
        // Resize risk factors array
        string[] memory actualFactors = new string[](factorCount);
        for (uint256 i = 0; i < factorCount; i++) {
            actualFactors[i] = riskFactors[i];
        }
        
        return (totalScore, actualFactors);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _calculateHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalBorrow) = _getUserPositionValues(user);
        
        if (totalBorrow == 0) return type(uint256).max;
        
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 adjustedCollateral = totalCollateral.mulDiv(liquidationThreshold, PRECISION);
        
        return adjustedCollateral.mulDiv(PRECISION, totalBorrow);
    }

    function _getUserPositionValues(address user) internal view returns (uint256 totalCollateral, uint256 totalBorrow) {
        // This would typically interface with the lending pool
        // For now, we'll use stored data
        UserRiskData memory data = userRiskData[user];
        return (data.totalCollateralValue, data.totalBorrowValue);
    }

    function _getUserLiquidationThreshold(address user) internal view returns (uint256 threshold) {
        // Calculate weighted average liquidation threshold based on user's collateral
        uint256 totalCollateral = 0;
        uint256 weightedThreshold = 0;
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            uint256 userCollateral = _getUserAssetCollateral(user, asset);
            
            if (userCollateral > 0) {
                uint256 assetThreshold = assetRiskParams[asset].liquidationThreshold;
                totalCollateral += userCollateral;
                weightedThreshold += userCollateral.mulDiv(assetThreshold, PRECISION);
            }
        }
        
        return totalCollateral > 0 ? weightedThreshold.mulDiv(PRECISION, totalCollateral) : 85e16; // Default 85%
    }

    function _calculateHealthFactorAfterBorrow(address user, address asset, uint256 amount) internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalBorrow) = _getUserPositionValues(user);
        
        uint256 assetPrice = priceOracle.getPrice(asset);
        uint256 borrowValueUSD = amount.mulDiv(assetPrice, PRECISION);
        uint256 newTotalBorrow = totalBorrow + borrowValueUSD;
        
        if (newTotalBorrow == 0) return type(uint256).max;
        
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 adjustedCollateral = totalCollateral.mulDiv(liquidationThreshold, PRECISION);
        
        return adjustedCollateral.mulDiv(PRECISION, newTotalBorrow);
    }

    function _calculateHealthFactorAfterWithdraw(address user, address asset, uint256 amount) internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalBorrow) = _getUserPositionValues(user);
        
        uint256 assetPrice = priceOracle.getPrice(asset);
        uint256 withdrawValueUSD = amount.mulDiv(assetPrice, PRECISION);
        uint256 newTotalCollateral = totalCollateral > withdrawValueUSD ? 
            totalCollateral - withdrawValueUSD : 0;
        
        if (totalBorrow == 0) return type(uint256).max;
        
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 adjustedCollateral = newTotalCollateral.mulDiv(liquidationThreshold, PRECISION);
        
        return adjustedCollateral.mulDiv(PRECISION, totalBorrow);
    }

    function _calculateHealthFactorWithPriceShock(address user, int256 priceShock) internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalBorrow) = _getUserPositionValues(user);
        
        if (totalBorrow == 0) return type(uint256).max;
        
        // Apply price shock to collateral (assuming negative shock reduces collateral value)
        uint256 shockedCollateral = totalCollateral;
        if (priceShock < 0) {
            uint256 reduction = totalCollateral.mulDiv(uint256(-priceShock), PRECISION);
            shockedCollateral = totalCollateral > reduction ? totalCollateral - reduction : 0;
        } else {
            uint256 increase = totalCollateral.mulDiv(uint256(priceShock), PRECISION);
            shockedCollateral = totalCollateral + increase;
        }
        
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 adjustedCollateral = shockedCollateral.mulDiv(liquidationThreshold, PRECISION);
        
        return adjustedCollateral.mulDiv(PRECISION, totalBorrow);
    }

    function _getUserRiskLevel(address user) internal view returns (uint8) {
        uint256 healthFactor = _calculateHealthFactor(user);
        
        if (healthFactor == type(uint256).max) return 1;
        
        for (uint8 i = 0; i < 5; i++) {
            if (healthFactor >= riskLevelThresholds[i]) {
                return i + 1;
            }
        }
        
        return 5;
    }

    function _calculatePortfolioVolatility(address user) internal view returns (uint256) {
        // Simplified portfolio volatility calculation
        // In practice, this would use correlation matrices and individual asset volatilities
        uint256 totalVolatility = 0;
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            uint256 assetValue = _getUserAssetValue(user, asset);
            
            if (assetValue > 0) {
                uint256 assetVolatility = _getAssetVolatilityScore(asset);
                totalVolatility += assetValue.mulDiv(assetVolatility, PRECISION);
                totalWeight += assetValue;
            }
        }
        
        return totalWeight > 0 ? totalVolatility.mulDiv(PRECISION, totalWeight) : 0;
    }

    function _getZScore(uint256 confidenceLevel) internal pure returns (uint256) {
        // Simplified Z-score mapping
        if (confidenceLevel >= 99) return 233e16; // ~2.33
        if (confidenceLevel >= 95) return 196e16; // ~1.96
        if (confidenceLevel >= 90) return 164e16; // ~1.64
        return 100e16; // Default 1.0
    }

    function _calculateAssetConcentrationRisk() internal view returns (uint256) {
        // Calculate Herfindahl-Hirschman Index for asset concentration
        uint256 totalValue = totalCollateralValue + totalBorrowValue;
        if (totalValue == 0) return 0;
        
        uint256 hhi = 0;
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            uint256 assetValue = _getAssetTotalValue(supportedAssets[i]);
            uint256 share = assetValue.mulDiv(PRECISION, totalValue);
            hhi += share.mulDiv(share, PRECISION);
        }
        
        // Convert to risk score (0-25 scale)
        return hhi.mulDiv(25, PRECISION);
    }

    function _calculateMarketVolatilityRisk() internal view returns (uint256) {
        // Simplified market volatility risk calculation
        uint256 totalVolatility = 0;
        uint256 assetCount = 0;
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            uint256 volatility = _getAssetVolatilityScore(supportedAssets[i]);
            totalVolatility += volatility;
            assetCount++;
        }
        
        uint256 avgVolatility = assetCount > 0 ? totalVolatility / assetCount : 0;
        
        // Convert to risk score (0-25 scale)
        return avgVolatility > 50e16 ? 25 : avgVolatility.mulDiv(50, PRECISION);
    }

    // Helper functions (would interface with lending pool in practice)
    function _getUserAssetBalance(address user, address asset) internal view returns (uint256) {
        // Placeholder - would query lending pool
        return 0;
    }

    function _getUserAssetDebt(address user, address asset) internal view returns (uint256) {
        // Placeholder - would query lending pool
        return 0;
    }

    function _getUserAssetCollateral(address user, address asset) internal view returns (uint256) {
        // Placeholder - would query lending pool
        return 0;
    }

    function _getUserAssetValue(address user, address asset) internal view returns (uint256) {
        // Placeholder - would query lending pool and price oracle
        return 0;
    }

    function _getAssetTotalSupply(address asset) internal view returns (uint256) {
        // Placeholder - would query lending pool
        return 0;
    }

    function _getAssetTotalBorrow(address asset) internal view returns (uint256) {
        // Placeholder - would query lending pool
        return 0;
    }

    function _getAssetTotalCollateralValue(address asset) internal view returns (uint256) {
        // Placeholder - would calculate from lending pool data
        return 0;
    }

    function _getAssetTotalBorrowValue(address asset) internal view returns (uint256) {
        // Placeholder - would calculate from lending pool data
        return 0;
    }

    function _getAssetTotalValue(address asset) internal view returns (uint256) {
        return _getAssetTotalCollateralValue(asset) + _getAssetTotalBorrowValue(asset);
    }

    function _getAssetVolatilityScore(address asset) internal view returns (uint256) {
        // Placeholder - would query price oracle for historical volatility
        return 20e16; // Default 20%
    }

    function _getAssetLiquidityScore(address asset) internal view returns (uint256) {
        // Placeholder - would calculate based on trading volume and market depth
        return 80e16; // Default 80%
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONFIGURATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function getRiskParameters(address asset) external view override returns (RiskParameters memory) {
        return assetRiskParams[asset];
    }

    function getLiquidationThreshold(address asset) external view override returns (uint256) {
        return assetRiskParams[asset].liquidationThreshold;
    }

    function getLiquidationBonus(address asset) external view override returns (uint256) {
        return assetRiskParams[asset].liquidationBonus;
    }

    function getBorrowFactor(address asset) external view override returns (uint256) {
        return assetRiskParams[asset].borrowFactor;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function setRiskParameters(
        address asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 borrowFactor
    ) external override onlyRole(RISK_ADMIN_ROLE) {
        require(asset != address(0), "RiskManager: Invalid asset");
        require(liquidationThreshold >= MIN_LIQUIDATION_THRESHOLD, "RiskManager: Threshold too low");
        require(liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD, "RiskManager: Threshold too high");
        require(liquidationBonus <= MAX_LIQUIDATION_BONUS, "RiskManager: Bonus too high");
        require(borrowFactor <= MAX_BORROW_FACTOR, "RiskManager: Borrow factor too high");

        assetRiskParams[asset].liquidationThreshold = liquidationThreshold;
        assetRiskParams[asset].liquidationBonus = liquidationBonus;
        assetRiskParams[asset].borrowFactor = borrowFactor;
        
        if (!isAssetSupported[asset]) {
            isAssetSupported[asset] = true;
            supportedAssets.push(asset);
        }

        emit RiskParametersUpdated(asset, liquidationThreshold, liquidationBonus, borrowFactor);
    }

    function setCaps(
        address asset,
        uint256 supplyCap,
        uint256 borrowCap
    ) external override onlyRole(RISK_ADMIN_ROLE) {
        require(isAssetSupported[asset], "RiskManager: Asset not supported");

        assetRiskParams[asset].supplyCap = supplyCap;
        assetRiskParams[asset].borrowCap = borrowCap;
    }

    function setAssetFrozen(address asset, bool frozen) external override onlyRole(ADMIN_ROLE) {
        require(isAssetSupported[asset], "RiskManager: Asset not supported");
        assetRiskParams[asset].isFrozen = frozen;
    }

    function setGlobalRiskParameters(
        uint256 _maxHealthFactorForLiquidation,
        uint256 _minHealthFactorForBorrow,
        uint256 _maxLiquidationRatio
    ) external override onlyRole(ADMIN_ROLE) {
        require(_maxHealthFactorForLiquidation <= PRECISION, "RiskManager: Invalid liquidation HF");
        require(_minHealthFactorForBorrow >= PRECISION, "RiskManager: Invalid borrow HF");
        require(_maxLiquidationRatio <= PRECISION, "RiskManager: Invalid liquidation ratio");

        maxHealthFactorForLiquidation = _maxHealthFactorForLiquidation;
        minHealthFactorForBorrow = _minHealthFactorForBorrow;
        maxLiquidationRatio = _maxLiquidationRatio;
    }

    function emergencyPause() external override onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function emergencyResume() external override onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Update user risk data (called by lending pool)
     */
    function updateUserRiskData(
        address user,
        uint256 totalCollateralValue,
        uint256 totalBorrowValue
    ) external onlyRole(POOL_ROLE) {
        uint256 healthFactor = totalBorrowValue > 0 ? 
            totalCollateralValue.mulDiv(_getUserLiquidationThreshold(user), totalBorrowValue) : 
            type(uint256).max;

        UserRiskData storage userData = userRiskData[user];
        uint256 oldHealthFactor = userData.healthFactor;
        
        userData.totalCollateralValue = totalCollateralValue;
        userData.totalBorrowValue = totalBorrowValue;
        userData.healthFactor = healthFactor;
        userData.liquidationThreshold = _getUserLiquidationThreshold(user);
        userData.maxBorrowValue = totalCollateralValue.mulDiv(userData.liquidationThreshold, PRECISION);
        userData.isLiquidatable = healthFactor < maxHealthFactorForLiquidation;
        
        userLastUpdate[user] = block.timestamp;

        // Update risk tracking
        _updateRiskTracking(user, oldHealthFactor, healthFactor);

        emit HealthFactorUpdated(user, oldHealthFactor, healthFactor);
    }

    function _updateRiskTracking(address user, uint256 oldHealthFactor, uint256 newHealthFactor) internal {
        uint8 oldRiskLevel = _calculateRiskLevel(oldHealthFactor);
        uint8 newRiskLevel = _calculateRiskLevel(newHealthFactor);
        
        // Add to risk tracking if health factor is concerning
        if (newHealthFactor < 150e16 && !isUserTracked[user]) { // < 1.5 HF
            riskUsers.push(user);
            riskUserIndex[user] = riskUsers.length - 1;
            isUserTracked[user] = true;
        }
        
        // Remove from risk tracking if health factor improves significantly
        if (newHealthFactor >= 150e16 && isUserTracked[user]) {
            _removeFromRiskTracking(user);
        }
        
        if (oldRiskLevel != newRiskLevel) {
            emit RiskLevelChanged(user, oldRiskLevel, newRiskLevel);
        }
        
        // Update system metrics
        _updateSystemMetrics();
    }

    function _calculateRiskLevel(uint256 healthFactor) internal view returns (uint8) {
        if (healthFactor == type(uint256).max) return 1;
        
        for (uint8 i = 0; i < 5; i++) {
            if (healthFactor >= riskLevelThresholds[i]) {
                return i + 1;
            }
        }
        return 5;
    }

    function _removeFromRiskTracking(address user) internal {
        if (!isUserTracked[user]) return;
        
        uint256 index = riskUserIndex[user];
        uint256 lastIndex = riskUsers.length - 1;
        
        if (index != lastIndex) {
            address lastUser = riskUsers[lastIndex];
            riskUsers[index] = lastUser;
            riskUserIndex[lastUser] = index;
        }
        
        riskUsers.pop();
        delete riskUserIndex[user];
        isUserTracked[user] = false;
    }

    function _updateSystemMetrics() internal {
        // Update system-wide risk metrics
        // This is a simplified implementation
        lastSystemUpdate = block.timestamp;
        
        // Calculate average health factor
        uint256 totalHealthFactor = 0;
        uint256 userCount = 0;
        uint256 riskCount = 0;
        
        for (uint256 i = 0; i < riskUsers.length; i++) {
            uint256 hf = userRiskData[riskUsers[i]].healthFactor;
            if (hf != type(uint256).max) {
                totalHealthFactor += hf;
                userCount++;
                
                if (hf < maxHealthFactorForLiquidation) {
                    riskCount++;
                }
            }
        }
        
        averageHealthFactor = userCount > 0 ? totalHealthFactor / userCount : type(uint256).max;
        positionsAtRisk = riskCount;
    }
}
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");
    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_LIQUIDATION_THRESHOLD = 95e16; // 95%
    uint256 public constant MIN_LIQUIDATION_THRESHOLD = 50e16; // 50%
    uint256 public constant MAX_LIQUIDATION_BONUS = 25e16; // 25%
    uint256 public constant MAX_BORROW_FACTOR = 90e16; // 90%

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    IPriceOracle public immutable priceOracle;
    address public immutable lendingPool;

    // Asset risk parameters
    mapping(address => RiskParameters) public assetRiskParams;
    mapping(address => bool) public isAssetSupported;
    address[] public supportedAssets;

    // Global risk parameters
    uint256 public maxHealthFactorForLiquidation = 1e18; // 1.0
    uint256 public minHealthFactorForBorrow = 105e16; // 1.05
    uint256 public maxLiquidationRatio = 50e16; // 50%

    // User position tracking
    mapping(address => UserRiskData) public userRiskData;
    mapping(address => uint256) public userLastUpdate;

    // Risk monitoring
    address[] public riskUsers;
    mapping(address => uint256) public riskUserIndex;
    mapping(address => bool) public isUserTracked;

    // System-wide risk metrics
    uint256 public totalCollateralValue;
    uint256 public totalBorrowValue;
    uint256 public averageHealthFactor;
    uint256 public positionsAtRisk;
    uint256 public lastSystemUpdate;

    // Risk level thresholds
    uint256[5] public riskLevelThresholds = [
        150e16, // Level 1: > 1.5
        125e16, // Level 2: 1.25 - 1.5
        110e16, // Level 3: 1.1 - 1.25
        105e16, // Level 4: 1.05 - 1.1
        100e16  // Level 5: 1.0 - 1.05
    ];

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        address _priceOracle,
        address _lendingPool,
        uint256 _defaultLiquidationThreshold,
        uint256 _defaultLiquidationBonus,
        uint256 _maxLiquidationRatio
    ) {
        require(_priceOracle != address(0), "RiskManager: Invalid price oracle");
        require(_lendingPool != address(0), "RiskManager: Invalid lending pool");
        require(_defaultLiquidationThreshold >= MIN_LIQUIDATION_THRESHOLD, "RiskManager: Threshold too low");
        require(_defaultLiquidationThreshold <= MAX_LIQUIDATION_THRESHOLD, "RiskManager: Threshold too high");

        priceOracle = IPriceOracle(_priceOracle);
        lendingPool = _lendingPool;
        maxLiquidationRatio = _maxLiquidationRatio;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(RISK_ADMIN_ROLE, msg.sender);
        _grantRole(POOL_ROLE, _lendingPool);

        lastSystemUpdate = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE RISK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate user's health factor
     */
    function calculateHealthFactor(address user) external view override returns (uint256 healthFactor) {
        return _calculateHealthFactor(user);
    }

    /**
     * @notice Get comprehensive user risk data
     */
    function getUserRiskData(address user) external view override returns (UserRiskData memory riskData) {
        UserRiskData memory userData = userRiskData[user];
        
        // Recalculate current values
        (uint256 totalCollateral, uint256 totalBorrow) = _getUserPositionValues(user);
        uint256 healthFactor = _calculateHealthFactor(user);
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 maxBorrowValue = totalCollateral.mulDiv(liquidationThreshold, PRECISION);
        
        return UserRiskData({
            totalCollateralValue: totalCollateral,
            totalBorrowValue: totalBorrow,
            healthFactor: healthFactor,
            liquidationThreshold: liquidationThreshold,
            maxBorrowValue: maxBorrowValue,
            isLiquidatable: healthFactor < maxHealthFactorForLiquidation
        });
    }

    /**
     * @notice Calculate maximum borrowing capacity
     */
    function getMaxBorrowAmount(address user, address asset) external view override returns (uint256 maxBorrowAmount) {
        (uint256 totalCollateral,) = _getUserPositionValues(user);
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 maxBorrowValue = totalCollateral.mulDiv(liquidationThreshold, PRECISION);
        
        uint256 assetPrice = priceOracle.getPrice(asset);
        return maxBorrowValue.mulDiv(PRECISION, assetPrice);
    }

    /**
     * @notice Calculate maximum withdrawal amount
     */
    function getMaxWithdrawAmount(address user, address asset) external view override returns (uint256 maxWithdrawAmount) {
        (uint256 totalCollateral, uint256 totalBorrow) = _getUserPositionValues(user);
        
        if (totalBorrow == 0) {
            // No debt, can withdraw everything
            return _getUserAssetBalance(user, asset);
        }
        
        uint256 liquidationThreshold = _getUserLiquidationThreshold(user);
        uint256 requiredCollateral = totalBorrow.mulDiv(PRECISION, liquidationThreshold);
        
        if (totalCollateral <= requiredCollateral) {
            return 0; // Cannot withdraw anything
        }
        
        uint256 excessCollateral = totalCollateral - requiredCollateral;
        uint256 assetPrice = priceOracle.getPrice(asset);
        uint256 maxWithdrawValue = excessCollateral;
        
        return maxWithdrawValue.mulDiv(PRECISION, assetPrice);
    }

    /**
     * @notice Calculate liquidation amounts
     */
    function calculateLiquidationAmounts(
        address user,
        address debtAsset,
        address collateralAsset,
        uint256 debtAmount
    ) external view override returns (uint256 collateralAmount, uint256 liquidationBonus) {
        uint256 debtPrice = priceOracle.getPrice(debtAsset);
        uint256 collateralPrice = priceOracle.getPrice(collateralAsset);
        
        uint256 liquidationBonusRate = assetRiskParams[collateralAsset].liquidationBonus;
        
        // Calculate debt value in USD
        uint256 debtValueUSD = debtAmount.mulDiv(debtPrice, PRECISION);
        
        // Calculate collateral to seize (including bonus)
        uint256 collateralValueUSD = debtValueUSD.mulDiv(PRECISION + liquidationBonusRate, PRECISION);
        collateralAmount = collateralValueUSD.mulDiv(PRECISION, collateralPrice);
        
        // Calculate liquidation bonus
        liquidationBonus = debtValueUSD.mulDiv(liquidationBonusRate, PRECISION).mulDiv(PRECISION, collateralPrice);
        
        return (collateralAmount, liquidationBonus);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if borrow operation is allowed
     */
    function isBorrowAllowed(
        address user,
        address asset,
        uint256 amount
    ) external view override returns (bool isAllowed, string memory reason) {
        if (!isAssetSupported[asset]) {
            return (false, "Asset not supported");
        }
        
        if (assetRiskParams[asset].isFrozen) {
            return (false, "Asset is frozen");
        }
        
        // Check borrow cap
        uint256 currentBorrow = _getAssetTotalBorrow(asset);
        if (currentBorrow + amount > assetRiskParams[asset].borrowCap) {
            return (false, "Borrow cap exceeded");
        }
        
        // Check health factor after borrow
        uint256 newHealthFactor = _calculateHealthFactorAfterBorrow(user, asset, amount);
        if (newHealthFactor < minHealthFactorForBorrow) {
            return (false, "Health factor too low");
        }
        
        return (true, "");
    }

    /**
     * @notice Check if withdrawal is allowed
     */
    function isWithdrawAllowed(
        address user,
        address asset,
        uint256 amount
    ) external view override returns (bool isAllowed, string memory reason) {
        if (!isAssetSupported[asset]) {
            return (false, "Asset not supported");
        }
        
        // Check if user has sufficient balance
        uint256 userBalance = _getUserAssetBalance(user, asset);
        if (amount > userBalance) {
            return (false, "Insufficient balance");
        }
        
        // Check health factor after withdrawal
        uint256 newHealthFactor = _calculateHealthFactorAfterWithdraw(user, asset, amount);
        if (newHealthFactor < minHealthFactorForBorrow && newHealthFactor != type(uint256).max) {
            return (false, "Health factor too low");
        }
        
        return (true, "");
    }

    /**
     * @notice Check if liquidation is allowed
     */
    function isLiquidationAllowed(address user) external view override returns (bool isAllowed, uint256 healthFactor) {
        healthFactor = _calculateHealthFactor(user);
        isAllowed = healthFactor < maxHealthFactorForLiquidation;
        
        return (isAllowed, healthFactor);
    }

    /**
     * @notice Validate supply operation
     */
    function validateSupply(
        address user,
        address asset,
        uint256 amount
    ) external view override returns (bool isValid, string memory reason) {
        if (!isAssetSupported[asset]) {
            return (false, "Asset not supported");
        }
        
        if (assetRiskParams[asset].isFrozen) {
            return (false, "Asset is frozen");
        }
        
        // Check supply cap
        uint256 currentSupply = _getAssetTotalSupply(asset);
        if (currentSupply + amount > assetRiskParams[asset].supplyCap) {
            return (false, "Supply cap exceeded");
        }
        
        return (true, "");
    }

    /**
     * @notice Validate repay operation
     */
    function validateRepay(
        address user,
        address asset,
        uint256 amount
    ) external view override returns (bool isValid, string memory reason) {
        if (!isAssetSupported[asset]) {
            return (false, "Asset not supported");
        }
        
        uint256 userDebt = _getUserAssetDebt(user, asset);
        if (amount > userDebt) {
            return (false, "Repay amount exceeds debt");
        }
        
        return (true, "");
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // RISK ASSESSMENT
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user's risk level (1-5 scale)
     */
    function getUserRiskLevel(address user) external view override returns (uint8 riskLevel) {
        uint256 healthFactor = _calculateHealthFactor(user);
        
        if (healthFactor == type(uint256).max) return 1; // No debt
        
        for (uint8 i = 0; i < 5; i++) {
            if (healthFactor >= riskLevelThresholds[i]) {
                return i + 1;
            }
        }
        
        return 5; // Highest risk
    }

    /**
     * @notice Get asset risk metrics
     */
    function getAssetRisk(address asset) external view override returns (AssetRisk memory assetRisk) {
        uint256 collateralValue = _getAssetTotalCollateralValue(asset);
        uint256 borrowValue = _getAssetTotalBorrowValue(asset);
        uint256 utilizationRate = collateralValue > 0 ? borrowValue.mulDiv(PRECISION, collateralValue) : 0;
        
        return AssetRisk({
            asset: asset,
            collateralValue: collateralValue,
            borrowValue: borrowValue,
            utilizationRate: utilizationRate,
            volatilityScore: _getAssetVolatilityScore(asset),
            liquidityScore: _getAssetLiquidityScore(asset)
        });
    }

    /**
     * @notice Get portfolio diversification score
     */
    function getPortfolioDiversification(address user) external view override returns (uint256 diversificationScore) {
        // Calculate Herfindahl-Hirschman Index for portfolio concentration
        uint256[] memory assetShares = new uint256[](supportedAssets.length);
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            uint256 assetValue = _getUserAssetValue(user, supportedAssets[i]);
            assetShares[i] = assetValue;
            totalValue += assetValue;
        }
        
        if (totalValue == 0) return 100; // Perfectly diversified (no positions)
        
        uint256 hhi = 0;
        for (uint256 i = 0; i < assetShares.length; i++) {
            uint256 share = assetShares[i].mulDiv(PRECISION, totalValue);
            hhi += share.mulDiv(share, PRECISION);
        }
        
        // Convert HHI to diversification score (lower HHI = higher diversification)
        diversificationScore = PRECISION - hhi;
        return diversificationScore.mulDiv(100, PRECISION); // Convert to 0-100 scale
    }

    /**
     * @notice Calculate value at risk (VaR)
     */
    function calculateValueAtRisk(
        address user,
        uint256 confidenceLevel,
        uint256 timeHorizon
    ) external view override returns (uint256 valueAtRisk) {
        (uint256 totalCollateral,) = _getUserPositionValues(user);
        
        if (totalCollateral == 0) return 0;
        
        // Simplified VaR calculation using historical volatility
        uint256 portfolioVolatility = _calculatePortfolioVolatility(user);
        
        // Z-score for confidence level (simplified)
        uint256 zScore = _getZScore(confidenceLevel);
        
        // VaR = Portfolio Value * Z-Score * Volatility * sqrt(Time Horizon)
        uint256 timeAdjustment = Math.sqrt(timeHorizon * PRECISION);
        valueAtRisk = totalCollateral
            .mulDiv(zScore, PRECISION)
            .mulDiv(portfolioVolatility, PRECISION)
            .mulDiv(timeAdjustment, PRECISION);
        
        return valueAtRisk;
    }

    /**
     * @notice Get stress test results
     */
    function stressTest(
        address user,
        int256[] calldata priceShocks
    ) external view override returns (uint256[] memory healthFactors, bool[] memory wouldBeLiquidated) {
        healthFactors = new uint256[](priceShocks.length);
        wouldBeLiquidated = new bool[](priceShocks.length);
        
        for (uint256 i = 0; i < priceShocks.length; i++) {
            uint256 healthFactor = _calculateHealthFactorWithPriceShock(user, priceShocks[i]);
            healthFactors[i] = healthFactor;
            wouldBeLiquidated[i] = healthFactor < maxHealthFactorForLiquidation;
        }
        
        return (healthFactors, wouldBeLiquidated);
    }

    // ═══════════════════════════════════════════════════════════