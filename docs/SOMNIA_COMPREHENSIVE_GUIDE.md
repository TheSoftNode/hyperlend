# Somnia Network - Comprehensive Developer Guide

## 📋 Table of Contents

1. [Overview](#overview)
2. [Core Network Features](#core-network-features)
3. [Network Configuration](#network-configuration)
4. [Development Toolchain](#development-toolchain)
5. [Native STT Token Integration](#native-stt-token-integration)
6. [Oracle Integration](#oracle-integration)
7. [Real-Time Features](#real-time-features)
8. [Advanced Use Cases](#advanced-use-cases)
9. [Data Access & Analytics](#data-access--analytics)
10. [Security & Best Practices](#security--best-practices)
11. [Developer Experience](#developer-experience)
12. [Gaming & Real-Time Applications](#gaming--real-time-applications)
13. [HyperLend Integration Opportunities](#hyperlend-integration-opportunities)

---

## 🌟 Overview

Somnia Network is a high-performance, EVM-compatible blockchain designed for **mass-consumer real-time applications**. It combines the developer familiarity of Ethereum with groundbreaking performance capabilities, making it ideal for gaming, DeFi, and other applications requiring instant responsiveness.

### Key Mission

> Enable the building of mass-consumer real-time applications with 1M+ TPS and sub-second finality.

---

## 🏗️ Core Network Features

### Performance Specifications

- **🚀 1M+ TPS** - Ultra-high transaction throughput
- **⚡ Sub-second finality** - Near-instant transaction confirmation
- **🔗 EVM-compatible** - Full Ethereum smart contract compatibility
- **💎 Native STT Token** - Built-in protocol token (not ERC-20)
- **🌐 Account Abstraction** - Gasless transaction support
- **📡 Real-time Capabilities** - WebSocket-based event streaming

### Technical Advantages

- **High TPS Performance** - Handle viral application scale
- **Ultra-fast Liquidations** - Perfect for DeFi protocols
- **Real-time Metrics** - Live data updates without polling
- **MEV-resistant** - Sub-second finality reduces MEV opportunities
- **Scalable Architecture** - Built for mass adoption

---

## 🌐 Network Configuration

### Somnia Testnet Details

| Parameter           | Value                                     |
| ------------------- | ----------------------------------------- |
| **Network Name**    | Somnia Testnet                            |
| **RPC URL**         | `https://dream-rpc.somnia.network`        |
| **WebSocket URL**   | `wss://dream-rpc.somnia.network/ws`       |
| **Chain ID**        | `50312` (hex: `0xC4B8`)                   |
| **Currency Symbol** | STT                                       |
| **Block Explorer**  | `https://shannon-explorer.somnia.network` |
| **Faucet**          | Available via Discord #dev-chat           |

### MetaMask Network Addition

```javascript
const SOMNIA_TESTNET = {
  chainId: "0xC4B8", // 50312
  chainName: "Somnia Testnet",
  nativeCurrency: {
    name: "STT",
    symbol: "STT",
    decimals: 18,
  },
  rpcUrls: ["https://dream-rpc.somnia.network"],
  blockExplorerUrls: ["https://shannon-explorer.somnia.network"],
};

await window.ethereum.request({
  method: "wallet_addEthereumChain",
  params: [SOMNIA_TESTNET],
});
```

---

## 🔧 Development Toolchain

### Smart Contract Development Frameworks

#### 1. Hardhat (Recommended)

```bash
# Initialize project
npx hardhat init

# Network configuration
module.exports = {
  solidity: "0.8.28",
  networks: {
    somnia: {
      url: "https://dream-rpc.somnia.network",
      accounts: ["YOUR_PRIVATE_KEY"],
    },
  },
  etherscan: {
    apiKey: {
      somnia: "ETHERSCAN_API_KEY",
    },
    customChains: [{
      network: "somnia",
      chainId: 50312,
      urls: {
        apiURL: "https://shannon-explorer.somnia.network/api",
        browserURL: "https://shannon-explorer.somnia.network",
      },
    }],
  },
};

# Deploy contract
npx hardhat ignition deploy ./ignition/modules/deploy.ts --network somnia

# Verify contract
npx hardhat verify --network somnia CONTRACT_ADDRESS
```

#### 2. Foundry (High Performance)

```bash
# Initialize project
forge init project-name

# Configuration (foundry.toml)
[rpc_endpoints]
somnia = "https://dream-rpc.somnia.network"

# Deploy contract
forge create --rpc-url https://dream-rpc.somnia.network --private-key PRIVATE_KEY src/Contract.sol:Contract

# Run tests
forge test --gas-report
```

#### 3. Remix IDE (Quick Prototyping)

- Browser-based development
- Direct deployment to Somnia
- Built-in debugging tools
- Perfect for learning and testing

### Frontend Integration Libraries

#### Viem (Recommended)

```typescript
import { createPublicClient, createWalletClient, custom, http } from "viem";
import { somniaTestnet } from "viem/chains";

// Public client for reading
const publicClient = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});

// Wallet client for transactions
const walletClient = createWalletClient({
  chain: somniaTestnet,
  transport: custom(window.ethereum),
});
```

#### Ethers.js (Alternative)

```javascript
const provider = new ethers.JsonRpcProvider("https://dream-rpc.somnia.network");
const signer = new ethers.Wallet(privateKey, provider);
```

#### Wallet Connection Libraries

- **ConnectKit** - Seamless wallet connection UI
- **RainbowKit** - Beautiful wallet connection modals
- **Thirdweb** - Account abstraction support

---

## 💰 Native STT Token Integration

### Key Characteristics

STT is Somnia's **native protocol token**, similar to ETH on Ethereum:

- ❌ **No contract address** - Built into the protocol
- ✅ **Direct payable functions** - Use `msg.value` to access STT
- ✅ **Standard Solidity patterns** - `.transfer()`, `.call()`, `address.balance`
- ✅ **Gas currency** - Used for transaction fees

### Implementation Patterns

#### ✅ Correct STT Usage

```solidity
contract STTExample {
    // Accept STT payments
    function deposit() external payable {
        require(msg.value > 0, "Must send STT");
        // Process STT deposit
    }

    // Send STT from contract
    function withdraw(uint256 amount) external {
        payable(msg.sender).transfer(amount);
    }

    // Check STT balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Receive STT directly
    receive() external payable {
        // Handle direct STT transfers
    }
}
```

#### ❌ Incorrect STT Usage

```solidity
// DON'T treat STT like ERC-20
STT.transfer(recipient, amount); // This won't work!
address sttContract = 0x...; // STT has no contract!
STT.balanceOf(address); // This doesn't exist!
```

### STT Use Cases

#### 1. Payments - Exact Payment Requirements

```solidity
function payToAccess() external payable {
    require(msg.value == 0.01 ether, "Must send exactly 0.01 STT");
    // Grant access logic
}
```

#### 2. Escrow - Secure Transactions

```solidity
contract STTEscrow {
    address public buyer;
    address payable public seller;
    uint256 public amount;

    constructor(address payable _seller) payable {
        buyer = msg.sender;
        seller = _seller;
        amount = msg.value;
    }

    function release() external {
        require(msg.sender == buyer, "Only buyer can release");
        seller.transfer(amount);
    }
}
```

#### 3. Donations & Tips

```solidity
contract TipJar {
    address public owner;

    receive() external payable {
        // Accept tips from any wallet
        emit TipReceived(msg.sender, msg.value);
    }

    function withdraw() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }
}
```

#### 4. Gasless Transactions (Account Abstraction)

```solidity
// Smart contracts called without user paying gas
// Paymaster/relayer covers transaction costs
function sponsoredAction() external {
    // User action executed with sponsored gas
}
```

---

## 🔮 Oracle Integration

### DIA Oracles (Primary)

#### Configuration

- **Contract Address**: `0x9206296Ea3aEE3E6bdC07F7AaeF14DfCf33d865D`
- **Pricing Methodology**: MAIR
- **Deviation Threshold**: 0.5%
- **Refresh Frequency**: Every 120 seconds
- **Heartbeat**: 24 hours (forced update)

#### Supported Assets

| Asset    | Adapter Address                              |
| -------- | -------------------------------------------- |
| **USDT** | `0x67d2C2a87A17b7267a6DBb1A59575C0E9A1D1c3e` |
| **USDC** | `0x235266D5ca6f19F134421C49834C108b32C2124e` |
| **BTC**  | `0x4803db1ca3A1DA49c3DB991e1c390321c20e1f21` |
| **ARB**  | `0x74952812B6a9e4f826b2969C6D189c4425CBc19B` |
| **SOL**  | `0xD5Ea6C434582F827303423dA21729bEa4F87D519` |

#### Implementation

```solidity
import { DIAOracleLib } from "./libraries/DIAOracleLib.sol";

contract PriceConsumer {
    address constant DIA_ORACLE = 0x9206296Ea3aEE3E6bdC07F7AaeF14DfCf33d865D;

    function getSTTPrice() external view returns (uint128, uint128) {
        return DIAOracleLib.getPrice(DIA_ORACLE, "STT/USD");
    }

    function getPriceIfFresh(uint128 maxAge) external view returns (uint128, bool) {
        return DIAOracleLib.getPriceIfNotOlderThan(DIA_ORACLE, "STT/USD", maxAge);
    }
}
```

### Protofire Chainlink Oracles (Alternative)

#### Price Feed Contracts

| Asset Pair   | Contract Address                             |
| ------------ | -------------------------------------------- |
| **ETH/USD**  | `0xd9132c1d762D432672493F640a63B758891B449e` |
| **BTC/USD**  | `0x8CeE6c58b8CbD8afdEaF14e6fCA0876765e161fE` |
| **USDC/USD** | `0xa2515C9480e62B510065917136B08F3f7ad743B4` |

#### Implementation

```solidity
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract ChainlinkPriceConsumer {
    AggregatorV3Interface internal priceFeed;

    constructor(address _priceFeed) {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function getLatestPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function getDecimals() public view returns (uint8) {
        return priceFeed.decimals();
    }
}
```

---

## ⚡ Real-Time Features

### WebSocket Event Listening

#### Connection Setup

```javascript
const { ethers } = require("ethers");

// WebSocket provider
const wsUrl = "wss://dream-rpc.somnia.network/ws";
const provider = new ethers.WebSocketProvider(wsUrl);

// Wait for connection
await provider._waitUntilReady();
console.log("Connected to Somnia WebSocket!");
```

#### Event Filtering

```javascript
// Single event filter
const filter = {
  address: contractAddress,
  topics: [ethers.id("Transfer(address,address,uint256)")],
};

// Listen for events
provider.on(filter, async (log) => {
  console.log("Event detected:", log);
  const parsedLog = contract.interface.parseLog(log);
  console.log("Parsed event:", parsedLog.args);
});
```

#### Production Event Listener

```javascript
class SomniaEventListener {
  constructor(contractAddress, abi) {
    this.contractAddress = contractAddress;
    this.abi = abi;
    this.wsUrl = "wss://dream-rpc.somnia.network/ws";
    this.provider = null;
    this.heartbeatInterval = null;
  }

  async connect() {
    this.provider = new ethers.WebSocketProvider(this.wsUrl);
    await this.provider._waitUntilReady();

    // Error handling
    this.provider.on("error", this.handleError.bind(this));
    this.provider.on("close", this.handleClose.bind(this));

    // Heartbeat
    this.startHeartbeat();
  }

  async listenForEvents(eventName, callback) {
    const eventSignature = this.contract.interface.getEvent(eventName);
    const filter = {
      address: this.contractAddress,
      topics: [ethers.id(eventSignature.format("sighash"))],
    };

    this.provider.on(filter, async (log) => {
      const parsedLog = this.contract.interface.parseLog(log);
      await callback(parsedLog, this.contract);
    });
  }
}
```

### High-Frequency Operations

#### Rapid Transaction Processing

```solidity
contract HighFrequencyContract {
    mapping(address => uint256) public balances;

    // Optimized for high TPS
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            balances[recipients[i]] += amounts[i];
            emit Transfer(msg.sender, recipients[i], amounts[i]);
        }
    }

    // Gas-optimized operations
    function rapidUpdate(uint256 newValue) external {
        assembly {
            sstore(balances.slot, newValue)
        }
    }
}
```

#### Frontend Real-Time Updates

```javascript
// React hook for real-time data
const useRealTimeData = (contractAddress, eventName) => {
  const [data, setData] = useState([]);

  useEffect(() => {
    const listener = new SomniaEventListener(contractAddress, abi);

    listener.connect().then(() => {
      listener.listenForEvents(eventName, (eventData) => {
        setData((prev) => [eventData, ...prev.slice(0, 99)]); // Keep last 100 events
      });
    });

    return () => listener.disconnect();
  }, [contractAddress, eventName]);

  return data;
};
```

---

## 🏛️ Advanced Use Cases

### DAO Smart Contracts

#### Core DAO Implementation

```solidity
contract DAO {
    struct Proposal {
        string description;
        uint256 deadline;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        address proposer;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public votingPower;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    uint256 public totalProposals;
    uint256 public votingDuration = 10 minutes;

    // Deposit STT to gain voting power
    function deposit() external payable {
        require(msg.value >= 0.001 ether, "Minimum 0.001 STT");
        votingPower[msg.sender] += msg.value;
        emit FundsDeposited(msg.sender, msg.value, votingPower[msg.sender]);
    }

    // Create proposal
    function createProposal(string calldata description) external {
        require(votingPower[msg.sender] > 0, "No voting power");

        proposals[totalProposals] = Proposal({
            description: description,
            deadline: block.timestamp + votingDuration,
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            proposer: msg.sender
        });

        emit ProposalCreated(totalProposals, msg.sender, description);
        totalProposals++;
    }

    // Vote on proposal
    function vote(uint256 proposalId, bool support) external {
        require(votingPower[msg.sender] > 0, "No voting power");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        require(block.timestamp < proposals[proposalId].deadline, "Voting ended");

        uint256 voterPower = votingPower[msg.sender];
        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            proposals[proposalId].yesVotes += voterPower;
        } else {
            proposals[proposalId].noVotes += voterPower;
        }

        emit VoteCast(proposalId, msg.sender, support, voterPower);
    }

    // Execute proposal
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.deadline, "Voting active");
        require(!proposal.executed, "Already executed");

        bool passed = proposal.yesVotes > proposal.noVotes;
        proposal.executed = true;

        if (passed) {
            // Execute proposal logic
            payable(proposal.proposer).transfer(0.001 ether);
        }

        emit ProposalExecuted(proposalId, passed);
    }
}
```

### Account Abstraction & Gasless Transactions

#### Smart Account Implementation

```solidity
contract SmartAccount {
    address public owner;
    mapping(address => bool) public authorizedSponsors;

    modifier onlyOwnerOrSponsor() {
        require(
            msg.sender == owner || authorizedSponsors[msg.sender],
            "Unauthorized"
        );
        _;
    }

    // Execute transaction with sponsored gas
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyOwnerOrSponsor {
        (bool success, ) = to.call{value: value}(data);
        require(success, "Transaction failed");
    }

    // Add sponsor for gasless transactions
    function addSponsor(address sponsor) external {
        require(msg.sender == owner, "Only owner");
        authorizedSponsors[sponsor] = true;
    }
}
```

#### Frontend Integration with Thirdweb

```typescript
import { useActiveAccount, useSendTransaction } from "thirdweb/react";

export default function GaslessTransaction() {
  const smartAccount = useActiveAccount();
  const { mutate: sendTransaction, isPending } = useSendTransaction();

  const executeGaslessTransaction = async () => {
    sendTransaction(
      {
        to: contractAddress,
        value: parseEther("0.01"),
        chain: somniaTestnet,
        client,
      },
      {
        onSuccess: (receipt) => {
          console.log(
            "Gasless transaction successful:",
            receipt.transactionHash
          );
        },
      }
    );
  };

  return (
    <button onClick={executeGaslessTransaction} disabled={isPending}>
      {isPending ? "Processing..." : "Execute Gasless Transaction"}
    </button>
  );
}
```

---

## 📊 Data Access & Analytics

### Ormi Data APIs

#### Configuration

- **Base URL**: `https://api.subgraph.somnia.network/public_api/data_api`
- **Authentication**: Bearer token required
- **Endpoint Pattern**: `/somnia/v1/address/{walletAddress}/balance/erc20`

#### Implementation

```typescript
// API route (Next.js)
export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const walletAddress = searchParams.get("address");

  const response = await fetch(
    `https://api.subgraph.somnia.network/public_api/data_api/somnia/v1/address/${walletAddress}/balance/erc20`,
    {
      headers: {
        Authorization: `Bearer ${process.env.ORMI_API_KEY}`,
        "Content-Type": "application/json",
      },
    }
  );

  return NextResponse.json(await response.json());
}

// Frontend usage
const fetchTokenBalances = async (address: string) => {
  const response = await fetch(`/api/balance?address=${address}`);
  return response.json();
};
```

### Subgraph Integration with GraphQL

#### Apollo Client Setup

```typescript
import { ApolloClient, InMemoryCache } from "@apollo/client";

const client = new ApolloClient({
  uri: "https://proxy.somnia.chain.love/subgraphs/name/somnia-testnet/SomFlip",
  cache: new InMemoryCache(),
});
```

#### GraphQL Queries

```typescript
import { gql } from "@apollo/client";

export const GET_FLIP_RESULTS = gql`
  query GetFlipResults($first: Int!, $skip: Int!) {
    flipResults(
      first: $first
      skip: $skip
      orderBy: blockTimestamp
      orderDirection: desc
    ) {
      id
      user
      amount
      guess
      result
      won
      blockTimestamp
      transactionHash
    }
  }
`;

// React component usage
const { loading, error, data } = useQuery(GET_FLIP_RESULTS, {
  variables: { first: 10, skip: 0 },
  pollInterval: 5000, // Auto-refresh every 5 seconds
});
```

---

## 🔐 Security & Best Practices

### Smart Contract Security

#### Access Control

```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SecureContract is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function adminFunction() external onlyRole(ADMIN_ROLE) nonReentrant {
        // Admin-only logic with reentrancy protection
    }

    function operatorFunction() external onlyRole(OPERATOR_ROLE) {
        // Operator-only logic
    }
}
```

#### Input Validation

```solidity
contract ValidatedContract {
    function processData(
        address user,
        uint256 amount,
        string calldata description
    ) external {
        require(user != address(0), "Invalid address");
        require(amount > 0 && amount <= 1000 ether, "Invalid amount");
        require(bytes(description).length > 0, "Empty description");
        require(bytes(description).length <= 256, "Description too long");

        // Process validated data
    }
}
```

### Frontend Security

#### Environment Variable Management

```javascript
// .env.local
NEXT_PUBLIC_SOMNIA_RPC_URL=https://dream-rpc.somnia.network
PRIVATE_ORMI_API_KEY=your-api-key-here
PRIVATE_KEY=your-private-key-here

// Usage
const rpcUrl = process.env.NEXT_PUBLIC_SOMNIA_RPC_URL;
const apiKey = process.env.PRIVATE_ORMI_API_KEY; // Server-side only
```

#### Error Handling

```typescript
enum WalletErrorCodes {
  USER_REJECTED = 4001,
  UNAUTHORIZED = 4100,
  UNSUPPORTED_METHOD = 4200,
  DISCONNECTED = 4900,
}

const handleWalletError = (error: any) => {
  switch (error.code) {
    case WalletErrorCodes.USER_REJECTED:
      return "User rejected the request";
    case WalletErrorCodes.UNAUTHORIZED:
      return "Account not authorized";
    default:
      return error.message || "Transaction failed";
  }
};
```

#### Network Validation

```typescript
const validateSomniaNetwork = async (provider: any) => {
  const network = await provider.getNetwork();
  if (network.chainId !== 50312) {
    throw new Error("Please switch to Somnia Network");
  }
};
```

---

## 🚀 Developer Experience

### Quick Start Templates

#### Hardhat Project Template

```bash
# Create project
npx create-next-app@latest somnia-dapp --typescript --tailwind
cd somnia-dapp

# Install blockchain dependencies
npm install hardhat @nomicfoundation/hardhat-toolbox viem

# Initialize Hardhat
npx hardhat init
```

#### Contract Deployment Script

```typescript
// ignition/modules/deploy.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ContractModule = buildModule("Contract", (m) => {
  const contract = m.contract("MyContract", [
    m.getParameter("initialValue", "Hello Somnia"),
  ]);

  return { contract };
});

export default ContractModule;
```

### Testing Frameworks

#### Hardhat Tests

```typescript
import { expect } from "chai";
import { ethers } from "hardhat";

describe("MyContract", function () {
  let contract: any;
  let owner: any;
  let user: any;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    const Contract = await ethers.getContractFactory("MyContract");
    contract = await Contract.deploy("Initial Value");
  });

  it("Should handle STT deposits", async function () {
    const depositAmount = ethers.parseEther("1.0");

    await contract.connect(user).deposit({ value: depositAmount });

    const balance = await contract.getBalance();
    expect(balance).to.equal(depositAmount);
  });

  it("Should emit events correctly", async function () {
    await expect(contract.performAction())
      .to.emit(contract, "ActionPerformed")
      .withArgs(owner.address, ethers.parseEther("1.0"));
  });
});
```

#### Foundry Tests

```solidity
// test/MyContract.t.sol
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MyContract.sol";

contract MyContractTest is Test {
    MyContract public myContract;
    address public user = address(0x1);

    function setUp() public {
        myContract = new MyContract("Initial Value");
        vm.deal(user, 10 ether);
    }

    function testDeposit() public {
        vm.startPrank(user);
        myContract.deposit{value: 1 ether}();
        assertEq(myContract.getBalance(), 1 ether);
        vm.stopPrank();
    }

    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10 ether);
        vm.deal(user, amount);
        vm.prank(user);
        myContract.deposit{value: amount}();
        assertEq(myContract.getBalance(), amount);
    }
}
```

### Performance Optimization

#### Gas Optimization

```solidity
contract OptimizedContract {
    // Pack structs efficiently
    struct User {
        uint128 balance;    // 16 bytes
        uint128 rewards;    // 16 bytes (total: 32 bytes = 1 slot)
        uint32 timestamp;   // 4 bytes
        bool active;        // 1 byte (total: 5 bytes, fits in second slot)
    }

    // Use mappings for O(1) lookup
    mapping(address => User) public users;

    // Batch operations
    function batchUpdate(
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external {
        uint256 length = addresses.length;
        for (uint256 i = 0; i < length; ) {
            users[addresses[i]].balance += uint128(amounts[i]);
            unchecked { ++i; }
        }
    }
}
```

#### Frontend Optimization

```typescript
// React Query for caching
import { useQuery, useMutation, useQueryClient } from "react-query";

export const useContractData = (contractAddress: string) => {
  return useQuery(
    ["contract", contractAddress],
    () => fetchContractData(contractAddress),
    {
      staleTime: 30000, // 30 seconds
      cacheTime: 300000, // 5 minutes
      refetchOnWindowFocus: false,
    }
  );
};

// Memoized components
import { memo, useMemo } from "react";

const ExpensiveComponent = memo(({ data }: { data: any[] }) => {
  const processedData = useMemo(() => {
    return data.map((item) => expensiveProcessing(item));
  }, [data]);

  return <div>{/* Render processed data */}</div>;
});
```

---

## 🎮 Gaming & Real-Time Applications

### Gaming-Optimized Features

#### Real-Time Leaderboards

```solidity
contract GameLeaderboard {
    struct Player {
        address wallet;
        uint256 score;
        uint256 lastUpdate;
    }

    Player[] public leaderboard;
    mapping(address => uint256) public playerIndex;

    event ScoreUpdated(address indexed player, uint256 newScore, uint256 rank);

    // Update score with O(log n) complexity
    function updateScore(address player, uint256 newScore) external {
        uint256 index = playerIndex[player];

        if (index == 0 && leaderboard.length > 0 && leaderboard[0].wallet != player) {
            // New player
            leaderboard.push(Player(player, newScore, block.timestamp));
            index = leaderboard.length - 1;
            playerIndex[player] = index;
        } else {
            // Existing player
            leaderboard[index].score = newScore;
            leaderboard[index].lastUpdate = block.timestamp;
        }

        // Bubble sort optimization for real-time updates
        _bubbleUp(index);

        emit ScoreUpdated(player, newScore, index + 1);
    }

    function _bubbleUp(uint256 index) internal {
        while (index > 0 && leaderboard[index].score > leaderboard[index - 1].score) {
            // Swap players
            Player memory temp = leaderboard[index];
            leaderboard[index] = leaderboard[index - 1];
            leaderboard[index - 1] = temp;

            // Update indices
            playerIndex[leaderboard[index].wallet] = index;
            playerIndex[leaderboard[index - 1].wallet] = index - 1;

            index--;
        }
    }
}
```

#### In-Game Economy

```solidity
contract GameEconomy {
    mapping(address => uint256) public playerBalances;
    mapping(uint256 => uint256) public itemPrices;
    mapping(address => mapping(uint256 => uint256)) public playerItems;

    event ItemPurchased(address indexed player, uint256 itemId, uint256 price);
    event RewardEarned(address indexed player, uint256 amount, string reason);

    // Instant reward distribution
    function distributeReward(
        address player,
        uint256 amount,
        string calldata reason
    ) external {
        playerBalances[player] += amount;
        emit RewardEarned(player, amount, reason);
    }

    // Atomic item purchase
    function purchaseItem(uint256 itemId) external payable {
        uint256 price = itemPrices[itemId];
        require(msg.value >= price, "Insufficient payment");

        playerItems[msg.sender][itemId]++;

        // Refund excess payment
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }

        emit ItemPurchased(msg.sender, itemId, price);
    }
}
```

### Real-Time Frontend Integration

#### WebSocket Game State

```typescript
class GameStateManager {
  private ws: WebSocket;
  private eventListeners: Map<string, Function[]> = new Map();

  constructor(private gameContractAddress: string) {
    this.connectWebSocket();
  }

  private connectWebSocket() {
    this.ws = new WebSocket("wss://dream-rpc.somnia.network/ws");

    this.ws.onopen = () => {
      console.log("Connected to Somnia WebSocket");
      this.subscribeToGameEvents();
    };

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.handleGameEvent(data);
    };
  }

  private subscribeToGameEvents() {
    // Subscribe to all game contract events
    const subscription = {
      method: "eth_subscribe",
      params: [
        "logs",
        {
          address: this.gameContractAddress,
          topics: [], // All events
        },
      ],
    };

    this.ws.send(JSON.stringify(subscription));
  }

  private handleGameEvent(eventData: any) {
    const eventType = this.parseEventType(eventData);
    const listeners = this.eventListeners.get(eventType) || [];

    listeners.forEach((listener) => listener(eventData));
  }

  public onGameEvent(eventType: string, callback: Function) {
    if (!this.eventListeners.has(eventType)) {
      this.eventListeners.set(eventType, []);
    }
    this.eventListeners.get(eventType)!.push(callback);
  }
}

// Usage in React
const useGameState = (contractAddress: string) => {
  const [playerScores, setPlayerScores] = useState<Map<string, number>>(
    new Map()
  );
  const [leaderboard, setLeaderboard] = useState<any[]>([]);

  useEffect(() => {
    const gameManager = new GameStateManager(contractAddress);

    gameManager.onGameEvent("ScoreUpdated", (event) => {
      setPlayerScores((prev) => new Map(prev.set(event.player, event.score)));
      updateLeaderboard(event.player, event.score);
    });

    gameManager.onGameEvent("RewardEarned", (event) => {
      showRewardNotification(event.player, event.amount, event.reason);
    });

    return () => gameManager.disconnect();
  }, [contractAddress]);

  return { playerScores, leaderboard };
};
```

---

## 🎯 HyperLend Integration Opportunities

### Leveraging Somnia's Unique Capabilities

#### 1. Ultra-Fast Liquidations

```solidity
contract HyperLendLiquidationEngine {
    using SomniaWrapper for address;

    // Sub-second liquidation execution
    function liquidatePosition(
        address borrower,
        address collateralAsset,
        uint256 debtToCover
    ) external {
        // Real-time health factor check with DIA Oracle
        uint256 healthFactor = calculateHealthFactor(borrower);
        require(healthFactor < 1e18, "Position healthy");

        // Instant liquidation with Somnia's sub-second finality
        _executeLiquidation(borrower, collateralAsset, debtToCover);

        // Real-time event emission for instant UI updates
        emit LiquidationExecuted(borrower, collateralAsset, debtToCover, block.timestamp);
    }

    // MEV-resistant liquidation with instant finality
    function flashLiquidation(
        address borrower,
        bytes calldata liquidationData
    ) external {
        // Execute liquidation atomically
        // Somnia's sub-second finality prevents front-running
        _performFlashLiquidation(borrower, liquidationData);
    }
}
```

#### 2. Native STT Integration

```solidity
contract HyperLendPool {
    // Direct STT handling without ERC-20 complexity
    function supplySTT() external payable {
        require(msg.value > 0, "Must supply STT");

        // Mint hlSTT tokens representing STT deposit
        hlSTTToken.mint(msg.sender, msg.value);

        // Update pool state
        totalSTTSupplied += msg.value;

        emit STTSupplied(msg.sender, msg.value, block.timestamp);
    }

    function borrowSTT(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(calculateHealthFactor(msg.sender) > 1.1e18, "Insufficient collateral");

        // Mint debt tokens
        debtSTTToken.mint(msg.sender, amount);

        // Transfer STT directly to borrower
        payable(msg.sender).transfer(amount);

        emit STTBorrowed(msg.sender, amount, block.timestamp);
    }

    function repaySTT() external payable {
        require(msg.value > 0, "Must repay STT");

        uint256 debt = debtSTTToken.balanceOf(msg.sender);
        uint256 repayAmount = msg.value > debt ? debt : msg.value;

        // Burn debt tokens
        debtSTTToken.burn(msg.sender, repayAmount);

        // Refund excess payment
        if (msg.value > repayAmount) {
            payable(msg.sender).transfer(msg.value - repayAmount);
        }

        emit STTRepaid(msg.sender, repayAmount, block.timestamp);
    }
}
```

#### 3. Real-Time Metrics with WebSocket

```typescript
// Real-time HyperLend metrics dashboard
class HyperLendMetrics {
  private wsProvider: ethers.WebSocketProvider;
  private poolContract: ethers.Contract;

  constructor(poolAddress: string) {
    this.wsProvider = new ethers.WebSocketProvider(
      "wss://dream-rpc.somnia.network/ws"
    );
    this.poolContract = new ethers.Contract(
      poolAddress,
      poolABI,
      this.wsProvider
    );
  }

  // Real-time TVL updates
  public onTVLUpdate(callback: (tvl: string) => void) {
    this.poolContract.on("STTSupplied", async () => {
      const tvl = await this.calculateTVL();
      callback(tvl);
    });

    this.poolContract.on("STTWithdrawn", async () => {
      const tvl = await this.calculateTVL();
      callback(tvl);
    });
  }

  // Real-time utilization rate
  public onUtilizationUpdate(callback: (rate: string) => void) {
    this.poolContract.on("STTBorrowed", async () => {
      const rate = await this.calculateUtilizationRate();
      callback(rate);
    });

    this.poolContract.on("STTRepaid", async () => {
      const rate = await this.calculateUtilizationRate();
      callback(rate);
    });
  }

  // Live liquidation monitoring
  public onLiquidation(callback: (event: any) => void) {
    this.poolContract.on(
      "LiquidationExecuted",
      (borrower, asset, amount, timestamp) => {
        callback({
          borrower,
          asset,
          amount: ethers.formatEther(amount),
          timestamp: new Date(timestamp * 1000),
        });
      }
    );
  }
}

// React hook for real-time metrics
const useHyperLendMetrics = (poolAddress: string) => {
  const [tvl, setTvl] = useState("0");
  const [utilizationRate, setUtilizationRate] = useState("0");
  const [recentLiquidations, setRecentLiquidations] = useState<any[]>([]);

  useEffect(() => {
    const metrics = new HyperLendMetrics(poolAddress);

    metrics.onTVLUpdate(setTvl);
    metrics.onUtilizationUpdate(setUtilizationRate);
    metrics.onLiquidation((liquidation) => {
      setRecentLiquidations((prev) => [liquidation, ...prev.slice(0, 9)]);
    });

    return () => metrics.disconnect();
  }, [poolAddress]);

  return { tvl, utilizationRate, recentLiquidations };
};
```

#### 4. DIA Oracle Price Feeds

```solidity
contract HyperLendPriceOracle {
    using DIAOracleLib for address;

    address constant DIA_ORACLE = 0x9206296Ea3aEE3E6bdC07F7AaeF14DfCf33d865D;
    mapping(address => string) public assetKeys; // asset -> DIA key

    constructor() {
        // Configure supported assets
        assetKeys[NATIVE_STT] = "STT/USD";
        assetKeys[USDC_ADDRESS] = "USDC/USD";
        assetKeys[BTC_ADDRESS] = "BTC/USD";
    }

    function getPrice(address asset) external view returns (uint256) {
        string memory key = assetKeys[asset];
        require(bytes(key).length > 0, "Asset not supported");

        (uint128 price, uint128 timestamp) = DIA_ORACLE.getPrice(key);

        // Ensure price is fresh (within 24 hours)
        require(block.timestamp - timestamp < 86400, "Price too old");

        // Convert to 18 decimals
        return uint256(price) * 1e10; // DIA uses 8 decimals
    }

    function getPriceWithFreshness(
        address asset,
        uint256 maxAge
    ) external view returns (uint256 price, bool isFresh) {
        string memory key = assetKeys[asset];
        require(bytes(key).length > 0, "Asset not supported");

        (uint128 rawPrice, bool fresh) = DIA_ORACLE.getPriceIfNotOlderThan(
            key,
            uint128(maxAge)
        );

        return (uint256(rawPrice) * 1e10, fresh);
    }
}
```

#### 5. Gasless User Experience

```solidity
contract HyperLendGasless {
    using SomniaWrapper for address;

    mapping(address => bool) public authorizedRelayers;
    mapping(bytes32 => bool) public executedMetaTxs;

    // Gasless supply with meta-transaction
    function metaSupply(
        address user,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external {
        require(authorizedRelayers[msg.sender], "Unauthorized relayer");

        bytes32 txHash = keccak256(abi.encodePacked(
            user, amount, nonce, address(this)
        ));

        require(!executedMetaTxs[txHash], "Transaction already executed");
        require(_verifySignature(txHash, signature, user), "Invalid signature");

        executedMetaTxs[txHash] = true;

        // Execute supply on behalf of user
        _executeSupply(user, amount);

        emit GaslessSupply(user, amount, msg.sender);
    }

    // Sponsored transaction for new users
    function sponsoredBorrow(
        address newUser,
        uint256 amount
    ) external {
        require(authorizedRelayers[msg.sender], "Unauthorized relayer");
        require(_isNewUser(newUser), "User not eligible for sponsorship");

        // Execute borrow with sponsored gas
        _executeBorrow(newUser, amount);

        emit SponsoredBorrow(newUser, amount, msg.sender);
    }
}
```

#### 6. High-Frequency Trading Support

```solidity
contract HyperLendFlashLoans {
    // Atomic flash loan execution leveraging Somnia's speed
    function flashLoan(
        address asset,
        uint256 amount,
        bytes calldata params
    ) external {
        uint256 balanceBefore = _getBalance(asset);

        // Transfer flash loan amount
        _transfer(asset, msg.sender, amount);

        // Execute user's flash loan logic
        IFlashLoanReceiver(msg.sender).executeOperation(asset, amount, params);

        // Verify repayment with fee
        uint256 fee = _calculateFlashLoanFee(amount);
        uint256 balanceAfter = _getBalance(asset);

        require(balanceAfter >= balanceBefore + fee, "Flash loan not repaid");

        emit FlashLoanExecuted(msg.sender, asset, amount, fee);
    }

    // Batch flash loans for arbitrage
    function batchFlashLoan(
        address[] calldata assets,
        uint256[] calldata amounts,
        bytes calldata params
    ) external {
        // Execute multiple flash loans atomically
        // Perfect for complex arbitrage strategies
        for (uint256 i = 0; i < assets.length; i++) {
            _executeFlashLoan(assets[i], amounts[i]);
        }

        // Single callback for batch operations
        IFlashLoanReceiver(msg.sender).executeBatchOperation(assets, amounts, params);

        // Verify all repayments
        _verifyBatchRepayment(assets, amounts);
    }
}
```

### Performance Advantages for HyperLend

1. **⚡ Instant Liquidations**: Sub-second finality enables real-time liquidation execution
2. **🏃‍♂️ High-Frequency Operations**: Handle rapid borrow/lend cycles without congestion
3. **📊 Real-Time Analytics**: WebSocket-based live TVL, APY, and utilization metrics
4. **💰 Native Token Efficiency**: Direct STT handling reduces gas costs vs ERC-20
5. **🔮 Fresh Price Data**: DIA Oracle integration with 120-second refresh cycles
6. **🚫 MEV Resistance**: Sub-second finality reduces front-running opportunities
7. **🎮 Gamified Experience**: Real-time rewards, leaderboards, and achievement systems
8. **🆓 Gasless Onboarding**: Account abstraction for seamless user experience

---

## 📝 Conclusion

Somnia Network provides the perfect foundation for building **next-generation DeFi protocols** like HyperLend. The combination of:

- **1M+ TPS performance** for handling viral application scale
- **Sub-second finality** for instant liquidations and responses
- **Native STT integration** for simplified token mechanics
- **Real-time capabilities** for live metrics and user experience
- **Account abstraction** for gasless transactions
- **Oracle integration** for reliable price feeds

Makes Somnia the ideal choice for **high-performance lending protocols** that can compete with centralized exchanges while maintaining full decentralization.

The extensive documentation, developer tooling, and production-ready infrastructure ensure that HyperLend can leverage all of Somnia's capabilities to deliver an unparalleled lending experience to users worldwide.

---

_This comprehensive guide covers all aspects of Somnia Network development based on extensive documentation review. For the latest updates and additional resources, visit the official Somnia documentation and community channels._
