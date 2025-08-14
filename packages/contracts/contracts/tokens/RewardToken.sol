// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title RewardToken
 * @dev HyperLend governance and reward token (HLR)
 * @notice ERC20 token with governance capabilities and reward distribution
 */
contract RewardToken is
    ERC20,
    ERC20Permit,
    ERC20Votes,
    AccessControl,
    Pausable
{
    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_SUPPLY = 1_000_000_000e18; // 1 billion tokens
    uint256 public constant INITIAL_MINT = 100_000_000e18; // 100 million initial mint

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Reward distribution tracking
    mapping(address => uint256) public rewardBalances;
    mapping(address => uint256) public lastRewardClaim;

    /// @notice Staking functionality
    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public stakingRewards;
    mapping(address => uint256) public stakingTimestamp;

    uint256 public totalStaked;
    uint256 public rewardRate = 1000; // 10% APY (basis points)
    uint256 public stakingDuration = 30 days; // Minimum staking period

    /// @notice Governance parameters
    uint256 public proposalThreshold = 1_000_000e18; // 1M tokens to create proposal
    uint256 public votingDelay = 1 days;
    uint256 public votingPeriod = 7 days;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event RewardDistributed(address indexed user, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 amount);
    event StakingParametersUpdated(uint256 rewardRate, uint256 stakingDuration);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address admin
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(admin != address(0), "RewardToken: Invalid admin");
        require(
            initialSupply <= INITIAL_MINT,
            "RewardToken: Initial supply too high"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _mint(admin, initialSupply);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE TOKEN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint new tokens (only by minters)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "RewardToken: Max supply exceeded"
        );
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from specified account (requires allowance)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // REWARD DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Distribute rewards to multiple users
     * @param users Array of user addresses
     * @param amounts Array of reward amounts
     */
    function distributeRewards(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) {
        require(users.length == amounts.length, "RewardToken: Length mismatch");

        uint256 totalRewards = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalRewards += amounts[i];
        }

        require(
            totalSupply() + totalRewards <= MAX_SUPPLY,
            "RewardToken: Max supply exceeded"
        );

        for (uint256 i = 0; i < users.length; i++) {
            if (amounts[i] > 0) {
                rewardBalances[users[i]] += amounts[i];
                emit RewardDistributed(users[i], amounts[i]);
            }
        }

        _mint(address(this), totalRewards);
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external whenNotPaused {
        uint256 rewards = rewardBalances[msg.sender];
        require(rewards > 0, "RewardToken: No rewards to claim");

        rewardBalances[msg.sender] = 0;
        lastRewardClaim[msg.sender] = block.timestamp;

        _transfer(address(this), msg.sender, rewards);
        emit RewardClaimed(msg.sender, rewards);
    }

    /**
     * @notice Get claimable rewards for a user
     * @param user User address
     * @return claimableRewards Amount of claimable rewards
     */
    function getClaimableRewards(
        address user
    ) external view returns (uint256 claimableRewards) {
        return rewardBalances[user];
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // STAKING FUNCTIONALITY
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Stake tokens to earn additional rewards
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "RewardToken: Invalid stake amount");
        require(
            balanceOf(msg.sender) >= amount,
            "RewardToken: Insufficient balance"
        );

        // Claim existing staking rewards if any
        if (stakedBalances[msg.sender] > 0) {
            _claimStakingRewards(msg.sender);
        }

        stakedBalances[msg.sender] += amount;
        stakingTimestamp[msg.sender] = block.timestamp;
        totalStaked += amount;

        _transfer(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake tokens and claim rewards
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external whenNotPaused {
        require(amount > 0, "RewardToken: Invalid unstake amount");
        require(
            stakedBalances[msg.sender] >= amount,
            "RewardToken: Insufficient staked balance"
        );
        require(
            block.timestamp >= stakingTimestamp[msg.sender] + stakingDuration,
            "RewardToken: Staking period not completed"
        );

        // Calculate and claim staking rewards
        uint256 rewards = _claimStakingRewards(msg.sender);

        stakedBalances[msg.sender] -= amount;
        totalStaked -= amount;

        if (stakedBalances[msg.sender] > 0) {
            stakingTimestamp[msg.sender] = block.timestamp; // Reset staking time for remaining balance
        }

        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount, rewards);
    }

    /**
     * @notice Claim staking rewards without unstaking
     */
    function claimStakingRewards() external whenNotPaused {
        require(
            stakedBalances[msg.sender] > 0,
            "RewardToken: No staked balance"
        );
        _claimStakingRewards(msg.sender);
    }

    /**
     * @notice Calculate pending staking rewards for a user
     * @param user User address
     * @return pendingRewards Amount of pending staking rewards
     */
    function getPendingStakingRewards(
        address user
    ) external view returns (uint256 pendingRewards) {
        if (stakedBalances[user] == 0) return 0;

        uint256 stakingTime = block.timestamp - stakingTimestamp[user];
        uint256 annualReward = (stakedBalances[user] * rewardRate) / 10000; // Convert basis points
        pendingRewards = (annualReward * stakingTime) / 365 days;

        return pendingRewards;
    }

    function _claimStakingRewards(
        address user
    ) internal returns (uint256 rewards) {
        rewards = this.getPendingStakingRewards(user);

        if (rewards > 0) {
            require(
                totalSupply() + rewards <= MAX_SUPPLY,
                "RewardToken: Max supply exceeded"
            );

            stakingRewards[user] += rewards;
            stakingTimestamp[user] = block.timestamp;

            _mint(user, rewards);
            emit RewardClaimed(user, rewards);
        }

        return rewards;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // GOVERNANCE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get voting power of an account
     * @param account Account address
     * @return votingPower Current voting power
     */
    function getVotingPower(
        address account
    ) external view returns (uint256 votingPower) {
        return getVotes(account);
    }

    /**
     * @notice Check if account can create proposals
     * @param account Account address
     * @return canPropose True if account can create proposals
     */
    function canCreateProposal(
        address account
    ) external view returns (bool canPropose) {
        return getVotes(account) >= proposalThreshold;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update staking parameters
     * @param newRewardRate New reward rate in basis points
     * @param newStakingDuration New minimum staking duration
     */
    function updateStakingParameters(
        uint256 newRewardRate,
        uint256 newStakingDuration
    ) external onlyRole(ADMIN_ROLE) {
        require(newRewardRate <= 5000, "RewardToken: Reward rate too high"); // Max 50% APY
        require(
            newStakingDuration >= 1 days,
            "RewardToken: Staking duration too short"
        );
        require(
            newStakingDuration <= 365 days,
            "RewardToken: Staking duration too long"
        );

        rewardRate = newRewardRate;
        stakingDuration = newStakingDuration;

        emit StakingParametersUpdated(newRewardRate, newStakingDuration);
    }

    /**
     * @notice Update governance parameters
     * @param newProposalThreshold New proposal threshold
     * @param newVotingDelay New voting delay
     * @param newVotingPeriod New voting period
     */
    function updateGovernanceParameters(
        uint256 newProposalThreshold,
        uint256 newVotingDelay,
        uint256 newVotingPeriod
    ) external onlyRole(ADMIN_ROLE) {
        require(
            newProposalThreshold <= MAX_SUPPLY / 100,
            "RewardToken: Threshold too high"
        ); // Max 1%
        require(newVotingDelay <= 7 days, "RewardToken: Voting delay too long");
        require(
            newVotingPeriod >= 1 days && newVotingPeriod <= 30 days,
            "RewardToken: Invalid voting period"
        );

        proposalThreshold = newProposalThreshold;
        votingDelay = newVotingDelay;
        votingPeriod = newVotingPeriod;
    }

    /**
     * @notice Emergency withdrawal of stuck tokens
     * @param token Token address (use address(0) for ETH)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "RewardToken: Invalid recipient");

        if (token == address(0)) {
            // Withdraw ETH
            payable(to).transfer(amount);
        } else {
            // Withdraw ERC20 tokens
            require(
                token != address(this),
                "RewardToken: Cannot withdraw own tokens"
            );
            IERC20(token).transfer(to, amount);
        }
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // OVERRIDE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get staking information for a user
     * @param user User address
     * @return stakedAmount Amount of tokens staked
     * @return stakingTime Timestamp when staking started
     * @return pendingRewards Pending staking rewards
     * @return canUnstake Whether user can unstake now
     */
    function getStakingInfo(
        address user
    )
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 stakingTime,
            uint256 pendingRewards,
            bool canUnstake
        )
    {
        stakedAmount = stakedBalances[user];
        stakingTime = stakingTimestamp[user];
        pendingRewards = this.getPendingStakingRewards(user);
        canUnstake = block.timestamp >= stakingTime + stakingDuration;
    }

    /**
     * @notice Get total staking statistics
     * @return totalStakedAmount Total amount of tokens staked
     * @return currentRewardRate Current reward rate in basis points
     * @return minimumStakingDuration Minimum staking duration
     */
    function getStakingStats()
        external
        view
        returns (
            uint256 totalStakedAmount,
            uint256 currentRewardRate,
            uint256 minimumStakingDuration
        )
    {
        return (totalStaked, rewardRate, stakingDuration);
    }

    /**
     * @notice Get governance parameters
     * @return threshold Proposal threshold
     * @return delay Voting delay
     * @return period Voting period
     */
    function getGovernanceParams()
        external
        view
        returns (uint256 threshold, uint256 delay, uint256 period)
    {
        return (proposalThreshold, votingDelay, votingPeriod);
    }
}
