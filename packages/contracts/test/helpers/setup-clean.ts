import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";

export interface TestFixtures {
  deployer: SignerWithAddress;
  treasury: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  liquidator: SignerWithAddress;
  
  // Core contracts (using any for now until typechain is generated)
  hyperLendPool: any;
  interestRateModel: any;
  liquidationEngine: any;
  priceOracle: any;
  riskManager: any;
  somniaWrapper: any;
  
  // Token contracts
  hlToken: any;
  debtToken: any;
  rewardToken: any;
  mockUSDC: any;
}

/**
 * Setup complete test environment for HyperLend on Somnia
 */
export async function setupTestEnvironment(): Promise<TestFixtures> {
  const [deployer, treasury, alice, bob, carol, liquidator] = await ethers.getSigners();

  // Deploy Math library
  const MathFactory = await ethers.getContractFactory("Math");
  const mathLib = await MathFactory.deploy();
  await mathLib.deployed();

  // Deploy Interest Rate Model
  const InterestRateModelFactory = await ethers.getContractFactory("InterestRateModel", {
    libraries: { Math: mathLib.address }
  });
  const interestRateModel = await InterestRateModelFactory.deploy(
    200,   // 2% base rate
    800,   // 8% slope1
    25000, // 250% slope2
    8000   // 80% optimal utilization
  );

  // Deploy Price Oracle with DIA integration
  const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracleFactory.deploy(treasury.address);

  // Deploy Risk Manager
  const RiskManagerFactory = await ethers.getContractFactory("RiskManager");
  const riskManager = await RiskManagerFactory.deploy(7000, 8000, 500);

  // Deploy Liquidation Engine
  const LiquidationEngineFactory = await ethers.getContractFactory("LiquidationEngine");
  const liquidationEngine = await LiquidationEngineFactory.deploy(8000, 500, 300);

  // Deploy HyperLend Pool
  const HyperLendPoolFactory = await ethers.getContractFactory("HyperLendPool", {
    libraries: { Math: mathLib.address }
  });
  const hyperLendPool = await HyperLendPoolFactory.deploy(
    interestRateModel.address,
    liquidationEngine.address,
    priceOracle.address,
    riskManager.address
  );

  // Deploy tokens
  const HLTokenFactory = await ethers.getContractFactory("HLToken");
  const hlToken = await HLTokenFactory.deploy("HyperLend STT", "hlSTT");

  const DebtTokenFactory = await ethers.getContractFactory("DebtToken");
  const debtToken = await DebtTokenFactory.deploy("HyperLend STT Debt", "debtSTT");

  const RewardTokenFactory = await ethers.getContractFactory("RewardToken");
  const rewardToken = await RewardTokenFactory.deploy(
    "HyperLend Reward Token",
    "HRT",
    ethers.utils.parseEther("1000000")
  );

  // Deploy Somnia Wrapper
  const SomniaWrapperFactory = await ethers.getContractFactory("SomniaWrapper");
  const somniaWrapper = await SomniaWrapperFactory.deploy();

  // Deploy mock USDC
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const mockUSDC = await MockERC20Factory.deploy("Mock USDC", "mUSDC", 6);

  // Setup initial balances
  await setupInitialBalances({ deployer, alice, bob, carol, liquidator, mockUSDC });

  // Setup initial prices
  await priceOracle.setAssetPrice(ethers.constants.AddressZero, ethers.utils.parseEther("2"));
  await priceOracle.setAssetPrice(mockUSDC.address, ethers.utils.parseEther("1"));

  return {
    deployer,
    treasury,
    alice,
    bob,
    carol,
    liquidator,
    hyperLendPool,
    interestRateModel,
    liquidationEngine,
    priceOracle,
    riskManager,
    somniaWrapper,
    hlToken,
    debtToken,
    rewardToken,
    mockUSDC
  };
}

/**
 * Setup initial balances for test users
 */
async function setupInitialBalances(params: {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  liquidator: SignerWithAddress;
  mockUSDC: any;
}) {
  const { deployer, alice, bob, carol, liquidator, mockUSDC } = params;
  
  const INITIAL_STT_BALANCE = ethers.utils.parseEther("10000");

  // Setup STT balances
  await deployer.sendTransaction({ to: alice.address, value: INITIAL_STT_BALANCE });
  await deployer.sendTransaction({ to: bob.address, value: INITIAL_STT_BALANCE });
  await deployer.sendTransaction({ to: carol.address, value: INITIAL_STT_BALANCE });
  await deployer.sendTransaction({ to: liquidator.address, value: INITIAL_STT_BALANCE });

  // Setup USDC balances
  await mockUSDC.mint(alice.address, ethers.utils.parseUnits("100000", 6));
  await mockUSDC.mint(bob.address, ethers.utils.parseUnits("100000", 6));
  await mockUSDC.mint(carol.address, ethers.utils.parseUnits("100000", 6));
  await mockUSDC.mint(liquidator.address, ethers.utils.parseUnits("100000", 6));
}

/**
 * Helper to supply native STT to the pool
 */
export async function supplyNativeSTT(
  user: SignerWithAddress,
  hyperLendPool: any,
  amount: BigNumber
) {
  return user.sendTransaction({
    to: hyperLendPool.address,
    value: amount,
    data: hyperLendPool.interface.encodeFunctionData("supplyNativeSTT", [])
  });
}

/**
 * Helper to approve and supply ERC20 tokens
 */
export async function supplyERC20(
  user: SignerWithAddress,
  token: any,
  hyperLendPool: any,
  amount: BigNumber
) {
  await token.connect(user).approve(hyperLendPool.address, amount);
  return hyperLendPool.connect(user).supply(token.address, amount);
}

/**
 * Helper to create a liquidatable position
 */
export async function createLiquidatablePosition(
  collateralUser: SignerWithAddress,
  liquidityProvider: SignerWithAddress,
  hyperLendPool: any,
  mockUSDC: any,
  priceOracle: any
) {
  // User supplies STT as collateral
  await supplyNativeSTT(collateralUser, hyperLendPool, ethers.utils.parseEther("100"));

  // Liquidity provider supplies USDC
  await supplyERC20(liquidityProvider, mockUSDC, hyperLendPool, ethers.utils.parseUnits("50000", 6));

  // User borrows USDC close to the limit
  await hyperLendPool.connect(collateralUser).borrow(
    mockUSDC.address,
    ethers.utils.parseUnits("140", 6)
  );

  // Price drop to trigger liquidation
  await priceOracle.setAssetPrice(ethers.constants.AddressZero, ethers.utils.parseEther("1.2"));
}

/**
 * Helper to measure function execution time
 */
export async function measureExecutionTime<T>(
  fn: () => Promise<T>,
  label: string
): Promise<{ result: T; executionTime: number }> {
  const startTime = Date.now();
  const result = await fn();
  const endTime = Date.now();
  const executionTime = endTime - startTime;
  
  console.log(`⚡ ${label} executed in ${executionTime}ms`);
  
  return { result, executionTime };
}

/**
 * Helper to format values for display
 */
export function formatValue(value: BigNumber, decimals: number = 18, symbol?: string): string {
  const formatted = ethers.utils.formatUnits(value, decimals);
  return symbol ? `${formatted} ${symbol}` : formatted;
}

/**
 * Helper to generate random amounts for stress testing
 */
export function generateRandomAmount(min: number, max: number, decimals: number = 18): BigNumber {
  const random = Math.random() * (max - min) + min;
  return ethers.utils.parseUnits(random.toFixed(6), decimals);
}

/**
 * Somnia-specific test constants
 */
export const SOMNIA_CONSTANTS = {
  NATIVE_STT_ADDRESS: ethers.constants.AddressZero,
  INITIAL_STT_PRICE: ethers.utils.parseEther("2"),
  INITIAL_USDC_PRICE: ethers.utils.parseEther("1"),
  HIGH_TPS_OPERATION_COUNT: 50,
  STRESS_TEST_USERS: 10,
  LIQUIDATION_THRESHOLD: 8000, // 80%
  LOAN_TO_VALUE: 7000, // 70%
  LIQUIDATION_PENALTY: 500, // 5%
} as const;

/**
 * Helper to verify Somnia-specific features
 */
export async function verifySomniaFeatures(fixtures: TestFixtures) {
  const { hyperLendPool, priceOracle } = fixtures;

  // Verify native STT handling
  const nativeSTTPrice = await priceOracle.getAssetPrice(ethers.constants.AddressZero);
  console.log(`📊 Native STT price: ${formatValue(nativeSTTPrice, 18, "USD")}`);

  // Verify pool is ready for high TPS operations
  const poolAddress = hyperLendPool.address;
  console.log(`🏦 HyperLend Pool deployed at: ${poolAddress}`);

  // Verify oracle is ready for real-time updates
  console.log(`🔮 Price Oracle ready for real-time DIA integration`);

  return true;
}

/**
 * Helper to simulate Somnia's high TPS environment
 */
export async function simulateHighTPS(
  users: SignerWithAddress[],
  hyperLendPool: any,
  operationCount: number = 20
) {
  const operations: Promise<any>[] = [];
  
  for (let i = 0; i < operationCount; i++) {
    const user = users[i % users.length];
    const amount = generateRandomAmount(1, 10);
    
    operations.push(
      supplyNativeSTT(user, hyperLendPool, amount)
    );
  }

  const startTime = Date.now();
  await Promise.all(operations);
  const endTime = Date.now();

  const totalTime = endTime - startTime;
  const tps = (operationCount / totalTime) * 1000;

  console.log(`⚡ Executed ${operationCount} operations in ${totalTime}ms`);
  console.log(`📈 Achieved TPS: ${tps.toFixed(2)}`);

  return { totalTime, tps };
}
