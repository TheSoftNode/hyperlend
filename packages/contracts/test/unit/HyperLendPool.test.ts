import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deploymentFixture } from "../fixtures/deployments";

describe("HyperLendPool", function () {
  // ═══════════════════════════════════════════════════════════════════════════════════
  // FIXTURES AND SETUP
  // ═══════════════════════════════════════════════════════════════════════════════════

  let hyperLendPool: any;
  let interestRateModel: any;
  let liquidationEngine: any;
  let priceOracle: any;
  let riskManager: any;
  let usdc: any;
  let weth: any;
  let hlUSDC: any;
  let hlWETH: any;
  let debtUSDC: any;
  let debtWETH: any;
  
  let admin: any;
  let user1: any;
  let user2: any;
  let liquidator: any;

  const PRECISION = ethers.utils.parseEther("1");
  const USDC_PRICE = ethers.utils.parseEther("1");     // $1
  const WETH_PRICE = ethers.utils.parseEther("2000");  // $2000

  beforeEach(async function () {
    const deployment = await loadFixture(deploymentFixture);
    
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
    admin = deployment.admin;

    [, user1, user2, liquidator] = await ethers.getSigners();

    // Setup initial token balances
    await usdc.transfer(user1.address, ethers.utils.parseEther("100000"));
    await usdc.transfer(user2.address, ethers.utils.parseEther("100000"));
    await weth.transfer(user1.address, ethers.utils.parseEther("100"));
    await weth.transfer(user2.address, ethers.utils.parseEther("100"));

    // Approve tokens for pool
    await usdc.connect(user1).approve(await hyperLendPool.getAddress(), ethers.constants.MaxUint256);
    await usdc.connect(user2).approve(await hyperLendPool.getAddress(), ethers.constants.MaxUint256);
    await weth.connect(user1).approve(await hyperLendPool.getAddress(), ethers.constants.MaxUint256);
    await weth.connect(user2).approve(await hyperLendPool.getAddress(), ethers.constants.MaxUint256);
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Deployment", function () {
    it("Should deploy with correct addresses", async function () {
      expect(await hyperLendPool.interestRateModel()).to.equal(await interestRateModel.getAddress());
      expect(await hyperLendPool.liquidationEngine()).to.equal(await liquidationEngine.getAddress());
      expect(await hyperLendPool.priceOracle()).to.equal(await priceOracle.getAddress());
      expect(await hyperLendPool.riskManager()).to.equal(await riskManager.getAddress());
    });

    it("Should have correct admin role", async function () {
      const defaultAdminRole = await hyperLendPool.DEFAULT_ADMIN_ROLE();
      expect(await hyperLendPool.hasRole(defaultAdminRole, admin.address)).to.be.true;
    });

    it("Should not be paused initially", async function () {
      expect(await hyperLendPool.paused()).to.be.false;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // NATIVE STT FUNCTIONALITY TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Native STT Operations", function () {
    it("Should allow STT supply via payable function", async function () {
      const sttAmount = ethers.utils.parseEther("10"); // 10 STT
      
      await expect(
        hyperLendPool.connect(user1).supplySTT({ value: sttAmount })
      ).to.emit(hyperLendPool, "STTSupplied")
        .withArgs(user1.address, sttAmount);

      // Check pool STT balance
      expect(await ethers.provider.getBalance(await hyperLendPool.getAddress())).to.equal(sttAmount);
    });

    it("Should reject zero STT supply", async function () {
      await expect(
        hyperLendPool.connect(user1).supplySTT({ value: 0 })
      ).to.be.revertedWith("HyperLend: Must supply STT");
    });

    it("Should allow STT borrowing against collateral", async function () {
      const collateralAmount = ethers.utils.parseEther("5"); // 5 WETH = $10k
      const borrowAmount = ethers.utils.parseEther("5000"); // 5000 STT (50% LTV)
      
      // First supply WETH as collateral
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), collateralAmount);
      
      // Then borrow STT
      const balanceBefore = await user1.getBalance();
      await expect(
        hyperLendPool.connect(user1).borrowSTT(borrowAmount)
      ).to.emit(hyperLendPool, "STTBorrowed")
        .withArgs(user1.address, borrowAmount);

      // Check user received STT
      const balanceAfter = await user1.getBalance();
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should allow STT repayment", async function () {
      const collateralAmount = ethers.utils.parseEther("5");
      const borrowAmount = ethers.utils.parseEther("3000");
      const repayAmount = ethers.utils.parseEther("1000");
      
      // Setup borrow position
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), collateralAmount);
      await hyperLendPool.connect(user1).borrowSTT(borrowAmount);
      
      // Repay STT
      await expect(
        hyperLendPool.connect(user1).repaySTT({ value: repayAmount })
      ).to.emit(hyperLendPool, "STTRepaid")
        .withArgs(user1.address, repayAmount);
    });

    it("Should handle STT withdrawal", async function () {
      const supplyAmount = ethers.utils.parseEther("10");
      const withdrawAmount = ethers.utils.parseEther("5");
      
      // Supply STT first
      await hyperLendPool.connect(user1).supplySTT({ value: supplyAmount });
      
      // Withdraw STT
      const balanceBefore = await user1.getBalance();
      await expect(
        hyperLendPool.connect(user1).withdrawSTT(withdrawAmount)
      ).to.emit(hyperLendPool, "STTWithdrawn")
        .withArgs(user1.address, withdrawAmount);

      const balanceAfter = await user1.getBalance();
      expect(balanceAfter).to.be.gt(balanceBefore);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ERC20 TOKEN OPERATIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("ERC20 Token Operations", function () {
    it("Should allow users to supply ERC20 tokens", async function () {
      const supplyAmount = ethers.utils.parseEther("1000");
      const usdcAddress = await usdc.getAddress();
      
      await expect(
        hyperLendPool.connect(user1).supply(usdcAddress, supplyAmount)
      ).to.emit(hyperLendPool, "Supply")
        .withArgs(user1.address, usdcAddress, supplyAmount);

      // Check token was transferred to pool
      expect(await usdc.balanceOf(await hyperLendPool.getAddress())).to.equal(supplyAmount);
    });

    it("Should allow users to withdraw ERC20 tokens", async function () {
      const supplyAmount = ethers.utils.parseEther("1000");
      const withdrawAmount = ethers.utils.parseEther("500");
      const usdcAddress = await usdc.getAddress();
      
      // Supply first
      await hyperLendPool.connect(user1).supply(usdcAddress, supplyAmount);
      
      // Withdraw
      await expect(
        hyperLendPool.connect(user1).withdraw(usdcAddress, withdrawAmount)
      ).to.emit(hyperLendPool, "Withdraw")
        .withArgs(user1.address, usdcAddress, withdrawAmount);

      expect(await usdc.balanceOf(await hyperLendPool.getAddress())).to.equal(supplyAmount.sub(withdrawAmount));
    });

    it("Should allow users to borrow ERC20 tokens", async function () {
      const collateralAmount = ethers.utils.parseEther("10"); // 10 WETH = $20k
      const borrowAmount = ethers.utils.parseEther("10000");  // $10k USDC (50% LTV)
      
      // Supply collateral
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), collateralAmount);
      
      // Supply liquidity for borrowing
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("50000"));
      
      // Borrow
      await expect(
        hyperLendPool.connect(user1).borrow(await usdc.getAddress(), borrowAmount)
      ).to.emit(hyperLendPool, "Borrow")
        .withArgs(user1.address, await usdc.getAddress(), borrowAmount);

      expect(await usdc.balanceOf(user1.address)).to.equal(ethers.utils.parseEther("110000")); // 100k initial + 10k borrowed
    });

    it("Should allow users to repay ERC20 debt", async function () {
      const collateralAmount = ethers.utils.parseEther("10");
      const borrowAmount = ethers.utils.parseEther("10000");
      const repayAmount = ethers.utils.parseEther("5000");
      
      // Setup borrow position
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("50000"));
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), collateralAmount);
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), borrowAmount);
      
      // Repay
      await expect(
        hyperLendPool.connect(user1).repay(await usdc.getAddress(), repayAmount)
      ).to.emit(hyperLendPool, "Repay")
        .withArgs(user1.address, await usdc.getAddress(), repayAmount);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Batch Operations", function () {
    it("Should execute batch supply operations", async function () {
      const assets = [await usdc.getAddress(), await weth.getAddress()];
      const amounts = [ethers.utils.parseEther("5000"), ethers.utils.parseEther("2")];
      
      await expect(
        hyperLendPool.connect(user1).batchSupply(assets, amounts)
      ).to.emit(hyperLendPool, "BatchSupplyExecuted")
        .withArgs(user1.address, assets.length);

      expect(await usdc.balanceOf(await hyperLendPool.getAddress())).to.equal(amounts[0]);
      expect(await weth.balanceOf(await hyperLendPool.getAddress())).to.equal(amounts[1]);
    });

    it("Should execute batch withdraw operations", async function () {
      const assets = [await usdc.getAddress(), await weth.getAddress()];
      const supplyAmounts = [ethers.utils.parseEther("5000"), ethers.utils.parseEther("2")];
      const withdrawAmounts = [ethers.utils.parseEther("2000"), ethers.utils.parseEther("1")];
      
      // Supply first
      await hyperLendPool.connect(user1).batchSupply(assets, supplyAmounts);
      
      // Batch withdraw
      await expect(
        hyperLendPool.connect(user1).batchWithdraw(assets, withdrawAmounts)
      ).to.emit(hyperLendPool, "BatchWithdrawExecuted")
        .withArgs(user1.address, assets.length);
    });

    it("Should reject mismatched batch arrays", async function () {
      const assets = [await usdc.getAddress()];
      const amounts = [ethers.utils.parseEther("1000"), ethers.utils.parseEther("2000")]; // Mismatched length
      
      await expect(
        hyperLendPool.connect(user1).batchSupply(assets, amounts)
      ).to.be.revertedWith("HyperLend: Array length mismatch");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // HEALTH FACTOR TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Health Factor Calculations", function () {
    beforeEach(async function () {
      // Setup basic lending position
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("50000"));
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), ethers.utils.parseEther("10")); // $20k collateral
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), ethers.utils.parseEther("10000")); // $10k debt
    });

    it("Should calculate health factor correctly", async function () {
      const healthFactor = await hyperLendPool.getHealthFactor(user1.address);
      
      // With $20k collateral and $10k debt at 80% liquidation threshold:
      // HF = (20000 * 0.8) / 10000 = 1.6
      expect(healthFactor).to.be.gt(ethers.utils.parseEther("1.5"));
      expect(healthFactor).to.be.lt(ethers.utils.parseEther("1.7"));
    });

    it("Should return max uint for users with no debt", async function () {
      const healthFactor = await hyperLendPool.getHealthFactor(user2.address);
      expect(healthFactor).to.equal(ethers.constants.MaxUint256);
    });

    it("Should update health factor when collateral price changes", async function () {
      const initialHF = await hyperLendPool.getHealthFactor(user1.address);
      
      // Drop WETH price by 20%
      await priceOracle.setAssetPrice(await weth.getAddress(), ethers.utils.parseEther("1600"));
      
      const newHF = await hyperLendPool.getHealthFactor(user1.address);
      expect(newHF).to.be.lt(initialHF);
    });

    it("Should identify liquidatable positions", async function () {
      // Drop WETH price significantly to make position liquidatable
      await priceOracle.setAssetPrice(await weth.getAddress(), ethers.utils.parseEther("1200")); // 40% drop
      
      const isLiquidatable = await hyperLendPool.isLiquidatable(user1.address);
      expect(isLiquidatable).to.be.true;
      
      const healthFactor = await hyperLendPool.getHealthFactor(user1.address);
      expect(healthFactor).to.be.lt(ethers.utils.parseEther("1"));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEREST RATE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Interest Rate Management", function () {
    beforeEach(async function () {
      // Setup utilization
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("100000"));
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), ethers.utils.parseEther("25")); // $50k collateral
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), ethers.utils.parseEther("50000")); // 50% utilization
    });

    it("Should calculate utilization rate correctly", async function () {
      const utilizationRate = await hyperLendPool.getUtilizationRate(await usdc.getAddress());
      expect(utilizationRate).to.equal(5000); // 50%
    });

    it("Should update interest rates based on utilization", async function () {
      const marketData = await hyperLendPool.getMarketData(await usdc.getAddress());
      
      expect(marketData.borrowAPY).to.be.gt(0);
      expect(marketData.supplyAPY).to.be.gt(0);
      expect(marketData.borrowAPY).to.be.gt(marketData.supplyAPY);
    });

    it("Should accrue interest over time", async function () {
      const initialMarketData = await hyperLendPool.getMarketData(await usdc.getAddress());
      
      // Fast forward time
      await time.increase(86400 * 30); // 30 days
      
      // Update interest
      await hyperLendPool.updateMarketInterest(await usdc.getAddress());
      
      const finalMarketData = await hyperLendPool.getMarketData(await usdc.getAddress());
      expect(finalMarketData.totalBorrows).to.be.gt(initialMarketData.totalBorrows);
    });

    it("Should handle batch interest updates", async function () {
      const assets = [await usdc.getAddress(), await weth.getAddress()];
      
      await expect(
        hyperLendPool.batchUpdateInterest(assets)
      ).to.emit(hyperLendPool, "BatchInterestUpdate")
        .withArgs(assets);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // LIQUIDATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Liquidations", function () {
    beforeEach(async function () {
      // Setup liquidatable position
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("100000"));
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), ethers.utils.parseEther("10"));
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), ethers.utils.parseEther("15000")); // 75% LTV
      
      // Setup liquidator
      await usdc.transfer(liquidator.address, ethers.utils.parseEther("20000"));
      await usdc.connect(liquidator).approve(await hyperLendPool.getAddress(), ethers.constants.MaxUint256);
    });

    it("Should execute liquidation when position is unhealthy", async function () {
      // Drop collateral price to make position liquidatable
      await priceOracle.setAssetPrice(await weth.getAddress(), ethers.utils.parseEther("1600")); // 20% drop
      
      const liquidationAmount = ethers.utils.parseEther("5000");
      
      await expect(
        hyperLendPool.connect(liquidator).liquidate(
          user1.address,
          await usdc.getAddress(),
          liquidationAmount,
          await weth.getAddress()
        )
      ).to.emit(hyperLendPool, "Liquidation")
        .withArgs(
          liquidator.address,
          user1.address,
          await usdc.getAddress(),
          liquidationAmount
        );
    });

    it("Should reject liquidation of healthy positions", async function () {
      const liquidationAmount = ethers.utils.parseEther("5000");
      
      await expect(
        hyperLendPool.connect(liquidator).liquidate(
          user1.address,
          await usdc.getAddress(),
          liquidationAmount,
          await weth.getAddress()
        )
      ).to.be.revertedWith("HyperLend: Position not liquidatable");
    });

    it("Should calculate liquidation bonus correctly", async function () {
      // Make position liquidatable
      await priceOracle.setAssetPrice(await weth.getAddress(), ethers.utils.parseEther("1500"));
      
      const liquidationAmount = ethers.utils.parseEther("5000");
      const expectedBonus = liquidationAmount.mul(500).div(10000); // 5% bonus
      
      const liquidationData = await hyperLendPool.calculateLiquidation(
        user1.address,
        await usdc.getAddress(),
        liquidationAmount,
        await weth.getAddress()
      );
      
      expect(liquidationData.liquidationBonus).to.equal(expectedBonus);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // REAL-TIME METRICS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Real-Time Metrics", function () {
    beforeEach(async function () {
      // Setup some activity
      await hyperLendPool.connect(user1).supply(await usdc.getAddress(), ethers.utils.parseEther("50000"));
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), ethers.utils.parseEther("10"));
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), ethers.utils.parseEther("20000"));
    });

    it("Should provide real-time TVL", async function () {
      const metrics = await hyperLendPool.getRealTimeMetrics();
      
      expect(metrics.tvl).to.be.gt(0);
      expect(metrics.totalBorrowed).to.be.gt(0);
      expect(metrics.utilizationRate).to.be.gt(0);
      expect(metrics.lastUpdate).to.be.gt(0);
    });

    it("Should track user account data", async function () {
      const userData = await hyperLendPool.getUserAccountData(user1.address);
      
      expect(userData.totalCollateralValue).to.be.gt(0);
      expect(userData.totalDebtValue).to.be.gt(0);
      expect(userData.healthFactor).to.be.gt(0);
      expect(userData.ltv).to.be.gt(0);
      expect(userData.availableBorrow).to.be.gte(0);
    });

    it("Should update metrics in real-time", async function () {
      const initialMetrics = await hyperLendPool.getRealTimeMetrics();
      
      // Add more activity
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("25000"));
      
      const updatedMetrics = await hyperLendPool.getRealTimeMetrics();
      expect(updatedMetrics.tvl).to.be.gt(initialMetrics.tvl);
      expect(updatedMetrics.lastUpdate).to.be.gte(initialMetrics.lastUpdate);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ADMIN FUNCTIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Admin Functions", function () {
    it("Should allow admin to pause the contract", async function () {
      await hyperLendPool.pause();
      expect(await hyperLendPool.paused()).to.be.true;
      
      // Operations should be paused
      await expect(
        hyperLendPool.connect(user1).supply(await usdc.getAddress(), ethers.utils.parseEther("1000"))
      ).to.be.revertedWith("Pausable: paused");
    });

    it("Should allow admin to unpause the contract", async function () {
      await hyperLendPool.pause();
      await hyperLendPool.unpause();
      
      expect(await hyperLendPool.paused()).to.be.false;
      
      // Operations should work again
      await expect(
        hyperLendPool.connect(user1).supply(await usdc.getAddress(), ethers.utils.parseEther("1000"))
      ).to.not.be.reverted;
    });

    it("Should restrict admin functions to admin role", async function () {
      await expect(
        hyperLendPool.connect(user1).pause()
      ).to.be.revertedWith("AccessControl:");
      
      await expect(
        hyperLendPool.connect(user1).setInterestRateModel(await interestRateModel.getAddress())
      ).to.be.revertedWith("AccessControl:");
    });

    it("Should allow admin to update contract addresses", async function () {
      const newPriceOracle = await priceOracle.getAddress(); // Same address for test
      
      await expect(
        hyperLendPool.setPriceOracle(newPriceOracle)
      ).to.emit(hyperLendPool, "PriceOracleUpdated")
        .withArgs(await priceOracle.getAddress(), newPriceOracle);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Error Handling", function () {
    it("Should reject zero amount operations", async function () {
      await expect(
        hyperLendPool.connect(user1).supply(await usdc.getAddress(), 0)
      ).to.be.revertedWith("HyperLend: Invalid amount");
      
      await expect(
        hyperLendPool.connect(user1).withdraw(await usdc.getAddress(), 0)
      ).to.be.revertedWith("HyperLend: Invalid amount");
    });

    it("Should reject operations with invalid assets", async function () {
      const invalidAsset = ethers.constants.AddressZero;
      
      await expect(
        hyperLendPool.connect(user1).supply(invalidAsset, ethers.utils.parseEther("1000"))
      ).to.be.revertedWith("HyperLend: Invalid asset");
    });

    it("Should handle insufficient balance gracefully", async function () {
      const largeAmount = ethers.utils.parseEther("1000000");
      
      await expect(
        hyperLendPool.connect(user1).supply(await usdc.getAddress(), largeAmount)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });

    it("Should prevent borrowing without sufficient collateral", async function () {
      const borrowAmount = ethers.utils.parseEther("10000");
      
      await expect(
        hyperLendPool.connect(user1).borrow(await usdc.getAddress(), borrowAmount)
      ).to.be.revertedWith("HyperLend: Insufficient collateral");
    });

    it("Should prevent withdrawal that would make position unhealthy", async function () {
      // Setup borrowing position
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("50000"));
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), ethers.utils.parseEther("10"));
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), ethers.utils.parseEther("15000"));
      
      // Try to withdraw too much collateral
      await expect(
        hyperLendPool.connect(user1).withdraw(await weth.getAddress(), ethers.utils.parseEther("9"))
      ).to.be.revertedWith("HyperLend: Withdrawal not allowed");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Integration Tests", function () {
    it("Should handle complete lending cycle", async function () {
      const supplyAmount = ethers.utils.parseEther("10000");
      const collateralAmount = ethers.utils.parseEther("5");
      const borrowAmount = ethers.utils.parseEther("7000");
      const repayAmount = ethers.utils.parseEther("3000");
      const withdrawAmount = ethers.utils.parseEther("2000");
      
      // 1. Supply liquidity
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), supplyAmount);
      
      // 2. Supply collateral and borrow
      await hyperLendPool.connect(user1).supply(await weth.getAddress(), collateralAmount);
      await hyperLendPool.connect(user1).borrow(await usdc.getAddress(), borrowAmount);
      
      // 3. Repay part of debt
      await hyperLendPool.connect(user1).repay(await usdc.getAddress(), repayAmount);
      
      // 4. Withdraw some collateral
      await hyperLendPool.connect(user1).withdraw(await weth.getAddress(), ethers.utils.parseEther("1"));
      
      // 5. Withdraw liquidity
      await hyperLendPool.connect(user2).withdraw(await usdc.getAddress(), withdrawAmount);
      
      // Check final state
      const user1Data = await hyperLendPool.getUserAccountData(user1.address);
      expect(user1Data.totalDebtValue).to.equal(borrowAmount.sub(repayAmount));
      expect(user1Data.healthFactor).to.be.gt(ethers.utils.parseEther("1"));
    });

    it("Should handle multiple users simultaneously", async function () {
      const users = [user1, user2];
      const supplyAmounts = [ethers.utils.parseEther("25000"), ethers.utils.parseEther("15000")];
      
      // Multiple users supply
      for (let i = 0; i < users.length; i++) {
        await hyperLendPool.connect(users[i]).supply(await usdc.getAddress(), supplyAmounts[i]);
      }
      
      // Check total supplies
      const marketData = await hyperLendPool.getMarketData(await usdc.getAddress());
      expect(marketData.totalSupply).to.equal(supplyAmounts[0].add(supplyAmounts[1]));
      
      // Multiple users can withdraw
      for (let i = 0; i < users.length; i++) {
        await hyperLendPool.connect(users[i]).withdraw(await usdc.getAddress(), ethers.utils.parseEther("5000"));
      }
    });

    it("Should maintain accurate accounting across operations", async function () {
      const initialBalance = await usdc.balanceOf(await hyperLendPool.getAddress());
      
      // Series of operations
      await hyperLendPool.connect(user1).supply(await usdc.getAddress(), ethers.utils.parseEther("10000"));
      await hyperLendPool.connect(user2).supply(await usdc.getAddress(), ethers.utils.parseEther("5000"));
      await hyperLendPool.connect(user1).withdraw(await usdc.getAddress(), ethers.utils.parseEther("3000"));
      
      const finalBalance = await usdc.balanceOf(await hyperLendPool.getAddress());
      const expectedBalance = initialBalance.add(ethers.utils.parseEther("12000")); // +15k -3k = +12k
      
      expect(finalBalance).to.equal(expectedBalance);
    });
  });
});
