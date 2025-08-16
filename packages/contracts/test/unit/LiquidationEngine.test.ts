import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deploymentFixture } from "../fixtures/deployments";

describe("LiquidationEngine", function () {
  // ═══════════════════════════════════════════════════════════════════════════════════
  // FIXTURES AND SETUP
  // ═══════════════════════════════════════════════════════════════════════════════════

  let liquidationEngine: any;
  let hyperLendPool: any;
  let priceOracle: any;
  let admin: any;
  let liquidator: any;
  let borrower: any;
  let usdc: any;
  let weth: any;

  const PRECISION = ethers.utils.parseEther("1");
  const LIQUIDATION_THRESHOLD = 8000; // 80%
  const LIQUIDATION_PENALTY = 500;    // 5%
  const MAX_SLIPPAGE = 300;           // 3%

  beforeEach(async function () {
    const deployment = await loadFixture(deploymentFixture);
    liquidationEngine = deployment.liquidationEngine;
    hyperLendPool = deployment.hyperLendPool;
    priceOracle = deployment.priceOracle;
    admin = deployment.admin;
    usdc = deployment.usdc;
    weth = deployment.weth;

    [, liquidator, borrower] = await ethers.getSigners();

    // Grant liquidator role
    const liquidatorRole = await liquidationEngine.LIQUIDATOR_ROLE();
    await liquidationEngine.grantRole(liquidatorRole, liquidator.address);
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Deployment", function () {
    it("Should deploy with correct parameters", async function () {
      expect(await liquidationEngine.liquidationThreshold()).to.equal(LIQUIDATION_THRESHOLD);
      expect(await liquidationEngine.liquidationPenalty()).to.equal(LIQUIDATION_PENALTY);
      expect(await liquidationEngine.maxSlippage()).to.equal(MAX_SLIPPAGE);
    });

    it("Should set correct admin role", async function () {
      const defaultAdminRole = await liquidationEngine.DEFAULT_ADMIN_ROLE();
      expect(await liquidationEngine.hasRole(defaultAdminRole, admin.address)).to.be.true;
    });

    it("Should initialize with correct precision", async function () {
      expect(await liquidationEngine.PRECISION()).to.equal(PRECISION);
    });

    it("Should set pool address after deployment", async function () {
      const poolAddress = await hyperLendPool.getAddress();
      expect(await liquidationEngine.poolAddress()).to.equal(poolAddress);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // LIQUIDATION CALCULATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Liquidation Calculations", function () {
    it("Should calculate liquidation amount correctly", async function () {
      const collateralValue = ethers.utils.parseEther("10000"); // $10,000
      const debtValue = ethers.utils.parseEther("9000");        // $9,000
      const maxLiquidation = ethers.utils.parseEther("2000");   // $2,000 max
      
      const liquidationAmount = await liquidationEngine.calculateLiquidationAmount(
        collateralValue,
        debtValue,
        maxLiquidation
      );
      
      // Should liquidate enough to bring position back to healthy state
      expect(liquidationAmount).to.be.gt(0);
      expect(liquidationAmount).to.be.lte(maxLiquidation);
    });

    it("Should calculate liquidation bonus correctly", async function () {
      const liquidationAmount = ethers.utils.parseEther("1000"); // $1,000
      const expectedBonus = liquidationAmount.mul(LIQUIDATION_PENALTY).div(10000);
      
      const bonus = await liquidationEngine.calculateLiquidationBonus(liquidationAmount);
      expect(bonus).to.equal(expectedBonus);
    });

    it("Should calculate optimal liquidation size", async function () {
      const collateralAmount = ethers.utils.parseEther("5"); // 5 WETH
      const collateralPrice = ethers.utils.parseEther("2000"); // $2000/WETH
      const debtAmount = ethers.utils.parseEther("9000"); // $9000 USDC debt
      
      const optimalAmount = await liquidationEngine.calculateOptimalLiquidation(
        borrower.address,
        await usdc.getAddress(),
        collateralAmount
      );
      
      expect(optimalAmount).to.be.gt(0);
      expect(optimalAmount).to.be.lte(debtAmount);
    });

    it("Should handle partial liquidations", async function () {
      const debtValue = ethers.utils.parseEther("8000");
      const maxLiquidationPercent = 5000; // 50%
      
      const maxPartialLiquidation = await liquidationEngine.calculateMaxPartialLiquidation(
        debtValue,
        maxLiquidationPercent
      );
      
      expect(maxPartialLiquidation).to.equal(debtValue.mul(maxLiquidationPercent).div(10000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // MICRO-LIQUIDATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Micro-Liquidations", function () {
    beforeEach(async function () {
      // Setup a position close to liquidation threshold
      const wethAmount = ethers.utils.parseEther("5"); // 5 WETH
      const usdcBorrow = ethers.utils.parseEther("7500"); // $7,500 (75% LTV)
      
      // Mock borrower position setup
      await liquidationEngine.setMockPosition(
        borrower.address,
        await weth.getAddress(),
        wethAmount,
        await usdc.getAddress(),
        usdcBorrow
      );
    });

    it("Should trigger micro-liquidation when position becomes risky", async function () {
      const microLiquidationThreshold = 7800; // 78% (just below liquidation threshold)
      
      // Position health drops slightly
      await liquidationEngine.updateMicroLiquidationThreshold(microLiquidationThreshold);
      
      const isMicroLiquidatable = await liquidationEngine.isMicroLiquidatable(borrower.address);
      expect(isMicroLiquidatable).to.be.true;
    });

    it("Should calculate micro-liquidation amount", async function () {
      const microAmount = await liquidationEngine.calculateMicroLiquidationAmount(borrower.address);
      
      // Micro-liquidation should be small percentage of total debt
      expect(microAmount).to.be.gt(0);
      expect(microAmount).to.be.lt(ethers.utils.parseEther("1000")); // Less than $1000
    });

    it("Should execute micro-liquidation with reduced penalty", async function () {
      const microPenalty = 200; // 2% (lower than normal 5%)
      await liquidationEngine.setMicroLiquidationPenalty(microPenalty);
      
      const liquidationAmount = ethers.utils.parseEther("500");
      
      await expect(
        liquidationEngine.connect(liquidator).executeMicroLiquidation(
          borrower.address,
          await usdc.getAddress(),
          liquidationAmount,
          await weth.getAddress()
        )
      ).to.emit(liquidationEngine, "MicroLiquidationExecuted")
        .withArgs(borrower.address, await usdc.getAddress(), liquidationAmount);
    });

    it("Should prevent excessive micro-liquidations", async function () {
      const maxMicroLiquidations = 3;
      await liquidationEngine.setMaxMicroLiquidationsPerHour(maxMicroLiquidations);
      
      // Execute maximum allowed micro-liquidations
      for (let i = 0; i < maxMicroLiquidations; i++) {
        await liquidationEngine.connect(liquidator).executeMicroLiquidation(
          borrower.address,
          await usdc.getAddress(),
          ethers.utils.parseEther("100"),
          await weth.getAddress()
        );
      }
      
      // Next micro-liquidation should fail
      await expect(
        liquidationEngine.connect(liquidator).executeMicroLiquidation(
          borrower.address,
          await usdc.getAddress(),
          ethers.utils.parseEther("100"),
          await weth.getAddress()
        )
      ).to.be.revertedWith("LiquidationEngine: Too many micro-liquidations");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // BATCH LIQUIDATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Batch Liquidations", function () {
    it("Should identify multiple liquidatable positions", async function () {
      const borrowers = [borrower.address];
      
      // Setup multiple unhealthy positions
      await liquidationEngine.setMockPosition(
        borrower.address,
        await weth.getAddress(),
        ethers.utils.parseEther("5"),
        await usdc.getAddress(),
        ethers.utils.parseEther("9000") // Unhealthy position
      );
      
      const liquidatablePositions = await liquidationEngine.getBatchLiquidatablePositions(borrowers);
      expect(liquidatablePositions.length).to.be.gt(0);
      expect(liquidatablePositions[0]).to.equal(borrower.address);
    });

    it("Should execute batch liquidations efficiently", async function () {
      const positions = [
        {
          borrower: borrower.address,
          debtAsset: await usdc.getAddress(),
          collateralAsset: await weth.getAddress(),
          liquidationAmount: ethers.utils.parseEther("1000")
        }
      ];
      
      await expect(
        liquidationEngine.connect(liquidator).executeBatchLiquidation(positions)
      ).to.emit(liquidationEngine, "BatchLiquidationExecuted")
        .withArgs(liquidator.address, positions.length);
    });

    it("Should handle partial batch failures gracefully", async function () {
      const positions = [
        {
          borrower: borrower.address,
          debtAsset: await usdc.getAddress(),
          collateralAsset: await weth.getAddress(),
          liquidationAmount: ethers.utils.parseEther("1000")
        },
        {
          borrower: liquidator.address, // Healthy position (should fail)
          debtAsset: await usdc.getAddress(),
          collateralAsset: await weth.getAddress(),
          liquidationAmount: ethers.utils.parseEther("1000")
        }
      ];
      
      const result = await liquidationEngine.connect(liquidator).callStatic.executeBatchLiquidation(positions);
      
      // Should report some successes and some failures
      expect(result.successCount).to.be.gt(0);
      expect(result.failureCount).to.be.gt(0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // REAL-TIME MONITORING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Real-Time Monitoring", function () {
    it("Should monitor position health in real-time", async function () {
      // Setup position monitoring
      await liquidationEngine.startPositionMonitoring(borrower.address);
      
      expect(await liquidationEngine.isPositionMonitored(borrower.address)).to.be.true;
      
      const monitoringData = await liquidationEngine.getPositionMonitoringData(borrower.address);
      expect(monitoringData.isActive).to.be.true;
      expect(monitoringData.lastCheck).to.be.gt(0);
    });

    it("Should trigger alerts when position becomes risky", async function () {
      await liquidationEngine.startPositionMonitoring(borrower.address);
      
      // Simulate position health degradation
      await liquidationEngine.updatePositionHealth(borrower.address, 7900); // 79% health
      
      const alerts = await liquidationEngine.getPositionAlerts(borrower.address);
      expect(alerts.length).to.be.gt(0);
      expect(alerts[0].alertType).to.equal("HEALTH_WARNING");
    });

    it("Should auto-execute liquidations when enabled", async function () {
      await liquidationEngine.enableAutoLiquidation(true);
      await liquidationEngine.setAutoLiquidationThreshold(7500); // 75%
      
      // Setup unhealthy position
      await liquidationEngine.setMockPosition(
        borrower.address,
        await weth.getAddress(),
        ethers.utils.parseEther("5"),
        await usdc.getAddress(),
        ethers.utils.parseEther("9500") // Very unhealthy
      );
      
      // Trigger monitoring update
      await liquidationEngine.updatePositionHealth(borrower.address, 7000); // 70% health
      
      // Auto-liquidation should be triggered
      const events = await liquidationEngine.queryFilter(liquidationEngine.filters.AutoLiquidationTriggered());
      expect(events.length).to.be.gt(0);
    });

    it("Should handle high-frequency position updates", async function () {
      const positions = [];
      for (let i = 0; i < 10; i++) {
        const [, , , user] = await ethers.getSigners();
        positions.push(user.address);
        await liquidationEngine.startPositionMonitoring(user.address);
      }
      
      // Batch update position health
      const healthFactors = new Array(10).fill(8500); // All healthy
      await liquidationEngine.batchUpdatePositionHealth(positions, healthFactors);
      
      // All positions should be updated
      for (const position of positions) {
        const data = await liquidationEngine.getPositionMonitoringData(position);
        expect(data.lastCheck).to.be.gt(0);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SLIPPAGE PROTECTION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Slippage Protection", function () {
    it("Should calculate expected collateral amount with slippage", async function () {
      const liquidationAmount = ethers.utils.parseEther("1000"); // $1000 USDC
      const collateralPrice = ethers.utils.parseEther("2000");   // $2000/WETH
      const slippage = 250; // 2.5%
      
      const expectedCollateral = await liquidationEngine.calculateExpectedCollateral(
        liquidationAmount,
        collateralPrice,
        slippage
      );
      
      // Should account for slippage in calculation
      const baseAmount = liquidationAmount.div(collateralPrice);
      const withSlippage = baseAmount.mul(10000 - slippage).div(10000);
      expect(expectedCollateral).to.be.closeTo(withSlippage, ethers.utils.parseEther("0.001"));
    });

    it("Should reject liquidations with excessive slippage", async function () {
      const liquidationAmount = ethers.utils.parseEther("1000");
      const maxSlippage = await liquidationEngine.maxSlippage();
      const excessiveSlippage = maxSlippage + 100; // Exceed max by 1%
      
      await expect(
        liquidationEngine.connect(liquidator).liquidateWithSlippageProtection(
          borrower.address,
          await usdc.getAddress(),
          liquidationAmount,
          await weth.getAddress(),
          excessiveSlippage
        )
      ).to.be.revertedWith("LiquidationEngine: Slippage too high");
    });

    it("Should adjust liquidation amount based on available collateral", async function () {
      const requestedAmount = ethers.utils.parseEther("5000"); // $5000
      const availableCollateral = ethers.utils.parseEther("2");  // 2 WETH = $4000
      const collateralPrice = ethers.utils.parseEther("2000");
      
      const adjustedAmount = await liquidationEngine.adjustLiquidationForCollateral(
        requestedAmount,
        availableCollateral,
        collateralPrice
      );
      
      // Should be limited by available collateral value
      expect(adjustedAmount).to.be.lte(availableCollateral.mul(collateralPrice));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PARAMETER MANAGEMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Parameter Management", function () {
    it("Should allow admin to update liquidation threshold", async function () {
      const newThreshold = 8500; // 85%
      
      await expect(liquidationEngine.updateLiquidationThreshold(newThreshold))
        .to.emit(liquidationEngine, "LiquidationThresholdUpdated")
        .withArgs(LIQUIDATION_THRESHOLD, newThreshold);
        
      expect(await liquidationEngine.liquidationThreshold()).to.equal(newThreshold);
    });

    it("Should allow admin to update liquidation penalty", async function () {
      const newPenalty = 750; // 7.5%
      
      await expect(liquidationEngine.updateLiquidationPenalty(newPenalty))
        .to.emit(liquidationEngine, "LiquidationPenaltyUpdated")
        .withArgs(LIQUIDATION_PENALTY, newPenalty);
        
      expect(await liquidationEngine.liquidationPenalty()).to.equal(newPenalty);
    });

    it("Should allow admin to update max slippage", async function () {
      const newSlippage = 500; // 5%
      
      await expect(liquidationEngine.updateMaxSlippage(newSlippage))
        .to.emit(liquidationEngine, "MaxSlippageUpdated")
        .withArgs(MAX_SLIPPAGE, newSlippage);
        
      expect(await liquidationEngine.maxSlippage()).to.equal(newSlippage);
    });

    it("Should restrict parameter updates to admin", async function () {
      const [, user] = await ethers.getSigners();
      
      await expect(
        liquidationEngine.connect(user).updateLiquidationThreshold(8500)
      ).to.be.revertedWith("AccessControl:");
      
      await expect(
        liquidationEngine.connect(user).updateLiquidationPenalty(750)
      ).to.be.revertedWith("AccessControl:");
    });

    it("Should validate parameter ranges", async function () {
      // Liquidation threshold should be reasonable (50% - 95%)
      await expect(
        liquidationEngine.updateLiquidationThreshold(4000) // 40%
      ).to.be.revertedWith("LiquidationEngine: Invalid threshold");
      
      await expect(
        liquidationEngine.updateLiquidationThreshold(9600) // 96%
      ).to.be.revertedWith("LiquidationEngine: Invalid threshold");
      
      // Liquidation penalty should be reasonable (1% - 20%)
      await expect(
        liquidationEngine.updateLiquidationPenalty(50) // 0.5%
      ).to.be.revertedWith("LiquidationEngine: Invalid penalty");
      
      await expect(
        liquidationEngine.updateLiquidationPenalty(2500) // 25%
      ).to.be.revertedWith("LiquidationEngine: Invalid penalty");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // EMERGENCY FUNCTIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Emergency Functions", function () {
    it("Should allow emergency liquidation with special parameters", async function () {
      const emergencyPenalty = 0; // No penalty in emergency
      
      await expect(
        liquidationEngine.emergencyLiquidation(
          borrower.address,
          await usdc.getAddress(),
          ethers.utils.parseEther("1000"),
          await weth.getAddress(),
          emergencyPenalty,
          "Market crisis"
        )
      ).to.emit(liquidationEngine, "EmergencyLiquidationExecuted");
    });

    it("Should pause liquidations in emergency", async function () {
      await liquidationEngine.pauseLiquidations();
      expect(await liquidationEngine.liquidationsPaused()).to.be.true;
      
      await expect(
        liquidationEngine.connect(liquidator).executeLiquidation(
          borrower.address,
          await usdc.getAddress(),
          ethers.utils.parseEther("1000"),
          await weth.getAddress()
        )
      ).to.be.revertedWith("LiquidationEngine: Liquidations paused");
    });

    it("Should resume liquidations after emergency", async function () {
      await liquidationEngine.pauseLiquidations();
      await liquidationEngine.resumeLiquidations();
      
      expect(await liquidationEngine.liquidationsPaused()).to.be.false;
      
      // Should allow normal liquidations again
      await expect(
        liquidationEngine.connect(liquidator).executeLiquidation(
          borrower.address,
          await usdc.getAddress(),
          ethers.utils.parseEther("1000"),
          await weth.getAddress()
        )
      ).to.not.be.revertedWith("LiquidationEngine: Liquidations paused");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Integration Tests", function () {
    it("Should integrate with HyperLendPool for liquidations", async function () {
      // This would test actual integration with the pool
      // For now, verify interface compatibility
      const poolAddress = await liquidationEngine.poolAddress();
      expect(poolAddress).to.equal(await hyperLendPool.getAddress());
    });

    it("Should integrate with PriceOracle for collateral valuation", async function () {
      const collateralAsset = await weth.getAddress();
      const collateralAmount = ethers.utils.parseEther("1");
      
      // Mock price oracle integration
      const collateralValue = await liquidationEngine.getCollateralValue(
        collateralAsset,
        collateralAmount
      );
      
      expect(collateralValue).to.be.gt(0);
    });

    it("Should handle complex liquidation scenarios", async function () {
      // Multi-asset collateral liquidation
      const collateralAssets = [await weth.getAddress(), await usdc.getAddress()];
      const collateralAmounts = [ethers.utils.parseEther("2"), ethers.utils.parseEther("1000")];
      const debtAsset = await usdc.getAddress();
      const liquidationAmount = ethers.utils.parseEther("2000");
      
      const liquidationPlan = await liquidationEngine.calculateMultiCollateralLiquidation(
        borrower.address,
        collateralAssets,
        collateralAmounts,
        debtAsset,
        liquidationAmount
      );
      
      expect(liquidationPlan.totalCollateralValue).to.be.gt(0);
      expect(liquidationPlan.liquidationAmounts.length).to.equal(collateralAssets.length);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PERFORMANCE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Performance Tests", function () {
    it("Should efficiently process high-frequency liquidations", async function () {
      const numLiquidations = 50;
      const startTime = Date.now();
      
      for (let i = 0; i < numLiquidations; i++) {
        // Mock rapid liquidation processing
        await liquidationEngine.processLiquidationQueue();
      }
      
      const endTime = Date.now();
      const avgTimePerLiquidation = (endTime - startTime) / numLiquidations;
      
      console.log(`Average liquidation processing time: ${avgTimePerLiquidation}ms`);
      expect(avgTimePerLiquidation).to.be.lt(100); // Should be under 100ms per liquidation
    });

    it("Should handle batch position monitoring efficiently", async function () {
      const numPositions = 100;
      const positions = [];
      
      // Create mock positions
      for (let i = 0; i < numPositions; i++) {
        const mockAddress = ethers.utils.getAddress(ethers.utils.keccak256(ethers.utils.toUtf8Bytes(`user${i}`)).slice(0, 42));
        positions.push(mockAddress);
      }
      
      const startTime = Date.now();
      await liquidationEngine.batchMonitorPositions(positions);
      const endTime = Date.now();
      
      console.log(`Batch monitoring of ${numPositions} positions: ${endTime - startTime}ms`);
      expect(endTime - startTime).to.be.lt(5000); // Should complete in under 5 seconds
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Error Handling", function () {
    it("Should handle invalid liquidation attempts gracefully", async function () {
      // Try to liquidate healthy position
      await expect(
        liquidationEngine.connect(liquidator).executeLiquidation(
          admin.address, // Admin has no debt
          await usdc.getAddress(),
          ethers.utils.parseEther("1000"),
          await weth.getAddress()
        )
      ).to.be.revertedWith("LiquidationEngine: Position not liquidatable");
    });

    it("Should handle insufficient collateral scenarios", async function () {
      const largeAmount = ethers.utils.parseEther("1000000"); // Very large amount
      
      await expect(
        liquidationEngine.connect(liquidator).executeLiquidation(
          borrower.address,
          await usdc.getAddress(),
          largeAmount,
          await weth.getAddress()
        )
      ).to.be.revertedWith("LiquidationEngine: Insufficient collateral");
    });

    it("Should validate liquidator permissions", async function () {
      const [, , , unauthorizedUser] = await ethers.getSigners();
      
      await expect(
        liquidationEngine.connect(unauthorizedUser).executeLiquidation(
          borrower.address,
          await usdc.getAddress(),
          ethers.utils.parseEther("1000"),
          await weth.getAddress()
        )
      ).to.be.revertedWith("AccessControl:");
    });
  });
});