import { ethers } from "hardhat";

export interface DeploymentResult {
  // Core contracts
  hyperLendPool: any;
  interestRateModel: any;
  liquidationEngine: any;
  priceOracle: any;
  riskManager: any;
  somniaWrapper: any;
  
  // Mock tokens (for testing)
  usdc: any;
  weth: any;
  
  // HL Tokens
  hlUSDC: any;
  hlWETH: any;
  
  // Debt Tokens
  debtUSDC: any;
  debtWETH: any;
  
  // Test addresses
  admin: any;
  treasury: any;
  oracle: any;
}

export async function deploymentFixture(): Promise<DeploymentResult> {
  const [admin, treasury, oracle, ...otherSigners] = await ethers.getSigners();

  console.log("🚀 Deploying test contracts...");

  // Libraries are now using OpenZeppelin's Math (no custom deployment needed)

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY MOCK TOKENS
  // ═══════════════════════════════════════════════════════════════════════════════════
  
  console.log("🪙 Deploying mock tokens...");
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  
  const usdc = await MockERC20Factory.deploy(
    "USD Coin",
    "USDC",
    6, // 6 decimals for USDC
    ethers.utils.parseEther("1000000000") // 1B USDC
  );
  await usdc.waitForDeployment();
  
  const weth = await MockERC20Factory.deploy(
    "Wrapped Ether",
    "WETH",
    18,
    ethers.utils.parseEther("1000000") // 1M WETH
  );
  await weth.waitForDeployment();

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY CORE CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════
  
  console.log("🏗️ Deploying core contracts...");
  
  // Deploy Interest Rate Model
  const InterestRateModelFactory = await ethers.getContractFactory("InterestRateModel");
  const interestRateModel = await InterestRateModelFactory.deploy(
    200,   // 2% base rate
    800,   // 8% slope 1
    25000, // 250% slope 2
    8000   // 80% optimal utilization
  );
  await interestRateModel.waitForDeployment();

  // Deploy Price Oracle
  const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracleFactory.deploy(admin.address);
  await priceOracle.waitForDeployment();

  // Deploy Risk Manager
  const RiskManagerFactory = await ethers.getContractFactory("RiskManager");
  const riskManager = await RiskManagerFactory.deploy(
    7000, // 70% default LTV
    8000, // 80% liquidation threshold
    500   // 5% liquidation penalty
  );
  await riskManager.waitForDeployment();

  // Deploy Liquidation Engine
  const LiquidationEngineFactory = await ethers.getContractFactory("LiquidationEngine");
  const liquidationEngine = await LiquidationEngineFactory.deploy(
    8000, // 80% liquidation threshold
    500,  // 5% liquidation penalty
    300   // 3% max slippage
  );
  await liquidationEngine.waitForDeployment();

  // Deploy Somnia Wrapper
  const SomniaWrapperFactory = await ethers.getContractFactory("SomniaWrapper");
  const somniaWrapper = await SomniaWrapperFactory.deploy();
  await somniaWrapper.waitForDeployment();

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY HL AND DEBT TOKENS
  // ═══════════════════════════════════════════════════════════════════════════════════
  
  console.log("🎫 Deploying HL and Debt tokens...");
  
  const HLTokenFactory = await ethers.getContractFactory("HLToken");
  const DebtTokenFactory = await ethers.getContractFactory("DebtToken");
  
  // We'll set pool address after deploying the main pool
  const hlUSDC = await HLTokenFactory.deploy(
    "HyperLend USDC",
    "hlUSDC"
  );
  await hlUSDC.waitForDeployment();
  
  const hlWETH = await HLTokenFactory.deploy(
    "HyperLend WETH",
    "hlWETH"
  );
  await hlWETH.waitForDeployment();
  
  const debtUSDC = await DebtTokenFactory.deploy(
    "HyperLend USDC Debt",
    "debtUSDC"
  );
  await debtUSDC.waitForDeployment();
  
  const debtWETH = await DebtTokenFactory.deploy(
    "HyperLend WETH Debt", 
    "debtWETH"
  );
  await debtWETH.waitForDeployment();

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY MAIN HYPERLEND POOL
  // ═══════════════════════════════════════════════════════════════════════════════════
  
  console.log("🏦 Deploying HyperLendPool...");
  const HyperLendPoolFactory = await ethers.getContractFactory("HyperLendPool", {
    libraries: { Math: mathLibAddress }
  });
  
  const hyperLendPool = await HyperLendPoolFactory.deploy(
    await interestRateModel.getAddress(),
    await liquidationEngine.getAddress(),
    await priceOracle.getAddress(),
    await riskManager.getAddress()
  );
  await hyperLendPool.waitForDeployment();

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════
  
  console.log("⚙️ Configuring contracts...");
  
  // Set pool address in liquidation engine
  await liquidationEngine.setPoolAddress(await hyperLendPool.getAddress());
  
  // Initialize markets in the pool (if needed)
  const usdcAddress = await usdc.getAddress();
  const wethAddress = await weth.getAddress();
  
  // Set initial prices (for testing)
  await priceOracle.setAssetPrice(usdcAddress, ethers.utils.parseEther("1"));     // $1
  await priceOracle.setAssetPrice(wethAddress, ethers.utils.parseEther("2000"));   // $2000
  await priceOracle.setAssetPrice(ethers.constants.AddressZero, ethers.utils.parseEther("1")); // STT = $1

  console.log("✅ Test deployment completed!");

  return {
    // Core contracts
    hyperLendPool,
    interestRateModel,
    liquidationEngine,
    priceOracle,
    riskManager,
    somniaWrapper,
    
    // Libraries
    mathLib,
    
    // Mock tokens
    usdc,
    weth,
    
    // HL Tokens
    hlUSDC,
    hlWETH,
    
    // Debt Tokens
    debtUSDC,
    debtWETH,
    
    // Test addresses
    admin,
    treasury,
    oracle
  };
}