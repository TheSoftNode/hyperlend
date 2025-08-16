// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title SomniaWrapper
 * @dev Wrapper contract for handling native STT token interactions
 * Somnia uses native STT (no contract address), this wrapper facilitates DeFi integrations
 */
contract SomniaWrapper is IERC20, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    string public constant name = "Wrapped STT";
    string public constant symbol = "WSTT";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Events for Somnia network optimizations
    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event FastTransfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    // Somnia-specific: Ultra-fast operations counter and gas optimization
    uint256 public operationCount;
    mapping(address => uint256) public lastOperationBlock;

    // Account abstraction compatibility
    mapping(address => bool) public isAuthorizedOperator;

    // Batch operations for Somnia's high TPS
    event BatchOperation(uint256 indexed batchId, uint256 operationCount);
    uint256 public nextBatchId = 1;

    modifier onlyValidAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0");
        _;
    }

    modifier rateLimit() {
        // Somnia allows sub-second finality, but we add basic rate limiting for security
        require(
            block.number > lastOperationBlock[msg.sender] ||
                block.number - lastOperationBlock[msg.sender] < 100, // ~2 seconds on Somnia
            "Rate limit exceeded"
        );
        lastOperationBlock[msg.sender] = block.number;
        _;
    }

    constructor() Ownable() {
        // Initialize with owner
    }

    /**
     * @dev Deposit native STT to get WSTT tokens
     * Optimized for Somnia's high TPS environment
     */
    function deposit()
        external
        payable
        whenNotPaused
        onlyValidAmount(msg.value)
        rateLimit
    {
        _depositInternal(msg.sender, msg.value);
    }

    function _depositInternal(address account, uint256 amount) internal {
        _mint(account, amount);
        operationCount++;
        emit Deposit(account, amount);
    }

    /**
     * @dev Withdraw native STT by burning WSTT tokens
     * Ultra-fast withdrawal for Somnia's sub-second finality
     */
    function withdraw(
        uint256 amount
    ) external nonReentrant whenNotPaused onlyValidAmount(amount) rateLimit {
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        operationCount++;

        // Transfer native STT
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "STT transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Fast transfer optimized for Somnia's speed
     * Includes additional event for real-time tracking
     */
    function fastTransfer(address to, uint256 amount) external returns (bool) {
        bool success = transfer(to, amount);
        if (success) {
            emit FastTransfer(msg.sender, to, amount);
        }
        return success;
    }

    // Standard ERC20 functions
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override whenNotPaused returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override whenNotPaused returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );

        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);

        return true;
    }

    // Internal functions
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        require(
            _balances[account] >= amount,
            "ERC20: burn amount exceeds balance"
        );

        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            _balances[from] >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Emergency functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Fallback to accept STT
    receive() external payable {
        require(msg.value > 0, "Amount must be greater than 0");
        require(!paused(), "Contract is paused");

        _depositInternal(msg.sender, msg.value);
    }

    /**
     * @dev Batch deposit for multiple users (Somnia optimization)
     * Leverages Somnia's high TPS for efficient batch operations
     */
    function batchDeposit(
        address[] calldata recipients
    ) external payable whenNotPaused onlyValidAmount(msg.value) {
        require(recipients.length > 0, "No recipients");

        uint256 amountPerRecipient = msg.value / recipients.length;
        require(amountPerRecipient > 0, "Amount too small for batch");

        uint256 batchId = nextBatchId++;

        for (uint256 i = 0; i < recipients.length; i++) {
            _depositInternal(recipients[i], amountPerRecipient);
        }

        emit BatchOperation(batchId, recipients.length);
    }

    /**
     * @dev Batch withdraw for gas efficiency on Somnia
     */
    function batchWithdraw(
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused {
        require(amounts.length > 0, "No amounts");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(_balances[msg.sender] >= totalAmount, "Insufficient balance");

        _burn(msg.sender, totalAmount);
        operationCount += amounts.length;

        // Single STT transfer for efficiency
        (bool success, ) = payable(msg.sender).call{value: totalAmount}("");
        require(success, "STT transfer failed");

        uint256 batchId = nextBatchId++;
        emit BatchOperation(batchId, amounts.length);
        emit Withdrawal(msg.sender, totalAmount);
    }

    // View functions for Somnia optimizations
    function getOperationCount() external view returns (uint256) {
        return operationCount;
    }

    function getLastOperationBlock(
        address account
    ) external view returns (uint256) {
        return lastOperationBlock[account];
    }

    /**
     * @dev Account abstraction support for Somnia
     */
    function setAuthorizedOperator(
        address operator,
        bool authorized
    ) external onlyOwner {
        isAuthorizedOperator[operator] = authorized;
    }

    /**
     * @dev Gas-optimized transfer for account abstraction
     */
    function operatorTransfer(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(isAuthorizedOperator[msg.sender], "Unauthorized operator");
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Get wrapper statistics for Somnia analytics
     */
    function getWrapperStats()
        external
        view
        returns (uint256 totalWrapped, uint256 operations, uint256 nextBatch)
    {
        return (_totalSupply, operationCount, nextBatchId);
    }
}
