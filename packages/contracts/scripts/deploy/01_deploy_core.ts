import { ethers, upgrades } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { verify } from "../utils/verification";
import { saveDeploymentData, getNetworkConfig } from "../utils/helpers";
import { DEPLOYMENT_CONFIG } from "../utils/constants";

const deployCore: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy } = deployments;
  const { deployer, admin } = await getNamedAccounts();

  console.log("🚀 Deploying HyperLend Core Contracts...");
  console.log("Network:", network.name);
  console.log("Deployer:", deployer);
  console.log("Admin:", admin);

  const networkConfig = getNetworkConfig(network.name);
  const config = DEPLOYMENT_CONFIG[network.name] || DEPLOYMENT_CONFIG.default;

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY LIBRARIES
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n📚 Deploying Libraries...");
  
  const mathLib = await deploy("Math", {
    from: deployer,
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  const safeTransferLib = await deploy("SafeTransfer", {
    from: deployer,
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  console.log("✅ Libraries deployed");
  console.log("  Math:", mathLib.address);
  console.log("  SafeTransfer:", safeTransferLib.address);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY INTEREST RATE MODEL
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n💹 Deploying Interest Rate Model...");
  
  const interestRateModel = await deploy("InterestRateModel", {
    from: deployer,
    args: [
      config.interestRateModel.baseRate,
      config.interestRateModel.multiplier,
      config.interestRateModel.kink,
      config.interestRateModel.jumpMultiplier,
    ],
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  console.log("✅ Interest Rate Model deployed:", interestRateModel.address);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY PRICE ORACLE
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n📊 Deploying Price Oracle...");
  
  const priceOracle = await deploy("PriceOracle", {
    from: deployer,
    args: [admin],
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  console.log("✅ Price Oracle deployed:", priceOracle.address);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY RISK MANAGER
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n⚠️  Deploying Risk Manager...");
  
  const riskManager = await deploy("RiskManager", {
    from: deployer,
    args: [
      config.riskManager.defaultLiquidationThreshold,
      config.riskManager.defaultLiquidationBonus,
      config.riskManager.maxLiquidationRatio,
    ],
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  console.log("✅ Risk Manager deployed:", riskManager.address);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY LIQUIDATION ENGINE
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n⚡ Deploying Liquidation Engine...");
  
  const liquidationEngine = await deploy("LiquidationEngine", {
    from: deployer,
    args: [priceOracle.address, riskManager.address],
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  console.log("✅ Liquidation Engine deployed:", liquidationEngine.address);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY HYPERLEND POOL (UPGRADEABLE)
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🏦 Deploying HyperLend Pool (Upgradeable)...");
  
  const HyperLendPool = await ethers.getContractFactory("HyperLendPool", {
    libraries: {
      Math: mathLib.address,
      SafeTransfer: safeTransferLib.address,
    },
  });

  const hyperLendPool = await upgrades.deployProxy(
    HyperLendPool,
    [
      admin,
      interestRateModel.address,
      liquidationEngine.address,
      priceOracle.address,
      riskManager.address,
    ],
    {
      kind: "uups",
      initializer: "initialize",
      unsafeAllow: ["external-library-linking"],
      timeout: 0,
    }
  );

  await hyperLendPool.waitForDeployment();
  const poolAddress = await hyperLendPool.getAddress();
  
  console.log("✅ HyperLend Pool deployed:", poolAddress);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n⚙️  Configuring contracts...");

  // Grant roles to the pool in other contracts
  const interestRateModelContract = await ethers.getContractAt("InterestRateModel", interestRateModel.address);
  const liquidationEngineContract = await ethers.getContractAt("LiquidationEngine", liquidationEngine.address);
  const riskManagerContract = await ethers.getContractAt("RiskManager", riskManager.address);

  // Grant RATE_UPDATER_ROLE to pool
  await interestRateModelContract.grantRateUpdaterRole(poolAddress);
  console.log("  ✓ Granted RATE_UPDATER_ROLE to pool");

  // Grant LIQUIDATOR_ROLE to admin for testing
  await liquidationEngineContract.grantRole(
    await liquidationEngineContract.LIQUIDATOR_ROLE(),
    admin
  );
  console.log("  ✓ Granted LIQUIDATOR_ROLE to admin");

  // Set initial liquidation parameters for default asset
  await liquidationEngineContract.setLiquidationParams(
    ethers.ZeroAddress, // Will be updated when assets are added
    config.riskManager.defaultLiquidationThreshold,
    config.riskManager.defaultLiquidationBonus,
    config.riskManager.maxLiquidationRatio
  );

  console.log("✅ Contract configuration completed");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SAVE DEPLOYMENT DATA
  // ═══════════════════════════════════════════════════════════════════════════════════

  const deploymentData = {
    network: network.name,
    chainId: network.config.chainId,
    timestamp: new Date().toISOString(),
    blockNumber: await ethers.provider.getBlockNumber(),
    gasPrice: (await ethers.provider.getFeeData()).gasPrice?.toString(),
    contracts: {
      // Libraries
      MathLib: mathLib.address,
      SafeTransferLib: safeTransferLib.address,
      
      // Core contracts
      InterestRateModel: interestRateModel.address,
      PriceOracle: priceOracle.address,
      RiskManager: riskManager.address,
      LiquidationEngine: liquidationEngine.address,
      HyperLendPool: poolAddress,
    },
    configuration: config,
    deployer,
    admin,
    transactionHashes: {
      mathLib: mathLib.transactionHash,
      safeTransferLib: safeTransferLib.transactionHash,
      interestRateModel: interestRateModel.transactionHash,
      priceOracle: priceOracle.transactionHash,
      riskManager: riskManager.transactionHash,
      liquidationEngine: liquidationEngine.transactionHash,
    },
  };

  await saveDeploymentData(deploymentData, network.name);
  console.log("✅ Deployment data saved");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // VERIFY CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  if (network.live && process.env.VERIFY_CONTRACTS === "true") {
    console.log("\n🔍 Verifying contracts...");
    
    try {
      await verify(interestRateModel.address, [
        config.interestRateModel.baseRate,
        config.interestRateModel.multiplier,
        config.interestRateModel.kink,
        config.interestRateModel.jumpMultiplier,
      ]);
      console.log("  ✓ InterestRateModel verified");
      
      await verify(priceOracle.address, [admin]);
      console.log("  ✓ PriceOracle verified");
      
      await verify(riskManager.address, [
        config.riskManager.defaultLiquidationThreshold,
        config.riskManager.defaultLiquidationBonus,
        config.riskManager.maxLiquidationRatio,
      ]);
      console.log("  ✓ RiskManager verified");
      
      await verify(liquidationEngine.address, [
        priceOracle.address,
        riskManager.address,
      ]);
      console.log("  ✓ LiquidationEngine verified");
      
      // Note: Proxy contracts need special verification
      console.log("  ⚠️  HyperLendPool proxy verification requires manual process");
      
    } catch (error) {
      console.log("  ⚠️  Verification failed:", error.message);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉");
  console.log("==========================================");
  console.log("Network:", network.name);
  console.log("Chain ID:", network.config.chainId);
  console.log("==========================================");
  console.log("📋 Contract Addresses:");
  console.log("  HyperLend Pool:", poolAddress);
  console.log("  Interest Rate Model:", interestRateModel.address);
  console.log("  Price Oracle:", priceOracle.address);
  console.log("  Risk Manager:", riskManager.address);
  console.log("  Liquidation Engine:", liquidationEngine.address);
  console.log("==========================================");
  console.log("📊 Configuration:");
  console.log("  Base Rate:", ethers.formatEther(config.interestRateModel.baseRate), "ETH");
  console.log("  Multiplier:", ethers.formatEther(config.interestRateModel.multiplier), "ETH");
  console.log("  Kink:", ethers.formatEther(config.interestRateModel.kink), "ETH");
  console.log("  Jump Multiplier:", ethers.formatEther(config.interestRateModel.jumpMultiplier), "ETH");
  console.log("  Liquidation Threshold:", ethers.formatEther(config.riskManager.defaultLiquidationThreshold), "ETH");
  console.log("  Liquidation Bonus:", ethers.formatEther(config.riskManager.defaultLiquidationBonus), "ETH");
  console.log("==========================================");
  
  if (network.name === "localhost" || network.name === "hardhat") {
    console.log("🔧 Next steps for local development:");
    console.log("  1. Run: npm run deploy:tokens");
    console.log("  2. Run: npm run configure:system");
    console.log("  3. Run: npm run initialize:pools");
    console.log("  4. Start frontend: npm run dev");
  } else if (network.name === "somnia-testnet") {
    console.log("🌐 Next steps for Somnia testnet:");
    console.log("  1. Add contract addresses to frontend config");
    console.log("  2. Run token deployment script");
    console.log("  3. Configure price feeds");
    console.log("  4. Initialize test markets");
    console.log("  5. Deploy frontend to production");
  }
  
  console.log("==========================================");
  
  return true;
};

export default deployCore;
