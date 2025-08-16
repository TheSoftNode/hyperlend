# 🚀 HyperLend Deployment Guide - Somnia Hackathon

> **Complete deployment guide for Somnia testnet submission**

## 📋 Pre-Deployment Checklist

### ✅ Prerequisites
- [ ] Node.js 18+ installed
- [ ] pnpm or npm installed
- [ ] Git repository cloned
- [ ] Somnia testnet access
- [ ] Testnet tokens (from faucet)

### ✅ Environment Setup
- [ ] Copy `env.example` to `.env`
- [ ] Configure private key
- [ ] Set deployer address
- [ ] Verify network configuration

### ✅ Dependencies
- [ ] Run `pnpm install`
- [ ] Verify Hardhat installation
- [ ] Check OpenZeppelin contracts

## 🌐 Somnia Network Configuration

### Testnet Details
```typescript
Network: Somnia Testnet
Chain ID: 50312
RPC URL: https://testnet.somnia.network/
Block Explorer: https://testnet-explorer.somnia.network
Currency: STT (Somnia Test Token)
```

### Devnet Details
```typescript
Network: Somnia Devnet
Chain ID: 50311
RPC URL: https://devnet.somnia.network/
Block Explorer: https://devnet-explorer.somnia.network
Currency: SDT (Somnia Dev Token)
```

## 🚀 Deployment Steps

### Step 1: Environment Configuration

```bash
# Copy environment file
cp env.example .env

# Edit .env with your values
nano .env
```

**Required Environment Variables:**
```bash
# Somnia Network
SOMNIA_TESTNET_RPC=https://testnet.somnia.network/
SOMNIA_DEVNET_RPC=https://devnet.somnia.network/
SOMNIA_API_KEY=your_api_key_here

# Deployment
PRIVATE_KEY=your_private_key_here
DEPLOYER_ADDRESS=your_address_here
```

### Step 2: Compile Contracts

```bash
# Clean previous builds
pnpm run clean

# Compile contracts
pnpm run compile

# Verify compilation
ls artifacts/
```

### Step 3: Run Tests

```bash
# Run all tests
pnpm run test

# Run specific test categories
pnpm run test:unit
pnpm run test:integration
pnpm run test:fuzz

# Generate coverage report
pnpm run test:coverage
```

### Step 4: Deploy to Devnet (Optional)

```bash
# Deploy to devnet first for testing
pnpm run deploy:devnet
```

**Expected Output:**
```
🚀 Starting HyperLend Complete Deployment on Somnia Network
==========================================
Network: somnia-devnet
Deployer: 0x...
Admin: 0x...
==========================================

🎯 PHASE 1: Deploying Core Contracts
==========================================
📚 Deploying Libraries...
✅ Libraries deployed
  Math: 0x...
  SafeTransfer: 0x...

💹 Deploying Interest Rate Model...
✅ Interest Rate Model deployed: 0x...

📊 Deploying Price Oracle...
✅ Price Oracle deployed: 0x...

⚠️  Deploying Risk Manager...
✅ Risk Manager deployed: 0x...

⚡ Deploying Liquidation Engine...
✅ Liquidation Engine deployed: 0x...

🏦 Deploying HyperLend Pool...
✅ HyperLend Pool deployed: 0x...

🎯 PHASE 2: Deploying Token Contracts
==========================================
🪙 Deploying HL Token...
✅ HL Token deployed: 0x...

💳 Deploying Debt Token...
✅ Debt Token deployed: 0x...

🎁 Deploying Reward Token...
✅ Reward Token deployed: 0x...

🎯 PHASE 3: Configuring System
==========================================
🔧 Configuring HyperLend Pool...
✅ HyperLend Pool configured

🔧 Configuring Risk Manager...
✅ Risk Manager configured

🔧 Configuring Price Oracle...
✅ Price Oracle configured

🎯 PHASE 4: Initializing Markets
==========================================
🏪 Adding initial markets...
✅ Mock USDC market added: 0x...

🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!
==========================================
📋 Contract Addresses:
  HyperLend Pool: 0x...
  Interest Rate Model: 0x...
  Price Oracle: 0x...
  Risk Manager: 0x...
  Liquidation Engine: 0x...
  HL Token: 0x...
  Debt Token: 0x...
  Reward Token: 0x...
  Mock USDC: 0x...
==========================================
```

### Step 5: Deploy to Testnet (Hackathon Submission)

```bash
# Deploy to testnet for hackathon submission
pnpm run deploy:testnet
```

### Step 6: Verify Contracts

```bash
# Verify all contracts on block explorer
pnpm run verify:testnet
```

## 🔍 Post-Deployment Verification

### 1. Block Explorer Verification
- Visit [Somnia Testnet Explorer](https://testnet-explorer.somnia.network)
- Search for your deployed contracts
- Verify contract addresses match deployment output

### 2. Contract Interaction Test
```bash
# Start Hardhat console
pnpm run console --network somnia-testnet

# Test basic functionality
const pool = await ethers.getContractAt("HyperLendPool", "POOL_ADDRESS")
await pool.getRealTimeMetrics()
```

### 3. Frontend Integration
- Update frontend configuration with contract addresses
- Test wallet connection
- Verify basic operations (supply, borrow)

## 📊 Contract Addresses

After successful deployment, save these addresses:

```typescript
export const CONTRACT_ADDRESSES = {
  // Core Contracts
  HyperLendPool: "0x...",
  InterestRateModel: "0x...",
  PriceOracle: "0x...",
  RiskManager: "0x...",
  LiquidationEngine: "0x...",
  
  // Token Contracts
  HLToken: "0x...",
  DebtToken: "0x...",
  RewardToken: "0x...",
  MockUSDC: "0x...",
  
  // Libraries
  Math: "0x...",
  SafeTransfer: "0x...",
};
```

## 🧪 Testing Deployment

### Basic Functionality Tests

1. **Supply Assets**
   - Connect wallet
   - Approve token spending
   - Supply assets to pool
   - Verify HL token minting

2. **Borrow Assets**
   - Check collateral ratio
   - Borrow against collateral
   - Verify debt token minting

3. **Liquidation Test**
   - Create risky position
   - Trigger liquidation
   - Execute liquidation
   - Verify rewards distribution

### Advanced Tests

1. **Interest Rate Updates**
   - Monitor rate changes
   - Verify utilization impact
   - Check APY calculations

2. **Risk Management**
   - Test liquidation thresholds
   - Verify health factor updates
   - Check emergency pauses

## 🚨 Troubleshooting

### Common Issues

1. **Gas Estimation Failed**
   ```bash
   # Increase gas limit in hardhat.config.ts
   gas: 10000000
   ```

2. **Transaction Stuck**
   ```bash
   # Check network status
   # Increase gas price
   # Verify RPC endpoint
   ```

3. **Contract Verification Failed**
   ```bash
   # Check constructor arguments
   # Verify network configuration
   # Wait for block explorer sync
   ```

### Debug Commands

```bash
# Check network status
pnpm run node --network somnia-testnet

# View deployment logs
tail -f deployments/somnia-testnet.json

# Check contract size
pnpm run size
```

## 📝 Hackathon Submission Checklist

### ✅ Technical Requirements
- [ ] Smart contracts deployed on Somnia testnet
- [ ] All 5 core contracts functional
- [ ] Token contracts deployed and configured
- [ ] Basic functionality tested
- [ ] Gas optimization verified

### ✅ Documentation
- [ ] README.md completed
- [ ] Architecture diagram created
- [ ] API documentation ready
- [ ] Deployment guide finished

### ✅ Testing
- [ ] Unit tests passing
- [ ] Integration tests working
- [ ] Gas reports generated
- [ ] Security checks completed

### ✅ Frontend
- [ ] Basic UI implemented
- [ ] Wallet connection working
- [ ] Contract interaction functional
- [ ] Responsive design ready

## 🎯 Next Steps

### Immediate (This Week)
1. Deploy to Somnia testnet
2. Test all functionality
3. Create demo video
4. Prepare pitch deck

### Post-Hackathon
1. Community feedback integration
2. Advanced features development
3. Security audit preparation
4. Mainnet deployment planning

## 📞 Support

### Resources
- [Somnia Documentation](https://docs.somnia.network)
- [Somnia Discord](https://discord.gg/somnia)
- [Somnia Twitter](https://twitter.com/SomniaEco)

### Contact
- **Developer**: Theophilus Uchechukwu
- **Project**: [HyperLend GitHub](https://github.com/TheSoftNode/hyperlend)
- **Hackathon**: Somnia DeFi Mini Hackathon 2025

---

**Ready to win the Somnia hackathon with HyperLend! 🏆**
