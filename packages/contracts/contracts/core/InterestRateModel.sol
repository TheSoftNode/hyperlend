// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IInterestRateModel.sol";
import "../libraries/Math.sol";

/**
 * @title InterestRateModel
 * @dev Dynamic interest rate model with real-time rate adjustments
 * @notice Optimized for Somnia's high-throughput environment
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
    mapping(address => bool) public hasCustomParams;

    // Rate caching for gas optimization
    mapping(address => uint256) public lastBorrowRate;
    mapping(address => uint256) public lastSupplyRate;
    mapping(address => uint256) public lastUtilizationRate;
    mapping(address => uint256) public lastUpdateTimestamp;

    // Real-time rate tracking
    mapping(address => uint256[]) public rateHistory;
    mapping(address => uint256[]) public timestampHistory;
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
        uint256 _jumpMultiplier
    ) {
        require(_baseRate <= MAX_RATE, "Base rate too high");
        require(_multiplier <= MAX_RATE, "Multiplier too high");
        require(_jumpMultiplier <= MAX_RATE, "Jump multiplier too high");
        require(_kink <= MAX_UTILIZATION, "Kink too high");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

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
     * @notice Calculate supply and borrow rates
     */
    function calculateRates(
        address asset,
        uint256 utilizationRate,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view override returns (uint256 borrowAPY, uint256 supplyAPY) {
        require(utilizationRate <= MAX_UTILIZATION, "Invalid utilization rate");

        InterestRateParams memory params = hasCustomParams[asset]
            ? assetParams[asset]
            : defaultParams;

        // Calculate borrow rate
        borrowAPY = _calculateBorrowRate(utilizationRate, params);

        // Calculate supply rate
        uint256 reserveFactor = 0; // Can be made configurable
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
        address asset,
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
        InterestRateParams memory params = hasCustomParams[asset]
            ? assetParams[asset]
            : defaultParams;

        uint256 borrowAPY = _calculateBorrowRate(utilizationRate, params);
        return borrowAPY / SECONDS_PER_YEAR;
    }

    /**
     * @notice Calculate supply rate per second
     */
    function getSupplyRate(
        address asset,
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
        uint256[] storage rates = rateHistory[asset];
        uint256[] storage timestamps = timestampHistory[asset];

        // Add new rate (store both borrow and supply rates in one value)
        uint256 combinedRate = (borrowRate << 128) | supplyRate;
        rates.push(combinedRate);
        timestamps.push(timestamp);

        // Maintain history length
        if (rates.length > MAX_HISTORY_LENGTH) {
            // Remove oldest entry
            for (uint256 i = 0; i < rates.length - 1; i++) {
                rates[i] = rates[i + 1];
                timestamps[i] = timestamps[i + 1];
            }
            rates.pop();
            timestamps.pop();
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
        InterestRateParams memory params = hasCustomParams[asset]
            ? assetParams[asset]
            : defaultParams;

        return (
            params.baseRate,
            params.multiplier,
            params.jumpMultiplier,
            params.kink
        );
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
        uint256[] storage rates = rateHistory[asset];
        uint256[] storage timestampsStored = timestampHistory[asset];

        uint256 actualLength = length > rates.length ? rates.length : length;

        borrowRates = new uint256[](actualLength);
        supplyRates = new uint256[](actualLength);
        timestamps = new uint256[](actualLength);

        uint256 startIndex = rates.length >= actualLength
            ? rates.length - actualLength
            : 0;

        for (uint256 i = 0; i < actualLength; i++) {
            uint256 combinedRate = rates[startIndex + i];
            borrowRates[i] = combinedRate >> 128;
            supplyRates[i] = combinedRate & ((1 << 128) - 1);
            timestamps[i] = timestampsStored[startIndex + i];
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

        hasCustomParams[asset] = true;

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
        hasCustomParams[asset] = false;
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
}
