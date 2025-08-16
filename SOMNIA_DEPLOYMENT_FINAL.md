# HyperLend Somnia Deployment Guide & Best Practices

## 🎯 Summary of Somnia Documentation Analysis

After comprehensive review of all Somnia example applications and documentation, here are the key findings and recommendations for HyperLend:

### ✅ **Native STT Integration is Optimal**

**Why Native STT is the Best Choice:**

1. **Gas Efficiency**: Direct `msg.value` operations are cheaper than ERC20 transfers
2. **No Contract Address**: STT is native - no deployment overhead or complexity
3. **Universal Adoption**: All Somnia example apps (DAO, DEX, payments) use native STT
4. **Oracle Support**: DIA and Protofire oracles provide STT price feeds
5. **Account Abstraction Ready**: Native STT works seamlessly with sponsored transactions

**Evidence from Documentation:**

- **DAO Tutorial**: Uses native STT for voting power and deposits (`payable` functions)
- **DEX Tutorial**: Primary trading pairs are STT/Token, with native operations
- **Payment Systems**: Escrow, tips, payments all use `msg.value` patterns
- **VRF Integration**: Protofire Chainlink VRF accepts native STT payment
- **Token Balance App**: Focuses on ERC20 but STT balance is handled natively

### 🚫 **When NOT to Use Native STT**

Use ERC20 tokens only when you need:

- Complex tokenomics (staking, inflation, burning)
- Governance tokens with delegation beyond simple balance voting
- Cross-chain bridging requirements
- Advanced token features (pausable, mintable with supply caps)

### ⚡ **Somnia-Specific Optimizations Implemented**

1. **Native STT Functions**: `supplySTT()`, `borrowSTT()`, `repaySTT()`, `liquidateWithSTT()`
2. **DIA Oracle Integration**: Real-time STT pricing via `getValue("STT/USD")`
3. **Ultra-Fast Liquidations**: Optimized for 1M+ TPS and sub-second finality
4. **Account Abstraction Support**: Ready for sponsored/gasless transactions
5. **Real-Time Updates**: Leverage Somnia's speed for live interest rates

---

## 🚀 Deployment Steps

### Prerequisites

1. **Environment Setup**

```bash
# Install dependencies
cd packages/contracts
npm install

# Set up environment variables
cp .env.example .env
```

2. **Configure .env for Somnia**

```bash
# Somnia Network Configuration
SOMNIA_RPC_URL=https://rpc-testnet.somnia.network
SOMNIA_DEVNET_RPC_URL=https://rpc-devnet.somnia.network
PRIVATE_KEY=your_private_key_here

# Oracle Addresses (Somnia Testnet)
DIA_ORACLE_ADDRESS=0x9206296Ea3aEE3E6bdC07F7AaeF14DfCf33d865D
PROTOFIRE_VRF_ADDRESS=0x763cC914d5CA79B04dC4787aC14CcAd780a16BD2

# Explorer (for verification)
SOMNIA_EXPLORER_URL=http://shannon-explorer.somnia.network
ETHERSCAN_API_KEY=your_explorer_api_key

# Protocol Configuration
LIQUIDATION_THRESHOLD=850000000000000000  # 85%
LIQUIDATION_BONUS=50000000000000000      # 5%
SUPPLY_CAP=1000000000000000000000000     # 1M STT
BORROW_CAP=800000000000000000000000      # 800K STT
```

### Step 1: Compile Contracts

```bash
npx hardhat compile
```

### Step 2: Deploy to Somnia Testnet

```bash
# Deploy with optimized script
npx hardhat run scripts/deploy/deploy-hyperlend-somnia.ts --network somnia_testnet

# Or use the task
npx hardhat deploy-hyperlend --network somnia_testnet
```

### Step 3: Verify Deployment

The script will automatically:

1. Deploy all contracts with Somnia-optimized parameters
2. Configure native STT market
3. Set up DIA Oracle integration
4. Configure permissions and roles
5. Verify contracts on Shannon Explorer

### Step 4: Test Native STT Operations

```typescript
// Test script example
const hyperLendPool = await ethers.getContractAt(
  "HyperLendPool",
  DEPLOYED_ADDRESS
);

// Supply STT
await hyperLendPool.supplySTT({ value: ethers.utils.parseEther("100") });

// Borrow STT
await hyperLendPool.borrowSTT(ethers.utils.parseEther("50"));

// Repay STT
await hyperLendPool.repaySTT({ value: ethers.utils.parseEther("55") });
```

---

## 🔧 Key Integration Points

### 1. DIA Oracle Integration

```solidity
// Get STT price
(uint128 price, uint128 timestamp) = diaOracle.getValue("STT/USD");

// Multi-asset pricing
string[] memory keys = ["STT/USD", "BTC/USD", "USDC/USD"];
(uint128[] memory prices, uint128[] memory timestamps) = diaOracle.getValues(keys);
```

### 2. Native STT Operations

```solidity
// Supply native STT
function supplySTT() external payable {
    require(msg.value > 0, "Invalid STT amount");
    // Use msg.value for STT amount
    _updateSupply(NATIVE_STT, msg.value);
}

// Transfer STT
(bool success, ) = recipient.call{value: amount}("");
require(success, "STT transfer failed");
```

### 3. Account Abstraction Support

```typescript
// Sponsored transaction example
const sponsoredTx = await hyperLendPool.populateTransaction.supplySTT({
  value: ethers.utils.parseEther("100"),
});

// Submit via account abstraction service
await accountAbstractionService.submitSponsoredTransaction(sponsoredTx);
```

---

## 📊 Configuration Details

### Network Parameters

- **Chain ID**: 50312 (testnet), 50311 (devnet)
- **Block Time**: ~1 second
- **Finality**: Sub-second
- **TPS**: 1M+ capability
- **Gas Price**: Extremely low (sub-cent transactions)

### Protocol Parameters

```solidity
LIQUIDATION_THRESHOLD = 85e16;  // 85%
LIQUIDATION_BONUS = 5e16;       // 5%
MAX_UTILIZATION_RATE = 95e16;   // 95%
SUPPLY_CAP = 1e24;              // 1M STT
BORROW_CAP = 8e23;              // 800K STT
```

### Oracle Configuration

- **DIA Oracle**: `0x9206296Ea3aEE3E6bdC07F7AaeF14DfCf33d865D`
- **Update Frequency**: 120 seconds
- **Deviation Threshold**: 0.5%
- **Heartbeat**: 24 hours
- **Supported Assets**: STT, USDT, USDC, BTC, ARB, SOL

---

## 🔍 Verification & Testing

### Contract Verification

```bash
# Automatic verification during deployment
npx hardhat verify --network somnia_testnet DEPLOYED_ADDRESS

# Manual verification
npx hardhat verify --network somnia_testnet \
  --constructor-args arguments.js \
  DEPLOYED_ADDRESS
```

### Functional Testing

```bash
# Run comprehensive tests
npx hardhat test --network somnia_testnet

# Test specific features
npx hardhat test test/native-stt.test.ts --network somnia_testnet
npx hardhat test test/liquidation.test.ts --network somnia_testnet
npx hardhat test test/oracle-integration.test.ts --network somnia_testnet
```

### Performance Testing

```typescript
// Test high-frequency operations
for (let i = 0; i < 1000; i++) {
  await hyperLendPool.updateMarketInterest(NATIVE_STT);
  // Should execute in sub-second due to Somnia's speed
}
```

---

## 🎯 Post-Deployment Setup

### 1. Configure Additional Markets

```bash
# Add USDC market
npx hardhat add-market --asset USDC_ADDRESS --network somnia_testnet

# Add BTC market
npx hardhat add-market --asset WBTC_ADDRESS --network somnia_testnet
```

### 2. Set Up Liquidation Bots

```typescript
// Ultra-fast liquidation bot for Somnia
const liquidationBot = new SomniaLiquidationBot({
  hyperLendPool: DEPLOYED_ADDRESS,
  updateInterval: 1000, // 1 second (leverage Somnia's speed)
  gaslessTx: true, // Use account abstraction
});

await liquidationBot.start();
```

### 3. Monitor Real-Time Metrics

```typescript
// Real-time monitoring dashboard
const metrics = await hyperLendPool.getRealTimeMetrics();
console.log("TVL:", ethers.utils.formatEther(metrics.tvl), "USD");
console.log("Utilization:", metrics.utilization / 1e16, "%");
console.log("Avg Supply APY:", metrics.avgSupplyAPY / 1e16, "%");
```

---

## 🚨 Security Considerations

### 1. Native STT Handling

- ✅ Use `receive()` and `fallback()` functions carefully
- ✅ Always check return values of STT transfers
- ✅ Implement reentrancy protection for native transfers
- ✅ Handle refunds properly in payable functions

### 2. Oracle Security

- ✅ Use DIA Oracle's tamper-proof pricing
- ✅ Implement price staleness checks
- ✅ Add circuit breakers for extreme price movements
- ✅ Validate oracle responses before use

### 3. Liquidation Protection

- ✅ Implement rate limiting for liquidations
- ✅ Use Somnia's speed for near-instantaneous health factor updates
- ✅ Add MEV protection for liquidation transactions
- ✅ Implement batch liquidation safeguards

---

## 🔗 Integration Examples

### Frontend Integration

```typescript
// Native STT supply
const supplyTx = await hyperLendPool.supplySTT({
  value: ethers.utils.parseEther("100"),
});

// Real-time updates using Somnia's WebSocket
const provider = new ethers.providers.WebSocketProvider(
  "wss://ws-testnet.somnia.network"
);
provider.on("block", async (blockNumber) => {
  const metrics = await hyperLendPool.getRealTimeMetrics();
  updateDashboard(metrics);
});
```

### Account Abstraction Integration

```typescript
// Gasless transaction via Somnia's AA
const userOp = await createUserOperation({
  target: hyperLendPool.address,
  data: hyperLendPool.interface.encodeFunctionData("supplySTT"),
  value: ethers.utils.parseEther("100"),
});

await executeUserOperation(userOp);
```

---

## ✅ Success Criteria

Your HyperLend deployment is successful when:

1. **✅ Native STT Operations Work**

   - `supplySTT()` accepts STT deposits
   - `borrowSTT()` transfers STT to borrowers
   - `repaySTT()` accepts STT repayments with automatic refunds
   - `liquidateWithSTT()` processes liquidations with STT

2. **✅ DIA Oracle Integration Active**

   - STT price feeds updating every 120 seconds
   - Price staleness checks working
   - Multi-asset pricing operational

3. **✅ Real-Time Performance**

   - Interest rate updates processing in <1 second
   - Liquidation detection and execution <1 second
   - Dashboard updates reflecting sub-second finality

4. **✅ Account Abstraction Ready**
   - Contracts compatible with sponsored transactions
   - Gasless operations functional
   - User experience optimized for mass adoption

---

## 🎉 What Makes This Deployment Special

**Optimized for Somnia's Unique Capabilities:**

- **Native STT Support**: First-class integration with Somnia's native token
- **1M+ TPS Ready**: Architecture scales with Somnia's throughput
- **Sub-Second Finality**: Real-time lending protocol with instant updates
- **Ultra-Low Costs**: Micro-transactions enabled by Somnia's economics
- **Account Abstraction**: Ready for gasless, user-friendly interactions
- **Real-Time Oracles**: Leverage DIA's secure, frequent price updates

This deployment positions HyperLend as a next-generation lending protocol that fully leverages Somnia's revolutionary blockchain capabilities!
