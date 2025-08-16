// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DebtToken
 * @dev Token representing debt positions in HyperLend
 * @notice Non-transferable token that tracks borrowing positions and accrued interest
 */
contract DebtToken is ERC20, AccessControl, Pausable {
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

    /// @notice The underlying asset this debt token represents
    address public immutable underlyingAsset;

    /// @notice The HyperLend pool that manages this token
    address public immutable pool;

    /// @notice Current borrow index for interest calculation
    uint256 public borrowIndex;

    /// @notice Last time the borrow index was updated
    uint256 public lastBorrowIndexUpdate;

    /// @notice Total principal debt (excluding interest)
    uint256 public totalPrincipalDebt;

    /// @notice Total interest accrued since inception
    uint256 public totalInterestAccrued;

    /// @notice Current borrow APY
    uint256 public currentBorrowAPY;

    /// @notice Last 24h interest accrued
    uint256 public last24hInterestAccrued;

    /// @notice Last metrics update timestamp
    uint256 public lastMetricsUpdate;

    // User debt tracking
    struct UserDebt {
        uint256 principalDebt; // Original borrowed amount
        uint256 borrowIndex; // Borrow index when debt was created/last updated
        uint256 lastUpdateTime; // Last time this user's debt was updated
        uint256 accruedInterest; // Total interest accrued for this user
    }

    mapping(address => UserDebt) public userDebts;
    mapping(address => uint256) public userTotalDebt; // Principal + interest

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event BorrowIndexUpdated(
        uint256 oldIndex,
        uint256 newIndex,
        uint256 timestamp
    );
    event UserDebtUpdated(
        address indexed user,
        uint256 principalDebt,
        uint256 totalDebt,
        uint256 accruedInterest
    );
    event InterestAccrued(address indexed user, uint256 interestAmount);
    event BorrowAPYUpdated(uint256 oldAPY, uint256 newAPY);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    modifier onlyPool() {
        require(msg.sender == pool, "DebtToken: Only pool can call");
        _;
    }

    modifier updateUserDebt(address user) {
        _updateUserDebt(user);
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
    ) ERC20(name, symbol) {
        require(
            _underlyingAsset != address(0),
            "DebtToken: Invalid underlying asset"
        );
        require(_pool != address(0), "DebtToken: Invalid pool");
        require(admin != address(0), "DebtToken: Invalid admin");

        underlyingAsset = _underlyingAsset;
        pool = _pool;
        borrowIndex = PRECISION; // Start with index of 1.0
        lastBorrowIndexUpdate = block.timestamp;
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
     * @notice Mint debt tokens to user (only callable by pool)
     * @param to Address to mint to
     * @param amount Amount of debt tokens to mint
     */
    function mint(
        address to,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) whenNotPaused updateUserDebt(to) {
        require(to != address(0), "DebtToken: Mint to zero address");
        require(amount > 0, "DebtToken: Invalid mint amount");

        _mint(to, amount);

        // Update user's debt tracking
        UserDebt storage userDebt = userDebts[to];
        userDebt.principalDebt += amount;
        userDebt.borrowIndex = borrowIndex;
        userDebt.lastUpdateTime = block.timestamp;

        // Update totals
        totalPrincipalDebt += amount;
        userTotalDebt[to] = _calculateUserTotalDebt(to);

        emit UserDebtUpdated(
            to,
            userDebt.principalDebt,
            userTotalDebt[to],
            userDebt.accruedInterest
        );
    }

    /**
     * @notice Burn debt tokens from user (only callable by pool)
     * @param from Address to burn from
     * @param amount Amount of debt tokens to burn
     */
    function burn(
        address from,
        uint256 amount
    ) external onlyRole(BURNER_ROLE) whenNotPaused updateUserDebt(from) {
        require(from != address(0), "DebtToken: Burn from zero address");
        require(amount > 0, "DebtToken: Invalid burn amount");
        require(balanceOf(from) >= amount, "DebtToken: Insufficient balance");

        _burn(from, amount);

        // Update user's debt tracking
        UserDebt storage userDebt = userDebts[from];

        // Burn reduces principal debt first, then accrued interest
        if (amount <= userDebt.principalDebt) {
            userDebt.principalDebt -= amount;
            totalPrincipalDebt -= amount;
        } else {
            uint256 principalReduction = userDebt.principalDebt;
            uint256 interestReduction = amount - principalReduction;

            userDebt.principalDebt = 0;
            userDebt.accruedInterest = userDebt.accruedInterest >
                interestReduction
                ? userDebt.accruedInterest - interestReduction
                : 0;

            totalPrincipalDebt -= principalReduction;
            totalInterestAccrued = totalInterestAccrued > interestReduction
                ? totalInterestAccrued - interestReduction
                : 0;
        }

        userDebt.borrowIndex = borrowIndex;
        userDebt.lastUpdateTime = block.timestamp;
        userTotalDebt[from] = _calculateUserTotalDebt(from);

        emit UserDebtUpdated(
            from,
            userDebt.principalDebt,
            userTotalDebt[from],
            userDebt.accruedInterest
        );
    }

    /**
     * @notice Update borrow index to accrue interest
     * @param newBorrowIndex New borrow index
     */
    function updateBorrowIndex(uint256 newBorrowIndex) external onlyPool {
        require(
            newBorrowIndex >= borrowIndex,
            "DebtToken: Borrow index cannot decrease"
        );

        uint256 oldIndex = borrowIndex;

        if (newBorrowIndex > oldIndex && totalSupply() > 0) {
            // Calculate total interest accrued
            uint256 indexDelta = newBorrowIndex - oldIndex;
            uint256 interestAccrued = (totalSupply() * indexDelta) / PRECISION;

            totalInterestAccrued += interestAccrued;
            _update24hMetrics(interestAccrued);
        }

        borrowIndex = newBorrowIndex;
        lastBorrowIndexUpdate = block.timestamp;

        emit BorrowIndexUpdated(oldIndex, newBorrowIndex, block.timestamp);
    }

    /**
     * @notice Update current borrow APY
     * @param borrowAPY New borrow APY
     */
    function updateBorrowAPY(uint256 borrowAPY) external onlyPool {
        uint256 oldAPY = currentBorrowAPY;
        currentBorrowAPY = borrowAPY;
        lastMetricsUpdate = block.timestamp;

        emit BorrowAPYUpdated(oldAPY, borrowAPY);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user's total debt including accrued interest
     * @param user User address
     * @return totalDebt Total debt amount
     */
    function balanceOfDebt(
        address user
    ) external view returns (uint256 totalDebt) {
        return _calculateUserTotalDebt(user);
    }

    /**
     * @notice Get user's principal debt (original borrowed amount)
     * @param user User address
     * @return principalDebt Principal debt amount
     */
    function principalDebtOf(
        address user
    ) external view returns (uint256 principalDebt) {
        return userDebts[user].principalDebt;
    }

    /**
     * @notice Get user's accrued interest
     * @param user User address
     * @return accruedInterest Accrued interest amount
     */
    function accruedInterestOf(
        address user
    ) external view returns (uint256 accruedInterest) {
        UserDebt memory userDebt = userDebts[user];
        if (userDebt.principalDebt == 0) return 0;

        // Calculate interest based on index difference
        uint256 indexDelta = borrowIndex - userDebt.borrowIndex;
        uint256 newInterest = (userDebt.principalDebt * indexDelta) / PRECISION;

        return userDebt.accruedInterest + newInterest;
    }

    /**
     * @notice Get comprehensive user debt information
     * @param user User address
     * @return principal Principal debt
     * @return interest Accrued interest
     * @return total Total debt
     * @return lastUpdate Last update timestamp
     */
    function getUserDebtData(
        address user
    )
        external
        view
        returns (
            uint256 principal,
            uint256 interest,
            uint256 total,
            uint256 lastUpdate
        )
    {
        UserDebt memory userDebt = userDebts[user];
        principal = userDebt.principalDebt;
        interest = this.accruedInterestOf(user);
        total = principal + interest;
        lastUpdate = userDebt.lastUpdateTime;
    }

    /**
     * @notice Get current debt metrics
     * @return borrowAPY Current borrow APY
     * @return totalPrincipal Total principal debt
     * @return totalInterest Total interest accrued
     * @return last24h Interest accrued in last 24 hours
     * @return index Current borrow index
     */
    function getCurrentMetrics()
        external
        view
        returns (
            uint256 borrowAPY,
            uint256 totalPrincipal,
            uint256 totalInterest,
            uint256 last24h,
            uint256 index
        )
    {
        return (
            currentBorrowAPY,
            totalPrincipalDebt,
            totalInterestAccrued,
            last24hInterestAccrued,
            borrowIndex
        );
    }

    /**
     * @notice Calculate projected debt after time period
     * @param user User address
     * @param timeSeconds Time period in seconds
     * @return projectedDebt Projected total debt
     */
    function getProjectedDebt(
        address user,
        uint256 timeSeconds
    ) external view returns (uint256 projectedDebt) {
        uint256 currentDebt = _calculateUserTotalDebt(user);
        if (currentDebt == 0 || currentBorrowAPY == 0) return currentDebt;

        // Calculate compound interest
        uint256 ratePerSecond = currentBorrowAPY / (365 days);
        uint256 compoundFactor = PRECISION + (ratePerSecond * timeSeconds);

        projectedDebt = (currentDebt * compoundFactor) / PRECISION;
    }

    /**
     * @notice Get total debt for all users
     * @return totalDebt Total debt including interest
     */
    function getTotalDebt() external view returns (uint256 totalDebt) {
        // Total debt = total supply (which includes interest through index)
        return totalSupply();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _calculateUserTotalDebt(
        address user
    ) internal view returns (uint256 totalDebt) {
        UserDebt memory userDebt = userDebts[user];
        if (userDebt.principalDebt == 0) return 0;

        // Calculate interest based on current index vs user's index
        uint256 indexDelta = borrowIndex - userDebt.borrowIndex;
        uint256 newInterest = (userDebt.principalDebt * indexDelta) / PRECISION;

        totalDebt =
            userDebt.principalDebt +
            userDebt.accruedInterest +
            newInterest;
    }

    function _updateUserDebt(address user) internal {
        if (user == address(0)) return;

        UserDebt storage userDebt = userDebts[user];
        if (userDebt.principalDebt == 0) return;

        // Calculate and add new interest
        uint256 indexDelta = borrowIndex - userDebt.borrowIndex;
        if (indexDelta > 0) {
            uint256 newInterest = (userDebt.principalDebt * indexDelta) /
                PRECISION;
            userDebt.accruedInterest += newInterest;

            emit InterestAccrued(user, newInterest);
        }

        // Update user's tracking
        userDebt.borrowIndex = borrowIndex;
        userDebt.lastUpdateTime = block.timestamp;
        userTotalDebt[user] = userDebt.principalDebt + userDebt.accruedInterest;

        emit UserDebtUpdated(
            user,
            userDebt.principalDebt,
            userTotalDebt[user],
            userDebt.accruedInterest
        );
    }

    function _update24hMetrics(uint256 newInterest) internal {
        // Reset 24h counter if needed
        if (block.timestamp >= lastMetricsUpdate + 24 hours) {
            last24hInterestAccrued = 0;
            lastMetricsUpdate = block.timestamp;
        }

        last24hInterestAccrued += newInterest;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // TRANSFER RESTRICTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Debt tokens are non-transferable
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("DebtToken: Transfer not allowed");
    }

    /**
     * @notice Debt tokens are non-transferable
     */
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("DebtToken: Transfer not allowed");
    }

    /**
     * @notice Debt tokens cannot be approved for transfer
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert("DebtToken: Approval not allowed");
    }

    /**
     * @notice Override _beforeTokenTransfer to update debt on mint/burn
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);

        // Only allow mint (from = 0) and burn (to = 0)
        require(
            from == address(0) || to == address(0),
            "DebtToken: Only mint/burn allowed"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update user debt manually (admin only, for emergency situations)
     * @param user User address
     */
    function forceUpdateUserDebt(address user) external onlyRole(ADMIN_ROLE) {
        _updateUserDebt(user);
    }

    /**
     * @notice Batch update multiple users' debt
     * @param users Array of user addresses
     */
    function batchUpdateUserDebt(
        address[] calldata users
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < users.length; i++) {
            _updateUserDebt(users[i]);
        }
    }

    /**
     * @notice Emergency function to update borrow index directly
     * @param newIndex New borrow index
     */
    function emergencyUpdateBorrowIndex(
        uint256 newIndex
    ) external onlyRole(ADMIN_ROLE) {
        require(newIndex > 0, "DebtToken: Invalid index");

        uint256 oldIndex = borrowIndex;
        borrowIndex = newIndex;
        lastBorrowIndexUpdate = block.timestamp;

        emit BorrowIndexUpdated(oldIndex, newIndex, block.timestamp);
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
}
