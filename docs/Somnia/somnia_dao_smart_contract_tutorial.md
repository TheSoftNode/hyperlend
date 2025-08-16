# Build a Simple DAO Smart Contract on Somnia Network

## Overview
This comprehensive tutorial teaches you how to build, deploy, and interact with a Decentralized Autonomous Organization (DAO) smart contract on the Somnia Network. DAOs enable decentralized governance where community members can propose, vote, and execute decisions collectively without centralized authority.

## What is a DAO?
A **Decentralized Autonomous Organization (DAO)** is a blockchain-based organization that operates through smart contracts, enabling:
- **Collective Decision Making**: Members vote on proposals
- **Transparent Governance**: All decisions are recorded on-chain
- **Automated Execution**: Smart contracts execute approved proposals
- **Democratic Participation**: Voting power based on stake or contribution

### Real-World Use Case: Gaming DAOs
DAOs are particularly powerful in gaming environments:

#### In-Game Treasury Management
- Players deposit earnings into a shared DAO treasury
- Community votes on fund allocation for tournaments, events, or rewards
- Transparent management of collective resources

#### Player-Driven Governance
- Gamers vote on new features (maps, characters, weapons)
- Community has direct influence on game evolution
- Democratic decision-making for game updates

#### Community Rewards System
- DAO allocates funds to reward top players or teams
- Merit-based distribution through community voting
- Enhanced engagement through collective ownership

This approach ensures game development aligns with player interests, creating more engaging and community-driven experiences.

## Prerequisites
- Basic Solidity programming knowledge
- MetaMask wallet with Somnia Network configured
- Development environment (Hardhat or Foundry)
- STT tokens for deployment and testing

## DAO Contract Architecture

### Core Features
Our DAO contract enables users to:
1. **Deposit funds** to gain proportional voting power
2. **Create proposals** for community consideration
3. **Vote on proposals** with weighted voting based on stake
4. **Execute approved proposals** automatically

### Data Structures

#### Proposal Struct
```solidity
struct Proposal {
    string description;      // Proposal details and purpose
    uint256 deadline;        // Voting deadline timestamp
    uint256 yesVotes;        // Total votes in favor
    uint256 noVotes;         // Total votes against
    bool executed;           // Execution status
    address proposer;        // Address that created proposal
}
```

#### Key Mappings
```solidity
// Store all DAO proposals
mapping(uint256 => Proposal) public proposals;

// Track voting power per address
mapping(address => uint256) public votingPower;

// Prevent double voting: proposalId => voter => hasVoted
mapping(uint256 => mapping(address => bool)) public hasVoted;
```

#### State Variables
```solidity
uint256 public totalProposals;              // Counter for proposals
uint256 public votingDuration = 10 minutes; // Default voting period
address public owner;                        // Contract owner
```

## Complete DAO Smart Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract DAO {
    // Proposal structure
    struct Proposal {
        string description;
        uint256 deadline;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        address proposer;
    }

    // State variables
    address public owner;
    uint256 public totalProposals;
    uint256 public votingDuration = 10 minutes;

    // Mappings
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public votingPower;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint256 deadline
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        bool passed
    );
    
    event FundsDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 newVotingPower
    );

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier hasVotingPower() {
        require(votingPower[msg.sender] > 0, "No voting power");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId < totalProposals, "Proposal does not exist");
        _;
    }

    modifier votingActive(uint256 proposalId) {
        require(
            block.timestamp < proposals[proposalId].deadline,
            "Voting has ended"
        );
        _;
    }

    modifier votingEnded(uint256 proposalId) {
        require(
            block.timestamp >= proposals[proposalId].deadline,
            "Voting still active"
        );
        _;
    }

    modifier notExecuted(uint256 proposalId) {
        require(!proposals[proposalId].executed, "Proposal already executed");
        _;
    }

    modifier hasNotVoted(uint256 proposalId) {
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        _;
    }

    // Constructor
    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Allows users to deposit STT to gain voting power
     * Voting power is proportional to the amount deposited
     */
    function deposit() external payable {
        require(msg.value >= 0.001 ether, "Minimum deposit is 0.001 STT");
        
        votingPower[msg.sender] += msg.value;
        
        emit FundsDeposited(msg.sender, msg.value, votingPower[msg.sender]);
    }

    /**
     * @dev Create a new proposal for the DAO to vote on
     * @param description Details of the proposal
     */
    function createProposal(string calldata description) 
        external 
        hasVotingPower 
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        
        proposals[totalProposals] = Proposal({
            description: description,
            deadline: block.timestamp + votingDuration,
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            proposer: msg.sender
        });

        emit ProposalCreated(
            totalProposals,
            msg.sender,
            description,
            block.timestamp + votingDuration
        );

        totalProposals++;
    }

    /**
     * @dev Vote on a specific proposal
     * @param proposalId ID of the proposal to vote on
     * @param support true for yes, false for no
     */
    function vote(uint256 proposalId, bool support)
        external
        proposalExists(proposalId)
        votingActive(proposalId)
        hasNotVoted(proposalId)
        hasVotingPower
    {
        Proposal storage proposal = proposals[proposalId];
        uint256 voterPower = votingPower[msg.sender];

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            proposal.yesVotes += voterPower;
        } else {
            proposal.noVotes += voterPower;
        }

        emit VoteCast(proposalId, msg.sender, support, voterPower);
    }

    /**
     * @dev Execute a proposal if it has passed
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId)
        external
        proposalExists(proposalId)
        votingEnded(proposalId)
        notExecuted(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        
        bool passed = proposal.yesVotes > proposal.noVotes;
        proposal.executed = true;

        if (passed) {
            // Example execution: send reward to proposer
            // In a real DAO, this would contain actual execution logic
            payable(proposal.proposer).transfer(0.001 ether);
        }

        emit ProposalExecuted(proposalId, passed);
    }

    /**
     * @dev Get proposal details
     * @param proposalId ID of the proposal
     * @return All proposal details
     */
    function getProposal(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (
            string memory description,
            uint256 deadline,
            uint256 yesVotes,
            uint256 noVotes,
            bool executed,
            address proposer
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.description,
            proposal.deadline,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.executed,
            proposal.proposer
        );
    }

    /**
     * @dev Check if a user has voted on a proposal
     * @param proposalId ID of the proposal
     * @param voter Address of the voter
     * @return Whether the voter has voted
     */
    function hasUserVoted(uint256 proposalId, address voter)
        external
        view
        returns (bool)
    {
        return hasVoted[proposalId][voter];
    }

    /**
     * @dev Get voting power of an address
     * @param user Address to check
     * @return Voting power amount
     */
    function getVotingPower(address user) external view returns (uint256) {
        return votingPower[user];
    }

    /**
     * @dev Get contract balance
     * @return Contract's STT balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Check if proposal has passed (for informational purposes)
     * @param proposalId ID of the proposal
     * @return Whether proposal has more yes votes than no votes
     */
    function hasProposalPassed(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (bool)
    {
        Proposal storage proposal = proposals[proposalId];
        return proposal.yesVotes > proposal.noVotes;
    }

    /**
     * @dev Emergency withdrawal function (owner only)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner).transfer(amount);
    }

    /**
     * @dev Update voting duration (owner only)
     * @param newDuration New voting duration in seconds
     */
    function updateVotingDuration(uint256 newDuration) external onlyOwner {
        require(newDuration > 0, "Duration must be positive");
        votingDuration = newDuration;
    }
}
```

## Function Analysis

### Core Functions

#### `deposit()` - Gain Voting Power
```solidity
function deposit() external payable {
    require(msg.value >= 0.001 ether, "Minimum deposit is 0.001 STT");
    votingPower[msg.sender] += msg.value;
    emit FundsDeposited(msg.sender, msg.value, votingPower[msg.sender]);
}
```
- **Purpose**: Users deposit STT to gain proportional voting power
- **Requirements**: Minimum 0.001 STT deposit
- **Effect**: Increases user's voting power by deposit amount

#### `createProposal()` - Submit New Proposals
```solidity
function createProposal(string calldata description) external hasVotingPower {
    require(bytes(description).length > 0, "Description cannot be empty");
    
    proposals[totalProposals] = Proposal({
        description: description,
        deadline: block.timestamp + votingDuration,
        yesVotes: 0,
        noVotes: 0,
        executed: false,
        proposer: msg.sender
    });
    
    emit ProposalCreated(totalProposals, msg.sender, description, block.timestamp + votingDuration);
    totalProposals++;
}
```
- **Purpose**: Create new proposals for community voting
- **Requirements**: Must have voting power, non-empty description
- **Effect**: Adds proposal to mapping, sets voting deadline

#### `vote()` - Cast Votes
```solidity
function vote(uint256 proposalId, bool support) external 
    proposalExists(proposalId)
    votingActive(proposalId)
    hasNotVoted(proposalId)
    hasVotingPower
{
    Proposal storage proposal = proposals[proposalId];
    uint256 voterPower = votingPower[msg.sender];

    hasVoted[proposalId][msg.sender] = true;

    if (support) {
        proposal.yesVotes += voterPower;
    } else {
        proposal.noVotes += voterPower;
    }

    emit VoteCast(proposalId, msg.sender, support, voterPower);
}
```
- **Purpose**: Cast weighted votes on proposals
- **Requirements**: Proposal exists, voting active, hasn't voted before, has voting power
- **Effect**: Adds voting power to yes/no votes, prevents double voting

#### `executeProposal()` - Execute Approved Proposals
```solidity
function executeProposal(uint256 proposalId) external
    proposalExists(proposalId)
    votingEnded(proposalId)
    notExecuted(proposalId)
{
    Proposal storage proposal = proposals[proposalId];
    
    bool passed = proposal.yesVotes > proposal.noVotes;
    proposal.executed = true;

    if (passed) {
        payable(proposal.proposer).transfer(0.001 ether);
    }

    emit ProposalExecuted(proposalId, passed);
}
```
- **Purpose**: Execute proposals that have passed voting
- **Requirements**: Proposal exists, voting ended, not executed
- **Effect**: Marks as executed, executes logic if passed

## Deployment Guide

### 1. Environment Setup
Follow the [Hardhat](./deploy-and-verify-a-smart-contract-on-somnia-using-hardhat) or [Foundry](./deploy-a-smart-contract-on-somnia-testnet-using-foundry) setup guides.

### 2. Hardhat Deployment Script
Create `ignition/modules/deploy.js`:
```javascript
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const dao = buildModule("DAO", (m) => {
  const contract = m.contract("DAO");
  return { contract };
});

module.exports = dao;
```

### 3. Network Configuration
Update `hardhat.config.js`:
```javascript
const config = {
  solidity: "0.8.28",
  networks: {
    somnia: {
      url: "https://dream-rpc.somnia.network",
      accounts: ["YOUR_PRIVATE_KEY"],
    },
  },
};
```

### 4. Deploy Contract
```bash
npx hardhat ignition deploy ./ignition/modules/deploy.js --network somnia
```

## Interaction Examples

### 1. Deposit Funds (JavaScript/Hardhat)
```javascript
// Deposit 0.001 STT to gain voting power
await dao.deposit({ value: ethers.parseEther("0.001") });

// Check voting power
const votingPower = await dao.getVotingPower(userAddress);
console.log("Voting power:", ethers.formatEther(votingPower), "STT");
```

### 2. Create Proposal
```javascript
// Create a new proposal
await dao.createProposal("Fund development of new gaming feature");

// Get total proposals
const totalProposals = await dao.totalProposals();
console.log("Total proposals:", totalProposals.toString());
```

### 3. Vote on Proposal
```javascript
// Vote YES on proposal 0
await dao.vote(0, true);

// Vote NO on proposal 1
await dao.vote(1, false);

// Check if user has voted
const hasVoted = await dao.hasUserVoted(0, userAddress);
console.log("Has voted:", hasVoted);
```

### 4. Execute Proposal
```javascript
// Check if proposal passed
const hasPassed = await dao.hasProposalPassed(0);
console.log("Proposal passed:", hasPassed);

// Execute if voting period ended
await dao.executeProposal(0);
```

### 5. Query Proposal Details
```javascript
// Get complete proposal information
const proposal = await dao.getProposal(0);
console.log({
  description: proposal.description,
  deadline: new Date(proposal.deadline * 1000),
  yesVotes: ethers.formatEther(proposal.yesVotes),
  noVotes: ethers.formatEther(proposal.noVotes),
  executed: proposal.executed,
  proposer: proposal.proposer
});
```

## Comprehensive Testing Suite

### Basic Test Setup (`test/DAO.test.js`)
```javascript
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DAO Contract", function () {
  let dao;
  let owner, addr1, addr2, addr3;
  const MINIMUM_DEPOSIT = ethers.parseEther("0.001");

  beforeEach(async function () {
    const DAO = await ethers.getContractFactory("DAO");
    dao = await DAO.deploy();
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
  });

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await dao.owner()).to.equal(owner.address);
    });

    it("Should initialize with zero proposals", async function () {
      expect(await dao.totalProposals()).to.equal(0);
    });

    it("Should set default voting duration", async function () {
      expect(await dao.votingDuration()).to.equal(600); // 10 minutes
    });
  });

  describe("Deposits", function () {
    it("Should allow deposits and update voting power", async function () {
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
      expect(await dao.getVotingPower(addr1.address)).to.equal(MINIMUM_DEPOSIT);
    });

    it("Should reject deposits below minimum", async function () {
      await expect(
        dao.connect(addr1).deposit({ value: ethers.parseEther("0.0005") })
      ).to.be.revertedWith("Minimum deposit is 0.001 STT");
    });

    it("Should emit FundsDeposited event", async function () {
      await expect(dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT }))
        .to.emit(dao, "FundsDeposited")
        .withArgs(addr1.address, MINIMUM_DEPOSIT, MINIMUM_DEPOSIT);
    });

    it("Should accumulate voting power from multiple deposits", async function () {
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
      expect(await dao.getVotingPower(addr1.address)).to.equal(MINIMUM_DEPOSIT * 2n);
    });
  });

  describe("Proposal Creation", function () {
    beforeEach(async function () {
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
    });

    it("Should allow proposal creation with voting power", async function () {
      await dao.connect(addr1).createProposal("Test Proposal");
      const proposal = await dao.getProposal(0);
      expect(proposal.description).to.equal("Test Proposal");
      expect(proposal.proposer).to.equal(addr1.address);
    });

    it("Should reject proposal creation without voting power", async function () {
      await expect(
        dao.connect(addr2).createProposal("Test Proposal")
      ).to.be.revertedWith("No voting power");
    });

    it("Should reject empty proposal descriptions", async function () {
      await expect(
        dao.connect(addr1).createProposal("")
      ).to.be.revertedWith("Description cannot be empty");
    });

    it("Should emit ProposalCreated event", async function () {
      await expect(dao.connect(addr1).createProposal("Test Proposal"))
        .to.emit(dao, "ProposalCreated");
    });

    it("Should increment total proposals", async function () {
      await dao.connect(addr1).createProposal("Proposal 1");
      await dao.connect(addr1).createProposal("Proposal 2");
      expect(await dao.totalProposals()).to.equal(2);
    });
  });

  describe("Voting", function () {
    beforeEach(async function () {
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
      await dao.connect(addr2).deposit({ value: MINIMUM_DEPOSIT * 2n });
      await dao.connect(addr1).createProposal("Test Proposal");
    });

    it("Should allow voting with proper conditions", async function () {
      await dao.connect(addr1).vote(0, true);
      const proposal = await dao.getProposal(0);
      expect(proposal.yesVotes).to.equal(MINIMUM_DEPOSIT);
    });

    it("Should weight votes by voting power", async function () {
      await dao.connect(addr2).vote(0, true);
      const proposal = await dao.getProposal(0);
      expect(proposal.yesVotes).to.equal(MINIMUM_DEPOSIT * 2n);
    });

    it("Should prevent double voting", async function () {
      await dao.connect(addr1).vote(0, true);
      await expect(
        dao.connect(addr1).vote(0, false)
      ).to.be.revertedWith("Already voted");
    });

    it("Should reject voting without power", async function () {
      await expect(
        dao.connect(addr3).vote(0, true)
      ).to.be.revertedWith("No voting power");
    });

    it("Should emit VoteCast event", async function () {
      await expect(dao.connect(addr1).vote(0, true))
        .to.emit(dao, "VoteCast")
        .withArgs(0, addr1.address, true, MINIMUM_DEPOSIT);
    });

    it("Should handle both yes and no votes", async function () {
      await dao.connect(addr1).vote(0, true);
      await dao.connect(addr2).vote(0, false);
      
      const proposal = await dao.getProposal(0);
      expect(proposal.yesVotes).to.equal(MINIMUM_DEPOSIT);
      expect(proposal.noVotes).to.equal(MINIMUM_DEPOSIT * 2n);
    });
  });

  describe("Proposal Execution", function () {
    beforeEach(async function () {
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
      await dao.connect(addr2).deposit({ value: MINIMUM_DEPOSIT });
      await dao.connect(addr1).createProposal("Test Proposal");
    });

    it("Should execute passing proposals", async function () {
      await dao.connect(addr1).vote(0, true);
      await dao.connect(addr2).vote(0, true);
      
      // Fast forward time past voting deadline
      await ethers.provider.send("evm_increaseTime", [601]); // 10 minutes + 1 second
      await ethers.provider.send("evm_mine");

      await expect(dao.executeProposal(0))
        .to.emit(dao, "ProposalExecuted")
        .withArgs(0, true);
    });

    it("Should not execute failing proposals", async function () {
      await dao.connect(addr1).vote(0, false);
      await dao.connect(addr2).vote(0, false);
      
      await ethers.provider.send("evm_increaseTime", [601]);
      await ethers.provider.send("evm_mine");

      await expect(dao.executeProposal(0))
        .to.emit(dao, "ProposalExecuted")
        .withArgs(0, false);
    });

    it("Should reject execution before deadline", async function () {
      await dao.connect(addr1).vote(0, true);
      await expect(
        dao.executeProposal(0)
      ).to.be.revertedWith("Voting still active");
    });

    it("Should reject double execution", async function () {
      await dao.connect(addr1).vote(0, true);
      
      await ethers.provider.send("evm_increaseTime", [601]);
      await ethers.provider.send("evm_mine");

      await dao.executeProposal(0);
      await expect(
        dao.executeProposal(0)
      ).to.be.revertedWith("Proposal already executed");
    });
  });

  describe("Administrative Functions", function () {
    it("Should allow owner to update voting duration", async function () {
      await dao.updateVotingDuration(1800); // 30 minutes
      expect(await dao.votingDuration()).to.equal(1800);
    });

    it("Should reject non-owner voting duration updates", async function () {
      await expect(
        dao.connect(addr1).updateVotingDuration(1800)
      ).to.be.revertedWith("Only owner can call this function");
    });

    it("Should allow owner emergency withdrawal", async function () {
      await dao.connect(addr1).deposit({ value: MINIMUM_DEPOSIT });
      const initialBalance = await ethers.provider.getBalance(owner.address);
      
      await dao.emergencyWithdraw(MINIMUM_DEPOSIT);
      
      const finalBalance = await ethers.provider.getBalance(owner.address);
      expect(finalBalance).to.be.gt(initialBalance);
    });
  });
});
```

### Run Tests
```bash
npx hardhat test
```

## Advanced Features & Enhancements

### 1. Governance Token Integration
```solidity
// Add ERC20 governance token support
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EnhancedDAO {
    IERC20 public governanceToken;
    
    function depositTokens(uint256 amount) external {
        governanceToken.transferFrom(msg.sender, address(this), amount);
        votingPower[msg.sender] += amount;
    }
}
```

### 2. Quorum Requirements
```solidity
uint256 public quorumPercentage = 25; // 25% of total voting power

function executeProposal(uint256 proposalId) external {
    Proposal storage proposal = proposals[proposalId];
    uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
    uint256 totalPower = address(this).balance; // or total token supply
    
    require(
        totalVotes >= (totalPower * quorumPercentage) / 100,
        "Quorum not reached"
    );
    
    require(proposal.yesVotes > proposal.noVotes, "Proposal did not pass");
    // Execute proposal logic
}
```

### 3. Delegation System
```solidity
mapping(address => address) public delegates;

function delegate(address to) external {
    delegates[msg.sender] = to;
}

function getVotingPower(address voter) public view returns (uint256) {
    uint256 power = votingPower[voter];
    
    // Add delegated power
    for (address delegator in allDelegators) {
        if (delegates[delegator] == voter) {
            power += votingPower[delegator];
        }
    }
    
    return power;
}
```

### 4. Time-Locked Execution
```solidity
uint256 public executionDelay = 2 days;
mapping(uint256 => uint256) public executionTime;

function queueExecution(uint256 proposalId) external {
    require(hasProposalPassed(proposalId), "Proposal did not pass");
    executionTime[proposalId] = block.timestamp + executionDelay;
}

function executeProposal(uint256 proposalId) external {
    require(
        block.timestamp >= executionTime[proposalId],
        "Execution delay not met"
    );
    // Execute proposal
}
```

### 5. Multi-Signature Execution
```solidity
mapping(uint256 => mapping(address => bool)) public executionApprovals;
address[] public executors;
uint256 public requiredApprovals = 3;

function approveExecution(uint256 proposalId) external {
    require(isExecutor(msg.sender), "Not an executor");
    executionApprovals[proposalId][msg.sender] = true;
}

function executeProposal(uint256 proposalId) external {
    uint256 approvals = 0;
    for (uint256 i = 0; i < executors.length; i++) {
        if (executionApprovals[proposalId][executors[i]]) {
            approvals++;
        }
    }
    
    require(approvals >= requiredApprovals, "Insufficient approvals");
    // Execute proposal
}
```

## Security Considerations

### 1. Reentrancy Protection
```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SecureDAO is ReentrancyGuard {
    function executeProposal(uint256 proposalId) external nonReentrant {
        // Execution logic
    }
}
```

### 2. Access Control
```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";

contract RoleBasedDAO is AccessControl {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    
    modifier onlyProposer() {
        require(hasRole(PROPOSER_ROLE, msg.sender), "Not a proposer");
        _;
    }
}
```

### 3. Input Validation
```solidity
function createProposal(string calldata description) external {
    require(bytes(description).length >= 10, "Description too short");
    require(bytes(description).length <= 1000, "Description too long");
    require(votingPower[msg.sender] >= minimumProposalPower, "Insufficient power");
    // Create proposal
}
```

## Gas Optimization Tips

### 1. Efficient Storage
```solidity
// Pack struct variables
struct Proposal {
    uint128 yesVotes;      // Instead of uint256
    uint128 noVotes;       // Pack in single slot
    uint64 deadline;       // Sufficient for timestamps
    bool executed;         // Pack with address
    address proposer;      // 20 bytes + 1 byte = 21 bytes
}
```

### 2. Batch Operations
```solidity
function batchVote(uint256[] calldata proposalIds, bool[] calldata supports) external {
    require(proposalIds.length == supports.length, "Array length mismatch");
    
    for (uint256 i = 0; i < proposalIds.length; i++) {
        vote(proposalIds[i], supports[i]);
    }
}
```

### 3. Events Over Storage
```solidity
// Instead of storing all voting history, emit events
event DetailedVote(
    uint256 indexed proposalId,
    address indexed voter,
    bool support,
    uint256 votingPower,
    string reason
);
```

## Frontend Integration Examples

### 1. React Hook for DAO Interaction
```javascript
// hooks/useDAO.js
import { useState, useEffect } from 'react';
import { useContract, useAccount } from 'wagmi';
import { DAO_ABI, DAO_ADDRESS } from '../constants';

export const useDAO = () => {
  const [proposals, setProposals] = useState([]);
  const [userVotingPower, setUserVotingPower] = useState(0);
  const [loading, setLoading] = useState(false);
  
  const { address } = useAccount();
  const daoContract = useContract({
    address: DAO_ADDRESS,
    abi: DAO_ABI,
  });

  // Fetch user's voting power
  const fetchVotingPower = async () => {
    if (!address || !daoContract) return;
    
    try {
      const power = await daoContract.getVotingPower(address);
      setUserVotingPower(power);
    } catch (error) {
      console.error('Error fetching voting power:', error);
    }
  };

  // Fetch all proposals
  const fetchProposals = async () => {
    if (!daoContract) return;
    
    setLoading(true);
    try {
      const totalProposals = await daoContract.totalProposals();
      const proposalPromises = [];
      
      for (let i = 0; i < totalProposals; i++) {
        proposalPromises.push(daoContract.getProposal(i));
      }
      
      const proposalData = await Promise.all(proposalPromises);
      const formattedProposals = proposalData.map((proposal, index) => ({
        id: index,
        description: proposal.description,
        deadline: new Date(proposal.deadline * 1000),
        yesVotes: proposal.yesVotes,
        noVotes: proposal.noVotes,
        executed: proposal.executed,
        proposer: proposal.proposer,
        isActive: Date.now() < proposal.deadline * 1000,
        hasPassed: proposal.yesVotes > proposal.noVotes,
      }));
      
      setProposals(formattedProposals);
    } catch (error) {
      console.error('Error fetching proposals:', error);
    } finally {
      setLoading(false);
    }
  };

  // Deposit STT to gain voting power
  const deposit = async (amount) => {
    if (!daoContract) throw new Error('Contract not available');
    
    try {
      const tx = await daoContract.deposit({ value: amount });
      await tx.wait();
      await fetchVotingPower();
      return tx.hash;
    } catch (error) {
      console.error('Error depositing:', error);
      throw error;
    }
  };

  // Create a new proposal
  const createProposal = async (description) => {
    if (!daoContract) throw new Error('Contract not available');
    
    try {
      const tx = await daoContract.createProposal(description);
      await tx.wait();
      await fetchProposals();
      return tx.hash;
    } catch (error) {
      console.error('Error creating proposal:', error);
      throw error;
    }
  };

  // Vote on a proposal
  const vote = async (proposalId, support) => {
    if (!daoContract) throw new Error('Contract not available');
    
    try {
      const tx = await daoContract.vote(proposalId, support);
      await tx.wait();
      await fetchProposals();
      return tx.hash;
    } catch (error) {
      console.error('Error voting:', error);
      throw error;
    }
  };

  // Execute a proposal
  const executeProposal = async (proposalId) => {
    if (!daoContract) throw new Error('Contract not available');
    
    try {
      const tx = await daoContract.executeProposal(proposalId);
      await tx.wait();
      await fetchProposals();
      return tx.hash;
    } catch (error) {
      console.error('Error executing proposal:', error);
      throw error;
    }
  };

  // Check if user has voted on a proposal
  const hasUserVoted = async (proposalId) => {
    if (!address || !daoContract) return false;
    
    try {
      return await daoContract.hasUserVoted(proposalId, address);
    } catch (error) {
      console.error('Error checking vote status:', error);
      return false;
    }
  };

  useEffect(() => {
    fetchVotingPower();
    fetchProposals();
  }, [address, daoContract]);

  return {
    proposals,
    userVotingPower,
    loading,
    deposit,
    createProposal,
    vote,
    executeProposal,
    hasUserVoted,
    refetch: () => {
      fetchVotingPower();
      fetchProposals();
    },
  };
};
```

### 2. Proposal Card Component
```javascript
// components/ProposalCard.jsx
import React, { useState, useEffect } from 'react';
import { formatEther } from 'viem';
import { useDAO } from '../hooks/useDAO';

export const ProposalCard = ({ proposal, userAddress }) => {
  const [hasVoted, setHasVoted] = useState(false);
  const [voting, setVoting] = useState(false);
  const [executing, setExecuting] = useState(false);
  const { vote, executeProposal, hasUserVoted } = useDAO();

  useEffect(() => {
    const checkVoteStatus = async () => {
      if (userAddress) {
        const voted = await hasUserVoted(proposal.id);
        setHasVoted(voted);
      }
    };
    checkVoteStatus();
  }, [proposal.id, userAddress]);

  const handleVote = async (support) => {
    setVoting(true);
    try {
      await vote(proposal.id, support);
      setHasVoted(true);
    } catch (error) {
      console.error('Voting failed:', error);
    } finally {
      setVoting(false);
    }
  };

  const handleExecute = async () => {
    setExecuting(true);
    try {
      await executeProposal(proposal.id);
    } catch (error) {
      console.error('Execution failed:', error);
    } finally {
      setExecuting(false);
    }
  };

  const totalVotes = proposal.yesVotes + proposal.noVotes;
  const yesPercentage = totalVotes > 0 ? (proposal.yesVotes / totalVotes) * 100 : 0;
  const noPercentage = totalVotes > 0 ? (proposal.noVotes / totalVotes) * 100 : 0;

  const getStatusColor = () => {
    if (proposal.executed) return 'bg-gray-500';
    if (!proposal.isActive) {
      return proposal.hasPassed ? 'bg-green-500' : 'bg-red-500';
    }
    return 'bg-blue-500';
  };

  const getStatusText = () => {
    if (proposal.executed) return 'Executed';
    if (!proposal.isActive) {
      return proposal.hasPassed ? 'Passed' : 'Failed';
    }
    return 'Active';
  };

  return (
    <div className="bg-white rounded-lg shadow-md p-6 border border-gray-200">
      {/* Header */}
      <div className="flex justify-between items-start mb-4">
        <h3 className="text-lg font-semibold text-gray-800">
          Proposal #{proposal.id}
        </h3>
        <span className={`px-3 py-1 rounded-full text-white text-sm ${getStatusColor()}`}>
          {getStatusText()}
        </span>
      </div>

      {/* Description */}
      <p className="text-gray-600 mb-4">{proposal.description}</p>

      {/* Proposer */}
      <p className="text-sm text-gray-500 mb-4">
        Proposed by: {proposal.proposer.slice(0, 6)}...{proposal.proposer.slice(-4)}
      </p>

      {/* Voting Stats */}
      <div className="mb-4">
        <div className="flex justify-between text-sm text-gray-600 mb-2">
          <span>Yes: {formatEther(proposal.yesVotes)} STT ({yesPercentage.toFixed(1)}%)</span>
          <span>No: {formatEther(proposal.noVotes)} STT ({noPercentage.toFixed(1)}%)</span>
        </div>
        
        {/* Progress Bar */}
        <div className="w-full bg-gray-200 rounded-full h-2">
          <div className="flex h-2 rounded-full overflow-hidden">
            <div 
              className="bg-green-500" 
              style={{ width: `${yesPercentage}%` }}
            ></div>
            <div 
              className="bg-red-500" 
              style={{ width: `${noPercentage}%` }}
            ></div>
          </div>
        </div>
      </div>

      {/* Deadline */}
      <p className="text-sm text-gray-500 mb-4">
        {proposal.isActive 
          ? `Voting ends: ${proposal.deadline.toLocaleString()}` 
          : `Voting ended: ${proposal.deadline.toLocaleString()}`
        }
      </p>

      {/* Action Buttons */}
      <div className="space-y-2">
        {proposal.isActive && userAddress && !hasVoted && (
          <div className="flex space-x-2">
            <button
              onClick={() => handleVote(true)}
              disabled={voting}
              className="flex-1 bg-green-500 hover:bg-green-600 disabled:bg-gray-400 text-white font-bold py-2 px-4 rounded transition-colors"
            >
              {voting ? 'Voting...' : 'Vote Yes'}
            </button>
            <button
              onClick={() => handleVote(false)}
              disabled={voting}
              className="flex-1 bg-red-500 hover:bg-red-600 disabled:bg-gray-400 text-white font-bold py-2 px-4 rounded transition-colors"
            >
              {voting ? 'Voting...' : 'Vote No'}
            </button>
          </div>
        )}

        {hasVoted && proposal.isActive && (
          <div className="bg-blue-100 border border-blue-300 text-blue-700 px-4 py-2 rounded">
            You have already voted on this proposal
          </div>
        )}

        {!proposal.isActive && proposal.hasPassed && !proposal.executed && (
          <button
            onClick={handleExecute}
            disabled={executing}
            className="w-full bg-purple-500 hover:bg-purple-600 disabled:bg-gray-400 text-white font-bold py-2 px-4 rounded transition-colors"
          >
            {executing ? 'Executing...' : 'Execute Proposal'}
          </button>
        )}
      </div>
    </div>
  );
};
```

### 3. Create Proposal Form
```javascript
// components/CreateProposalForm.jsx
import React, { useState } from 'react';
import { useDAO } from '../hooks/useDAO';

export const CreateProposalForm = ({ userVotingPower, onSuccess }) => {
  const [description, setDescription] = useState('');
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState('');
  const { createProposal } = useDAO();

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    if (!description.trim()) {
      setError('Description is required');
      return;
    }

    if (userVotingPower === 0) {
      setError('You need voting power to create proposals. Please deposit STT first.');
      return;
    }

    setCreating(true);
    setError('');

    try {
      const txHash = await createProposal(description.trim());
      setDescription('');
      onSuccess?.(txHash);
    } catch (error) {
      setError(error.message || 'Failed to create proposal');
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <h2 className="text-xl font-bold mb-4">Create New Proposal</h2>
      
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Proposal Description
          </label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Describe your proposal in detail..."
            rows={4}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={creating}
          />
          <p className="text-sm text-gray-500 mt-1">
            {description.length}/1000 characters
          </p>
        </div>

        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
            {error}
          </div>
        )}

        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <p className="text-sm text-blue-800">
            <strong>Your Voting Power:</strong> {userVotingPower} STT
          </p>
          {userVotingPower === 0 && (
            <p className="text-sm text-blue-600 mt-1">
              Deposit STT to gain voting power and create proposals.
            </p>
          )}
        </div>

        <button
          type="submit"
          disabled={creating || userVotingPower === 0 || !description.trim()}
          className="w-full bg-blue-500 hover:bg-blue-600 disabled:bg-gray-400 text-white font-bold py-2 px-4 rounded transition-colors"
        >
          {creating ? 'Creating Proposal...' : 'Create Proposal'}
        </button>
      </form>
    </div>
  );
};
```

### 4. Deposit Form Component
```javascript
// components/DepositForm.jsx
import React, { useState } from 'react';
import { parseEther, formatEther } from 'viem';
import { useDAO } from '../hooks/useDAO';

export const DepositForm = ({ currentVotingPower, onSuccess }) => {
  const [amount, setAmount] = useState('');
  const [depositing, setDepositing] = useState(false);
  const [error, setError] = useState('');
  const { deposit } = useDAO();

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    const depositAmount = parseFloat(amount);
    if (isNaN(depositAmount) || depositAmount < 0.001) {
      setError('Minimum deposit is 0.001 STT');
      return;
    }

    setDepositing(true);
    setError('');

    try {
      const txHash = await deposit(parseEther(amount));
      setAmount('');
      onSuccess?.(txHash);
    } catch (error) {
      setError(error.message || 'Failed to deposit');
    } finally {
      setDepositing(false);
    }
  };

  const presetAmounts = ['0.001', '0.01', '0.1', '1'];

  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <h2 className="text-xl font-bold mb-4">Deposit STT for Voting Power</h2>
      
      <div className="mb-4 bg-gray-50 rounded-lg p-4">
        <p className="text-sm text-gray-600">Current Voting Power</p>
        <p className="text-2xl font-bold text-blue-600">
          {formatEther(currentVotingPower)} STT
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Deposit Amount (STT)
          </label>
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.001"
            step="0.001"
            min="0.001"
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={depositing}
          />
        </div>

        {/* Preset Amount Buttons */}
        <div>
          <p className="text-sm text-gray-600 mb-2">Quick amounts:</p>
          <div className="grid grid-cols-4 gap-2">
            {presetAmounts.map((preset) => (
              <button
                key={preset}
                type="button"
                onClick={() => setAmount(preset)}
                className="bg-gray-200 hover:bg-gray-300 text-gray-700 py-2 px-3 rounded text-sm transition-colors"
                disabled={depositing}
              >
                {preset} STT
              </button>
            ))}
          </div>
        </div>

        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
            {error}
          </div>
        )}

        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
          <p className="text-sm text-yellow-800">
            <strong>Note:</strong> Deposited STT gives you voting power proportional to your deposit. 
            Higher voting power means your votes carry more weight in proposals.
          </p>
        </div>

        <button
          type="submit"
          disabled={depositing || !amount || parseFloat(amount) < 0.001}
          className="w-full bg-green-500 hover:bg-green-600 disabled:bg-gray-400 text-white font-bold py-2 px-4 rounded transition-colors"
        >
          {depositing ? 'Depositing...' : `Deposit ${amount || '0'} STT`}
        </button>
      </form>
    </div>
  );
};
```

## Production Deployment Checklist

### 1. Security Audit
- [ ] **Smart Contract Audit**: Engage professional auditors
- [ ] **Access Control Review**: Verify all role-based permissions
- [ ] **Reentrancy Protection**: Ensure all state-changing functions are protected
- [ ] **Integer Overflow/Underflow**: Use SafeMath or Solidity 0.8+
- [ ] **Gas Limit Considerations**: Test with various proposal sizes

### 2. Testing Suite
- [ ] **Unit Tests**: Cover all functions with edge cases
- [ ] **Integration Tests**: Test complete workflows
- [ ] **Fork Testing**: Test against mainnet state
- [ ] **Gas Optimization**: Profile and optimize expensive operations
- [ ] **Stress Testing**: Test with many proposals and voters

### 3. Frontend Security
- [ ] **Input Validation**: Sanitize all user inputs
- [ ] **Error Handling**: Graceful error messages
- [ ] **Transaction Monitoring**: Implement proper loading states
- [ ] **Wallet Integration**: Secure wallet connection handling

### 4. Governance Parameters
- [ ] **Voting Duration**: Set appropriate voting periods
- [ ] **Minimum Deposit**: Balance accessibility vs spam prevention
- [ ] **Quorum Requirements**: Ensure meaningful participation
- [ ] **Execution Delays**: Implement timelock for security

## Troubleshooting Common Issues

### 1. Transaction Failures
```javascript
// Common error handling patterns
const handleTransactionError = (error) => {
  if (error.code === 4001) {
    return "Transaction rejected by user";
  } else if (error.message.includes("insufficient funds")) {
    return "Insufficient STT balance for transaction";
  } else if (error.message.includes("already voted")) {
    return "You have already voted on this proposal";
  } else if (error.message.includes("No voting power")) {
    return "You need to deposit STT to gain voting power";
  } else if (error.message.includes("Voting has ended")) {
    return "Voting period has ended for this proposal";
  }
  return "Transaction failed. Please try again.";
};
```

### 2. Network Issues
```javascript
// Network validation
const validateNetwork = async (provider) => {
  const network = await provider.getNetwork();
  const expectedChainId = 50312; // Somnia testnet
  
  if (network.chainId !== expectedChainId) {
    throw new Error(`Please switch to Somnia Network (Chain ID: ${expectedChainId})`);
  }
};
```

### 3. Gas Estimation Problems
```javascript
// Gas estimation with buffer
const estimateGasWithBuffer = async (contract, method, args) => {
  try {
    const gasEstimate = await contract.estimateGas[method](...args);
    return gasEstimate.mul(120).div(100); // Add 20% buffer
  } catch (error) {
    console.error('Gas estimation failed:', error);
    return ethers.utils.parseUnits('500000', 'wei'); // Fallback gas limit
  }
};
```

## Performance Optimization

### 1. Event Indexing
```solidity
// Efficient event indexing for frontend queries
event ProposalCreated(
    uint256 indexed proposalId,
    address indexed proposer,
    uint256 indexed category, // For filtering
    string description,
    uint256 deadline
);

event VoteCast(
    uint256 indexed proposalId,
    address indexed voter,
    bool indexed support,
    uint256 votingPower
);
```

### 2. Batch Queries
```javascript
// Efficient batch data fetching
const fetchAllProposalData = async (contract, proposalIds) => {
  const multicallData = proposalIds.map(id => 
    contract.interface.encodeFunctionData('getProposal', [id])
  );
  
  // Use multicall contract for batch execution
  const results = await multicallContract.aggregate(multicallData);
  
  return results.map((result, index) => 
    contract.interface.decodeFunctionResult('getProposal', result)
  );
};
```

### 3. Caching Strategies
```javascript
// React Query for data caching
import { useQuery, useMutation, useQueryClient } from 'react-query';

export const useProposals = () => {
  return useQuery(
    ['proposals'],
    fetchProposals,
    {
      staleTime: 30000, // 30 seconds
      cacheTime: 300000, // 5 minutes
      refetchOnWindowFocus: false,
    }
  );
};

export const useCreateProposal = () => {
  const queryClient = useQueryClient();
  
  return useMutation(createProposal, {
    onSuccess: () => {
      queryClient.invalidateQueries(['proposals']);
    },
  });
};
```

## Conclusion

You have successfully learned how to:

1. **Design and implement** a comprehensive DAO smart contract with voting mechanisms
2. **Handle complex governance flows** including proposal creation, voting, and execution
3. **Implement security best practices** with proper access controls and validation
4. **Create production-ready frontend integration** with React hooks and components
5. **Optimize for performance** with efficient data structures and caching strategies
6. **Deploy and test** on Somnia Network's high-performance blockchain
7. **Plan for production** with security audits and monitoring

This DAO implementation provides a solid foundation for building sophisticated governance systems that can handle the scale and performance requirements of modern decentralized applications. The modular design makes it easy to extend with additional features like governance tokens, delegation systems, and complex execution logic.

**Next Steps**: 
- Integrate with the [DAO UI tutorial](./how-to-build-a-user-interface-for-dao-smart-contract-p1) for complete frontend implementation
- Add governance token functionality using the [ERC20 tutorial](./create-and-deploy-your-erc20-smart-contract-to-somnia-network)
- Implement advanced features like quadratic voting or conviction voting for more sophisticated governance mechanisms

The combination of Somnia's 1M+ TPS performance and this robust DAO framework enables building governance systems that can handle enterprise-scale decision-making with real-time responsiveness.