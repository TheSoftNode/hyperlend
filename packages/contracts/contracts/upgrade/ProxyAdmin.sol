// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title HyperLendProxyAdmin
 * @dev Enhanced ProxyAdmin with additional security features and governance
 * @notice Manages upgrades for HyperLend protocol contracts
 */
contract HyperLendProxyAdmin is AccessControl {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice The underlying OpenZeppelin ProxyAdmin
    ProxyAdmin public immutable proxyAdmin;

    /// @notice Upgrade proposals
    struct UpgradeProposal {
        address proxy;
        address newImplementation;
        bytes data;
        uint256 proposedAt;
        uint256 executionTime;
        bool executed;
        bool cancelled;
        string description;
    }

    mapping(uint256 => UpgradeProposal) public upgradeProposals;
    uint256 public proposalCount;

    /// @notice Governance parameters
    uint256 public upgradeDelay = 2 days;
    uint256 public emergencyUpgradeDelay = 6 hours;
    bool public upgradesPaused = false;

    /// @notice Proxy registry
    mapping(address => bool) public managedProxies;
    address[] public proxyList;

    /// @notice Implementation whitelist
    mapping(address => bool) public whitelistedImplementations;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event UpgradeProposed(
        uint256 indexed proposalId,
        address indexed proxy,
        address indexed newImplementation,
        uint256 executionTime,
        string description
    );

    event UpgradeExecuted(
        uint256 indexed proposalId,
        address indexed proxy,
        address indexed newImplementation
    );

    event UpgradeCancelled(uint256 indexed proposalId);

    event EmergencyUpgradeExecuted(
        address indexed proxy,
        address indexed newImplementation,
        address indexed executor
    );

    event UpgradeDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event UpgradesPausedToggled(bool paused);
    event ProxyAdded(address indexed proxy);
    event ProxyRemoved(address indexed proxy);
    event ImplementationWhitelisted(
        address indexed implementation,
        bool whitelisted
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(address admin) {
        require(admin != address(0), "HyperLendProxyAdmin: Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(EMERGENCY_ROLE, admin);

        proxyAdmin = new ProxyAdmin();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UPGRADE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Propose an upgrade for a proxy contract
     * @param proxy The proxy contract address
     * @param newImplementation The new implementation address
     * @param data Optional data for upgrade call
     * @param description Description of the upgrade
     * @return proposalId The ID of the created proposal
     */
    function proposeUpgrade(
        address proxy,
        address newImplementation,
        bytes calldata data,
        string calldata description
    ) external onlyRole(UPGRADER_ROLE) returns (uint256 proposalId) {
        require(!upgradesPaused, "HyperLendProxyAdmin: Upgrades paused");
        require(
            managedProxies[proxy],
            "HyperLendProxyAdmin: Proxy not managed"
        );
        require(
            whitelistedImplementations[newImplementation],
            "HyperLendProxyAdmin: Implementation not whitelisted"
        );

        proposalId = proposalCount++;
        uint256 executionTime = block.timestamp + upgradeDelay;

        upgradeProposals[proposalId] = UpgradeProposal({
            proxy: proxy,
            newImplementation: newImplementation,
            data: data,
            proposedAt: block.timestamp,
            executionTime: executionTime,
            executed: false,
            cancelled: false,
            description: description
        });

        emit UpgradeProposed(
            proposalId,
            proxy,
            newImplementation,
            executionTime,
            description
        );

        return proposalId;
    }

    /**
     * @notice Execute a pending upgrade proposal
     * @param proposalId The proposal ID to execute
     */
    function executeUpgrade(
        uint256 proposalId
    ) external onlyRole(UPGRADER_ROLE) {
        UpgradeProposal storage proposal = upgradeProposals[proposalId];

        require(!proposal.executed, "HyperLendProxyAdmin: Already executed");
        require(!proposal.cancelled, "HyperLendProxyAdmin: Proposal cancelled");
        require(
            block.timestamp >= proposal.executionTime,
            "HyperLendProxyAdmin: Too early to execute"
        );
        require(!upgradesPaused, "HyperLendProxyAdmin: Upgrades paused");

        proposal.executed = true;

        if (proposal.data.length > 0) {
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(proposal.proxy),
                proposal.newImplementation,
                proposal.data
            );
        } else {
            proxyAdmin.upgrade(
                ITransparentUpgradeableProxy(proposal.proxy),
                proposal.newImplementation
            );
        }

        emit UpgradeExecuted(
            proposalId,
            proposal.proxy,
            proposal.newImplementation
        );
    }

    /**
     * @notice Cancel a pending upgrade proposal
     * @param proposalId The proposal ID to cancel
     */
    function cancelUpgrade(uint256 proposalId) external onlyRole(ADMIN_ROLE) {
        UpgradeProposal storage proposal = upgradeProposals[proposalId];

        require(!proposal.executed, "HyperLendProxyAdmin: Already executed");
        require(!proposal.cancelled, "HyperLendProxyAdmin: Already cancelled");

        proposal.cancelled = true;

        emit UpgradeCancelled(proposalId);
    }

    /**
     * @notice Execute emergency upgrade (shorter delay)
     * @param proxy The proxy contract address
     * @param newImplementation The new implementation address
     * @param data Optional data for upgrade call
     */
    function emergencyUpgrade(
        address proxy,
        address newImplementation,
        bytes calldata data
    ) external onlyRole(EMERGENCY_ROLE) {
        require(
            managedProxies[proxy],
            "HyperLendProxyAdmin: Proxy not managed"
        );
        require(
            whitelistedImplementations[newImplementation],
            "HyperLendProxyAdmin: Implementation not whitelisted"
        );

        if (data.length > 0) {
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(proxy),
                newImplementation,
                data
            );
        } else {
            proxyAdmin.upgrade(
                ITransparentUpgradeableProxy(proxy),
                newImplementation
            );
        }

        emit EmergencyUpgradeExecuted(proxy, newImplementation, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // PROXY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a proxy to management
     * @param proxy The proxy contract address
     */
    function addProxy(address proxy) external onlyRole(ADMIN_ROLE) {
        require(proxy != address(0), "HyperLendProxyAdmin: Invalid proxy");
        require(
            !managedProxies[proxy],
            "HyperLendProxyAdmin: Proxy already managed"
        );

        managedProxies[proxy] = true;
        proxyList.push(proxy);

        emit ProxyAdded(proxy);
    }

    /**
     * @notice Remove a proxy from management
     * @param proxy The proxy contract address
     */
    function removeProxy(address proxy) external onlyRole(ADMIN_ROLE) {
        require(
            managedProxies[proxy],
            "HyperLendProxyAdmin: Proxy not managed"
        );

        managedProxies[proxy] = false;

        // Remove from array
        for (uint256 i = 0; i < proxyList.length; i++) {
            if (proxyList[i] == proxy) {
                proxyList[i] = proxyList[proxyList.length - 1];
                proxyList.pop();
                break;
            }
        }

        emit ProxyRemoved(proxy);
    }

    /**
     * @notice Change proxy admin (transfer ownership)
     * @param proxy The proxy contract address
     * @param newAdmin The new admin address
     */
    function changeProxyAdmin(
        address proxy,
        address newAdmin
    ) external onlyRole(ADMIN_ROLE) {
        require(
            managedProxies[proxy],
            "HyperLendProxyAdmin: Proxy not managed"
        );
        require(
            newAdmin != address(0),
            "HyperLendProxyAdmin: Invalid new admin"
        );

        proxyAdmin.changeProxyAdmin(
            ITransparentUpgradeableProxy(proxy),
            newAdmin
        );

        // Remove from management since we no longer control it
        managedProxies[proxy] = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // IMPLEMENTATION WHITELIST
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Whitelist or blacklist an implementation
     * @param implementation The implementation address
     * @param whitelisted Whether to whitelist or blacklist
     */
    function setImplementationWhitelisted(
        address implementation,
        bool whitelisted
    ) external onlyRole(ADMIN_ROLE) {
        require(
            implementation != address(0),
            "HyperLendProxyAdmin: Invalid implementation"
        );

        whitelistedImplementations[implementation] = whitelisted;

        emit ImplementationWhitelisted(implementation, whitelisted);
    }

    /**
     * @notice Batch whitelist implementations
     * @param implementations Array of implementation addresses
     * @param whitelisted Whether to whitelist or blacklist
     */
    function batchSetImplementationWhitelisted(
        address[] calldata implementations,
        bool whitelisted
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < implementations.length; i++) {
            whitelistedImplementations[implementations[i]] = whitelisted;
            emit ImplementationWhitelisted(implementations[i], whitelisted);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // GOVERNANCE SETTINGS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set upgrade delay
     * @param newDelay New delay in seconds
     */
    function setUpgradeDelay(uint256 newDelay) external onlyRole(ADMIN_ROLE) {
        require(newDelay >= 1 hours, "HyperLendProxyAdmin: Delay too short");
        require(newDelay <= 30 days, "HyperLendProxyAdmin: Delay too long");

        uint256 oldDelay = upgradeDelay;
        upgradeDelay = newDelay;

        emit UpgradeDelayUpdated(oldDelay, newDelay);
    }

    /**
     * @notice Set emergency upgrade delay
     * @param newDelay New emergency delay in seconds
     */
    function setEmergencyUpgradeDelay(
        uint256 newDelay
    ) external onlyRole(ADMIN_ROLE) {
        require(
            newDelay >= 1 hours,
            "HyperLendProxyAdmin: Emergency delay too short"
        );
        require(
            newDelay <= upgradeDelay,
            "HyperLendProxyAdmin: Emergency delay too long"
        );

        emergencyUpgradeDelay = newDelay;
    }

    /**
     * @notice Pause or unpause upgrades
     * @param paused Whether upgrades should be paused
     */
    function setUpgradesPaused(bool paused) external onlyRole(ADMIN_ROLE) {
        upgradesPaused = paused;
        emit UpgradesPausedToggled(paused);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get implementation address for a proxy
     * @param proxy The proxy contract address
     * @return implementation The current implementation address
     */
    function getProxyImplementation(
        address proxy
    ) external view returns (address implementation) {
        return
            proxyAdmin.getProxyImplementation(
                ITransparentUpgradeableProxy(proxy)
            );
    }

    /**
     * @notice Get proxy admin for a proxy
     * @param proxy The proxy contract address
     * @return admin The current admin address
     */
    function getProxyAdmin(
        address proxy
    ) external view returns (address admin) {
        return proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(proxy));
    }

    /**
     * @notice Get all managed proxies
     * @return proxies Array of managed proxy addresses
     */
    function getManagedProxies()
        external
        view
        returns (address[] memory proxies)
    {
        return proxyList;
    }

    /**
     * @notice Get upgrade proposal details
     * @param proposalId The proposal ID
     * @return proposal The proposal details
     */
    function getUpgradeProposal(
        uint256 proposalId
    ) external view returns (UpgradeProposal memory proposal) {
        return upgradeProposals[proposalId];
    }

    /**
     * @notice Check if upgrade proposal can be executed
     * @param proposalId The proposal ID
     * @return canExecute Whether the proposal can be executed
     * @return reason Reason if cannot execute
     */
    function canExecuteUpgrade(
        uint256 proposalId
    ) external view returns (bool canExecute, string memory reason) {
        UpgradeProposal memory proposal = upgradeProposals[proposalId];

        if (proposal.executed) {
            return (false, "Already executed");
        }

        if (proposal.cancelled) {
            return (false, "Proposal cancelled");
        }

        if (upgradesPaused) {
            return (false, "Upgrades paused");
        }

        if (block.timestamp < proposal.executionTime) {
            return (false, "Too early to execute");
        }

        return (true, "");
    }

    /**
     * @notice Get pending upgrade proposals
     * @return proposalIds Array of pending proposal IDs
     */
    function getPendingUpgrades()
        external
        view
        returns (uint256[] memory proposalIds)
    {
        uint256 pendingCount = 0;

        // Count pending proposals
        for (uint256 i = 0; i < proposalCount; i++) {
            UpgradeProposal memory proposal = upgradeProposals[i];
            if (
                !proposal.executed &&
                !proposal.cancelled &&
                block.timestamp >= proposal.executionTime
            ) {
                pendingCount++;
            }
        }

        // Collect pending proposal IDs
        proposalIds = new uint256[](pendingCount);
        uint256 index = 0;

        for (uint256 i = 0; i < proposalCount; i++) {
            UpgradeProposal memory proposal = upgradeProposals[i];
            if (
                !proposal.executed &&
                !proposal.cancelled &&
                block.timestamp >= proposal.executionTime
            ) {
                proposalIds[index] = i;
                index++;
            }
        }

        return proposalIds;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EMERGENCY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emergency pause all upgrades
     */
    function emergencyPause() external onlyRole(EMERGENCY_ROLE) {
        upgradesPaused = true;
        emit UpgradesPausedToggled(true);
    }

    /**
     * @notice Emergency resume upgrades
     */
    function emergencyResume() external onlyRole(EMERGENCY_ROLE) {
        upgradesPaused = false;
        emit UpgradesPausedToggled(false);
    }

    /**
     * @notice Cancel all pending proposals (emergency function)
     */
    function emergencyCancelAllPending() external onlyRole(EMERGENCY_ROLE) {
        for (uint256 i = 0; i < proposalCount; i++) {
            UpgradeProposal storage proposal = upgradeProposals[i];
            if (!proposal.executed && !proposal.cancelled) {
                proposal.cancelled = true;
                emit UpgradeCancelled(i);
            }
        }
    }
}
