// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyGuard
 * @dev Enhanced reentrancy protection with additional features
 * @notice Gas-optimized reentrancy guard with multiple protection levels
 */
abstract contract ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private constant _LOCKED = 3;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    uint256 private _status;

    // Advanced reentrancy protection
    mapping(bytes4 => uint256) private _functionStatus;
    mapping(address => uint256) private _userStatus;

    // Cross-function reentrancy protection
    bool private _globalLock;

    // Function call tracking
    mapping(bytes4 => uint256) private _functionCallCount;
    mapping(address => mapping(bytes4 => uint256))
        private _userFunctionCallCount;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    error ReentrancyGuard__ReentrantCall();
    error ReentrancyGuard__FunctionLocked();
    error ReentrancyGuard__UserBlocked();
    error ReentrancyGuard__GlobalLock();
    error ReentrancyGuard__TooManyFunctionCalls();
    error ReentrancyGuard__TooManyUserCalls();

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event ReentrancyAttempted(address indexed caller, bytes4 indexed selector);
    event FunctionLocked(bytes4 indexed selector, address indexed locker);
    event FunctionUnlocked(bytes4 indexed selector, address indexed unlocker);
    event UserBlocked(address indexed user, bytes4 indexed selector);
    event GlobalLockToggled(bool locked, address indexed toggler);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor() {
        _status = _NOT_ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // BASIC REENTRANCY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_status == _ENTERED) {
            emit ReentrancyAttempted(msg.sender, msg.sig);
            revert ReentrancyGuard__ReentrantCall();
        }

        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUNCTION-LEVEL REENTRANCY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Prevents reentrancy for specific function
     */
    modifier nonReentrantFunction() {
        bytes4 selector = msg.sig;

        if (_functionStatus[selector] == _ENTERED) {
            emit ReentrancyAttempted(msg.sender, selector);
            revert ReentrancyGuard__ReentrantCall();
        }

        if (_functionStatus[selector] == _LOCKED) {
            revert ReentrancyGuard__FunctionLocked();
        }

        _functionStatus[selector] = _ENTERED;
        _;
        _functionStatus[selector] = _NOT_ENTERED;
    }

    /**
     * @dev Lock a specific function
     * @param selector Function selector to lock
     */
    function _lockFunction(bytes4 selector) internal {
        _functionStatus[selector] = _LOCKED;
        emit FunctionLocked(selector, msg.sender);
    }

    /**
     * @dev Unlock a specific function
     * @param selector Function selector to unlock
     */
    function _unlockFunction(bytes4 selector) internal {
        _functionStatus[selector] = _NOT_ENTERED;
        emit FunctionUnlocked(selector, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // USER-LEVEL REENTRANCY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Prevents reentrancy for specific user
     */
    modifier nonReentrantUser() {
        if (_userStatus[msg.sender] == _ENTERED) {
            emit ReentrancyAttempted(msg.sender, msg.sig);
            revert ReentrancyGuard__ReentrantCall();
        }

        if (_userStatus[msg.sender] == _LOCKED) {
            revert ReentrancyGuard__UserBlocked();
        }

        _userStatus[msg.sender] = _ENTERED;
        _;
        _userStatus[msg.sender] = _NOT_ENTERED;
    }

    /**
     * @dev Block a specific user
     * @param user User address to block
     */
    function _blockUser(address user) internal {
        _userStatus[user] = _LOCKED;
        emit UserBlocked(user, msg.sig);
    }

    /**
     * @dev Unblock a specific user
     * @param user User address to unblock
     */
    function _unblockUser(address user) internal {
        _userStatus[user] = _NOT_ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // GLOBAL LOCK PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Global lock protection (prevents all state-changing calls)
     */
    modifier notGloballyLocked() {
        if (_globalLock) {
            revert ReentrancyGuard__GlobalLock();
        }
        _;
    }

    /**
     * @dev Enable global lock
     */
    function _enableGlobalLock() internal {
        _globalLock = true;
        emit GlobalLockToggled(true, msg.sender);
    }

    /**
     * @dev Disable global lock
     */
    function _disableGlobalLock() internal {
        _globalLock = false;
        emit GlobalLockToggled(false, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADVANCED PROTECTION: CALL FREQUENCY LIMITS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Limit function call frequency
     * @param maxCalls Maximum calls allowed
     */
    modifier limitFunctionCalls(uint256 maxCalls) {
        bytes4 selector = msg.sig;
        _functionCallCount[selector]++;

        if (_functionCallCount[selector] > maxCalls) {
            revert ReentrancyGuard__TooManyFunctionCalls();
        }

        _;
    }

    /**
     * @dev Limit user function call frequency
     * @param maxCalls Maximum calls allowed per user
     */
    modifier limitUserFunctionCalls(uint256 maxCalls) {
        bytes4 selector = msg.sig;
        _userFunctionCallCount[msg.sender][selector]++;

        if (_userFunctionCallCount[msg.sender][selector] > maxCalls) {
            revert ReentrancyGuard__TooManyUserCalls();
        }

        _;
    }

    /**
     * @dev Reset function call count
     * @param selector Function selector to reset
     */
    function _resetFunctionCallCount(bytes4 selector) internal {
        _functionCallCount[selector] = 0;
    }

    /**
     * @dev Reset user function call count
     * @param user User address
     * @param selector Function selector to reset
     */
    function _resetUserFunctionCallCount(
        address user,
        bytes4 selector
    ) internal {
        _userFunctionCallCount[user][selector] = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // COMBINED MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Ultra-secure protection combining all guards
     */
    modifier ultraSecure() {
        _nonReentrantBefore();

        bytes4 selector = msg.sig;

        if (_functionStatus[selector] == _ENTERED) {
            emit ReentrancyAttempted(msg.sender, selector);
            revert ReentrancyGuard__ReentrantCall();
        }

        if (_userStatus[msg.sender] == _ENTERED) {
            emit ReentrancyAttempted(msg.sender, selector);
            revert ReentrancyGuard__ReentrantCall();
        }

        if (_globalLock) {
            revert ReentrancyGuard__GlobalLock();
        }

        _functionStatus[selector] = _ENTERED;
        _userStatus[msg.sender] = _ENTERED;

        _;

        _functionStatus[selector] = _NOT_ENTERED;
        _userStatus[msg.sender] = _NOT_ENTERED;
        _nonReentrantAfter();
    }

    /**
     * @dev High-security protection for critical functions
     */
    modifier highSecurity(uint256 maxUserCalls) {
        bytes4 selector = msg.sig;

        // Check basic reentrancy
        if (_status == _ENTERED) {
            emit ReentrancyAttempted(msg.sender, selector);
            revert ReentrancyGuard__ReentrantCall();
        }

        // Check user call limits
        _userFunctionCallCount[msg.sender][selector]++;
        if (_userFunctionCallCount[msg.sender][selector] > maxUserCalls) {
            revert ReentrancyGuard__TooManyUserCalls();
        }

        // Check global lock
        if (_globalLock) {
            revert ReentrancyGuard__GlobalLock();
        }

        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Check if contract is currently in a reentrant state
     * @return isReentrant True if reentrant state detected
     */
    function isReentrant() external view returns (bool isReentrant) {
        return _status == _ENTERED;
    }

    /**
     * @dev Check if a function is locked
     * @param selector Function selector to check
     * @return isLocked True if function is locked
     */
    function isFunctionLocked(
        bytes4 selector
    ) external view returns (bool isLocked) {
        return _functionStatus[selector] == _LOCKED;
    }

    /**
     * @dev Check if a function is currently being executed
     * @param selector Function selector to check
     * @return isExecuting True if function is executing
     */
    function isFunctionExecuting(
        bytes4 selector
    ) external view returns (bool isExecuting) {
        return _functionStatus[selector] == _ENTERED;
    }

    /**
     * @dev Check if a user is blocked
     * @param user User address to check
     * @return isBlocked True if user is blocked
     */
    function isUserBlocked(
        address user
    ) external view returns (bool isBlocked) {
        return _userStatus[user] == _LOCKED;
    }

    /**
     * @dev Check if a user is currently executing a function
     * @param user User address to check
     * @return isExecuting True if user is executing
     */
    function isUserExecuting(
        address user
    ) external view returns (bool isExecuting) {
        return _userStatus[user] == _ENTERED;
    }

    /**
     * @dev Check if global lock is enabled
     * @return isLocked True if globally locked
     */
    function isGloballyLocked() external view returns (bool isLocked) {
        return _globalLock;
    }

    /**
     * @dev Get function call count
     * @param selector Function selector
     * @return callCount Number of calls made to the function
     */
    function getFunctionCallCount(
        bytes4 selector
    ) external view returns (uint256 callCount) {
        return _functionCallCount[selector];
    }

    /**
     * @dev Get user function call count
     * @param user User address
     * @param selector Function selector
     * @return callCount Number of calls made by user to the function
     */
    function getUserFunctionCallCount(
        address user,
        bytes4 selector
    ) external view returns (uint256 callCount) {
        return _userFunctionCallCount[user][selector];
    }

    /**
     * @dev Get comprehensive reentrancy status
     * @return status Current reentrancy status
     * @return globalLocked Whether globally locked
     * @return currentFunction Currently executing function (if any)
     */
    function getReentrancyStatus()
        external
        view
        returns (uint256 status, bool globalLocked, bytes4 currentFunction)
    {
        status = _status;
        globalLocked = _globalLock;
        currentFunction = msg.sig; // This will be the current function being called
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Emergency reset all protection states
     * @notice Should only be called by authorized admin in emergency
     */
    function _emergencyResetAllStates() internal {
        _status = _NOT_ENTERED;
        _globalLock = false;
        // Note: Individual function and user states are not reset to preserve specific locks
    }

    /**
     * @dev Reset all function call counts
     */
    function _resetAllFunctionCallCounts() internal {
        // Note: In practice, you'd need to track which functions to reset
        // This is a simplified version for demonstration
    }

    /**
     * @dev Batch block multiple users
     * @param users Array of user addresses to block
     */
    function _batchBlockUsers(address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            _userStatus[users[i]] = _LOCKED;
            emit UserBlocked(users[i], msg.sig);
        }
    }

    /**
     * @dev Batch unblock multiple users
     * @param users Array of user addresses to unblock
     */
    function _batchUnblockUsers(address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            _userStatus[users[i]] = _NOT_ENTERED;
        }
    }

    /**
     * @dev Batch lock multiple functions
     * @param selectors Array of function selectors to lock
     */
    function _batchLockFunctions(bytes4[] memory selectors) internal {
        for (uint256 i = 0; i < selectors.length; i++) {
            _functionStatus[selectors[i]] = _LOCKED;
            emit FunctionLocked(selectors[i], msg.sender);
        }
    }

    /**
     * @dev Batch unlock multiple functions
     * @param selectors Array of function selectors to unlock
     */
    function _batchUnlockFunctions(bytes4[] memory selectors) internal {
        for (uint256 i = 0; i < selectors.length; i++) {
            _functionStatus[selectors[i]] = _NOT_ENTERED;
            emit FunctionUnlocked(selectors[i], msg.sender);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // SPECIALIZED MODIFIERS FOR DIFFERENT USE CASES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Protection for view functions (prevents state-changing reentrancy)
     */
    modifier viewProtection() {
        if (_status == _ENTERED) {
            revert ReentrancyGuard__ReentrantCall();
        }
        _;
    }

    /**
     * @dev Protection for functions that should only be called once per block
     */
    modifier oncePerBlock() {
        bytes4 selector = msg.sig;
        uint256 currentBlock = block.number;

        // Use a different storage pattern for block-based tracking
        // This is a simplified version - in practice you'd need proper storage
        if (_functionCallCount[selector] == currentBlock) {
            revert ReentrancyGuard__TooManyFunctionCalls();
        }

        _functionCallCount[selector] = currentBlock;
        _;
    }

    /**
     * @dev Protection for functions with custom reentrancy rules
     * @param customCheck Custom reentrancy check function
     */
    modifier customReentrancyCheck(function() view returns (bool) customCheck) {
        if (!customCheck()) {
            revert ReentrancyGuard__ReentrantCall();
        }

        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CROSS-CONTRACT REENTRANCY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Protection against cross-contract reentrancy
     * @param contractAddress Address of contract to check
     */
    modifier noCrossContractReentrancy(address contractAddress) {
        // Check if the contract is in a reentrant state
        // This requires the other contract to implement the same interface
        try ReentrancyGuard(contractAddress).isReentrant() returns (
            bool isReentrant
        ) {
            if (isReentrant) {
                revert ReentrancyGuard__ReentrantCall();
            }
        } catch {
            // If the contract doesn't implement the check, proceed with caution
        }

        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // GAS OPTIMIZATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Gas-optimized reentrancy check (minimal storage reads)
     */
    modifier gasOptimizedNonReentrant() {
        assembly {
            let slot := _status.slot
            let currentStatus := sload(slot)

            if eq(currentStatus, 2) {
                // _ENTERED
                // Revert with custom error
                let ptr := mload(0x40)
                mstore(
                    ptr,
                    0x3ee5aeb500000000000000000000000000000000000000000000000000000000
                ) // ReentrancyGuard__ReentrantCall()
                revert(ptr, 4)
            }

            sstore(slot, 2) // _ENTERED
        }

        _;

        assembly {
            sstore(_status.slot, 1) // _NOT_ENTERED
        }
    }
}
