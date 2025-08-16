import { ethers } from "hardhat";

// Simple deployment script for testing and quick deployment
async function deploySimple() {
  console.log("🚀 Simple HyperLend Deployment for Testing");
  
  const [deployer] = await ethers.getSigners();
  console.log("📍 Deploying from:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", ethers.utils.formatEther(balance), "ETH");

  try {
    // Deploy Math library
    console.log("⏳ Deploying Math library...");
    const MathFactory = await ethers.getContractFactory("Math");
    const mathLib = await MathFactory.deploy();
    await mathLib.waitForDeployment();
    const mathLibAddress = await mathLib.getAddress();
    console.log(`✅ Math: ${mathLibAddress}`);

    // Deploy Interest Rate Model
    console.log("⏳ Deploying InterestRateModel...");
    const InterestRateModelFactory = await ethers.getContractFactory("InterestRateModel", {
      libraries: { Math: mathLibAddress }
    });
    const interestRateModel = await InterestRateModelFactory.deploy(200, 800, 25000, 8000);
    await interestRateModel.waitForDeployment();
    const interestRateModelAddress = await interestRateModel.getAddress();
    console.log(`✅ InterestRateModel: ${interestRateModelAddress}`);

    // Deploy Price Oracle
    console.log("⏳ Deploying PriceOracle...");
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracleFactory.deploy(deployer.address);
    await priceOracle.waitForDeployment();
    const priceOracleAddress = await priceOracle.getAddress();
    console.log(`✅ PriceOracle: ${priceOracleAddress}`);

    // Deploy Risk Manager
    console.log("⏳ Deploying RiskManager...");
    const RiskManagerFactory = await ethers.getContractFactory("RiskManager");
    const riskManager = await RiskManagerFactory.deploy(7000, 8000, 500);
    await riskManager.waitForDeployment();
    const riskManagerAddress = await riskManager.getAddress();
    console.log(`✅ RiskManager: ${riskManagerAddress}`);

    // Deploy Liquidation Engine
    console.log("⏳ Deploying LiquidationEngine...");
    const LiquidationEngineFactory = await ethers.getContractFactory("LiquidationEngine");
    const liquidationEngine = await LiquidationEngineFactory.deploy(8000, 500, 300);
    await liquidationEngine.waitForDeployment();
    const liquidationEngineAddress = await liquidationEngine.getAddress();
    console.log(`✅ LiquidationEngine: ${liquidationEngineAddress}`);

    // Deploy HyperLend Pool
    console.log("⏳ Deploying HyperLendPool...");
    const HyperLendPoolFactory = await ethers.getContractFactory("HyperLendPool", {
      libraries: { Math: mathLibAddress }
    });
    const hyperLendPool = await HyperLendPoolFactory.deploy(
      interestRateModelAddress,
      liquidationEngineAddress,
      priceOracleAddress,
      riskManagerAddress
    );
    await hyperLendPool.waitForDeployment();
    const hyperLendPoolAddress = await hyperLendPool.getAddress();
    console.log(`✅ HyperLendPool: ${hyperLendPoolAddress}`);

    // Deploy tokens
    console.log("⏳ Deploying HLToken...");
    const HLTokenFactory = await ethers.getContractFactory("HLToken");
    const hlToken = await HLTokenFactory.deploy("HyperLend Token", "HLT");
    await hlToken.waitForDeployment();
    const hlTokenAddress = await hlToken.getAddress();
    console.log(`✅ HLToken: ${hlTokenAddress}`);

    console.log("⏳ Deploying DebtToken...");
    const DebtTokenFactory = await ethers.getContractFactory("DebtToken");
    const debtToken = await DebtTokenFactory.deploy("HyperLend Debt Token", "HDT");
    await debtToken.waitForDeployment();
    const debtTokenAddress = await debtToken.getAddress();
    console.log(`✅ DebtToken: ${debtTokenAddress}`);

    console.log("⏳ Deploying RewardToken...");
    const RewardTokenFactory = await ethers.getContractFactory("RewardToken");
    const rewardToken = await RewardTokenFactory.deploy(
      "HyperLend Reward Token", 
      "HRT", 
      ethers.utils.parseEther("1000000")
    );
    await rewardToken.waitForDeployment();
    const rewardTokenAddress = await rewardToken.getAddress();
    console.log(`✅ RewardToken: ${rewardTokenAddress}`);

    console.log("⏳ Deploying SomniaWrapper...");
    const SomniaWrapperFactory = await ethers.getContractFactory("SomniaWrapper");
    const somniaWrapper = await SomniaWrapperFactory.deploy();
    await somniaWrapper.waitForDeployment();
    const somniaWrapperAddress = await somniaWrapper.getAddress();
    console.log(`✅ SomniaWrapper: ${somniaWrapperAddress}`);

    console.log("\n🎉 Simple deployment completed!");
    console.log("📊 Deployed Contracts:");
    console.log(`   Math Library: ${mathLibAddress}`);
    console.log(`   HyperLendPool: ${hyperLendPoolAddress}`);
    console.log(`   InterestRateModel: ${interestRateModelAddress}`);
    console.log(`   PriceOracle: ${priceOracleAddress}`);
    console.log(`   LiquidationEngine: ${liquidationEngineAddress}`);
    console.log(`   RiskManager: ${riskManagerAddress}`);
    console.log(`   HLToken: ${hlTokenAddress}`);
    console.log(`   DebtToken: ${debtTokenAddress}`);
    console.log(`   RewardToken: ${rewardTokenAddress}`);
    console.log(`   SomniaWrapper: ${somniaWrapperAddress}`);
    
    return {
      mathLib: mathLibAddress,
      hyperLendPool: hyperLendPoolAddress,
      interestRateModel: interestRateModelAddress,
      priceOracle: priceOracleAddress,
      liquidationEngine: liquidationEngineAddress,
      riskManager: riskManagerAddress,
      hlToken: hlTokenAddress,
      debtToken: debtTokenAddress,
      rewardToken: rewardTokenAddress,
      somniaWrapper: somniaWrapperAddress,
    };

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    throw error;
  }
}

// Execute if called directly
if (require.main === module) {
  deploySimple()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

export default deploySimple;
