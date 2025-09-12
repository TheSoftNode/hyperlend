// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IHyperLendPool
 * @dev Interface for the main HyperLend lending pool
 */
interface IHyperLendPool {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct Market {
        address asset;
        address hlToken;
        address debtToken;
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 borrowIndex;
        uint256 supplyIndex;
        uint256 lastUpdateTimestamp;
        bool isActive;
        bool isFrozen;
        uint256 reserveFactor;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 borrowCap;
        uint256 supplyCap;
    }

    struct UserAccount {
        uint256 totalCollateralValue;
        uint256 totalBorrowValue;
        uint256 healthFactor;
        uint256 lastUpdateTimestamp;
        bool isLiquidatable;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event Supply(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event Withdraw(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event Borrow(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event Repay(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event Liquidation(
        address indexed liquidator,
        address indexed user,
        address indexed collateralAsset,
        address debtAsset,
        uint256 debtAmount,
        uint256 collateralAmount
    );
    event InterestRateUpdate(
        address indexed asset,
        uint256 supplyAPY,
        uint256 borrowAPY
    );
    event HealthFactorUpdate(
        address indexed user,
        uint256 oldHealthFactor,
        uint256 newHealthFactor
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function borrow(address asset, uint256 amount) external;
    function repay(address asset, uint256 amount) external;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // LIQUIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function liquidate(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    ) external;

    function microLiquidate(
        address user,
        address debtAsset,
        uint256 maxDebtAmount,
        address collateralAsset
    ) external;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function updateMarketInterest(address asset) external;
    function batchUpdateInterest(address[] calldata assets) external;
    function updateUserHealth(address user) external;
    function batchUpdateUserHealth(address[] calldata users) external;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralValue,
            uint256 totalBorrowValue,
            uint256 healthFactor,
            bool isLiquidatable
        );

    function getMarketData(
        address asset
    )
        external
        view
        returns (
            uint256 totalSupply,
            uint256 totalBorrow,
            uint256 utilizationRate,
            uint256 supplyAPY,
            uint256 borrowAPY
        );

    function getRealTimeMetrics()
        external
        view
        returns (
            uint256 tvl,
            uint256 borrowed,
            uint256 utilization,
            uint256 avgSupplyAPY,
            uint256 avgBorrowAPY,
            uint256 lastUpdate
        );

    // User position getters (public mappings)
    function supplyShares(
        address user,
        address asset
    ) external view returns (uint256);
    function borrowShares(
        address user,
        address asset
    ) external view returns (uint256);
    function markets(
        address asset
    )
        external
        view
        returns (
            address asset_,
            address hlToken,
            address debtToken,
            uint256 totalSupply,
            uint256 totalBorrow,
            uint256 borrowIndex,
            uint256 supplyIndex,
            uint256 lastUpdateTimestamp,
            bool isActive,
            bool isFrozen,
            uint256 reserveFactor,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 borrowCap,
            uint256 supplyCap
        );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function addMarket(
        address asset,
        address hlToken,
        address debtToken,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 borrowCap,
        uint256 supplyCap
    ) external;

    function pause() external;
    function unpause() external;
}
