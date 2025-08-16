import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deploymentFixture } from "../fixtures/deployments";

describe("RiskManager", function () {
  // ═══════════════════════════════════════════════════════════════════════════════════
  // FIXTURES AND SETUP
  // ═══════════════════════════════════════════════════════════════════════════════════

  let riskManager: any;
  let priceOracle: any;
  let admin: any;
  let user1: any;
  let user2: any;
  let usdc: any;
  let weth: any;

  const PRECISION = ethers.utils.parseEther("1");
  const DEFAULT_LTV = 7000;              // 70%
  const LIQUIDATION_THRESHOLD = 8000;    // 80%
  const LIQUIDATION_PENALTY = 500;       // 5%

  beforeEach(async function () {
    const deployment = await loadFixture(deploymentFixture);
    riskManager = deployment.riskManager;
    priceOracle = deployment.priceOracle;
    admin = deployment.admin;
    usdc = deployment.usdc;
    weth = deployment.weth;

    [, user1, user2] = await ethers.getSigners();
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Deployment", function () {
    it("Should deploy with correct parameters", async function () {
      expect(await riskManager.defaultLTV()).to.equal(DEFAULT_LTV);
      expect(await riskManager.liquidationThreshold()).to.equal(LIQUIDATION_THRESHOLD);
      expect(await riskManager.liquidationPenalty()).to.equal(LIQUIDATION_PENALTY);
    });

    it("Should set correct admin role", async function () {
      const defaultAdminRole = await riskManager.DEFAULT_ADMIN_ROLE();
      expect(await riskManager.hasRole(defaultAdminRole, admin.address)).to.be.true;
    });

    it("Should initialize with correct precision", async function () {
      expect(await riskManager.PRECISION()).to.equal(PRECISION);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // RISK CALCULATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Risk Calculations", function () {
    it("Should calculate health factor correctly", async function () {
      const collateralValue = ethers.utils.parseEther("10000"); // $10,000
      const debtValue = ethers.utils.parseEther("6000");        // $6,000
      
      const healthFactor = await riskManager.calculateHealthFactor(
        collateralValue,
        debtValue,
        LIQUIDATION_THRESHOLD
      );
      
      // Health factor = (collateralValue * liquidationThreshold) / debtValue
      // HF = (10000 * 0.8) / 6000 = 8000 / 6000 = 1.333...
      const expectedHF = collateralValue.mul(LIQUIDATION_THRESHOLD).div(debtValue.mul(10000));
      expect(healthFactor).to.equal(expectedHF);
    });

    it("Should return max uint for zero debt", async function () {
      const collateralValue = ethers.utils.parseEther("10000");
      const debtValue = 0;
      
      const healthFactor = await riskManager.calculateHealthFactor(
        collateralValue,
        debtValue,
        LIQUIDATION_THRESHOLD
      );
      
      expect(healthFactor).to.equal(ethers.constants.MaxUint256);
    });

    it("Should calculate loan-to-value ratio", async function () {
      const collateralValue = ethers.utils.parseEther("10000");
      const debtValue = ethers.utils.parseEther("7000");
      
      const ltv = await riskManager.calculateLTV(collateralValue, debtValue);
      
      // LTV = debtValue / collateralValue * 100%
      // LTV = 7000 / 10000 = 70%
      const expectedLTV = debtValue.mul(10000).div(collateralValue);
      expect(ltv).to.equal(expectedLTV);
    });

    it("Should determine liquidation eligibility", async function () {
      const healthyHF = ethers.utils.parseEther("1.5");    // 150% - healthy
      const unhealthyHF = ethers.utils.parseEther("0.95");  // 95% - unhealthy
      
      expect(await riskManager.isLiquidatable(healthyHF)).to.be.false;
      expect(await riskManager.isLiquidatable(unhealthyHF)).to.be.true;
    });

    it("Should calculate maximum borrow amount", async function () {
      const collateralValue = ethers.utils.parseEther("10000");
      const existingDebt = ethers.utils.parseEther("3000");
      const ltv = DEFAULT_LTV; // 70%
      
      const maxBorrow = await riskManager.calculateMaxBorrow(
        collateralValue,
        existingDebt,
        ltv
      );
      
      // Max total debt = collateralValue * LTV
      // Max additional borrow = (collateralValue * LTV) - existingDebt
      const maxTotalDebt = collateralValue.mul(ltv).div(10000);
      const expectedMaxBorrow = maxTotalDebt.sub(existingDebt);
      expect(maxBorrow).to.equal(expectedMaxBorrow);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // VALUE-AT-RISK TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Value-at-Risk (VaR)", function () {
    beforeEach(async function () {
      // Setup mock price history for VaR calculations
      const usdcAddress = await usdc.getAddress();
      const wethAddress = await weth.getAddress();
      
      // Set current prices
      await priceOracle.setAssetPrice(usdcAddress, ethers.utils.parseEther("1"));
      await priceOracle.setAssetPrice(wethAddress, ethers.utils.parseEther("2000"));
    });

    it("Should calculate portfolio VaR", async function () {
      const portfolio = {
        assets: [await usdc.getAddress(), await weth.getAddress()],
        amounts: [ethers.utils.parseEther("10000"), ethers.utils.parseEther("5")],
        prices: [ethers.utils.parseEther("1"), ethers.utils.parseEther("2000")]
      };
      
      const confidenceLevel = 9500; // 95%
      const timeHorizon = 86400;    // 1 day
      
      const portfolioVaR = await riskManager.calculatePortfolioVaR(
        portfolio.assets,
        portfolio.amounts,
        portfolio.prices,
        confidenceLevel,
        timeHorizon
      );
      
      expect(portfolioVaR).to.be.gt(0);
      expect(portfolioVaR).to.be.lt(ethers.utils.parseEther("20000")); // Should be less than total portfolio value
    });

    it("Should calculate asset-specific VaR", async function () {
      const wethAddress = await weth.getAddress();
      const amount = ethers.utils.parseEther("5");
      const price = ethers.utils.parseEther("2000");
      const volatility = 6000; // 60% annual volatility
      const confidenceLevel = 9500; // 95%
      
      const assetVaR = await riskManager.calculateAssetVaR(
        wethAddress,
        amount,
        price,
        volatility,
        confidenceLevel
      );
      
      expect(assetVaR).to.be.gt(0);
      expect(assetVaR).to.be.lt(amount.mul(price)); // VaR should be less than total value
    });

    it("Should track VaR over time", async function () {
      const portfolio = {
        assets: [await weth.getAddress()],
        amounts: [ethers.utils.parseEther("10")],
        prices: [ethers.utils.parseEther("2000")]
      };
      
      // Calculate VaR at different time points
      let var1 = await riskManager.calculatePortfolioVaR(
        portfolio.assets,
        portfolio.amounts,
        portfolio.prices,
        9500,
        86400
      );
      
      // Simulate price change
      await time.increase(3600); // 1 hour later
      portfolio.prices = [ethers.utils.parseEther("2100")]; // 5% increase
      
      let var2 = await riskManager.calculatePortfolioVaR(
        portfolio.assets,
        portfolio.amounts,
        portfolio.prices,
        9500,
        86400
      );
      
      // VaR should change with price changes
      expect(var2).to.not.equal(var1);
    });

    it("Should calculate conditional VaR (Expected Shortfall)", async function () {
      const portfolio = {
        assets: [await weth.getAddress()],
        amounts: [ethers.utils.parseEther("5")],
        prices: [ethers.utils.parseEther("2000")]
      };
      
      const confidenceLevel = 9500; // 95%
      
      const cvar = await riskManager.calculateConditionalVaR(
        portfolio.assets,
        portfolio.amounts,
        portfolio.prices,
        confidenceLevel
      );
      
      // CVaR should be higher than VaR
      const portfolioVaR = await riskManager.calculatePortfolioVaR(
        portfolio.assets,
        portfolio.amounts,
        portfolio.prices,
        confidenceLevel,
        86400
      );
      
      expect(cvar).to.be.gte(portfolioVaR);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // STRESS TESTING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Stress Testing", function () {
    it("Should perform stress test with price shocks", async function () {
      const portfolio = {
        assets: [await weth.getAddress(), await usdc.getAddress()],
        amounts: [ethers.utils.parseEther("10"), ethers.utils.parseEther("20000")]
      };
      
      const priceShocks = [-3000, 0]; // 30% drop in WETH, no change in USDC
      
      const stressResult = await riskManager.performStressTest(
        portfolio.assets,
        portfolio.amounts,
        priceShocks
      );
      
      expect(stressResult.totalLoss).to.be.gt(0);
      expect(stressResult.worstCaseValue).to.be.lt(stressResult.baseValue);
      expect(stressResult.survivedShock).to.be.a('boolean');
    });

    it("Should test multiple stress scenarios", async function () {
      const portfolio = {
        assets: [await weth.getAddress()],
        amounts: [ethers.utils.parseEther("5")]
      };
      
      const scenarios = [
        { name: "Mild Correction", shocks: [-1000] },    // 10% drop
        { name: "Market Crash", shocks: [-5000] },       // 50% drop
        { name: "Black Swan", shocks: [-8000] }          // 80% drop
      ];
      
      const results = [];
      for (const scenario of scenarios) {
        const result = await riskManager.performStressTest(
          portfolio.assets,
          portfolio.amounts,
          scenario.shocks
        );
        results.push({
          name: scenario.name,
          loss: result.totalLoss,
          survived: result.survivedShock
        });
      }
      
      // Losses should increase with severity
      expect(results[0].loss).to.be.lt(results[1].loss);
      expect(results[1].loss).to.be.lt(results[2].loss);
      
      // Survival rate should decrease with severity
      expect(results[2].survived).to.be.false; // Should not survive 80% drop
    });

    it("Should calculate correlation-adjusted stress scenarios", async function () {
      const assets = [await weth.getAddress(), await usdc.getAddress()];
      const amounts = [ethers.utils.parseEther("10"), ethers.utils.parseEther("15000")];
      const correlationMatrix = [
        [10000, -200],  // WETH-WETH: 100%, WETH-USDC: -2%
        [-200, 10000]   // USDC-WETH: -2%, USDC-USDC: 100%
      ];
      
      const correlatedStress = await riskManager.performCorrelatedStressTest(
        assets,
        amounts,
        correlationMatrix,
        [-3000, 0] // Base shocks
      );
      
      expect(correlatedStress.adjustedShocks.length).to.equal(assets.length);
      expect(correlatedStress.correlationAdjustedLoss).to.be.gte(0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SYSTEM-WIDE RISK METRICS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("System-Wide Risk Metrics", function () {
    beforeEach(async function () {
      // Setup mock system data
      await riskManager.updateSystemMetrics(
        ethers.utils.parseEther("100000000"), // $100M TVL
        ethers.utils.parseEther("60000000"),  // $60M borrowed
        7500,                                 // 75% avg health factor
        5000                                  // 50% utilization
      );
    });

    it("Should calculate system utilization rate", async function () {
      const utilization = await riskManager.getSystemUtilizationRate();
      expect(utilization).to.equal(5000); // 50%
    });

    it("Should calculate average health factor", async function () {
      const avgHealthFactor = await riskManager.getAverageHealthFactor();
      expect(avgHealthFactor).to.equal(7500); // 75%
    });

    it("Should track total value locked (TVL)", async function () {
      const tvl = await riskManager.getTotalValueLocked();
      expect(tvl).to.equal(ethers.utils.parseEther("100000000"));
    });

    it("Should calculate system risk score", async function () {
      const riskScore = await riskManager.calculateSystemRiskScore();
      
      // Risk score should be between 0 and 10000 (0% to 100%)
      expect(riskScore).to.be.gte(0);
      expect(riskScore).to.be.lte(10000);
    });

    it("Should track concentration risk", async function () {
      // Mock large borrower data
      const largePositions = [
        { borrower: user1.address, debt: ethers.utils.parseEther("10000000") }, // $10M
        { borrower: user2.address, debt: ethers.utils.parseEther("5000000") }   // $5M
      ];
      
      for (const position of largePositions) {
        await riskManager.updateBorrowerData(position.borrower, position.debt, ethers.utils.parseEther("0"));
      }
      
      const concentrationRisk = await riskManager.calculateConcentrationRisk();
      expect(concentrationRisk).to.be.gt(1000); // Should show elevated concentration risk
    });

    it("Should calculate liquidity risk", async function () {
      const liquidityRisk = await riskManager.calculateLiquidityRisk();
      
      // Should consider utilization rate and available liquidity
      expect(liquidityRisk).to.be.gte(0);
      expect(liquidityRisk).to.be.lte(10000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // REAL-TIME MONITORING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Real-Time Monitoring", function () {
    it("Should monitor individual position risks", async function () {
      const collateralValue = ethers.utils.parseEther("20000");
      const debtValue = ethers.utils.parseEther("15000");
      
      await riskManager.updatePositionRisk(
        user1.address,
        collateralValue,
        debtValue
      );
      
      const positionRisk = await riskManager.getPositionRisk(user1.address);
      expect(positionRisk.healthFactor).to.be.gt(ethers.utils.parseEther("1"));
      expect(positionRisk.ltv).to.equal(7500); // 75%
      expect(positionRisk.riskLevel).to.be.oneOf([0, 1, 2, 3]); // Low, Medium, High, Critical
    });

    it("Should generate risk alerts", async function () {
      // Setup risky position
      await riskManager.updatePositionRisk(
        user1.address,
        ethers.utils.parseEther("10000"), // $10k collateral
        ethers.utils.parseEther("9500")   // $9.5k debt (95% LTV, very risky)
      );
      
      const alerts = await riskManager.getPositionAlerts(user1.address);
      expect(alerts.length).to.be.gt(0);
      expect(alerts[0].alertType).to.be.oneOf(['HIGH_LTV', 'LOW_HEALTH_FACTOR', 'LIQUIDATION_WARNING']);
    });

    it("Should track risk metrics over time", async function () {
      const timestamps = [];
      const healthFactors = [];
      
      // Simulate declining health over time
      for (let i = 0; i < 5; i++) {
        const collateral = ethers.utils.parseEther("10000");
        const debt = ethers.utils.parseEther((7000 + i * 500).toString()); // Increasing debt
        
        await riskManager.updatePositionRisk(user1.address, collateral, debt);
        
        const currentTime = await time.latest();
        const positionRisk = await riskManager.getPositionRisk(user1.address);
        
        timestamps.push(currentTime);
        healthFactors.push(positionRisk.healthFactor);
        
        await time.increase(3600); // 1 hour
      }
      
      // Health factor should be declining
      for (let i = 1; i < healthFactors.length; i++) {
        expect(healthFactors[i]).to.be.lt(healthFactors[i-1]);
      }
    });

    it("Should provide real-time system health dashboard", async function () {
      const dashboard = await riskManager.getSystemHealthDashboard();
      
      expect(dashboard.totalTVL).to.be.gt(0);
      expect(dashboard.totalBorrowed).to.be.gte(0);
      expect(dashboard.avgHealthFactor).to.be.gt(0);
      expect(dashboard.utilizationRate).to.be.gte(0);
      expect(dashboard.systemRiskScore).to.be.gte(0);
      expect(dashboard.activeAlerts).to.be.a('number');
      expect(dashboard.lastUpdate).to.be.gt(0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PARAMETER MANAGEMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Parameter Management", function () {
    it("Should allow admin to update default LTV", async function () {
      const newLTV = 6500; // 65%
      
      await expect(riskManager.updateDefaultLTV(newLTV))
        .to.emit(riskManager, "DefaultLTVUpdated")
        .withArgs(DEFAULT_LTV, newLTV);
        
      expect(await riskManager.defaultLTV()).to.equal(newLTV);
    });

    it("Should allow admin to update liquidation threshold", async function () {
      const newThreshold = 8500; // 85%
      
      await expect(riskManager.updateLiquidationThreshold(newThreshold))
        .to.emit(riskManager, "LiquidationThresholdUpdated")
        .withArgs(LIQUIDATION_THRESHOLD, newThreshold);
        
      expect(await riskManager.liquidationThreshold()).to.equal(newThreshold);
    });

    it("Should allow asset-specific risk parameters", async function () {
      const wethAddress = await weth.getAddress();
      const assetLTV = 7500;        // 75% for WETH
      const assetThreshold = 8200;  // 82% for WETH
      const assetPenalty = 750;     // 7.5% for WETH
      
      await riskManager.setAssetRiskParameters(
        wethAddress,
        assetLTV,
        assetThreshold,
        assetPenalty
      );
      
      const assetParams = await riskManager.getAssetRiskParameters(wethAddress);
      expect(assetParams.ltv).to.equal(assetLTV);
      expect(assetParams.liquidationThreshold).to.equal(assetThreshold);
      expect(assetParams.liquidationPenalty).to.equal(assetPenalty);
    });

    it("Should validate parameter ranges", async function () {
      // LTV should be reasonable (30% - 90%)
      await expect(
        riskManager.updateDefaultLTV(2000) // 20%
      ).to.be.revertedWith("RiskManager: Invalid LTV");
      
      await expect(
        riskManager.updateDefaultLTV(9500) // 95%
      ).to.be.revertedWith("RiskManager: Invalid LTV");
      
      // Liquidation threshold should be higher than LTV
      await expect(
        riskManager.updateLiquidationThreshold(6000) // 60% (lower than 70% LTV)
      ).to.be.revertedWith("RiskManager: Threshold must be higher than LTV");
    });

    it("Should restrict parameter updates to admin", async function () {
      const [, user] = await ethers.getSigners();
      
      await expect(
        riskManager.connect(user).updateDefaultLTV(6500)
      ).to.be.revertedWith("AccessControl:");
      
      await expect(
        riskManager.connect(user).updateLiquidationThreshold(8500)
      ).to.be.revertedWith("AccessControl:");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Integration Tests", function () {
    it("Should integrate with PriceOracle for asset valuations", async function () {
      const wethAddress = await weth.getAddress();
      const wethAmount = ethers.utils.parseEther("5");
      
      const value = await riskManager.getAssetValue(wethAddress, wethAmount);
      expect(value).to.equal(ethers.utils.parseEther("10000")); // 5 WETH * $2000
    });

    it("Should provide risk data to HyperLendPool", async function () {
      const borrower = user1.address;
      const collateralAsset = await weth.getAddress();
      const debtAsset = await usdc.getAddress();
      const borrowAmount = ethers.utils.parseEther("5000");
      
      const borrowAllowed = await riskManager.isBorrowAllowed(
        borrower,
        collateralAsset,
        debtAsset,
        borrowAmount
      );
      
      expect(borrowAllowed).to.be.a('boolean');
    });

    it("Should coordinate with LiquidationEngine for risk management", async function () {
      const borrower = user1.address;
      const currentHealthFactor = ethers.utils.parseEther("1.2"); // 120%
      
      const liquidationData = await riskManager.getLiquidationData(borrower);
      expect(liquidationData.isLiquidatable).to.equal(currentHealthFactor.lt(ethers.utils.parseEther("1")));
      expect(liquidationData.maxLiquidation).to.be.gte(0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PERFORMANCE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Performance Tests", function () {
    it("Should efficiently calculate risk for many positions", async function () {
      const numPositions = 100;
      const startTime = Date.now();
      
      for (let i = 0; i < numPositions; i++) {
        const mockBorrower = ethers.utils.getAddress(ethers.utils.keccak256(ethers.utils.toUtf8Bytes(`borrower${i}`)).slice(0, 42));
        await riskManager.updatePositionRisk(
          mockBorrower,
          ethers.utils.parseEther("10000"),
          ethers.utils.parseEther("7000")
        );
      }
      
      const endTime = Date.now();
      const avgTimePerPosition = (endTime - startTime) / numPositions;
      
      console.log(`Average risk calculation time: ${avgTimePerPosition}ms per position`);
      expect(avgTimePerPosition).to.be.lt(50); // Should be under 50ms per position
    });

    it("Should handle high-frequency risk updates", async function () {
      const borrower = user1.address;
      const numUpdates = 1000;
      
      const startTime = Date.now();
      
      for (let i = 0; i < numUpdates; i++) {
        await riskManager.updatePositionRisk(
          borrower,
          ethers.utils.parseEther("10000"),
          ethers.utils.parseEther((7000 + i).toString())
        );
      }
      
      const endTime = Date.now();
      const avgTimePerUpdate = (endTime - startTime) / numUpdates;
      
      console.log(`Average risk update time: ${avgTimePerUpdate}ms`);
      expect(endTime - startTime).to.be.lt(30000); // Should complete 1000 updates in under 30 seconds
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Error Handling", function () {
    it("Should handle invalid asset addresses", async function () {
      const invalidAddress = "0x0000000000000000000000000000000000000000";
      
      await expect(
        riskManager.getAssetValue(invalidAddress, ethers.utils.parseEther("1"))
      ).to.be.revertedWith("RiskManager: Invalid asset");
    });

    it("Should handle zero amounts gracefully", async function () {
      const wethAddress = await weth.getAddress();
      
      const value = await riskManager.getAssetValue(wethAddress, 0);
      expect(value).to.equal(0);
      
      const healthFactor = await riskManager.calculateHealthFactor(
        ethers.utils.parseEther("10000"),
        0, // Zero debt
        LIQUIDATION_THRESHOLD
      );
      expect(healthFactor).to.equal(ethers.constants.MaxUint256);
    });

    it("Should handle extreme market conditions", async function () {
      // Test with very high volatility
      const extremeVolatility = 20000; // 200% volatility
      const wethAddress = await weth.getAddress();
      
      const assetVaR = await riskManager.calculateAssetVaR(
        wethAddress,
        ethers.utils.parseEther("1"),
        ethers.utils.parseEther("2000"),
        extremeVolatility,
        9500
      );
      
      expect(assetVaR).to.be.gt(0);
      expect(assetVaR).to.be.finite;
    });
  });
});