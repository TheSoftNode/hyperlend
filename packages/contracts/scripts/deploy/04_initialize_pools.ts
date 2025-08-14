import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { loadDeploymentData, saveDeploymentData } from "../utils/helpers";
import { POOL_INITIALIZATION_CONFIG } from "../utils/constants";

const initializePools: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { getNamedAccounts, network } = hre;
  const { deployer, admin } = await getNamedAccounts();

  console.log("🏊 Initializing HyperLend Pools...");
  console.log("Network:", network.name);
  console.log("Admin:", admin);

  // Load deployment data
  const deploymentData = await loadDeploymentData(network.name);
  if (!deploymentData || !deploymentData.configuration) {
    throw new Error("System not configured. Run configure:system script first.");
  }

  const config = POOL_INITIALIZATION_CONFIG[network.name] || POOL_INITIALIZATION_CONFIG.default;

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONNECT TO CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n📡 Connecting to contracts...");

  const hyperLendPool = await ethers.getContractAt("HyperLendPool", deploymentData.contracts.HyperLendPool);
  const priceOracle = await ethers.getContractAt("PriceOracle", deploymentData.contracts.PriceOracle);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INITIALIZE LIQUIDITY POOLS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n💧 Initializing Liquidity Pools...");

  if (!deploymentData.tokens?.testTokens || !deploymentData.tokens?.marketTokens) {
    throw new Error("Test tokens not found. Run deploy:tokens script first.");
  }

  const poolsInitialized = [];

  for (const [symbol, tokenAddress] of Object.entries(deploymentData.tokens.testTokens)) {
    const marketTokens = deploymentData.tokens.marketTokens[symbol];
    
    if (!marketTokens) {
      console.log(`  ⚠️  Market tokens not found for ${symbol}, skipping...`);
      continue;
    }

    console.log(`\n  🏊 Initializing ${symbol} pool...`);

    try {
      // Check if market is already listed
      const isListed = await hyperLendPool.isMarketListed(tokenAddress);
      
      if (isListed) {
        console.log(`    ✓ ${symbol} market already listed`);
        
        // Check market data
        const marketData = await hyperLendPool.getMarketData(tokenAddress);
        console.log(`      Total Supply: ${ethers.formatEther(marketData.totalSupply)}`);
        console.log(`      Total Borrow: ${ethers.formatEther(marketData.totalBorrow)}`);
        console.log(`      Utilization: ${ethers.formatEther(marketData.utilizationRate)}%`);
        
        poolsInitialized.push({
          symbol,
          address: tokenAddress,
          hlToken: marketTokens.hlToken,
          debtToken: marketTokens.debtToken,
          status: "already_listed"
        });
        
        continue;
      }

      // Get pool configuration for this asset
      const poolConfig = config.pools[symbol] || config.pools.default;

      console.log(`    📋 Pool configuration for ${symbol}:`);
      console.log(`      Liquidation Threshold: ${poolConfig.liquidationThreshold}%`);
      console.log(`      Liquidation Bonus: ${poolConfig.liquidationBonus}%`);
      console.log(`      Supply Cap: ${poolConfig.supplyCap}`);
      console.log(`      Borrow Cap: ${poolConfig.borrowCap}`);

      // Add market to pool
      const tx = await hyperLendPool.addMarket(
        tokenAddress,
        marketTokens.hlToken,
        marketTokens.debtToken,
        ethers.parseEther((poolConfig.liquidationThreshold / 100).toString()),
        ethers.parseEther((poolConfig.liquidationBonus / 100).toString()),
        ethers.parseEther(poolConfig.borrowCap.toString()),
        ethers.parseEther(poolConfig.supplyCap.toString())
      );

      console.log(`    ⏳ Adding ${symbol} market to pool...`);
      const receipt = await tx.wait();
      console.log(`    ✅ ${symbol} market added successfully!`);
      console.log(`      Transaction: ${receipt.hash}`);
      console.log(`      Gas Used: ${receipt.gasUsed.toString()}`);

      // Verify market was added correctly
      const isNowListed = await hyperLendPool.isMarketListed(tokenAddress);
      if (!isNowListed) {
        throw new Error(`Market listing verification failed for ${symbol}`);
      }

      // Get initial market data
      const initialMarketData = await hyperLendPool.getMarketData(tokenAddress);
      console.log(`    📊 Initial market state:`);
      console.log(`      Supply APY: ${ethers.formatEther(initialMarketData.supplyAPY)}%`);
      console.log(`      Borrow APY: ${ethers.formatEther(initialMarketData.borrowAPY)}%`);
      console.log(`      Utilization: ${ethers.formatEther(initialMarketData.utilizationRate)}%`);

      poolsInitialized.push({
        symbol,
        address: tokenAddress,
        hlToken: marketTokens.hlToken,
        debtToken: marketTokens.debtToken,
        status: "newly_added",
        transactionHash: receipt.hash,
        gasUsed: receipt.gasUsed.toString()
      });

    } catch (error) {
      console.log(`    ❌ Failed to initialize ${symbol} pool:`, error.message);
      
      poolsInitialized.push({
        symbol,
        address: tokenAddress,
        status: "failed",
        error: error.message
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INITIALIZE SAMPLE LIQUIDITY (TESTNET ONLY)
  // ═══════════════════════════════════════════════════════════════════════════════════

  if (!network.live || network.name.includes("test")) {
    console.log("\n💰 Adding Initial Liquidity (Testnet Only)...");

    // Get signers for initial liquidity
    const signers = await ethers.getSigners();
    const liquidityProvider = signers[0]; // Use deployer as liquidity provider

    for (const [symbol, tokenAddress] of Object.entries(deploymentData.tokens.testTokens)) {
      if (!poolsInitialized.find(p => p.symbol === symbol && p.status !== "failed")) {
        continue;
      }

      const liquidityConfig = config.initialLiquidity[symbol];
      if (!liquidityConfig) {
        console.log(`    ⚠️  No liquidity config for ${symbol}, skipping...`);
        continue;
      }

      console.log(`\n  💧 Adding initial liquidity for ${symbol}...`);

      try {
        // Get token contract
        const token = await ethers.getContractAt("MockERC20", tokenAddress);
        
        // Check if liquidity provider has enough tokens
        const balance = await token.balanceOf(liquidityProvider.address);
        const requiredAmount = ethers.parseEther(liquidityConfig.amount.toString());
        
        if (balance < requiredAmount) {
          console.log(`    🪙 Minting ${liquidityConfig.amount} ${symbol} for liquidity...`);
          await token.mint(liquidityProvider.address, requiredAmount);
        }

        // Approve tokens for pool
        console.log(`    ✅ Approving ${liquidityConfig.amount} ${symbol}...`);
        await token.approve(hyperLendPool.target, requiredAmount);

        // Supply tokens to pool
        console.log(`    🏦 Supplying ${liquidityConfig.amount} ${symbol} to pool...`);
        const supplyTx = await hyperLendPool.supply(tokenAddress, requiredAmount);
        const supplyReceipt = await supplyTx.wait();
        
        console.log(`    ✅ Initial liquidity added for ${symbol}!`);
        console.log(`      Amount: ${liquidityConfig.amount} ${symbol}`);
        console.log(`      Transaction: ${supplyReceipt.hash}`);

        // Update pool data
        const updatedMarketData = await hyperLendPool.getMarketData(tokenAddress);
        console.log(`    📊 Updated market state:`);
        console.log(`      Total Supply: ${ethers.formatEther(updatedMarketData.totalSupply)}`);
        console.log(`      Supply APY: ${ethers.formatEther(updatedMarketData.supplyAPY)}%`);

      } catch (error) {
        console.log(`    ❌ Failed to add liquidity for ${symbol}:`, error.message);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SYSTEM HEALTH CHECK
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🔍 Performing System Health Check...");

  try {
    // Check real-time metrics
    const metrics = await hyperLendPool.getRealTimeMetrics();
    console.log(`  📊 System Metrics:`);
    console.log(`    Total Value Locked: $${ethers.formatEther(metrics.tvl)}`);
    console.log(`    Total Borrowed: $${ethers.formatEther(metrics.borrowed)}`);
    console.log(`    Overall Utilization: ${ethers.formatEther(metrics.utilization)}%`);
    console.log(`    Average Supply APY: ${ethers.formatEther(metrics.avgSupplyAPY)}%`);
    console.log(`    Average Borrow APY: ${ethers.formatEther(metrics.avgBorrowAPY)}%`);

    // Check market list
    const marketList = [];
    for (let i = 0; ; i++) {
      try {
        const market = await hyperLendPool.marketList(i);
        marketList.push(market);
      } catch {
        break;
      }
    }
    console.log(`  📋 Active Markets: ${marketList.length}`);

    // Test interest rate updates
    console.log(`  ⚡ Testing real-time updates...`);
    const updateTx = await hyperLendPool.batchUpdateInterest(marketList);
    await updateTx.wait();
    console.log(`    ✅ Interest rates updated successfully`);

    // Test price oracle
    console.log(`  📊 Testing price oracle...`);
    if (marketList.length > 0) {
      const price = await priceOracle.getPrice(marketList[0]);
      console.log(`    ✅ Price retrieved: $${ethers.formatEther(price)}`);
    }

  } catch (error) {
    console.log(`  ❌ Health check failed:`, error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SAVE INITIALIZATION DATA
  // ═══════════════════════════════════════════════════════════════════════════════════

  const initializationData = {
    network: network.name,
    timestamp: new Date().toISOString(),
    blockNumber: await ethers.provider.getBlockNumber(),
    poolsInitialized,
    totalPoolsCreated: poolsInitialized.filter(p => p.status === "newly_added" || p.status === "already_listed").length,
    failedPools: poolsInitialized.filter(p => p.status === "failed").length,
    initialLiquidityAdded: !network.live || network.name.includes("test"),
    systemMetrics: {
      tvl: "0", // Will be updated with actual values
      totalBorrowed: "0",
      utilization: "0",
      activeMarkets: poolsInitialized.filter(p => p.status !== "failed").length
    }
  };

  // Get actual system metrics if available
  try {
    const metrics = await hyperLendPool.getRealTimeMetrics();
    initializationData.systemMetrics = {
      tvl: ethers.formatEther(metrics.tvl),
      totalBorrowed: ethers.formatEther(metrics.borrowed),
      utilization: ethers.formatEther(metrics.utilization),
      activeMarkets: poolsInitialized.filter(p => p.status !== "failed").length
    };
  } catch (error) {
    console.log("  ⚠️  Could not retrieve system metrics for storage");
  }

  // Merge with existing deployment data
  const updatedDeployment = {
    ...deploymentData,
    initialization: initializationData,
    lastInitialized: new Date().toISOString(),
  };

  await saveDeploymentData(updatedDeployment, network.name);
  console.log("✅ Initialization data saved");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CREATE TESTING SCENARIOS (TESTNET ONLY)
  // ═══════════════════════════════════════════════════════════════════════════════════

  if (!network.live || network.name.includes("test")) {
    console.log("\n🧪 Setting up Testing Scenarios...");

    try {
      // Create test borrowing scenario
      const testAccounts = await ethers.getSigners();
      const borrower = testAccounts[1]; // Use second account as borrower

      if (deploymentData.tokens.testTokens.TWETH && deploymentData.tokens.testTokens.TUSDC) {
        const weth = await ethers.getContractAt("MockERC20", deploymentData.tokens.testTokens.TWETH);
        const usdc = await ethers.getContractAt("MockERC20", deploymentData.tokens.testTokens.TUSDC);

        // Give borrower some WETH for collateral
        console.log("  🏗️  Setting up borrowing scenario...");
        await weth.mint(borrower.address, ethers.parseEther("10")); // 10 WETH
        
        // Borrower supplies WETH as collateral
        await weth.connect(borrower).approve(hyperLendPool.target, ethers.parseEther("5"));
        await hyperLendPool.connect(borrower).supply(deploymentData.tokens.testTokens.TWETH, ethers.parseEther("5"));
        
        // Borrower borrows USDC
        await hyperLendPool.connect(borrower).borrow(deploymentData.tokens.testTokens.TUSDC, ethers.parseEther("5000"));
        
        console.log("    ✅ Test borrowing scenario created");
        console.log("      Borrower supplied: 5 WETH");
        console.log("      Borrower borrowed: 5000 USDC");

        // Check borrower's health factor
        const userData = await hyperLendPool.getUserAccountData(borrower.address);
        console.log(`      Health Factor: ${ethers.formatEther(userData.healthFactor)}`);
      }

    } catch (error) {
      console.log("  ⚠️  Failed to create testing scenarios:", error.message);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // FINAL SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🎉 POOL INITIALIZATION COMPLETED! 🎉");
  console.log("==========================================");
  console.log("Network:", network.name);
  console.log("==========================================");
  console.log("📊 Summary:");
  console.log(`  ✅ Pools Successfully Initialized: ${poolsInitialized.filter(p => p.status !== "failed").length}`);
  console.log(`  ❌ Failed Pool Initializations: ${poolsInitialized.filter(p => p.status === "failed").length}`);
  console.log(`  💧 Initial Liquidity Added: ${!network.live || network.name.includes("test") ? "Yes" : "No"}`);
  console.log("==========================================");
  console.log("🏊 Active Pools:");
  
  poolsInitialized.forEach(pool => {
    const status = pool.status === "newly_added" ? "🆕" : 
                  pool.status === "already_listed" ? "✅" : "❌";
    console.log(`  ${status} ${pool.symbol} - ${pool.address}`);
    if (pool.hlToken) {
      console.log(`      hlToken: ${pool.hlToken}`);
      console.log(`      debtToken: ${pool.debtToken}`);
    }
  });

  console.log("==========================================");
  console.log("🔧 Next steps:");
  console.log("  1. Run: npm run test:integration");
  console.log("  2. Run: npm run test:liquidation");
  console.log("  3. Start frontend: npm run dev");
  console.log("  4. Begin testing user flows");
  console.log("==========================================");
  
  if (network.name === "localhost" || network.name === "hardhat") {
    console.log("💡 Ready for Development:");
    console.log("  - All pools are initialized and funded");
    console.log("  - Test borrowing scenario is set up");
    console.log("  - System is ready for frontend integration");
    console.log("  - Use test accounts for different user flows");
  } else if (network.name.includes("somnia")) {
    console.log("🌐 Somnia Testnet Ready:");
    console.log("  - Verify all pools on block explorer");
    console.log("  - Test real-time features with high TPS");
    console.log("  - Monitor liquidation engine performance");
    console.log("  - Prepare for mainnet deployment");
  }
  
  console.log("==========================================");
  
  return true;
};

export default initializePools;
initializePools.tags = ["Initialize", "Pools", "HyperLend"];
initializePools.dependencies = ["Core", "Tokens", "Configure"];