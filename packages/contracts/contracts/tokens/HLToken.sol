// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title HLToken
 * @dev Interest-bearing token representing supply positions in HyperLend
 * @notice Automatically accrues interest through exchange rate mechanism
 */
contract HLToken is ERC20, ERC20Permit, AccessControl, Pausable {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 public constant PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice The underlying asset this token represents
    address public immutable underlyingAsset;

    /// @notice The HyperLend pool that manages this token
    address public immutable pool;

    /// @notice Initial exchange rate (scaled by PRECISION)
    uint256 public constant INITIAL_EXCHANGE_RATE = 1e18;

    /// @notice Current exchange rate from hlTokens to underlying asset
    uint256 public exchangeRate;

    /// @notice Last time the exchange rate was updated
    uint256 public lastExchangeRateUpdate;

    /// @notice Total underlying assets represented by this token
    uint256 public totalUnderlying;

    /// @notice Accumulated interest since inception
    uint256 public totalInterestEarned;

    /// @notice Reserve factor for protocol fees
    uint256 public reserveFactor;

    /// @notice Protocol reserves accumulated
    uint256 public protocolReserves;

    // Real-time metrics
    uint256 public currentSupplyAPY;
    uint256 public last24hInterestEarned;
    uint256 public lastMetricsUpdate;

    // User tracking
    mapping(address => uint256) public userLastUpdate;
    mapping(address => uint256) public userAccruedInterest;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event ExchangeRateUpdated(
        uint256 oldRate,
        uint256 newRate,
        uint256 timestamp
    );
    event InterestAccrued(uint256 interestAmount, uint256 newExchangeRate);
    event UserInterestClaimed(address indexed user, uint256 amount);
    event ReserveFactorUpdated(uint256 oldFactor, uint256 newFactor);
    event ProtocolReservesWithdrawn(address indexed to, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    modifier onlyPool() {
        require(msg.sender == pool, "HLToken: Only pool can call");
        _;
    }

    modifier updateUserMetrics(address user) {
        _updateUserMetrics(user);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        string memory name,
        string memory symbol,
        address _underlyingAsset,
        address _pool,
        address admin
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(
            _underlyingAsset != address(0),
            "HLToken: Invalid underlying asset"
        );
        require(_pool != address(0), "HLToken: Invalid pool");
        require(admin != address(0), "HLToken: Invalid admin");

        underlyingAsset = _underlyingAsset;
        pool = _pool;
        exchangeRate = INITIAL_EXCHANGE_RATE;
        lastExchangeRateUpdate = block.timestamp;
        lastMetricsUpdate = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, _pool);
        _grantRole(BURNER_ROLE, _pool);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint hlTokens to user (only callable by pool)
     * @param to Address to mint to
     * @param amount Amount of hlTokens to mint
     */
    function mint(
        address to,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) whenNotPaused updateUserMetrics(to) {
        require(to != address(0), "HLToken: Mint to zero address");
        require(amount > 0, "HLToken: Invalid mint amount");

        _mint(to, amount);

        // Update total underlying based on current exchange rate
        uint256 underlyingAmount = hlTokensToUnderlying(amount);
        totalUnderlying += underlyingAmount;
    }

    /**
     * @notice Burn hlTokens from user (only callable by pool)
     * @param from Address to burn from
     * @param amount Amount of hlTokens to burn
     */
    function burn(
        address from,
        uint256 amount
    ) external onlyRole(BURNER_ROLE) whenNotPaused updateUserMetrics(from) {
        require(from != address(0), "HLToken: Burn from zero address");
        require(amount > 0, "HLToken: Invalid burn amount");
        require(balanceOf(from) >= amount, "HLToken: Insufficient balance");

        _burn(from, amount);

        // Update total underlying
        uint256 underlyingAmount = hlTokensToUnderlying(amount);
        totalUnderlying = totalUnderlying > underlyingAmount
            ? totalUnderlying - underlyingAmount
            : 0;
    }

    /**
     * @notice Update exchange rate to accrue interest
     * @param newExchangeRate New exchange rate
     */
    function updateExchangeRate(uint256 newExchangeRate) external onlyPool {
        require(
            newExchangeRate >= exchangeRate,
            "HLToken: Exchange rate cannot decrease"
        );

        uint256 oldRate = exchangeRate;

        if (newExchangeRate > oldRate) {
            // Calculate interest earned
            uint256 totalSupply = totalSupply();
            if (totalSupply > 0) {
                uint256 oldUnderlying = (totalSupply * oldRate) / PRECISION;
                uint256 newUnderlying = (totalSupply * newExchangeRate) /
                    PRECISION;
                uint256 interestEarned = newUnderlying - oldUnderlying;

                // Apply reserve factor
                uint256 protocolFee = (interestEarned * reserveFactor) /
                    PRECISION;
                protocolReserves += protocolFee;

                totalInterestEarned += interestEarned;
                _update24hMetrics(interestEarned);

                emit InterestAccrued(interestEarned, newExchangeRate);
            }
        }

        exchangeRate = newExchangeRate;
        lastExchangeRateUpdate = block.timestamp;

        emit ExchangeRateUpdated(oldRate, newExchangeRate, block.timestamp);
    }

    /**
     * @notice Update current supply APY
     * @param supplyAPY New supply APY
     */
    function updateSupplyAPY(uint256 supplyAPY) external onlyPool {
        currentSupplyAPY = supplyAPY;
        lastMetricsUpdate = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert hlTokens to underlying asset amount
     * @param hlTokenAmount Amount of hlTokens
     * @return underlyingAmount Equivalent underlying asset amount
     */
    function hlTokensToUnderlying(
        uint256 hlTokenAmount
    ) public view returns (uint256 underlyingAmount) {
        return (hlTokenAmount * exchangeRate) / PRECISION;
    }

    /**
     * @notice Convert underlying asset amount to hlTokens
     * @param underlyingAmount Amount of underlying asset
     * @return hlTokenAmount Equivalent hlToken amount
     */
    function underlyingToHlTokens(
        uint256 underlyingAmount
    ) public view returns (uint256 hlTokenAmount) {
        return (underlyingAmount * PRECISION) / exchangeRate;
    }

    /**
     * @notice Get user's underlying asset balance
     * @param user User address
     * @return underlyingBalance Underlying asset balance
     */
    function balanceOfUnderlying(
        address user
    ) external view returns (uint256 underlyingBalance) {
        return hlTokensToUnderlying(balanceOf(user));
    }

    /**
     * @notice Get user's accrued interest since last update
     * @param user User address
     * @return accruedInterest Interest accrued since last update
     */
    function getAccruedInterest(
        address user
    ) external view returns (uint256 accruedInterest) {
        uint256 currentBalance = balanceOf(user);
        if (currentBalance == 0 || userLastUpdate[user] == 0) return 0;

        uint256 currentUnderlying = hlTokensToUnderlying(currentBalance);
        uint256 lastUnderlying = userAccruedInterest[user];

        return
            currentUnderlying > lastUnderlying
                ? currentUnderlying - lastUnderlying
                : 0;
    }

    /**
     * @notice Get current metrics
     * @return supplyAPY Current supply APY
     * @return totalEarned Total interest earned
     * @return last24h Interest earned in last 24 hours
     * @return rate Current exchange rate
     */
    function getCurrentMetrics()
        external
        view
        returns (
            uint256 supplyAPY,
            uint256 totalEarned,
            uint256 last24h,
            uint256 rate
        )
    {
        return (
            currentSupplyAPY,
            totalInterestEarned,
            last24hInterestEarned,
            exchangeRate
        );
    }

    /**
     * @notice Calculate projected balance after time period
     * @param user User address
     * @param timeSeconds Time period in seconds
     * @return projectedBalance Projected balance
     */
    function getProjectedBalance(
        address user,
        uint256 timeSeconds
    ) external view returns (uint256 projectedBalance) {
        uint256 currentBalance = balanceOf(user);
        if (currentBalance == 0 || currentSupplyAPY == 0) return currentBalance;

        // Calculate compound interest
        uint256 ratePerSecond = currentSupplyAPY / (365 days);
        uint256 compoundFactor = PRECISION + (ratePerSecond * timeSeconds);

        projectedBalance = (currentBalance * compoundFactor) / PRECISION;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _updateUserMetrics(address user) internal {
        if (user == address(0)) return;

        uint256 currentBalance = balanceOf(user);
        uint256 currentUnderlying = hlTokensToUnderlying(currentBalance);

        // Update user's accrued interest tracking
        if (
            userLastUpdate[user] > 0 &&
            currentUnderlying > userAccruedInterest[user]
        ) {
            uint256 newInterest = currentUnderlying - userAccruedInterest[user];
            emit UserInterestClaimed(user, newInterest);
        }

        userAccruedInterest[user] = currentUnderlying;
        userLastUpdate[user] = block.timestamp;
    }

    function _update24hMetrics(uint256 newInterest) internal {
        // Reset 24h counter if needed
        if (block.timestamp >= lastMetricsUpdate + 24 hours) {
            last24hInterestEarned = 0;
            lastMetricsUpdate = block.timestamp;
        }

        last24hInterestEarned += newInterest;
    }

    // Override transfer functions to update user metrics
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);

        if (from != address(0)) {
            _updateUserMetrics(from);
        }
        if (to != address(0)) {
            _updateUserMetrics(to);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set reserve factor
     * @param newReserveFactor New reserve factor (scaled by PRECISION)
     */
    function setReserveFactor(
        uint256 newReserveFactor
    ) external onlyRole(ADMIN_ROLE) {
        require(
            newReserveFactor <= PRECISION / 2,
            "HLToken: Reserve factor too high"
        ); // Max 50%

        uint256 oldFactor = reserveFactor;
        reserveFactor = newReserveFactor;

        emit ReserveFactorUpdated(oldFactor, newReserveFactor);
    }

    /**
     * @notice Withdraw protocol reserves
     * @param to Address to send reserves to
     * @param amount Amount to withdraw
     */
    function withdrawReserves(
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "HLToken: Invalid recipient");
        require(amount <= protocolReserves, "HLToken: Insufficient reserves");

        protocolReserves -= amount;

        // This would transfer underlying assets to the recipient
        // Implementation depends on how reserves are managed

        emit ProtocolReservesWithdrawn(to, amount);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency function to update exchange rate directly
     * @param newRate New exchange rate
     */
    function emergencyUpdateExchangeRate(
        uint256 newRate
    ) external onlyRole(ADMIN_ROLE) {
        require(newRate > 0, "HLToken: Invalid rate");

        uint256 oldRate = exchangeRate;
        exchangeRate = newRate;
        lastExchangeRateUpdate = block.timestamp;

        emit ExchangeRateUpdated(oldRate, newRate, block.timestamp);
    }
}
