// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SafeTransfer
 * @dev Library for safe token transfers with proper error handling
 * @notice Handles tokens that don't return bool on transfer/transferFrom
 */
library SafeTransfer {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    error SafeTransfer__TransferFailed();
    error SafeTransfer__TransferFromFailed();
    error SafeTransfer__ApproveFailed();
    error SafeTransfer__InsufficientBalance();
    error SafeTransfer__InsufficientAllowance();

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes4 private constant TRANSFER_SELECTOR = IERC20.transfer.selector;
    bytes4 private constant TRANSFER_FROM_SELECTOR =
        IERC20.transferFrom.selector;
    bytes4 private constant APPROVE_SELECTOR = IERC20.approve.selector;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // SAFE TRANSFER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Safely transfer tokens to a recipient
     * @param token The token contract
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        if (amount == 0) return;

        // Check balance before transfer
        uint256 balanceBefore = token.balanceOf(address(this));
        if (balanceBefore < amount) {
            revert SafeTransfer__InsufficientBalance();
        }

        bool success = _callOptionalReturn(
            token,
            abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount)
        );

        if (!success) {
            revert SafeTransfer__TransferFailed();
        }

        // Verify the transfer actually happened
        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter != balanceBefore - amount) {
            revert SafeTransfer__TransferFailed();
        }
    }

    /**
     * @notice Safely transfer tokens from one address to another
     * @param token The token contract
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;

        // Check balance and allowance before transfer
        uint256 fromBalance = token.balanceOf(from);
        uint256 allowance = token.allowance(from, address(this));

        if (fromBalance < amount) {
            revert SafeTransfer__InsufficientBalance();
        }

        if (allowance < amount) {
            revert SafeTransfer__InsufficientAllowance();
        }

        uint256 toBalanceBefore = token.balanceOf(to);

        bool success = _callOptionalReturn(
            token,
            abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, amount)
        );

        if (!success) {
            revert SafeTransfer__TransferFromFailed();
        }

        // Verify the transfer actually happened
        uint256 toBalanceAfter = token.balanceOf(to);
        if (toBalanceAfter != toBalanceBefore + amount) {
            revert SafeTransfer__TransferFromFailed();
        }
    }

    /**
     * @notice Safely approve token spending
     * @param token The token contract
     * @param spender The spender address
     * @param amount The amount to approve
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        // Some tokens require setting allowance to 0 first
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance != 0) {
            bool success = _callOptionalReturn(
                token,
                abi.encodeWithSelector(APPROVE_SELECTOR, spender, 0)
            );
            if (!success) {
                revert SafeTransfer__ApproveFailed();
            }
        }

        bool success = _callOptionalReturn(
            token,
            abi.encodeWithSelector(APPROVE_SELECTOR, spender, amount)
        );

        if (!success) {
            revert SafeTransfer__ApproveFailed();
        }

        // Verify the approval actually happened
        uint256 newAllowance = token.allowance(address(this), spender);
        if (newAllowance != amount) {
            revert SafeTransfer__ApproveFailed();
        }
    }

    /**
     * @notice Safely increase token allowance
     * @param token The token contract
     * @param spender The spender address
     * @param addedValue The amount to add to allowance
     */
    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 addedValue
    ) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        uint256 newAllowance = currentAllowance + addedValue;

        bool success = _callOptionalReturn(
            token,
            abi.encodeWithSelector(APPROVE_SELECTOR, spender, newAllowance)
        );

        if (!success) {
            revert SafeTransfer__ApproveFailed();
        }

        // Verify the approval actually happened
        uint256 finalAllowance = token.allowance(address(this), spender);
        if (finalAllowance != newAllowance) {
            revert SafeTransfer__ApproveFailed();
        }
    }

    /**
     * @notice Safely decrease token allowance
     * @param token The token contract
     * @param spender The spender address
     * @param subtractedValue The amount to subtract from allowance
     */
    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 subtractedValue
    ) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);

        if (currentAllowance < subtractedValue) {
            revert SafeTransfer__InsufficientAllowance();
        }

        uint256 newAllowance = currentAllowance - subtractedValue;

        bool success = _callOptionalReturn(
            token,
            abi.encodeWithSelector(APPROVE_SELECTOR, spender, newAllowance)
        );

        if (!success) {
            revert SafeTransfer__ApproveFailed();
        }

        // Verify the approval actually happened
        uint256 finalAllowance = token.allowance(address(this), spender);
        if (finalAllowance != newAllowance) {
            revert SafeTransfer__ApproveFailed();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if token transfer would succeed without executing it
     * @param token The token contract
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount to transfer
     * @return success True if transfer would succeed
     */
    function canTransfer(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal view returns (bool success) {
        if (amount == 0) return true;

        uint256 fromBalance = token.balanceOf(from);
        uint256 allowance = token.allowance(from, address(this));

        return fromBalance >= amount && allowance >= amount;
    }

    /**
     * @notice Get the actual transferable amount (considering balance and allowance)
     * @param token The token contract
     * @param from The sender address
     * @param amount The desired amount
     * @return transferableAmount The actual transferable amount
     */
    function getTransferableAmount(
        IERC20 token,
        address from,
        uint256 amount
    ) internal view returns (uint256 transferableAmount) {
        uint256 balance = token.balanceOf(from);
        uint256 allowance = token.allowance(from, address(this));

        transferableAmount = amount;
        if (transferableAmount > balance) {
            transferableAmount = balance;
        }
        if (transferableAmount > allowance) {
            transferableAmount = allowance;
        }

        return transferableAmount;
    }

    /**
     * @notice Force transfer by approving first (use with caution)
     * @param token The token contract
     * @param from The sender address (must be msg.sender or have approval)
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function forceTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        // First try normal transferFrom
        try token.transferFrom(from, to, amount) returns (bool success) {
            if (success) return;
        } catch {}

        // If that fails, check if we need to handle allowance
        uint256 currentAllowance = token.allowance(from, address(this));
        if (currentAllowance < amount) {
            // This will only work if the calling contract has permission to approve
            safeApprove(token, address(this), amount);
        }

        // Try transfer again
        safeTransferFrom(token, from, to, amount);
    }

    /**
     * @notice Rescue tokens stuck in contract
     * @param token The token contract
     * @param to The recipient address
     * @param amount The amount to rescue (0 = all balance)
     */
    function rescueTokens(IERC20 token, address to, uint256 amount) internal {
        uint256 balance = token.balanceOf(address(this));

        if (amount == 0) {
            amount = balance;
        }

        if (amount > balance) {
            amount = balance;
        }

        if (amount > 0) {
            safeTransfer(token, to, amount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Call function on token contract and handle optional return value
     * @param token The token contract
     * @param data The function call data
     * @return success True if call succeeded
     */
    function _callOptionalReturn(
        IERC20 token,
        bytes memory data
    ) private returns (bool success) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking
        // mechanism, since we're implementing it ourselves.

        bytes memory returndata;
        bool callSuccess;

        // Perform the call
        (callSuccess, returndata) = address(token).call(data);

        if (!callSuccess) {
            return false;
        }

        // Check return data
        if (returndata.length == 0) {
            // No return data means the function succeeded (some tokens don't return bool)
            // But we need to check that the contract actually exists
            return _isContract(address(token));
        } else {
            // Return data exists, decode it as bool
            return abi.decode(returndata, (bool));
        }
    }

    /**
     * @notice Check if address is a contract
     * @param account The address to check
     * @return isContractAddress True if address is a contract
     */
    function _isContract(
        address account
    ) private view returns (bool isContractAddress) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // BATCH OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Batch transfer tokens to multiple recipients
     * @param token The token contract
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to transfer
     */
    function batchTransfer(
        IERC20 token,
        address[] memory recipients,
        uint256[] memory amounts
    ) internal {
        require(
            recipients.length == amounts.length,
            "SafeTransfer: Length mismatch"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                safeTransfer(token, recipients[i], amounts[i]);
            }
        }
    }

    /**
     * @notice Batch transfer tokens from multiple senders
     * @param token The token contract
     * @param senders Array of sender addresses
     * @param recipient The recipient address
     * @param amounts Array of amounts to transfer
     */
    function batchTransferFrom(
        IERC20 token,
        address[] memory senders,
        address recipient,
        uint256[] memory amounts
    ) internal {
        require(
            senders.length == amounts.length,
            "SafeTransfer: Length mismatch"
        );

        for (uint256 i = 0; i < senders.length; i++) {
            if (amounts[i] > 0) {
                safeTransferFrom(token, senders[i], recipient, amounts[i]);
            }
        }
    }

    /**
     * @notice Batch approve multiple spenders
     * @param token The token contract
     * @param spenders Array of spender addresses
     * @param amounts Array of amounts to approve
     */
    function batchApprove(
        IERC20 token,
        address[] memory spenders,
        uint256[] memory amounts
    ) internal {
        require(
            spenders.length == amounts.length,
            "SafeTransfer: Length mismatch"
        );

        for (uint256 i = 0; i < spenders.length; i++) {
            safeApprove(token, spenders[i], amounts[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADVANCED FEATURES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Transfer tokens with callback verification
     * @param token The token contract
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param data Additional data for callback
     */
    function safeTransferWithCallback(
        IERC20 token,
        address to,
        uint256 amount,
        bytes memory data
    ) internal {
        safeTransfer(token, to, amount);

        // If recipient is a contract, call onTokenReceived
        if (_isContract(to)) {
            try
                IERC1363Receiver(to).onTransferReceived(
                    msg.sender,
                    address(this),
                    amount,
                    data
                )
            returns (bytes4 response) {
                if (response != IERC1363Receiver.onTransferReceived.selector) {
                    revert SafeTransfer__TransferFailed();
                }
            } catch {
                // Ignore callback failures for non-IERC1363Receiver contracts
            }
        }
    }

    /**
     * @notice Transfer tokens with deadline check
     * @param token The token contract
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param deadline The deadline timestamp
     */
    function safeTransferWithDeadline(
        IERC20 token,
        address to,
        uint256 amount,
        uint256 deadline
    ) internal {
        require(
            block.timestamp <= deadline,
            "SafeTransfer: Transfer deadline exceeded"
        );
        safeTransfer(token, to, amount);
    }

    /**
     * @notice Transfer tokens with slippage protection
     * @param token The token contract
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param minReceived Minimum amount recipient should receive
     */
    function safeTransferWithSlippage(
        IERC20 token,
        address to,
        uint256 amount,
        uint256 minReceived
    ) internal {
        uint256 balanceBefore = token.balanceOf(to);
        safeTransfer(token, to, amount);
        uint256 balanceAfter = token.balanceOf(to);

        uint256 received = balanceAfter - balanceBefore;
        require(
            received >= minReceived,
            "SafeTransfer: Insufficient received amount"
        );
    }

    /**
     * @notice Conditional transfer based on balance check
     * @param token The token contract
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param minBalance Minimum balance required before transfer
     * @return transferred True if transfer was executed
     */
    function conditionalTransfer(
        IERC20 token,
        address to,
        uint256 amount,
        uint256 minBalance
    ) internal returns (bool transferred) {
        uint256 balance = token.balanceOf(address(this));

        if (balance >= minBalance && balance >= amount) {
            safeTransfer(token, to, amount);
            return true;
        }

        return false;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════
// INTERFACE FOR CALLBACK SUPPORT
// ═══════════════════════════════════════════════════════════════════════════════════

interface IERC1363Receiver {
    function onTransferReceived(
        address operator,
        address from,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);
}
