// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IHyperLendPool.sol";
import "../interfaces/IInterestRateModel.sol";
import "../interfaces/ILiquidationEngine.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/IDIAOracleV2.sol";
import "../tokens/HLToken.sol";
import "../tokens/DebtToken.sol";
import "../tokens/SomniaWrapper.sol";

/**
 * @title HyperLendPool
 * @dev Core lending pool contract optimized for Somnia Network with native STT support
 * @notice Supports both native STT and ERC20 token lending/borrowing
 * Features:
 * - Native STT as primary collateral and payment method
 * - Ultra-fast liquidations leveraging Somnia's 1M+ TPS
 * - Real-time interest rate updates
 * - DIA Oracle integration for accurate pricing
 * - Account abstraction support for gasless operations
 */
contract HyperLendPool is
    IHyperLendPool,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_UTILIZATION_RATE = 95e16; // 95%
    uint256 public constant LIQUIDATION_THRESHOLD = 85e16; // 85%
    uint256 public constant LIQUIDATION_BONUS = 5e16; // 5%

    // Somnia native STT address (0x0 for native token)
    address public constant NATIVE_STT = address(0);

    // STT market identifier for DIA Oracle
    string public constant STT_MARKET_KEY = "STT/USD";

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    // Market data - using structs from interface
    mapping(address => Market) public markets;
    mapping(address => UserAccount) public userAccounts;
    mapping(address => bool) public isMarketListed;
    address[] public marketList;

    // User supply and borrow shares (separate from UserAccount struct)
    mapping(address => mapping(address => uint256)) public supplyShares;
    mapping(address => mapping(address => uint256)) public borrowShares;

    IInterestRateModel public interestRateModel;
    ILiquidationEngine public liquidationEngine;
    IPriceOracle public priceOracle;
    IRiskManager public riskManager;

    // Somnia-specific integrations
    IDIAOracleV2 public diaOracle;
    SomniaWrapper public somniaWrapper;

    // Real-time metrics
    uint256 public totalValueLocked;
    uint256 public totalBorrowed;
    uint256 public utilizationRate;
    uint256 public averageSupplyAPY;
    uint256 public averageBorrowAPY;
    uint256 public lastMetricsUpdate;

    // Liquidation tracking
    uint256 public totalLiquidations;
    uint256 public totalLiquidationVolume;
    mapping(address => uint256) public userLiquidationCount;

    // Additional events not in interface
    event MarketAdded(
        address indexed asset,
        address indexed hlToken,
        address indexed debtToken
    );
    event RealTimeMetricsUpdate(
        uint256 totalValueLocked,
        uint256 totalBorrowed,
        uint256 utilizationRate,
        uint256 averageSupplyAPY,
        uint256 averageBorrowAPY,
        uint256 timestamp
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "HyperLend: Not admin");
        _;
    }

    modifier onlyLiquidator() {
        require(
            hasRole(LIQUIDATOR_ROLE, msg.sender),
            "HyperLend: Not liquidator"
        );
        _;
    }

    modifier validMarket(address asset) {
        require(isMarketListed[asset], "HyperLend: Market not listed");
        require(markets[asset].isActive, "HyperLend: Market not active");
        require(!markets[asset].isFrozen, "HyperLend: Market frozen");
        _;
    }

    modifier updateAccount(address user) {
        _updateUserAccount(user);
        _;
    }

    modifier updateMetrics() {
        _;
        _updateRealTimeMetrics();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR & INITIALIZER
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        address _admin,
        address _interestRateModel,
        address _liquidationEngine,
        address _priceOracle,
        address _riskManager,
        address _diaOracle,
        address payable _somniaWrapper
    ) {
        require(_admin != address(0), "HyperLend: Invalid admin");
        require(
            _interestRateModel != address(0),
            "HyperLend: Invalid interest rate model"
        );
        require(
            _liquidationEngine != address(0),
            "HyperLend: Invalid liquidation engine"
        );
        require(_priceOracle != address(0), "HyperLend: Invalid price oracle");
        require(_riskManager != address(0), "HyperLend: Invalid risk manager");
        require(_diaOracle != address(0), "HyperLend: Invalid DIA oracle");
        require(
            _somniaWrapper != address(0),
            "HyperLend: Invalid Somnia wrapper"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        interestRateModel = IInterestRateModel(_interestRateModel);
        liquidationEngine = ILiquidationEngine(_liquidationEngine);
        priceOracle = IPriceOracle(_priceOracle);
        riskManager = IRiskManager(_riskManager);
        diaOracle = IDIAOracleV2(_diaOracle);
        somniaWrapper = SomniaWrapper(_somniaWrapper);

        lastMetricsUpdate = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE LENDING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Supply assets to earn interest
     * @param asset The asset to supply
     * @param amount The amount to supply
     */
    function supply(
        address asset,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(asset)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(amount > 0, "HyperLend: Invalid amount");

        Market storage market = markets[asset];
        require(
            market.totalSupply + amount <= market.supplyCap,
            "HyperLend: Supply cap exceeded"
        );

        // Validate supply operation
        (bool isValid, string memory reason) = riskManager.validateSupply(
            msg.sender,
            asset,
            amount
        );
        require(isValid, reason);

        // Update interest before supply
        _updateMarketInterest(asset);

        // Calculate shares
        uint256 shares = _calculateSupplyShares(asset, amount);

        // Update market state
        market.totalSupply += amount;
        supplyShares[msg.sender][asset] += shares;

        // Transfer tokens
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint hlTokens
        HLToken(market.hlToken).mint(msg.sender, shares);

        emit Supply(msg.sender, asset, amount, shares);
    }

    /**
     * @notice Withdraw supplied assets
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     */
    function withdraw(
        address asset,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(asset)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(amount > 0, "HyperLend: Invalid amount");

        Market storage market = markets[asset];

        // Update interest before withdrawal
        _updateMarketInterest(asset);

        // Calculate shares to burn
        uint256 shares = _calculateWithdrawShares(asset, amount);
        require(
            supplyShares[msg.sender][asset] >= shares,
            "HyperLend: Insufficient balance"
        );

        // Check if withdrawal is allowed (health factor)
        (bool isAllowed, string memory reason) = riskManager.isWithdrawAllowed(
            msg.sender,
            asset,
            amount
        );
        require(isAllowed, reason);

        // Update market state
        market.totalSupply -= amount;
        supplyShares[msg.sender][asset] -= shares;

        // Burn hlTokens
        HLToken(market.hlToken).burn(msg.sender, shares);

        // Transfer tokens
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, asset, amount, shares);
    }

    /**
     * @notice Borrow assets against collateral
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     */
    function borrow(
        address asset,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(asset)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(amount > 0, "HyperLend: Invalid amount");

        Market storage market = markets[asset];
        require(
            market.totalBorrow + amount <= market.borrowCap,
            "HyperLend: Borrow cap exceeded"
        );

        // Update interest before borrow
        _updateMarketInterest(asset);

        // Check if borrow is allowed
        (bool isAllowed, string memory reason) = riskManager.isBorrowAllowed(
            msg.sender,
            asset,
            amount
        );
        require(isAllowed, reason);

        // Calculate shares
        uint256 shares = _calculateBorrowShares(asset, amount);

        // Update market state
        market.totalBorrow += amount;
        borrowShares[msg.sender][asset] += shares;

        // Mint debt tokens
        DebtToken(market.debtToken).mint(msg.sender, shares);

        // Transfer tokens
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, asset, amount, shares);
    }

    /**
     * @notice Repay borrowed assets
     * @param asset The asset to repay
     * @param amount The amount to repay
     */
    function repay(
        address asset,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(asset)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(amount > 0, "HyperLend: Invalid amount");

        Market storage market = markets[asset];

        // Update interest before repay
        _updateMarketInterest(asset);

        // Calculate shares to burn
        uint256 shares = _calculateRepayShares(asset, amount);
        uint256 userShares = borrowShares[msg.sender][asset];

        if (shares > userShares) {
            shares = userShares;
            amount = _sharesToBorrow(asset, shares);
        }

        // Update market state
        market.totalBorrow -= amount;
        borrowShares[msg.sender][asset] -= shares;

        // Burn debt tokens
        DebtToken(market.debtToken).burn(msg.sender, shares);

        // Transfer tokens
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Repay(msg.sender, asset, amount, shares);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NATIVE STT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Supply native STT to earn interest
     * @dev Uses msg.value for STT amount, leveraging Somnia's native token capabilities
     */
    function supplySTT()
        external
        payable
        nonReentrant
        whenNotPaused
        validMarket(NATIVE_STT)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(msg.value > 0, "HyperLend: Invalid STT amount");

        Market storage market = markets[NATIVE_STT];
        require(
            market.totalSupply + msg.value <= market.supplyCap,
            "HyperLend: Supply cap exceeded"
        );

        // Validate supply operation
        (bool isValid, string memory reason) = riskManager.validateSupply(
            msg.sender,
            NATIVE_STT,
            msg.value
        );
        require(isValid, reason);

        // Update interest before supply
        _updateMarketInterest(NATIVE_STT);

        // Calculate shares
        uint256 shares = _calculateSupplyShares(NATIVE_STT, msg.value);

        // Update market state
        market.totalSupply += msg.value;
        supplyShares[msg.sender][NATIVE_STT] += shares;

        // Mint hlTokens
        HLToken(market.hlToken).mint(msg.sender, shares);

        emit Supply(msg.sender, NATIVE_STT, msg.value, shares);
    }

    /**
     * @notice Withdraw supplied STT
     * @param amount The amount of STT to withdraw
     */
    function withdrawSTT(
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(NATIVE_STT)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(amount > 0, "HyperLend: Invalid amount");

        Market storage market = markets[NATIVE_STT];

        // Update interest before withdrawal
        _updateMarketInterest(NATIVE_STT);

        // Calculate shares to burn
        uint256 shares = _calculateWithdrawShares(NATIVE_STT, amount);
        require(
            supplyShares[msg.sender][NATIVE_STT] >= shares,
            "HyperLend: Insufficient balance"
        );

        // Check if withdrawal is allowed (health factor)
        (bool isAllowed, string memory reason) = riskManager.isWithdrawAllowed(
            msg.sender,
            NATIVE_STT,
            amount
        );
        require(isAllowed, reason);

        // Update market state
        market.totalSupply -= amount;
        supplyShares[msg.sender][NATIVE_STT] -= shares;

        // Burn hlTokens
        HLToken(market.hlToken).burn(msg.sender, shares);

        // Transfer STT
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "HyperLend: STT transfer failed");

        emit Withdraw(msg.sender, NATIVE_STT, amount, shares);
    }

    /**
     * @notice Borrow STT against collateral
     * @param amount The amount of STT to borrow
     */
    function borrowSTT(
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(NATIVE_STT)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(amount > 0, "HyperLend: Invalid amount");

        Market storage market = markets[NATIVE_STT];
        require(
            market.totalBorrow + amount <= market.borrowCap,
            "HyperLend: Borrow cap exceeded"
        );

        // Update interest before borrow
        _updateMarketInterest(NATIVE_STT);

        // Check if borrow is allowed
        (bool isAllowed, string memory reason) = riskManager.isBorrowAllowed(
            msg.sender,
            NATIVE_STT,
            amount
        );
        require(isAllowed, reason);

        // Calculate shares
        uint256 shares = _calculateBorrowShares(NATIVE_STT, amount);

        // Update market state
        market.totalBorrow += amount;
        borrowShares[msg.sender][NATIVE_STT] += shares;

        // Mint debt tokens
        DebtToken(market.debtToken).mint(msg.sender, shares);

        // Transfer STT
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "HyperLend: STT transfer failed");

        emit Borrow(msg.sender, NATIVE_STT, amount, shares);
    }

    /**
     * @notice Repay borrowed STT
     * @dev Uses msg.value for repayment amount
     */
    function repaySTT()
        external
        payable
        nonReentrant
        whenNotPaused
        validMarket(NATIVE_STT)
        updateAccount(msg.sender)
        updateMetrics
    {
        require(msg.value > 0, "HyperLend: Invalid amount");

        Market storage market = markets[NATIVE_STT];

        // Update interest before repay
        _updateMarketInterest(NATIVE_STT);

        // Calculate shares to burn
        uint256 shares = _calculateRepayShares(NATIVE_STT, msg.value);
        uint256 userShares = borrowShares[msg.sender][NATIVE_STT];

        uint256 actualAmount = msg.value;

        if (shares > userShares) {
            shares = userShares;
            actualAmount = _sharesToBorrow(NATIVE_STT, shares);

            // Refund excess STT
            uint256 excess = msg.value - actualAmount;
            if (excess > 0) {
                (bool success, ) = msg.sender.call{value: excess}("");
                require(success, "HyperLend: Refund failed");
            }
        }

        // Update market state
        market.totalBorrow -= actualAmount;
        borrowShares[msg.sender][NATIVE_STT] -= shares;

        // Burn debt tokens
        DebtToken(market.debtToken).burn(msg.sender, shares);

        emit Repay(msg.sender, NATIVE_STT, actualAmount, shares);
    }

    /**
     * @notice Fast liquidation with native STT
     * @param user The user to liquidate
     * @param debtAmount The amount of STT debt to repay
     * @param collateralAsset The collateral asset to seize
     */
    function liquidateWithSTT(
        address user,
        uint256 debtAmount,
        address collateralAsset
    )
        external
        payable
        nonReentrant
        whenNotPaused
        updateAccount(user)
        updateMetrics
    {
        require(msg.value >= debtAmount, "HyperLend: Insufficient STT");
        require(user != msg.sender, "HyperLend: Cannot liquidate self");
        require(
            isMarketListed[collateralAsset],
            "HyperLend: Invalid collateral asset"
        );

        // Update interest for both markets
        _updateMarketInterest(NATIVE_STT);
        _updateMarketInterest(collateralAsset);

        // Check if liquidation is allowed
        (bool isAllowed, ) = riskManager.isLiquidationAllowed(user);
        require(isAllowed, "HyperLend: Liquidation not allowed");

        // Execute liquidation through liquidation engine
        (uint256 collateralAmount, uint256 liquidationBonus) = liquidationEngine
            .executeLiquidation(user, NATIVE_STT, debtAmount, collateralAsset);

        // Update user positions
        _updatePositionAfterLiquidation(
            user,
            NATIVE_STT,
            debtAmount,
            collateralAsset,
            collateralAmount
        );

        // Transfer collateral to liquidator
        _transferCollateral(
            user,
            msg.sender,
            collateralAsset,
            collateralAmount + liquidationBonus
        );

        // Refund excess STT
        if (msg.value > debtAmount) {
            (bool success, ) = msg.sender.call{value: msg.value - debtAmount}(
                ""
            );
            require(success, "HyperLend: Refund failed");
        }

        // Update liquidation statistics
        totalLiquidations++;
        totalLiquidationVolume += debtAmount;
        userLiquidationCount[user]++;

        emit Liquidation(
            msg.sender,
            user,
            collateralAsset,
            NATIVE_STT,
            debtAmount,
            collateralAmount
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // LIQUIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidate unhealthy positions
     * @param user The user to liquidate
     * @param debtAsset The debt asset to repay
     * @param debtAmount The amount of debt to repay
     * @param collateralAsset The collateral asset to seize
     */
    function liquidate(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset
    ) external nonReentrant whenNotPaused updateAccount(user) updateMetrics {
        require(user != msg.sender, "HyperLend: Cannot liquidate self");
        require(isMarketListed[debtAsset], "HyperLend: Invalid debt asset");
        require(
            isMarketListed[collateralAsset],
            "HyperLend: Invalid collateral asset"
        );

        // Update interest for both markets
        _updateMarketInterest(debtAsset);
        _updateMarketInterest(collateralAsset);

        // Check if liquidation is allowed
        (bool isAllowed, ) = riskManager.isLiquidationAllowed(user);
        require(isAllowed, "HyperLend: Liquidation not allowed");

        // Execute liquidation through liquidation engine
        (uint256 collateralAmount, uint256 liquidationBonus) = liquidationEngine
            .executeLiquidation(user, debtAsset, debtAmount, collateralAsset);

        // Update user positions
        _updatePositionAfterLiquidation(
            user,
            debtAsset,
            debtAmount,
            collateralAsset,
            collateralAmount
        );

        // Transfer collateral to liquidator
        _transferCollateral(
            user,
            msg.sender,
            collateralAsset,
            collateralAmount + liquidationBonus
        );

        // Update liquidation statistics
        totalLiquidations++;
        totalLiquidationVolume += debtAmount;
        userLiquidationCount[user]++;

        emit Liquidation(
            msg.sender,
            user,
            collateralAsset,
            debtAsset,
            debtAmount,
            collateralAmount
        );
    }

    /**
     * @notice Micro-liquidation for real-time risk management
     * @param user The user to liquidate
     * @param debtAsset The debt asset
     * @param maxDebtAmount Maximum debt to liquidate
     * @param collateralAsset The collateral asset
     */
    function microLiquidate(
        address user,
        address debtAsset,
        uint256 maxDebtAmount,
        address collateralAsset
    )
        external
        onlyLiquidator
        nonReentrant
        whenNotPaused
        updateAccount(user)
        updateMetrics
    {
        // Micro-liquidation logic for sub-second execution
        uint256 optimalLiquidationAmount = liquidationEngine
            .calculateOptimalLiquidation(user, debtAsset, maxDebtAmount);

        if (optimalLiquidationAmount > 0) {
            this.liquidate(
                user,
                debtAsset,
                optimalLiquidationAmount,
                collateralAsset
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REAL-TIME UPDATE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update market interest rates in real-time
     * @param asset The market asset
     */
    function updateMarketInterest(address asset) external validMarket(asset) {
        _updateMarketInterest(asset);
    }

    /**
     * @notice Batch update interest rates for multiple markets
     * @param assets Array of market assets
     */
    function batchUpdateInterest(address[] calldata assets) external {
        for (uint256 i = 0; i < assets.length; i++) {
            if (isMarketListed[assets[i]]) {
                _updateMarketInterest(assets[i]);
            }
        }
    }

    /**
     * @notice Update user account health factor
     * @param user The user address
     */
    function updateUserHealth(address user) external {
        _updateUserAccount(user);
    }

    /**
     * @notice Batch update multiple user accounts
     * @param users Array of user addresses
     */
    function batchUpdateUserHealth(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            _updateUserAccount(users[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _updateMarketInterest(address asset) internal {
        Market storage market = markets[asset];

        if (block.timestamp == market.lastUpdateTimestamp) return;

        uint256 timeDelta = block.timestamp - market.lastUpdateTimestamp;
        uint256 currentUtilizationRate = _calculateUtilizationRate(asset);

        (uint256 borrowAPY, uint256 supplyAPY) = interestRateModel
            .calculateRates(
                asset,
                currentUtilizationRate,
                market.totalSupply,
                market.totalBorrow
            );

        // Update indices
        uint256 borrowRatePerSecond = borrowAPY / 365 days;
        uint256 supplyRatePerSecond = supplyAPY / 365 days;

        market.borrowIndex = market.borrowIndex.mulDiv(
            PRECISION + (borrowRatePerSecond * timeDelta),
            PRECISION
        );

        market.supplyIndex = market.supplyIndex.mulDiv(
            PRECISION + (supplyRatePerSecond * timeDelta),
            PRECISION
        );

        market.lastUpdateTimestamp = block.timestamp;

        // Update hlToken and debtToken rates
        HLToken(market.hlToken).updateExchangeRate(market.supplyIndex);
        HLToken(market.hlToken).updateSupplyAPY(supplyAPY);
        DebtToken(market.debtToken).updateBorrowIndex(market.borrowIndex);
        DebtToken(market.debtToken).updateBorrowAPY(borrowAPY);

        emit InterestRateUpdate(asset, supplyAPY, borrowAPY);
    }

    function _updateUserAccount(address user) internal {
        UserAccount storage account = userAccounts[user];

        (
            uint256 totalCollateral,
            uint256 totalBorrow
        ) = _calculateUserPositions(user);

        account.totalCollateralValue = totalCollateral;
        account.totalBorrowValue = totalBorrow;

        uint256 oldHealthFactor = account.healthFactor;
        account.healthFactor = totalBorrow > 0
            ? totalCollateral.mulDiv(PRECISION, totalBorrow)
            : type(uint256).max;

        account.isLiquidatable = account.healthFactor < LIQUIDATION_THRESHOLD;
        account.lastUpdateTimestamp = block.timestamp;

        if (oldHealthFactor != account.healthFactor) {
            emit HealthFactorUpdate(
                user,
                oldHealthFactor,
                account.healthFactor
            );
        }
    }

    function _updateRealTimeMetrics() internal {
        uint256 currentTime = block.timestamp;

        // Update only if enough time has passed (every block)
        if (currentTime <= lastMetricsUpdate) return;

        uint256 newTVL = 0;
        uint256 newTotalBorrowed = 0;
        uint256 weightedSupplyAPY = 0;
        uint256 weightedBorrowAPY = 0;

        for (uint256 i = 0; i < marketList.length; i++) {
            address asset = marketList[i];
            Market storage market = markets[asset];

            uint256 assetPrice = priceOracle.getPrice(asset);
            uint256 supplyValue = market.totalSupply.mulDiv(
                assetPrice,
                PRECISION
            );
            uint256 borrowValue = market.totalBorrow.mulDiv(
                assetPrice,
                PRECISION
            );

            newTVL += supplyValue;
            newTotalBorrowed += borrowValue;

            uint256 utilization = _calculateUtilizationRate(asset);
            (uint256 borrowAPY, uint256 supplyAPY) = interestRateModel
                .calculateRates(
                    asset,
                    utilization,
                    market.totalSupply,
                    market.totalBorrow
                );

            if (newTVL > 0) {
                weightedSupplyAPY += supplyAPY.mulDiv(supplyValue, newTVL);
            }
            if (newTotalBorrowed > 0) {
                weightedBorrowAPY += borrowAPY.mulDiv(
                    borrowValue,
                    newTotalBorrowed
                );
            }
        }

        totalValueLocked = newTVL;
        totalBorrowed = newTotalBorrowed;
        utilizationRate = newTVL > 0
            ? newTotalBorrowed.mulDiv(PRECISION, newTVL)
            : 0;
        averageSupplyAPY = weightedSupplyAPY;
        averageBorrowAPY = weightedBorrowAPY;
        lastMetricsUpdate = currentTime;

        emit RealTimeMetricsUpdate(
            totalValueLocked,
            totalBorrowed,
            utilizationRate,
            averageSupplyAPY,
            averageBorrowAPY,
            currentTime
        );
    }

    function _calculateUtilizationRate(
        address asset
    ) internal view returns (uint256) {
        Market storage market = markets[asset];
        if (market.totalSupply == 0) return 0;
        return market.totalBorrow.mulDiv(PRECISION, market.totalSupply);
    }

    function _calculateSupplyShares(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        Market storage market = markets[asset];
        uint256 totalShares = HLToken(market.hlToken).totalSupply();

        if (totalShares == 0) {
            return amount;
        }

        return amount.mulDiv(totalShares, market.totalSupply);
    }

    function _calculateWithdrawShares(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        Market storage market = markets[asset];
        uint256 totalShares = HLToken(market.hlToken).totalSupply();

        return amount.mulDiv(totalShares, market.totalSupply);
    }

    function _calculateBorrowShares(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        Market storage market = markets[asset];
        uint256 totalShares = DebtToken(market.debtToken).totalSupply();

        if (totalShares == 0) {
            return amount;
        }

        return amount.mulDiv(totalShares, market.totalBorrow);
    }

    function _calculateRepayShares(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        Market storage market = markets[asset];
        uint256 totalShares = DebtToken(market.debtToken).totalSupply();

        return amount.mulDiv(totalShares, market.totalBorrow);
    }

    function _sharesToBorrow(
        address asset,
        uint256 shares
    ) internal view returns (uint256) {
        Market storage market = markets[asset];
        uint256 totalShares = DebtToken(market.debtToken).totalSupply();

        if (totalShares == 0) return 0;
        return shares.mulDiv(market.totalBorrow, totalShares);
    }

    function _calculateUserPositions(
        address user
    ) internal view returns (uint256 totalCollateral, uint256 totalBorrow) {
        for (uint256 i = 0; i < marketList.length; i++) {
            address asset = marketList[i];
            Market storage market = markets[asset];

            uint256 userSupplyShares = supplyShares[user][asset];
            uint256 userBorrowShares = borrowShares[user][asset];

            if (userSupplyShares > 0) {
                uint256 supplyAmount = userSupplyShares.mulDiv(
                    market.totalSupply,
                    HLToken(market.hlToken).totalSupply()
                );
                uint256 assetPrice = priceOracle.getPrice(asset);
                totalCollateral += supplyAmount.mulDiv(assetPrice, PRECISION);
            }

            if (userBorrowShares > 0) {
                uint256 borrowAmount = userBorrowShares.mulDiv(
                    market.totalBorrow,
                    DebtToken(market.debtToken).totalSupply()
                );
                uint256 assetPrice = priceOracle.getPrice(asset);
                totalBorrow += borrowAmount.mulDiv(assetPrice, PRECISION);
            }
        }
    }

    function _updatePositionAfterLiquidation(
        address user,
        address debtAsset,
        uint256 debtAmount,
        address collateralAsset,
        uint256 collateralAmount
    ) internal {
        Market storage debtMarket = markets[debtAsset];
        Market storage collateralMarket = markets[collateralAsset];

        // Reduce debt
        uint256 debtShares = _calculateRepayShares(debtAsset, debtAmount);
        borrowShares[user][debtAsset] -= debtShares;
        debtMarket.totalBorrow -= debtAmount;

        // Reduce collateral
        uint256 collateralShares = _calculateWithdrawShares(
            collateralAsset,
            collateralAmount
        );
        supplyShares[user][collateralAsset] -= collateralShares;
        collateralMarket.totalSupply -= collateralAmount;
    }

    function _transferCollateral(
        address from,
        address to,
        address asset,
        uint256 amount
    ) internal {
        Market storage market = markets[asset];

        // Transfer hlTokens from liquidated user to liquidator
        HLToken(market.hlToken).transferFrom(from, to, amount);
    }

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
        )
    {
        UserAccount storage account = userAccounts[user];
        return (
            account.totalCollateralValue,
            account.totalBorrowValue,
            account.healthFactor,
            account.isLiquidatable
        );
    }

    function getMarketData(
        address asset
    )
        external
        view
        returns (
            uint256 totalSupply,
            uint256 totalBorrow,
            uint256 currentUtilizationRate,
            uint256 supplyAPY,
            uint256 borrowAPY
        )
    {
        Market storage market = markets[asset];
        uint256 utilization = _calculateUtilizationRate(asset);
        (uint256 borrowAPY_, uint256 supplyAPY_) = interestRateModel
            .calculateRates(
                asset,
                utilization,
                market.totalSupply,
                market.totalBorrow
            );

        return (
            market.totalSupply,
            market.totalBorrow,
            utilization,
            supplyAPY_,
            borrowAPY_
        );
    }

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
        )
    {
        return (
            totalValueLocked,
            totalBorrowed,
            utilizationRate,
            averageSupplyAPY,
            averageBorrowAPY,
            lastMetricsUpdate
        );
    }

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
    ) external onlyAdmin {
        require(!isMarketListed[asset], "HyperLend: Market already listed");

        markets[asset] = Market({
            asset: asset,
            hlToken: hlToken,
            debtToken: debtToken,
            totalSupply: 0,
            totalBorrow: 0,
            borrowIndex: PRECISION,
            supplyIndex: PRECISION,
            lastUpdateTimestamp: block.timestamp,
            isActive: true,
            isFrozen: false,
            reserveFactor: 0,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            borrowCap: borrowCap,
            supplyCap: supplyCap
        });

        isMarketListed[asset] = true;
        marketList.push(asset);

        emit MarketAdded(asset, hlToken, debtToken);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setInterestRateModel(
        address _interestRateModel
    ) external onlyAdmin {
        interestRateModel = IInterestRateModel(_interestRateModel);
    }

    function setLiquidationEngine(
        address _liquidationEngine
    ) external onlyAdmin {
        liquidationEngine = ILiquidationEngine(_liquidationEngine);
    }

    function setPriceOracle(address _priceOracle) external onlyAdmin {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function setRiskManager(address _riskManager) external onlyAdmin {
        riskManager = IRiskManager(_riskManager);
    }

    function setDIAOracle(address _diaOracle) external onlyAdmin {
        diaOracle = IDIAOracleV2(_diaOracle);
    }

    function setSomniaWrapper(
        address payable _somniaWrapper
    ) external onlyAdmin {
        somniaWrapper = SomniaWrapper(_somniaWrapper);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NATIVE STT SUPPORT
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive function to accept native STT transfers
     * @dev Required for native STT operations
     */
    receive() external payable {
        // Accept STT transfers for protocol operations
        // This enables native STT deposits and liquidations
    }

    /**
     * @notice Fallback function for native STT operations
     */
    fallback() external payable {
        revert("HyperLend: Function not found");
    }

    /**
     * @notice Get native STT balance of the contract
     */
    function getSTTBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Emergency STT withdrawal (admin only)
     * @param amount Amount of STT to withdraw
     */
    function emergencyWithdrawSTT(uint256 amount) external onlyAdmin {
        require(
            amount <= address(this).balance,
            "HyperLend: Insufficient balance"
        );
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "HyperLend: Transfer failed");
    }
}
