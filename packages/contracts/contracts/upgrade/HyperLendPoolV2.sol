// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HyperLendPool.sol";

/**
 * @title HyperLendPoolV2
 * @dev Upgraded version of HyperLendPool with additional features
 * @notice Example upgrade contract demonstrating new functionality
 */
contract HyperLendPoolV2 is HyperLendPool {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // NEW STATE VARIABLES (V2)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice New feature: Flash loan functionality
    uint256 public flashLoanFee = 9; // 0.09% fee (9 basis points)
    mapping(address => bool) public flashLoanEnabled;

    /// @notice New feature: Credit delegation
    struct CreditDelegation {
        uint256 allowance;
        uint256 used;
        uint256 expiry;
        bool isActive;
    }
    mapping(address => mapping(address => CreditDelegation))
        public creditDelegations;

    /// @notice New feature: Yield farming rewards
    mapping(address => uint256) public yieldMultipliers; // Basis points (10000 = 1x)
    mapping(address => uint256) public lastYieldUpdate;

    /// @notice New feature: Insurance fund
    uint256 public insuranceFundBalance;
    mapping(address => uint256) public insuranceContributions;

    /// @notice New feature: Governance voting power
    mapping(address => uint256) public votingPower;
    uint256 public totalVotingPower;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NEW EVENTS (V2)
    // ═══════════════════════════════════════════════════════════════════════════════════

    event FlashLoan(
        address indexed borrower,
        address indexed asset,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );

    event CreditDelegated(
        address indexed delegator,
        address indexed delegatee,
        address indexed asset,
        uint256 amount,
        uint256 expiry
    );

    event CreditUsed(
        address indexed delegator,
        address indexed delegatee,
        address indexed asset,
        uint256 amount
    );

    event YieldMultiplierUpdated(address indexed asset, uint256 multiplier);
    event InsuranceFundContribution(
        address indexed contributor,
        uint256 amount
    );
    event VotingPowerUpdated(
        address indexed user,
        uint256 oldPower,
        uint256 newPower
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // MODIFIERS (V2)
    // ═══════════════════════════════════════════════════════════════════════════════════

    modifier flashLoanGuard() {
        require(!_flashLoanActive, "HyperLendPoolV2: Flash loan in progress");
        _flashLoanActive = true;
        _;
        _flashLoanActive = false;
    }

    bool private _flashLoanActive;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INITIALIZER (V2)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize V2 features
     * @dev Called after upgrade to set up new functionality
     */
    function initializeV2() external reinitializer(2) {
        flashLoanFee = 9; // 0.09%

        // Set default yield multipliers to 1x (10000 basis points)
        for (uint256 i = 0; i < marketList.length; i++) {
            yieldMultipliers[marketList[i]] = 10000;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FLASH LOAN FUNCTIONALITY
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute a flash loan
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     * @param params Additional parameters for the flash loan
     */
    function flashLoan(
        address asset,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant whenNotPaused validMarket(asset) flashLoanGuard {
        require(
            flashLoanEnabled[asset],
            "HyperLendPoolV2: Flash loans disabled for asset"
        );
        require(amount > 0, "HyperLendPoolV2: Invalid flash loan amount");

        Market storage market = markets[asset];
        uint256 availableLiquidity = IERC20(asset).balanceOf(address(this));
        require(
            amount <= availableLiquidity,
            "HyperLendPoolV2: Insufficient liquidity"
        );

        uint256 fee = (amount * flashLoanFee) / 10000;
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        // Transfer tokens to borrower
        IERC20(asset).safeTransfer(msg.sender, amount);

        // Call borrower's callback
        IFlashLoanReceiver(msg.sender).executeOperation(
            asset,
            amount,
            fee,
            params
        );

        // Check repayment
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore + fee,
            "HyperLendPoolV2: Flash loan not repaid"
        );

        // Add fee to reserves
        market.reserveFactor += fee;
        insuranceFundBalance += fee / 2; // 50% of fee goes to insurance fund

        emit FlashLoan(msg.sender, asset, amount, fee, block.timestamp);
    }

    /**
     * @notice Enable/disable flash loans for an asset
     * @param asset The asset address
     * @param enabled Whether flash loans should be enabled
     */
    function setFlashLoanEnabled(
        address asset,
        bool enabled
    ) external onlyAdmin {
        flashLoanEnabled[asset] = enabled;
    }

    /**
     * @notice Set flash loan fee
     * @param newFee New fee in basis points
     */
    function setFlashLoanFee(uint256 newFee) external onlyAdmin {
        require(newFee <= 100, "HyperLendPoolV2: Fee too high"); // Max 1%
        flashLoanFee = newFee;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CREDIT DELEGATION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Delegate credit to another user
     * @param delegatee The user to delegate credit to
     * @param asset The asset to delegate
     * @param amount The amount to delegate
     * @param expiry Expiry timestamp for the delegation
     */
    function delegateCredit(
        address delegatee,
        address asset,
        uint256 amount,
        uint256 expiry
    ) external validMarket(asset) {
        require(delegatee != address(0), "HyperLendPoolV2: Invalid delegatee");
        require(
            delegatee != msg.sender,
            "HyperLendPoolV2: Cannot delegate to self"
        );
        require(amount > 0, "HyperLendPoolV2: Invalid delegation amount");
        require(expiry > block.timestamp, "HyperLendPoolV2: Invalid expiry");

        // Check if delegator has sufficient collateral
        (uint256 totalCollateral, ) = _calculateUserPositions(msg.sender);
        uint256 assetPrice = priceOracle.getPrice(asset);
        uint256 delegationValueUSD = amount.mulDiv(assetPrice, PRECISION);

        require(
            totalCollateral >= delegationValueUSD,
            "HyperLendPoolV2: Insufficient collateral"
        );

        creditDelegations[msg.sender][delegatee] = CreditDelegation({
            allowance: amount,
            used: 0,
            expiry: expiry,
            isActive: true
        });

        emit CreditDelegated(msg.sender, delegatee, asset, amount, expiry);
    }

    /**
     * @notice Borrow using delegated credit
     * @param delegator The user who delegated credit
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     */
    function borrowWithDelegatedCredit(
        address delegator,
        address asset,
        uint256 amount
    ) external nonReentrant whenNotPaused validMarket(asset) updateMetrics {
        CreditDelegation storage delegation = creditDelegations[delegator][
            msg.sender
        ];

        require(delegation.isActive, "HyperLendPoolV2: No active delegation");
        require(
            block.timestamp <= delegation.expiry,
            "HyperLendPoolV2: Delegation expired"
        );
        require(
            delegation.used + amount <= delegation.allowance,
            "HyperLendPoolV2: Insufficient delegation"
        );

        Market storage market = markets[asset];
        require(
            market.totalBorrow + amount <= market.borrowCap,
            "HyperLendPoolV2: Borrow cap exceeded"
        );

        // Update delegation
        delegation.used += amount;

        // Update interest before borrow
        _updateMarketInterest(asset);

        // Calculate shares
        uint256 shares = _calculateBorrowShares(asset, amount);

        // Update market state - debt goes to the actual borrower
        market.totalBorrow += amount;
        userAccounts[msg.sender].borrowShares[asset] += shares;

        // Mint debt tokens to borrower
        DebtToken(market.debtToken).mint(msg.sender, shares);

        // Transfer tokens to borrower
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit CreditUsed(delegator, msg.sender, asset, amount);
        emit Borrow(msg.sender, asset, amount, shares);
    }

    /**
     * @notice Revoke credit delegation
     * @param delegatee The delegatee to revoke credit from
     */
    function revokeCreditDelegation(address delegatee) external {
        creditDelegations[msg.sender][delegatee].isActive = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // YIELD FARMING ENHANCEMENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set yield multiplier for an asset
     * @param asset The asset address
     * @param multiplier The yield multiplier in basis points (10000 = 1x)
     */
    function setYieldMultiplier(
        address asset,
        uint256 multiplier
    ) external onlyAdmin {
        require(
            multiplier >= 5000 && multiplier <= 50000,
            "HyperLendPoolV2: Invalid multiplier"
        ); // 0.5x to 5x

        yieldMultipliers[asset] = multiplier;
        lastYieldUpdate[asset] = block.timestamp;

        emit YieldMultiplierUpdated(asset, multiplier);
    }

    /**
     * @notice Calculate enhanced yield for a user
     * @param user The user address
     * @param asset The asset address
     * @return enhancedYield The enhanced yield amount
     */
    function calculateEnhancedYield(
        address user,
        address asset
    ) external view returns (uint256 enhancedYield) {
        uint256 userSupply = userAccounts[user].supplyShares[asset];
        if (userSupply == 0) return 0;

        uint256 multiplier = yieldMultipliers[asset];
        if (multiplier <= 10000) return 0; // No enhancement if multiplier <= 1x

        uint256 baseYield = _calculateUserSupplyYield(user, asset);
        uint256 enhancement = (baseYield * (multiplier - 10000)) / 10000;

        return enhancement;
    }

    function _calculateUserSupplyYield(
        address user,
        address asset
    ) internal view returns (uint256) {
        // Simplified yield calculation
        uint256 userShares = userAccounts[user].supplyShares[asset];
        Market storage market = markets[asset];

        if (userShares == 0 || HLToken(market.hlToken).totalSupply() == 0)
            return 0;

        uint256 userSupply = userShares.mulDiv(
            market.totalSupply,
            HLToken(market.hlToken).totalSupply()
        );
        uint256 utilizationRate = _calculateUtilizationRate(asset);

        (, uint256 supplyAPY) = interestRateModel.calculateRates(
            asset,
            utilizationRate,
            market.totalSupply,
            market.totalBorrow
        );

        return userSupply.mulDiv(supplyAPY, PRECISION) / 365 days; // Daily yield
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INSURANCE FUND
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Contribute to insurance fund
     * @param amount Amount to contribute
     */
    function contributeToInsuranceFund(uint256 amount) external {
        require(amount > 0, "HyperLendPoolV2: Invalid contribution amount");

        // Assume contribution is in the protocol's native token or stablecoin
        // For simplicity, we'll use the first market's asset
        address contributionAsset = marketList[0];

        IERC20(contributionAsset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        insuranceFundBalance += amount;
        insuranceContributions[msg.sender] += amount;

        emit InsuranceFundContribution(msg.sender, amount);
    }

    /**
     * @notice Use insurance fund to cover bad debt
     * @param asset The asset with bad debt
     * @param amount Amount to cover
     */
    function useInsuranceFund(
        address asset,
        uint256 amount
    ) external onlyAdmin {
        require(
            amount <= insuranceFundBalance,
            "HyperLendPoolV2: Insufficient insurance fund"
        );

        insuranceFundBalance -= amount;

        // Logic to cover bad debt would go here
        // For now, just emit an event
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // GOVERNANCE ENHANCEMENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update voting power based on user's participation
     * @param user The user address
     */
    function updateVotingPower(address user) external {
        uint256 oldPower = votingPower[user];

        // Calculate voting power based on TVL contribution and participation
        (uint256 totalCollateral, ) = _calculateUserPositions(user);
        uint256 newPower = totalCollateral / 1000e18; // 1 vote per 1000 USD

        // Bonus for long-term users
        if (userAccounts[user].lastUpdateTimestamp > 0) {
            uint256 participationTime = block.timestamp -
                userAccounts[user].lastUpdateTimestamp;
            if (participationTime > 90 days) {
                newPower = newPower.mulDiv(120, 100); // 20% bonus for 90+ days
            }
        }

        totalVotingPower = totalVotingPower - oldPower + newPower;
        votingPower[user] = newPower;

        emit VotingPowerUpdated(user, oldPower, newPower);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS (V2)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get available flash loan liquidity
     * @param asset The asset address
     * @return availableLiquidity Available liquidity for flash loans
     */
    function getFlashLoanLiquidity(
        address asset
    ) external view returns (uint256 availableLiquidity) {
        return IERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Get credit delegation info
     * @param delegator The delegator address
     * @param delegatee The delegatee address
     * @return delegation Credit delegation details
     */
    function getCreditDelegation(
        address delegator,
        address delegatee
    ) external view returns (CreditDelegation memory delegation) {
        return creditDelegations[delegator][delegatee];
    }

    /**
     * @notice Get protocol version
     * @return version Protocol version string
     */
    function getVersion() external pure returns (string memory version) {
        return "2.0.0";
    }

    /**
     * @notice Get V2 features status
     * @return flashLoanActive Whether flash loans are active
     * @return creditDelegationActive Whether credit delegation is active
     * @return yieldFarmingActive Whether yield farming is active
     * @return insuranceFundActive Whether insurance fund is active
     */
    function getV2FeaturesStatus()
        external
        view
        returns (
            bool flashLoanActive,
            bool creditDelegationActive,
            bool yieldFarmingActive,
            bool insuranceFundActive
        )
    {
        flashLoanActive = flashLoanFee > 0;
        creditDelegationActive = true; // Always active once deployed
        yieldFarmingActive =
            marketList.length > 0 &&
            yieldMultipliers[marketList[0]] > 0;
        insuranceFundActive = insuranceFundBalance > 0;
    }

    /**
     * @notice Get insurance fund info
     * @return balance Current insurance fund balance
     * @return totalContributions Total contributions made
     * @return userContribution User's contribution amount
     */
    function getInsuranceFundInfo(
        address user
    )
        external
        view
        returns (
            uint256 balance,
            uint256 totalContributions,
            uint256 userContribution
        )
    {
        balance = insuranceFundBalance;

        // Calculate total contributions
        // In a real implementation, you'd track this more efficiently
        totalContributions = insuranceFundBalance; // Simplified

        userContribution = insuranceContributions[user];
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════
// INTERFACE FOR FLASH LOAN RECEIVER
// ═══════════════════════════════════════════════════════════════════════════════════

interface IFlashLoanReceiver {
    /**
     * @notice Execute operation after receiving flash loan
     * @param asset The asset borrowed
     * @param amount The amount borrowed
     * @param fee The fee to be paid
     * @param params Additional parameters
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        bytes calldata params
    ) external;
}
