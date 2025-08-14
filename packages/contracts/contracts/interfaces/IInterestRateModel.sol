// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IInterestRateModel
 * @dev Interface for interest rate calculation models
 */
interface IInterestRateModel {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event InterestRateModelUpdate(
        address indexed asset,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate supply and borrow rates
     * @param asset The market asset
     * @param utilizationRate Current utilization rate
     * @param totalSupply Total supplied amount
     * @param totalBorrow Total borrowed amount
     * @return borrowAPY Annual percentage yield for borrowing
     * @return supplyAPY Annual percentage yield for supplying
     */
    function calculateRates(
        address asset,
        uint256 utilizationRate,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view returns (uint256 borrowAPY, uint256 supplyAPY);

    /**
     * @notice Get current utilization rate for an asset
     * @param asset The market asset
     * @param totalSupply Total supplied amount
     * @param totalBorrow Total borrowed amount
     * @return utilizationRate Current utilization rate (scaled by 1e18)
     */
    function getUtilizationRate(
        address asset,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external pure returns (uint256 utilizationRate);

    /**
     * @notice Calculate borrow rate per second
     * @param asset The market asset
     * @param utilizationRate Current utilization rate
     * @return borrowRatePerSecond Borrow rate per second
     */
    function getBorrowRate(
        address asset,
        uint256 utilizationRate
    ) external view returns (uint256 borrowRatePerSecond);

    /**
     * @notice Calculate supply rate per second
     * @param asset The market asset
     * @param utilizationRate Current utilization rate
     * @param borrowRate Current borrow rate
     * @param reserveFactor Reserve factor for the market
     * @return supplyRatePerSecond Supply rate per second
     */
    function getSupplyRate(
        address asset,
        uint256 utilizationRate,
        uint256 borrowRate,
        uint256 reserveFactor
    ) external view returns (uint256 supplyRatePerSecond);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get interest rate model parameters for an asset
     * @param asset The market asset
     * @return baseRate Base interest rate
     * @return multiplier Rate multiplier before kink
     * @return jumpMultiplier Rate multiplier after kink
     * @return kink Utilization rate where jump multiplier kicks in
     */
    function getInterestRateParams(
        address asset
    )
        external
        view
        returns (
            uint256 baseRate,
            uint256 multiplier,
            uint256 jumpMultiplier,
            uint256 kink
        );

    /**
     * @notice Check if asset has custom interest rate parameters
     * @param asset The market asset
     * @return hasCustomParams True if asset has custom parameters
     */
    function hasCustomParams(
        address asset
    ) external view returns (bool hasCustomParams);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set interest rate model parameters for an asset
     * @param asset The market asset
     * @param baseRate Base interest rate (scaled by 1e18)
     * @param multiplier Rate multiplier before kink (scaled by 1e18)
     * @param jumpMultiplier Rate multiplier after kink (scaled by 1e18)
     * @param kink Utilization rate where jump multiplier kicks in (scaled by 1e18)
     */
    function setInterestRateParams(
        address asset,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    ) external;

    /**
     * @notice Remove custom parameters for an asset (revert to default)
     * @param asset The market asset
     */
    function removeCustomParams(address asset) external;

    /**
     * @notice Update default interest rate parameters
     * @param baseRate Default base interest rate
     * @param multiplier Default rate multiplier before kink
     * @param jumpMultiplier Default rate multiplier after kink
     * @param kink Default utilization rate where jump multiplier kicks in
     */
    function updateDefaultParams(
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    ) external;
}
