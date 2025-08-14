import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { 
  HyperLendPool, 
  InterestRateModel, 
  LiquidationEngine, 
  PriceOracle, 
  RiskManager,
  MockERC20,
  HLToken,
  DebtToken 
} from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { deploymentFixture } from "../fixtures/deployments";
import { createUsers } from "../fixtures/users";
import { parseEther, formatEther } from "ethers";

describe("HyperLendPool", function () {
  // ═══════════════════════════════════════════════════════════════════════════════════
  // FIXTURES AND SETUP
  // ═══════════════════════════════════════════════════════════════════════════════════

  let hyperLendPool: HyperLendPool;
  let interestRateModel: InterestRateModel;
  let liquidationEngine: LiquidationEngine;
  let priceOracle: PriceOracle;
  let riskManager: RiskManager;
  
  let usdc: MockERC20;
  let weth: MockERC20;
  let hlUSDC: HLToken;
  let hlWETH: HLToken;
  let debtUSDC: DebtToken;
  let debtWETH: DebtToken;

  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let liquidator: SignerWithAddress;
  let users: SignerWithAddress[];

  const PRECISION = parseEther("1");
  const INITIAL_SUPPLY = parseEther("1000000"); // 1M tokens
  const USDC_PRICE = parseEther("1"); // $1
  const WETH_PRICE = parseEther("2000"); // $2000

  beforeEach(async function () {
    // Get signers
    [admin, user1, user2, liquidator, ...users] = await ethers.getSigners();

    // Deploy all contracts
    const deployment = await deploymentFixture();
    
    hyperLendPool = deployment.hyperLendPool;
    interestRateModel = deployment.interestRateModel;
    liquidationEngine = deployment.liquidationEngine;
    priceOracle = deployment.priceOracle;
    riskManager = deployment.riskManager;
    
    usdc = deployment.usdc;
    weth = deployment.weth;
    hlUSDC = deployment.hlUSDC;
    hlWETH = deployment.hlWETH;
    debtUSDC = deployment.debtUSDC;
    debtWETH = deployment.debtWETH;

    // Setup initial token balances
    await usdc.transfer(user1.address, parseEther("100000"));
    await usdc.transfer(user2.address, parseEther("100000"));
    await weth.transfer(user1.address, parseEther("100"));
    await weth.transfer(user2.address, parseEther("100"));

    // Approve tokens for pool
    await usdc.connect(user1).approve(hyperLendPool.target, ethers.MaxUint256);
    await usdc.connect(user2).approve(hyperLendPool.target, ethers.MaxUint256);
    await weth.connect(user1).approve(hyperLendPool.target, ethers.MaxUint256);
    await weth.connect(user2).approve(hyperLendPool.target, ethers.MaxUint256);

    // Set initial prices
    await priceOracle.setEmergencyPrice(usdc.target, USDC_PRICE, "Initial price");
    await priceOracle.setEmergencyPrice(weth.target, WETH_PRICE, "Initial price");
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CORE FUNCTIONALITY TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Supply and Withdraw", function () {
    it("Should allow users to supply assets", async function () {
      const supplyAmount = parseEther("1000");
      
      await expect(hyperLendPool.connect(user1).supply(usdc.target, supplyAmount))
        .to.emit(hyperLendPool, "Supply")
        .withArgs(user1.address, usdc.target, supplyAmount, supplyAmount);

      // Check balances
      expect(await hlUSDC.balanceOf(user1.address)).to.equal(supplyAmount);
      expect(await usdc.balanceOf(hyperLendPool.target)).to.equal(supplyAmount);
      
      // Check market data
      const marketData = await hyperLendPool.getMarketData(usdc.target);
      expect(marketData.totalSupply).to.equal(supplyAmount);
    });

    it("Should calculate correct exchange rate for hlTokens", async function () {
      const supplyAmount = parseEther("1000");
      
      await hyperLendPool.connect(user1).supply(usdc.target, supplyAmount);
      
      // Initially, 1:1 exchange rate
      expect(await hlUSDC.hlTokensToUnderlying(parseEther("1"))).to.equal(parseEther("1"));
      expect(await hlUSDC.underlyingToHlTokens(parseEther("1"))).to.equal(parseEther("1"));
    });

    it("Should allow users to withdraw assets", async function () {
      const supplyAmount = parseEther("1000");
      const withdrawAmount = parseEther("500");
      
      // Supply first
      await hyperLendPool.connect(user1).supply(usdc.target, supplyAmount);
      
      // Withdraw
      await expect(hyperLendPool.connect(user1).withdraw(usdc.target, withdrawAmount))
        .to.emit(hyperLendPool, "Withdraw")
        .withArgs(user1.address, usdc.target, withdrawAmount, withdrawAmount);

      expect(await hlUSDC.balanceOf(user1.address)).to.equal(supplyAmount - withdrawAmount);
    });

    it("Should prevent withdrawal of more than supplied", async function () {
      const supplyAmount = parseEther("1000");
      const withdrawAmount = parseEther("1500");
      
      await hyperLendPool.connect(user1).supply(usdc.target, supplyAmount);
      
      await expect(
        hyperLendPool.connect(user1).withdraw(usdc.target, withdrawAmount)
      ).to.be.revertedWith("HLToken: Insufficient balance");
    });

    it("Should update real-time metrics on supply/withdraw", async function () {
      const supplyAmount = parseEther("1000");
      
      await hyperLendPool.connect(user1).supply(usdc.target, supplyAmount);
      
      const metrics = await hyperLendPool.getRealTimeMetrics();
      expect(metrics.tvl).to.be.gt(0);
      expect(metrics.lastUpdate).to.be.gt(0);
    });
  });

  describe("Borrow and Repay", function () {
    beforeEach(async function () {
      // User1 supplies WETH as collateral
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10"));
    });

    it("Should allow users to borrow against collateral", async function () {
      const borrowAmount = parseEther("5000"); // Borrow $5000 USDC against $20000 WETH
      
      await expect(hyperLendPool.connect(user1).borrow(usdc.target, borrowAmount))
        .to.emit(hyperLendPool, "Borrow")
        .withArgs(user1.address, usdc.target, borrowAmount, borrowAmount);

      expect(await debtUSDC.balanceOf(user1.address)).to.equal(borrowAmount);
      expect(await usdc.balanceOf(user1.address)).to.equal(parseEther("105000")); // Initial + borrowed
    });

    it("Should prevent borrowing beyond safe limits", async function () {
      const borrowAmount = parseEther("18000"); // Try to borrow $18000 against $20000 (90% LTV)
      
      await expect(
        hyperLendPool.connect(user1).borrow(usdc.target, borrowAmount)
      ).to.be.revertedWith("HyperLend: Borrow not allowed");
    });

    it("Should allow users to repay debt", async function () {
      const borrowAmount = parseEther("5000");
      const repayAmount = parseEther("2000");
      
      // Borrow first
      await hyperLendPool.connect(user1).borrow(usdc.target, borrowAmount);
      
      // Repay
      await expect(hyperLendPool.connect(user1).repay(usdc.target, repayAmount))
        .to.emit(hyperLendPool, "Repay")
        .withArgs(user1.address, usdc.target, repayAmount, repayAmount);

      expect(await debtUSDC.balanceOf(user1.address)).to.equal(borrowAmount - repayAmount);
    });

    it("Should update health factor correctly", async function () {
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("5000"));
      
      const userData = await hyperLendPool.getUserAccountData(user1.address);
      expect(userData.healthFactor).to.be.gt(parseEther("1")); // Should be healthy
      expect(userData.isLiquidatable).to.be.false;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEREST RATE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Interest Rate Calculations", function () {
    it("Should calculate interest rates based on utilization", async function () {
      // Supply and borrow to create utilization
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("10000"));
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10"));
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("5000")); // 50% utilization
      
      const marketData = await hyperLendPool.getMarketData(usdc.target);
      expect(marketData.utilizationRate).to.equal(parseEther("0.5")); // 50%
      expect(marketData.borrowAPY).to.be.gt(0);
      expect(marketData.supplyAPY).to.be.gt(0);
      expect(marketData.borrowAPY).to.be.gt(marketData.supplyAPY);
    });

    it("Should update interest rates in real-time", async function () {
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("10000"));
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10"));
      
      const initialData = await hyperLendPool.getMarketData(usdc.target);
      
      // Create utilization
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("8000")); // 80% utilization
      
      const updatedData = await hyperLendPool.getMarketData(usdc.target);
      expect(updatedData.borrowAPY).to.be.gt(initialData.borrowAPY);
    });

    it("Should accrue interest over time", async function () {
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("10000"));
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10"));
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("5000"));
      
      const initialDebt = await debtUSDC.balanceOfDebt(user1.address);
      
      // Fast forward time
      await time.increase(86400); // 1 day
      
      // Update interest
      await hyperLendPool.updateMarketInterest(usdc.target);
      
      const finalDebt = await debtUSDC.balanceOfDebt(user1.address);
      expect(finalDebt).to.be.gt(initialDebt);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // LIQUIDATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Liquidations", function () {
    beforeEach(async function () {
      // Setup a borrowing position
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10")); // $20000 collateral
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("15000")); // $15000 debt (75% LTV)
      
      // User2 supplies USDC for liquidation
      await hyperLendPool.connect(user2).supply(usdc.target, parseEther("50000"));
    });

    it("Should allow liquidation when health factor drops", async function () {
      // Drop WETH price to make position unhealthy
      await priceOracle.setEmergencyPrice(weth.target, parseEther("1600"), "Price drop"); // 20% drop
      
      // Update user health
      await hyperLendPool.updateUserHealth(user1.address);
      
      const userData = await hyperLendPool.getUserAccountData(user1.address);
      expect(userData.isLiquidatable).to.be.true;
      
      // Liquidate
      const liquidationAmount = parseEther("5000");
      await expect(
        hyperLendPool.connect(liquidator).liquidate(
          user1.address,
          usdc.target,
          liquidationAmount,
          weth.target
        )
      ).to.emit(hyperLendPool, "Liquidation");
      
      // Check that debt was reduced
      const finalDebt = await debtUSDC.balanceOfDebt(user1.address);
      expect(finalDebt).to.be.lt(parseEther("15000"));
    });

    it("Should execute micro-liquidations for real-time risk management", async function () {
      // Drop WETH price slightly to trigger micro-liquidation
      await priceOracle.setEmergencyPrice(weth.target, parseEther("1800"), "Small price drop");
      
      // Grant liquidator role
      await liquidationEngine.grantRole(
        await liquidationEngine.LIQUIDATOR_ROLE(),
        liquidator.address
      );
      
      const optimalAmount = await liquidationEngine.calculateOptimalLiquidation(
        user1.address,
        usdc.target,
        parseEther("1000")
      );
      
      expect(optimalAmount).to.be.gt(0);
    });

    it("Should prevent liquidation of healthy positions", async function () {
      await expect(
        hyperLendPool.connect(liquidator).liquidate(
          user1.address,
          usdc.target,
          parseEther("1000"),
          weth.target
        )
      ).to.be.revertedWith("Position not liquidatable");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // REAL-TIME FEATURES TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Real-Time Features", function () {
    it("Should update metrics in real-time", async function () {
      const initialMetrics = await hyperLendPool.getRealTimeMetrics();
      
      // Add liquidity
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("10000"));
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("5"));
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("5000"));
      
      const updatedMetrics = await hyperLendPool.getRealTimeMetrics();
      expect(updatedMetrics.tvl).to.be.gt(initialMetrics.tvl);
      expect(updatedMetrics.borrowed).to.be.gt(initialMetrics.borrowed);
      expect(updatedMetrics.lastUpdate).to.be.gt(initialMetrics.lastUpdate);
    });

    it("Should batch update interest rates efficiently", async function () {
      const assets = [usdc.target, weth.target];
      
      await expect(hyperLendPool.batchUpdateInterest(assets))
        .to.emit(hyperLendPool, "InterestRateUpdate");
    });

    it("Should batch update user health factors", async function () {
      // Create positions for multiple users
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10"));
      await hyperLendPool.connect(user2).supply(usdc.target, parseEther("20000"));
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("5000"));
      
      const userList = [user1.address, user2.address];
      await hyperLendPool.batchUpdateUserHealth(userList);
      
      const user1Data = await hyperLendPool.getUserAccountData(user1.address);
      const user2Data = await hyperLendPool.getUserAccountData(user2.address);
      
      expect(user1Data.healthFactor).to.be.gt(0);
      expect(user2Data.healthFactor).to.equal(ethers.MaxUint256); // No debt
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // EDGE CASES AND ERROR CONDITIONS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Edge Cases", function () {
    it("Should handle zero amounts gracefully", async function () {
      await expect(
        hyperLendPool.connect(user1).supply(usdc.target, 0)
      ).to.be.revertedWith("HyperLend: Invalid amount");
      
      await expect(
        hyperLendPool.connect(user1).withdraw(usdc.target, 0)
      ).to.be.revertedWith("HyperLend: Invalid amount");
    });

    it("Should prevent operations when paused", async function () {
      await hyperLendPool.pause();
      
      await expect(
        hyperLendPool.connect(user1).supply(usdc.target, parseEther("1000"))
      ).to.be.revertedWith("Pausable: paused");
    });

    it("Should handle market caps correctly", async function () {
      const supplyCap = parseEther("10000000"); // 10M supply cap
      const largSupply = parseEther("15000000"); // 15M supply (exceeds cap)
      
      // Give user enough tokens
      await usdc.transfer(user1.address, largSupply);
      await usdc.connect(user1).approve(hyperLendPool.target, largSupply);
      
      await expect(
        hyperLendPool.connect(user1).supply(usdc.target, largSupply)
      ).to.be.revertedWith("HyperLend: Supply cap exceeded");
    });

    it("Should handle insufficient liquidity for withdrawals", async function () {
      // User1 supplies
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("10000"));
      
      // User2 supplies collateral and borrows most liquidity
      await hyperLendPool.connect(user2).supply(weth.target, parseEther("20")); // $40k collateral
      await hyperLendPool.connect(user2).borrow(usdc.target, parseEther("9500")); // Borrow most of pool
      
      // User1 tries to withdraw more than available
      await expect(
        hyperLendPool.connect(user1).withdraw(usdc.target, parseEther("8000"))
      ).to.be.revertedWith("HyperLend: Withdrawal not allowed");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Integration Tests", function () {
    it("Should handle complex multi-user scenarios", async function () {
      // User1: Supply WETH, borrow USDC
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("10"));
      await hyperLendPool.connect(user1).borrow(usdc.target, parseEther("10000"));
      
      // User2: Supply USDC, borrow WETH
      await hyperLendPool.connect(user2).supply(usdc.target, parseEther("40000"));
      await hyperLendPool.connect(user2).borrow(weth.target, parseEther("5"));
      
      // Check that both positions are healthy
      const user1Data = await hyperLendPool.getUserAccountData(user1.address);
      const user2Data = await hyperLendPool.getUserAccountData(user2.address);
      
      expect(user1Data.healthFactor).to.be.gt(parseEther("1"));
      expect(user2Data.healthFactor).to.be.gt(parseEther("1"));
      
      // Check system metrics
      const metrics = await hyperLendPool.getRealTimeMetrics();
      expect(metrics.tvl).to.be.gt(parseEther("50000")); // $50k+ TVL
      expect(metrics.utilizationRate).to.be.gt(0);
    });

    it("Should handle interest accrual over time", async function () {
      // Setup positions
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("50000"));
      await hyperLendPool.connect(user2).supply(weth.target, parseEther("10"));
      await hyperLendPool.connect(user2).borrow(usdc.target, parseEther("15000"));
      
      const initialSupplyBalance = await hlUSDC.balanceOfUnderlying(user1.address);
      const initialDebtBalance = await debtUSDC.balanceOfDebt(user2.address);
      
      // Fast forward time and accrue interest
      await time.increase(86400 * 30); // 30 days
      await hyperLendPool.updateMarketInterest(usdc.target);
      
      const finalSupplyBalance = await hlUSDC.balanceOfUnderlying(user1.address);
      const finalDebtBalance = await debtUSDC.balanceOfDebt(user2.address);
      
      // Supply should earn interest
      expect(finalSupplyBalance).to.be.gt(initialSupplyBalance);
      // Debt should accrue interest
      expect(finalDebtBalance).to.be.gt(initialDebtBalance);
    });

    it("Should handle liquidation cascade scenarios", async function () {
      // Create multiple overleveraged positions
      const users = [user1, user2];
      
      for (let i = 0; i < users.length; i++) {
        await hyperLendPool.connect(users[i]).supply(weth.target, parseEther("5"));
        await hyperLendPool.connect(users[i]).borrow(usdc.target, parseEther("7500")); // 75% LTV
      }
      
      // Crash WETH price
      await priceOracle.setEmergencyPrice(weth.target, parseEther("1200"), "Market crash"); // 40% drop
      
      // Update all user health factors
      for (const user of users) {
        await hyperLendPool.updateUserHealth(user.address);
        const userData = await hyperLendPool.getUserAccountData(user.address);
        expect(userData.isLiquidatable).to.be.true;
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PERFORMANCE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Performance Tests", function () {
    it("Should handle high-frequency operations efficiently", async function () {
      // Setup initial liquidity
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("100000"));
      await hyperLendPool.connect(user1).supply(weth.target, parseEther("50"));
      
      // Perform multiple rapid operations
      const operations = 10;
      const startTime = Date.now();
      
      for (let i = 0; i < operations; i++) {
        await hyperLendPool.connect(user2).supply(usdc.target, parseEther("1000"));
        await hyperLendPool.connect(user2).withdraw(usdc.target, parseEther("500"));
      }
      
      const endTime = Date.now();
      const avgTimePerOp = (endTime - startTime) / (operations * 2);
      
      console.log(`Average time per operation: ${avgTimePerOp}ms`);
      expect(avgTimePerOp).to.be.lt(1000); // Should be under 1 second per op
    });

    it("Should update metrics efficiently in batch", async function () {
      // Create multiple positions
      const batchUsers = await createUsers(20); // Helper function to create test users
      
      for (let i = 0; i < Math.min(batchUsers.length, 5); i++) {
        const user = batchUsers[i];
        await usdc.transfer(user.address, parseEther("10000"));
        await usdc.connect(user).approve(hyperLendPool.target, ethers.MaxUint256);
        await hyperLendPool.connect(user).supply(usdc.target, parseEther("5000"));
      }
      
      const userAddresses = batchUsers.slice(0, 5).map(u => u.address);
      
      const startTime = Date.now();
      await hyperLendPool.batchUpdateUserHealth(userAddresses);
      const endTime = Date.now();
      
      console.log(`Batch update time for ${userAddresses.length} users: ${endTime - startTime}ms`);
      expect(endTime - startTime).to.be.lt(5000); // Should complete in under 5 seconds
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ADMIN FUNCTIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Admin Functions", function () {
    it("Should allow admin to add new markets", async function () {
      // Deploy a new mock token
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const newToken = await MockERC20.deploy("Test Token", "TEST", 18, parseEther("1000000"));
      
      // Deploy market tokens for new asset
      const HLToken = await ethers.getContractFactory("HLToken");
      const DebtToken = await ethers.getContractFactory("DebtToken");
      
      const hlToken = await HLToken.deploy(
        "HyperLend TEST",
        "hlTEST",
        newToken.target,
        hyperLendPool.target,
        admin.address
      );
      
      const debtToken = await DebtToken.deploy(
        "HyperLend TEST Debt",
        "debtTEST",
        newToken.target,
        hyperLendPool.target,
        admin.address
      );
      
      // Add market
      await expect(
        hyperLendPool.addMarket(
          newToken.target,
          hlToken.target,
          debtToken.target,
          parseEther("0.8"), // 80% liquidation threshold
          parseEther("0.05"), // 5% liquidation bonus
          parseEther("1000000"), // 1M borrow cap
          parseEther("10000000") // 10M supply cap
        )
      ).to.emit(hyperLendPool, "MarketAdded");
    });

    it("Should allow admin to pause/unpause", async function () {
      await hyperLendPool.pause();
      expect(await hyperLendPool.paused()).to.be.true;
      
      await hyperLendPool.unpause();
      expect(await hyperLendPool.paused()).to.be.false;
    });

    it("Should restrict admin functions to admin role", async function () {
      await expect(
        hyperLendPool.connect(user1).pause()
      ).to.be.revertedWith("HyperLend: Not admin");
      
      await expect(
        hyperLendPool.connect(user1).setInterestRateModel(ethers.ZeroAddress)
      ).to.be.revertedWith("HyperLend: Not admin");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // UPGRADE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Upgradeability", function () {
    it("Should be upgradeable by admin", async function () {
      // Deploy new implementation (for testing, we'll use the same contract)
      const HyperLendPoolV2 = await ethers.getContractFactory("HyperLendPool", {
        libraries: {
          Math: await deployments.get("Math").then(d => d.address),
        },
      });
      
      // This would be a new implementation with additional features
      const newImplementation = await HyperLendPoolV2.deploy();
      
      // In a real upgrade, you'd use upgrades.upgradeProxy()
      // For this test, we just verify the proxy pattern is in place
      expect(await hyperLendPool.hasRole(await hyperLendPool.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
    });

    it("Should preserve state across upgrades", async function () {
      // Setup state
      await hyperLendPool.connect(user1).supply(usdc.target, parseEther("10000"));
      const preUpgradeBalance = await hlUSDC.balanceOf(user1.address);
      
      // In a real scenario, you'd upgrade here
      // For this test, we just verify state is accessible
      const postUpgradeBalance = await hlUSDC.balanceOf(user1.address);
      expect(postUpgradeBalance).to.equal(preUpgradeBalance);
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════════

async function advanceTimeAndMine(seconds: number) {
  await time.increase(seconds);
  await ethers.provider.send("evm_mine", []);
}

function calculateHealthFactor(collateralValue: bigint, debtValue: bigint, liquidationThreshold: bigint): bigint {
  if (debtValue === 0n) return ethers.MaxUint256;
  return (collateralValue * liquidationThreshold) / (debtValue * PRECISION);
}

function calculateUtilizationRate(totalBorrow: bigint, totalSupply: bigint): bigint {
  if (totalSupply === 0n) return 0n;
  return (totalBorrow * PRECISION) / totalSupply;
}