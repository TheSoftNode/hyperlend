import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { loadDeploymentData, saveDeploymentData } from "../utils/helpers";
import { SYSTEM_CONFIG } from "../utils/constants";

const configureSystem: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { getNamedAccounts, network } = hre;
  const { deployer, admin } = await getNamedAccounts();

  console.log("⚙️  Configuring HyperLend System...");
  console.log("Network:", network.name);
  console.log("Admin:", admin);

  // Load deployment data
  const deploymentData = await loadDeploymentData(network.name);
  if (!deploymentData) {
    throw new Error("Deployment data not found. Run deploy scripts first.");
  }

  const config = SYSTEM_CONFIG[network.name] || SYSTEM_CONFIG.default;

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONNECT TO CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n📡 Connecting to contracts...");

  const hyperLendPool = await ethers.getContractAt("HyperLendPool", deploymentData.contracts.HyperLendPool);
  const interestRateModel = await ethers.getContractAt("InterestRateModel", deploymentData.contracts.InterestRateModel);
  const liquidationEngine = await ethers.getContractAt("LiquidationEngine", deploymentData.contracts.LiquidationEngine);
  const priceOracle = await ethers.getContractAt("PriceOracle", deploymentData.contracts.PriceOracle);
  const riskManager = await ethers.getContractAt("RiskManager", deploymentData.contracts.RiskManager);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE INTEREST RATE MODEL
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n💹 Configuring Interest Rate Model...");

  // Set custom parameters for specific assets if defined
  if (config.assetSpecificRates) {
    for (const [assetSymbol, rateConfig] of Object.entries(config.assetSpecificRates)) {
      if (deploymentData.tokens?.testTokens?.[assetSymbol]) {
        const assetAddress = deploymentData.tokens.testTokens[assetSymbol];
        
        console.log(`  Setting custom rates for ${assetSymbol}...`);
        
        try {
          const tx = await interestRateModel.setInterestRateParams(
            assetAddress,
            ethers.parseEther(rateConfig.baseRate.toString()),
            ethers.parseEther(rateConfig.multiplier.toString()),
            ethers.parseEther(rateConfig.jumpMultiplier.toString()),
            ethers.parseEther(rateConfig.kink.toString())
          );
          
          await tx.wait();
          console.log(`    ✓ Custom rates set for ${assetSymbol}`);
        } catch (error) {
          console.log(`    ⚠️  Failed to set rates for ${assetSymbol}:`, error.message);
        }
      }
    }
  }

  // Grant rate updater role to pool
  try {
    const hasRole = await interestRateModel.hasRole(
      await interestRateModel.RATE_UPDATER_ROLE(),
      hyperLendPool.target
    );
    
    if (!hasRole) {
      console.log("  Granting RATE_UPDATER_ROLE to pool...");
      await interestRateModel.grantRateUpdaterRole(hyperLendPool.target);
      console.log("    ✓ Role granted");
    } else {
      console.log("    ✓ Pool already has RATE_UPDATER_ROLE");
    }
  } catch (error) {
    console.log("    ⚠️  Failed to grant rate updater role:", error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE PRICE ORACLE
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n📊 Configuring Price Oracle...");

  // Set emergency prices for test tokens
  if (deploymentData.tokens?.testTokens) {
    const emergencyPrices = config.emergencyPrices || {
      TUSDC: "1",
      TWETH: "2000",
      TBTC: "45000",
      TLINK: "15",
      TUNI: "8"
    };

    for (const [symbol, address] of Object.entries(deploymentData.tokens.testTokens)) {
      if (emergencyPrices[symbol]) {
        console.log(`  Setting emergency price for ${symbol}...`);
        
        try {
          const tx = await priceOracle.setEmergencyPrice(
            address,
            ethers.parseEther(emergencyPrices[symbol]),
            `Initial ${symbol} price for testing`
          );
          
          await tx.wait();
          console.log(`    ✓ ${symbol} price set to $${emergencyPrices[symbol]}`);
        } catch (error) {
          console.log(`    ⚠️  Failed to set price for ${symbol}:`, error.message);
        }
      }
    }
  }

  // Configure circuit breakers
  console.log("  Setting up circuit breakers...");
  if (deploymentData.tokens?.testTokens) {
    for (const [symbol, address] of Object.entries(deploymentData.tokens.testTokens)) {
      try {
        await priceOracle.setCircuitBreaker(
          address,
          true, // enabled
          ethers.parseEther("0.2") // 20% threshold
        );
        console.log(`    ✓ Circuit breaker set for ${symbol}`);
      } catch (error) {
        console.log(`    ⚠️  Failed to set circuit breaker for ${symbol}:`, error.message);
      }
    }
  }

  // Grant price updater role to admin for testing
  try {
    const hasRole = await priceOracle.hasRole(
      await priceOracle.PRICE_UPDATER_ROLE(),
      admin
    );
    
    if (!hasRole) {
      await priceOracle.grantPriceUpdaterRole(admin);
      console.log("    ✓ PRICE_UPDATER_ROLE granted to admin");
    }
  } catch (error) {
    console.log("    ⚠️  Failed to grant price updater role:", error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE RISK MANAGER
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n⚠️  Configuring Risk Manager...");

  // Set risk parameters for each asset
  if (deploymentData.tokens?.testTokens) {
    const riskParams = config.riskParameters || {
      TUSDC: {
        liquidationThreshold: "0.95", // 95%
        liquidationBonus: "0.05",     // 5%
        borrowFactor: "0.90"          // 90%
      },
      TWETH: {
        liquidationThreshold: "0.85", // 85%
        liquidationBonus: "0.08",     // 8%
        borrowFactor: "0.80"          // 80%
      },
      TBTC: {
        liquidationThreshold: "0.80", // 80%
        liquidationBonus: "0.10",     // 10%
        borrowFactor: "0.75"          // 75%
      },
      TLINK: {
        liquidationThreshold: "0.75", // 75%
        liquidationBonus: "0.12",     // 12%
        borrowFactor: "0.70"          // 70%
      },
      TUNI: {
        liquidationThreshold: "0.70", // 70%
        liquidationBonus: "0.15",     // 15%
        borrowFactor: "0.65"          // 65%
      }
    };

    for (const [symbol, address] of Object.entries(deploymentData.tokens.testTokens)) {
      if (riskParams[symbol]) {
        console.log(`  Setting risk parameters for ${symbol}...`);
        
        try {
          const params = riskParams[symbol];
          const tx = await riskManager.setRiskParameters(
            address,
            ethers.parseEther(params.liquidationThreshold),
            ethers.parseEther(params.liquidationBonus),
            ethers.parseEther(params.borrowFactor)
          );
          
          await tx.wait();
          console.log(`    ✓ Risk parameters set for ${symbol}`);
        } catch (error) {
          console.log(`    ⚠️  Failed to set risk parameters for ${symbol}:`, error.message);
        }
      }
    }
  }

  // Set supply and borrow caps
  console.log("  Setting supply and borrow caps...");
  if (deploymentData.tokens?.testTokens) {
    const caps = config.caps || {
      TUSDC: { supply: "10000000", borrow: "8000000" }, // 10M supply, 8M borrow
      TWETH: { supply: "5000", borrow: "4000" },        // 5K supply, 4K borrow
      TBTC: { supply: "1000", borrow: "800" },          // 1K supply, 800 borrow
      TLINK: { supply: "1000000", borrow: "800000" },   // 1M supply, 800K borrow
      TUNI: { supply: "1000000", borrow: "800000" }     // 1M supply, 800K borrow
    };

    for (const [symbol, address] of Object.entries(deploymentData.tokens.testTokens)) {
      if (caps[symbol]) {
        try {
          const cap = caps[symbol];
          await riskManager.setCaps(
            address,
            ethers.parseEther(cap.supply),
            ethers.parseEther(cap.borrow)
          );
          console.log(`    ✓ Caps set for ${symbol}: ${cap.supply}/${cap.borrow}`);
        } catch (error) {
          console.log(`    ⚠️  Failed to set caps for ${symbol}:`, error.message);
        }
      }
    }
  }

  // Grant pool role to hyperLendPool
  try {
    const hasRole = await riskManager.hasRole(
      await riskManager.POOL_ROLE(),
      hyperLendPool.target
    );
    
    if (!hasRole) {
      await riskManager.grantRole(
        await riskManager.POOL_ROLE(),
        hyperLendPool.target
      );
      console.log("    ✓ POOL_ROLE granted to HyperLendPool");
    }
  } catch (error) {
    console.log("    ⚠️  Failed to grant pool role:", error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE LIQUIDATION ENGINE
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n⚡ Configuring Liquidation Engine...");

  // Set liquidation parameters for each asset
  if (deploymentData.tokens?.testTokens) {
    for (const [symbol, address] of Object.entries(deploymentData.tokens.testTokens)) {
      console.log(`  Setting liquidation parameters for ${symbol}...`);
      
      try {
        // Get risk parameters first
        const riskParams = config.riskParameters?.[symbol] || {
          liquidationThreshold: "0.85",
          liquidationBonus: "0.05"
        };
        
        await liquidationEngine.setLiquidationParams(
          address,
          ethers.parseEther(riskParams.liquidationThreshold),
          ethers.parseEther(riskParams.liquidationBonus),
          ethers.parseEther("0.5") // 50% max liquidation ratio
        );
        
        console.log(`    ✓ Liquidation parameters set for ${symbol}`);
      } catch (error) {
        console.log(`    ⚠️  Failed to set liquidation parameters for ${symbol}:`, error.message);
      }
    }
  }

  // Enable micro-liquidations
  try {
    await liquidationEngine.setMicroLiquidationEnabled(true);
    console.log("    ✓ Micro-liquidations enabled");
  } catch (error) {
    console.log("    ⚠️  Failed to enable micro-liquidations:", error.message);
  }

  // Grant liquidator role to admin for testing
  try {
    const hasRole = await liquidationEngine.hasRole(
      await liquidationEngine.LIQUIDATOR_ROLE(),
      admin
    );
    
    if (!hasRole) {
      await liquidationEngine.grantRole(
        await liquidationEngine.LIQUIDATOR_ROLE(),
        admin
      );
      console.log("    ✓ LIQUIDATOR_ROLE granted to admin");
    }
  } catch (error) {
    console.log("    ⚠️  Failed to grant liquidator role:", error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE HYPERLEND POOL
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🏦 Configuring HyperLend Pool...");

  // Grant liquidator role to liquidation engine
  try {
    const hasRole = await hyperLendPool.hasRole(
      await hyperLendPool.LIQUIDATOR_ROLE(),
      liquidationEngine.target
    );
    
    if (!hasRole) {
      await hyperLendPool.grantRole(
        await hyperLendPool.LIQUIDATOR_ROLE(),
        liquidationEngine.target
      );
      console.log("    ✓ LIQUIDATOR_ROLE granted to liquidation engine");
    }
  } catch (error) {
    console.log("    ⚠️  Failed to grant liquidator role to engine:", error.message);
  }

  // Verify all contracts are properly connected
  console.log("  Verifying contract connections...");
  
  try {
    const poolInterestRateModel = await hyperLendPool.interestRateModel();
    const poolLiquidationEngine = await hyperLendPool.liquidationEngine();
    const poolPriceOracle = await hyperLendPool.priceOracle();
    const poolRiskManager = await hyperLendPool.riskManager();
    
    console.log("    ✓ Interest Rate Model:", poolInterestRateModel === deploymentData.contracts.InterestRateModel ? "✓" : "✗");
    console.log("    ✓ Liquidation Engine:", poolLiquidationEngine === deploymentData.contracts.LiquidationEngine ? "✓" : "✗");
    console.log("    ✓ Price Oracle:", poolPriceOracle === deploymentData.contracts.PriceOracle ? "✓" : "✗");
    console.log("    ✓ Risk Manager:", poolRiskManager === deploymentData.contracts.RiskManager ? "✓" : "✗");
  } catch (error) {
    console.log("    ⚠️  Failed to verify connections:", error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE TOKEN CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🪙 Configuring Token Contracts...");

  if (deploymentData.tokens?.marketTokens) {
    for (const [symbol, tokens] of Object.entries(deploymentData.tokens.marketTokens)) {
      console.log(`  Configuring tokens for ${symbol}...`);
      
      try {
        // Configure HLToken
        const hlToken = await ethers.getContractAt("HLToken", tokens.hlToken);
        
        // Grant minter/burner roles to pool if not already granted
        const hasMinterRole = await hlToken.hasRole(await hlToken.MINTER_ROLE(), hyperLendPool.target);
        const hasBurnerRole = await hlToken.hasRole(await hlToken.BURNER_ROLE(), hyperLendPool.target);
        
        if (!hasMinterRole) {
          await hlToken.grantRole(await hlToken.MINTER_ROLE(), hyperLendPool.target);
          console.log(`    ✓ MINTER_ROLE granted to pool for hl${symbol}`);
        }
        
        if (!hasBurnerRole) {
          await hlToken.grantRole(await hlToken.BURNER_ROLE(), hyperLendPool.target);
          console.log(`    ✓ BURNER_ROLE granted to pool for hl${symbol}`);
        }
        
        // Configure DebtToken
        const debtToken = await ethers.getContractAt("DebtToken", tokens.debtToken);
        
        const hasDebtMinterRole = await debtToken.hasRole(await debtToken.MINTER_ROLE(), hyperLendPool.target);
        const hasDebtBurnerRole = await debtToken.hasRole(await debtToken.BURNER_ROLE(), hyperLendPool.target);
        
        if (!hasDebtMinterRole) {
          await debtToken.grantRole(await debtToken.MINTER_ROLE(), hyperLendPool.target);
          console.log(`    ✓ MINTER_ROLE granted to pool for debt${symbol}`);
        }
        
        if (!hasDebtBurnerRole) {
          await debtToken.grantRole(await debtToken.BURNER_ROLE(), hyperLendPool.target);
          console.log(`    ✓ BURNER_ROLE granted to pool for debt${symbol}`);
        }
        
      } catch (error) {
        console.log(`    ⚠️  Failed to configure tokens for ${symbol}:`, error.message);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SAVE CONFIGURATION DATA
  // ═══════════════════════════════════════════════════════════════════════════════════

  const configurationData = {
    network: network.name,
    timestamp: new Date().toISOString(),
    blockNumber: await ethers.provider.getBlockNumber(),
    configuration: {
      interestRateModel: {
        defaultParams: config.interestRateModel,
        assetSpecificRates: config.assetSpecificRates || {}
      },
      priceOracle: {
        emergencyPrices: config.emergencyPrices || {},
        circuitBreakers: true
      },
      riskManager: {
        riskParameters: config.riskParameters || {},
        caps: config.caps || {}
      },
      liquidationEngine: {
        microLiquidationsEnabled: true,
        liquidationParams: config.riskParameters || {}
      }
    },
    rolesGranted: {
      interestRateModel: ["RATE_UPDATER_ROLE to pool"],
      priceOracle: ["PRICE_UPDATER_ROLE to admin"],
      riskManager: ["POOL_ROLE to pool"],
      liquidationEngine: ["LIQUIDATOR_ROLE to admin"],
      hyperLendPool: ["LIQUIDATOR_ROLE to liquidation engine"],
      tokens: ["MINTER_ROLE and BURNER_ROLE to pool for all tokens"]
    }
  };

  // Merge with existing deployment data
  const updatedDeployment = {
    ...deploymentData,
    configuration: configurationData,
    lastConfigured: new Date().toISOString(),
  };

  await saveDeploymentData(updatedDeployment, network.name);
  console.log("✅ Configuration data saved");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SYSTEM VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🔍 Verifying System Configuration...");

  // Test price oracle functionality
  if (deploymentData.tokens?.testTokens?.TUSDC) {
    try {
      const usdcPrice = await priceOracle.getPrice(deploymentData.tokens.testTokens.TUSDC);
      console.log(`    ✓ USDC price: ${ethers.formatEther(usdcPrice)}`);
    } catch (error) {
      console.log("    ⚠️  Failed to get USDC price:", error.message);
    }
  }

  // Test interest rate calculation
  if (deploymentData.tokens?.testTokens?.TUSDC) {
    try {
      const rates = await interestRateModel.calculateRates(
        deploymentData.tokens.testTokens.TUSDC,
        ethers.parseEther("0.5"), // 50% utilization
        ethers.parseEther("1000000"), // 1M total supply
        ethers.parseEther("500000")   // 500K total borrow
      );
      console.log(`    ✓ USDC rates at 50% utilization:`);
      console.log(`      Supply APY: ${ethers.formatEther(rates[1])}%`);
      console.log(`      Borrow APY: ${ethers.formatEther(rates[0])}%`);
    } catch (error) {
      console.log("    ⚠️  Failed to calculate interest rates:", error.message);
    }
  }

  // Test risk manager
  try {
    const systemMetrics = await riskManager.getSystemRiskMetrics();
    console.log(`    ✓ System risk metrics retrieved`);
    console.log(`      Total Collateral: ${ethers.formatEther(systemMetrics[0])}`);
    console.log(`      Total Debt: ${ethers.formatEther(systemMetrics[1])}`);
  } catch (error) {
    console.log("    ⚠️  Failed to get system risk metrics:", error.message);
  }

  // Test liquidation engine
  try {
    const liquidationStats = await liquidationEngine.getLiquidationStats();
    console.log(`    ✓ Liquidation stats retrieved`);
    console.log(`      Total Liquidations: ${liquidationStats[0]}`);
    console.log(`      Total Volume: ${ethers.formatEther(liquidationStats[1])}`);
  } catch (error) {
    console.log("    ⚠️  Failed to get liquidation stats:", error.message);
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // FINAL SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🎉 SYSTEM CONFIGURATION COMPLETED! 🎉");
  console.log("==========================================");
  console.log("Network:", network.name);
  console.log("==========================================");
  console.log("✅ Configured Components:");
  console.log("  📈 Interest Rate Model - Custom rates and role permissions");
  console.log("  📊 Price Oracle - Emergency prices and circuit breakers");
  console.log("  ⚠️  Risk Manager - Asset parameters and caps");
  console.log("  ⚡ Liquidation Engine - Parameters and micro-liquidations");
  console.log("  🏦 HyperLend Pool - Role permissions and connections");
  console.log("  🪙 Token Contracts - Minting and burning permissions");
  console.log("==========================================");
  console.log("🔧 Next steps:");
  console.log("  1. Run: npm run initialize:pools");
  console.log("  2. Run: npm run test:integration");
  console.log("  3. Start frontend: npm run dev");
  console.log("==========================================");
  
  if (network.name === "localhost" || network.name === "hardhat") {
    console.log("💡 For local development:");
    console.log("  - All test tokens have been configured");
    console.log("  - Emergency prices have been set");
    console.log("  - System is ready for testing");
  } else if (network.name.includes("somnia")) {
    console.log("🌐 For Somnia testnet:");
    console.log("  - Verify all configurations on block explorer");
    console.log("  - Test basic operations before mainnet");
    console.log("  - Monitor system metrics dashboard");
  }
  
  console.log("==========================================");
  
  return true;
};

export default configureSystem;
configureSystem.tags = ["Configure", "System", "HyperLend"];
configureSystem.dependencies = ["Core", "Tokens"];