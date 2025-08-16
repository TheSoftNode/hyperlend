// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @dev Mock ERC20 token for testing purposes
 * @notice Includes additional features for testing scenarios
 */
contract MockERC20 is ERC20, Ownable {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    uint8 private _decimals;

    // Testing features
    bool public transfersEnabled = true;
    bool public mintingEnabled = true;
    bool public burningEnabled = true;

    // Fee simulation
    uint256 public transferFee = 0; // Basis points (100 = 1%)
    address public feeRecipient;

    // Blacklist functionality for testing
    mapping(address => bool) public blacklisted;

    // Transfer delay for testing time-sensitive operations
    mapping(address => uint256) public lastTransferTime;
    uint256 public transferDelay = 0;

    // Maximum transfer amount for testing limits
    uint256 public maxTransferAmount = type(uint256).max;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event TransfersToggled(bool enabled);
    event MintingToggled(bool enabled);
    event BurningToggled(bool enabled);
    event TransferFeeUpdated(uint256 fee, address recipient);
    event AddressBlacklisted(address indexed account, bool blacklisted);
    event TransferDelayUpdated(uint256 delay);
    event MaxTransferAmountUpdated(uint256 amount);
    event ForcedTransfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable() {
        _decimals = decimals_;
        feeRecipient = msg.sender;

        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // BASIC TOKEN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to an address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(mintingEnabled, "MockERC20: Minting disabled");
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        require(burningEnabled, "MockERC20: Burning disabled");
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from specified account (requires allowance)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external {
        require(burningEnabled, "MockERC20: Burning disabled");
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // TESTING UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set decimals (for testing different decimal configurations)
     * @param newDecimals New number of decimals
     */
    function setDecimals(uint8 newDecimals) external onlyOwner {
        _decimals = newDecimals;
    }

    /**
     * @notice Toggle transfers on/off
     * @param enabled Whether transfers should be enabled
     */
    function setTransfersEnabled(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
        emit TransfersToggled(enabled);
    }

    /**
     * @notice Toggle minting on/off
     * @param enabled Whether minting should be enabled
     */
    function setMintingEnabled(bool enabled) external onlyOwner {
        mintingEnabled = enabled;
        emit MintingToggled(enabled);
    }

    /**
     * @notice Toggle burning on/off
     * @param enabled Whether burning should be enabled
     */
    function setBurningEnabled(bool enabled) external onlyOwner {
        burningEnabled = enabled;
        emit BurningToggled(enabled);
    }

    /**
     * @notice Set transfer fee and recipient
     * @param fee Fee in basis points (100 = 1%)
     * @param recipient Address to receive fees
     */
    function setTransferFee(uint256 fee, address recipient) external onlyOwner {
        require(fee <= 1000, "MockERC20: Fee too high"); // Max 10%
        require(recipient != address(0), "MockERC20: Invalid fee recipient");

        transferFee = fee;
        feeRecipient = recipient;
        emit TransferFeeUpdated(fee, recipient);
    }

    /**
     * @notice Blacklist or whitelist an address
     * @param account Address to blacklist/whitelist
     * @param isBlacklisted Whether the address should be blacklisted
     */
    function setBlacklisted(
        address account,
        bool isBlacklisted
    ) external onlyOwner {
        blacklisted[account] = isBlacklisted;
        emit AddressBlacklisted(account, isBlacklisted);
    }

    /**
     * @notice Set transfer delay for testing time-sensitive operations
     * @param delay Delay in seconds between transfers
     */
    function setTransferDelay(uint256 delay) external onlyOwner {
        require(delay <= 1 hours, "MockERC20: Delay too long");
        transferDelay = delay;
        emit TransferDelayUpdated(delay);
    }

    /**
     * @notice Set maximum transfer amount
     * @param amount Maximum amount that can be transferred in one transaction
     */
    function setMaxTransferAmount(uint256 amount) external onlyOwner {
        maxTransferAmount = amount;
        emit MaxTransferAmountUpdated(amount);
    }

    /**
     * @notice Force transfer tokens (bypasses all restrictions)
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyOwner {
        _transfer(from, to, amount);
        emit ForcedTransfer(from, to, amount);
    }

    /**
     * @notice Airdrop tokens to multiple addresses
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send
     */
    function airdrop(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(
            recipients.length == amounts.length,
            "MockERC20: Length mismatch"
        );
        require(mintingEnabled, "MockERC20: Minting disabled");

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                _mint(recipients[i], amounts[i]);
            }
        }
    }

    /**
     * @notice Mint tokens to multiple addresses
     * @param recipients Array of recipient addresses
     * @param amount Amount to mint to each recipient
     */
    function batchMint(
        address[] calldata recipients,
        uint256 amount
    ) external onlyOwner {
        require(mintingEnabled, "MockERC20: Minting disabled");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }

    /**
     * @notice Set balance of an address directly (for testing)
     * @param account Address to set balance for
     * @param newBalance New balance amount
     */
    function setBalance(
        address account,
        uint256 newBalance
    ) external onlyOwner {
        uint256 currentBalance = balanceOf(account);

        if (newBalance > currentBalance) {
            _mint(account, newBalance - currentBalance);
        } else if (newBalance < currentBalance) {
            _burn(account, currentBalance - newBalance);
        }
    }

    /**
     * @notice Simulate a revert on transfer (for testing error handling)
     * @param shouldRevert Whether transfers should revert
     */
    function setShouldRevert(bool shouldRevert) external onlyOwner {
        if (shouldRevert) {
            transfersEnabled = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // OVERRIDE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _validateTransfer(msg.sender, to, amount);

        if (transferFee > 0) {
            return _transferWithFee(msg.sender, to, amount);
        }

        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _validateTransfer(from, to, amount);

        if (transferFee > 0) {
            _spendAllowance(from, msg.sender, amount);
            return _transferWithFee(from, to, amount);
        }

        return super.transferFrom(from, to, amount);
    }

    function _validateTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(transfersEnabled, "MockERC20: Transfers disabled");
        require(!blacklisted[from], "MockERC20: Sender blacklisted");
        require(!blacklisted[to], "MockERC20: Recipient blacklisted");
        require(
            amount <= maxTransferAmount,
            "MockERC20: Amount exceeds maximum"
        );

        if (transferDelay > 0) {
            require(
                block.timestamp >= lastTransferTime[from] + transferDelay,
                "MockERC20: Transfer delay not met"
            );
        }

        lastTransferTime[from] = block.timestamp;
    }

    function _transferWithFee(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 feeAmount = (amount * transferFee) / 10000;
        uint256 transferAmount = amount - feeAmount;

        if (feeAmount > 0) {
            _transfer(from, feeRecipient, feeAmount);
        }

        _transfer(from, to, transferAmount);
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS FOR TESTING
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get contract configuration for testing verification
     */
    function getConfig()
        external
        view
        returns (
            bool _transfersEnabled,
            bool _mintingEnabled,
            bool _burningEnabled,
            uint256 _transferFee,
            address _feeRecipient,
            uint256 _transferDelay,
            uint256 _maxTransferAmount
        )
    {
        return (
            transfersEnabled,
            mintingEnabled,
            burningEnabled,
            transferFee,
            feeRecipient,
            transferDelay,
            maxTransferAmount
        );
    }

    /**
     * @notice Check if address can transfer (not blacklisted, transfers enabled, etc.)
     * @param from Address to check
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return canTransferResult Whether the transfer would succeed
     * @return reason Reason if transfer would fail
     */
    function canTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool canTransferResult, string memory reason) {
        if (!transfersEnabled) {
            return (false, "Transfers disabled");
        }

        if (blacklisted[from]) {
            return (false, "Sender blacklisted");
        }

        if (blacklisted[to]) {
            return (false, "Recipient blacklisted");
        }

        if (amount > maxTransferAmount) {
            return (false, "Amount exceeds maximum");
        }

        if (
            transferDelay > 0 &&
            block.timestamp < lastTransferTime[from] + transferDelay
        ) {
            return (false, "Transfer delay not met");
        }

        if (balanceOf(from) < amount) {
            return (false, "Insufficient balance");
        }

        return (true, "");
    }

    /**
     * @notice Calculate transfer fee for a given amount
     * @param amount Transfer amount
     * @return feeAmount Fee that would be charged
     * @return netAmount Amount that would be received after fee
     */
    function calculateTransferFee(
        uint256 amount
    ) external view returns (uint256 feeAmount, uint256 netAmount) {
        feeAmount = (amount * transferFee) / 10000;
        netAmount = amount - feeAmount;
    }

    /**
     * @notice Reset all testing parameters to default
     */
    function resetToDefaults() external onlyOwner {
        transfersEnabled = true;
        mintingEnabled = true;
        burningEnabled = true;
        transferFee = 0;
        feeRecipient = owner();
        transferDelay = 0;
        maxTransferAmount = type(uint256).max;
    }
}
