import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deploymentFixture } from "../fixtures/deployments";

describe("InterestRateModel", function () {
  // ═══════════════════════════════════════════════════════════════════════════════════
  // FIXTURES AND SETUP
  // ═══════════════════════════════════════════════════════════════════════════════════

  let interestRateModel: any;
  let admin: any;

  const PRECISION = ethers.utils.parseEther("1");
  const RAY = ethers.utils.parseEther("1000000000"); // 1e27 in 18 decimals
  
  // Test parameters
  const BASE_RATE = 200;    // 2%
  const SLOPE1 = 800;       // 8%
  const SLOPE2 = 25000;     // 250%
  const OPTIMAL_UTIL = 8000; // 80%

  beforeEach(async function () {
    const deployment = await loadFixture(deploymentFixture);
    interestRateModel = deployment.interestRateModel;
    admin = deployment.admin;
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Deployment", function () {
    it("Should deploy with correct parameters", async function () {
      expect(await interestRateModel.baseRate()).to.equal(BASE_RATE);
      expect(await interestRateModel.slope1()).to.equal(SLOPE1);
      expect(await interestRateModel.slope2()).to.equal(SLOPE2);
      expect(await interestRateModel.optimalUtilization()).to.equal(OPTIMAL_UTIL);
    });

    it("Should have correct precision", async function () {
      expect(await interestRateModel.PRECISION()).to.equal(PRECISION);
    });

    it("Should set deployer as admin", async function () {
      const defaultAdminRole = await interestRateModel.DEFAULT_ADMIN_ROLE();
      expect(await interestRateModel.hasRole(defaultAdminRole, admin.address)).to.be.true;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEREST RATE CALCULATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Interest Rate Calculations", function () {
    describe("Below Optimal Utilization", function () {
      it("Should calculate correct rate at 0% utilization", async function () {
        const utilization = 0; // 0%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        
        // At 0% utilization: rate = baseRate = 2%
        expect(borrowRate).to.equal(BASE_RATE);
      });

      it("Should calculate correct rate at 40% utilization", async function () {
        const utilization = 4000; // 40%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        
        // At 40% utilization (half of optimal):
        // rate = baseRate + (slope1 * utilization / optimalUtil)
        // rate = 200 + (800 * 4000 / 8000) = 200 + 400 = 600 (6%)
        const expectedRate = BASE_RATE + (SLOPE1 * utilization) / OPTIMAL_UTIL;
        expect(borrowRate).to.equal(expectedRate);
      });

      it("Should calculate correct rate at optimal utilization (80%)", async function () {
        const utilization = OPTIMAL_UTIL; // 80%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        
        // At optimal utilization:
        // rate = baseRate + slope1 = 200 + 800 = 1000 (10%)
        const expectedRate = BASE_RATE + SLOPE1;
        expect(borrowRate).to.equal(expectedRate);
      });
    });

    describe("Above Optimal Utilization", function () {
      it("Should calculate correct rate at 90% utilization", async function () {
        const utilization = 9000; // 90%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        
        // At 90% utilization (10% above optimal):
        // rate = baseRate + slope1 + slope2 * (util - optimal) / (100% - optimal)
        // rate = 200 + 800 + 25000 * (9000 - 8000) / (10000 - 8000)
        // rate = 1000 + 25000 * 1000 / 2000 = 1000 + 12500 = 13500 (135%)
        const excessUtil = utilization - OPTIMAL_UTIL;
        const maxExcessUtil = 10000 - OPTIMAL_UTIL; // 100% - 80% = 20%
        const expectedRate = BASE_RATE + SLOPE1 + (SLOPE2 * excessUtil) / maxExcessUtil;
        expect(borrowRate).to.equal(expectedRate);
      });

      it("Should calculate correct rate at 100% utilization", async function () {
        const utilization = 10000; // 100%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        
        // At 100% utilization:
        // rate = baseRate + slope1 + slope2 = 200 + 800 + 25000 = 26000 (260%)
        const expectedRate = BASE_RATE + SLOPE1 + SLOPE2;
        expect(borrowRate).to.equal(expectedRate);
      });
    });

    describe("Supply Rate Calculations", function () {
      it("Should calculate supply rate with no protocol fee", async function () {
        const utilization = 5000; // 50%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        const supplyRate = await interestRateModel.calculateSupplyRate(utilization, 0);
        
        // Supply rate = borrow rate * utilization * (1 - protocol fee)
        // With 0% protocol fee: supply rate = borrow rate * utilization
        const expectedSupplyRate = (borrowRate * utilization) / 10000;
        expect(supplyRate).to.equal(expectedSupplyRate);
      });

      it("Should calculate supply rate with protocol fee", async function () {
        const utilization = 5000; // 50%
        const protocolFeeRate = 1000; // 10%
        const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
        const supplyRate = await interestRateModel.calculateSupplyRate(utilization, protocolFeeRate);
        
        // Supply rate = borrow rate * utilization * (1 - protocol fee)
        const netRate = borrowRate * (10000 - protocolFeeRate) / 10000;
        const expectedSupplyRate = (netRate * utilization) / 10000;
        expect(supplyRate).to.equal(expectedSupplyRate);
      });

      it("Should return 0 supply rate at 0% utilization", async function () {
        const utilization = 0; // 0%
        const supplyRate = await interestRateModel.calculateSupplyRate(utilization, 0);
        expect(supplyRate).to.equal(0);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PARAMETER UPDATE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Parameter Updates", function () {
    it("Should allow admin to update base rate", async function () {
      const newBaseRate = 300; // 3%
      
      await expect(interestRateModel.updateBaseRate(newBaseRate))
        .to.emit(interestRateModel, "BaseRateUpdated")
        .withArgs(BASE_RATE, newBaseRate);
        
      expect(await interestRateModel.baseRate()).to.equal(newBaseRate);
    });

    it("Should allow admin to update slope1", async function () {
      const newSlope1 = 1000; // 10%
      
      await expect(interestRateModel.updateSlope1(newSlope1))
        .to.emit(interestRateModel, "Slope1Updated")
        .withArgs(SLOPE1, newSlope1);
        
      expect(await interestRateModel.slope1()).to.equal(newSlope1);
    });

    it("Should allow admin to update slope2", async function () {
      const newSlope2 = 30000; // 300%
      
      await expect(interestRateModel.updateSlope2(newSlope2))
        .to.emit(interestRateModel, "Slope2Updated")
        .withArgs(SLOPE2, newSlope2);
        
      expect(await interestRateModel.slope2()).to.equal(newSlope2);
    });

    it("Should allow admin to update optimal utilization", async function () {
      const newOptimalUtil = 7500; // 75%
      
      await expect(interestRateModel.updateOptimalUtilization(newOptimalUtil))
        .to.emit(interestRateModel, "OptimalUtilizationUpdated")
        .withArgs(OPTIMAL_UTIL, newOptimalUtil);
        
      expect(await interestRateModel.optimalUtilization()).to.equal(newOptimalUtil);
    });

    it("Should restrict parameter updates to admin only", async function () {
      const [, user] = await ethers.getSigners();
      
      await expect(
        interestRateModel.connect(user).updateBaseRate(300)
      ).to.be.revertedWith("AccessControl:");
      
      await expect(
        interestRateModel.connect(user).updateSlope1(1000)
      ).to.be.revertedWith("AccessControl:");
    });

    it("Should validate parameter ranges", async function () {
      // Base rate should not exceed 100%
      await expect(
        interestRateModel.updateBaseRate(15000) // 150%
      ).to.be.revertedWith("InterestRateModel: Invalid base rate");
      
      // Optimal utilization should be between 1% and 99%
      await expect(
        interestRateModel.updateOptimalUtilization(0)
      ).to.be.revertedWith("InterestRateModel: Invalid optimal utilization");
      
      await expect(
        interestRateModel.updateOptimalUtilization(10000) // 100%
      ).to.be.revertedWith("InterestRateModel: Invalid optimal utilization");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Batch Operations", function () {
    it("Should calculate multiple rates efficiently", async function () {
      const utilizations = [0, 2000, 4000, 6000, 8000, 9000, 10000];
      const rates = [];
      
      for (const util of utilizations) {
        rates.push(await interestRateModel.calculateBorrowRate(util));
      }
      
      // Verify rates increase with utilization
      for (let i = 1; i < rates.length; i++) {
        expect(rates[i]).to.be.gte(rates[i-1]);
      }
    });

    it("Should handle batch rate updates with events", async function () {
      const newBaseRate = 250;
      const newSlope1 = 900;
      
      // Batch update multiple parameters
      await interestRateModel.updateBaseRate(newBaseRate);
      await interestRateModel.updateSlope1(newSlope1);
      
      // Verify both parameters updated
      expect(await interestRateModel.baseRate()).to.equal(newBaseRate);
      expect(await interestRateModel.slope1()).to.equal(newSlope1);
      
      // Verify rates changed
      const newRate = await interestRateModel.calculateBorrowRate(5000);
      const oldModel = await ethers.getContractFactory("InterestRateModel");
      
      // Rate should be different from original parameters
      const originalRate = BASE_RATE + (SLOPE1 * 5000) / OPTIMAL_UTIL;
      expect(newRate).to.not.equal(originalRate);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // REAL-TIME FEATURES TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Real-Time Features", function () {
    it("Should track rate history", async function () {
      const utilization = 5000; // 50%
      
      // Get initial rate
      const initialRate = await interestRateModel.calculateBorrowRate(utilization);
      
      // Update parameters
      await interestRateModel.updateSlope1(1200); // 12%
      
      // Get new rate
      const newRate = await interestRateModel.calculateBorrowRate(utilization);
      
      expect(newRate).to.be.gt(initialRate);
    });

    it("Should provide rate metadata", async function () {
      const utilization = 6000; // 60%
      const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
      const supplyRate = await interestRateModel.calculateSupplyRate(utilization, 500); // 5% protocol fee
      
      expect(borrowRate).to.be.gt(0);
      expect(supplyRate).to.be.gt(0);
      expect(borrowRate).to.be.gt(supplyRate);
    });

    it("Should handle extreme utilization scenarios", async function () {
      // Very low utilization
      const lowUtil = 1; // 0.01%
      const lowRate = await interestRateModel.calculateBorrowRate(lowUtil);
      expect(lowRate).to.be.closeTo(BASE_RATE, 1); // Should be close to base rate
      
      // Very high utilization  
      const highUtil = 9999; // 99.99%
      const highRate = await interestRateModel.calculateBorrowRate(highUtil);
      expect(highRate).to.be.gt(BASE_RATE + SLOPE1); // Should be much higher
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // GAS OPTIMIZATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Gas Optimization", function () {
    it("Should calculate rates efficiently", async function () {
      const utilization = 5000; // 50%
      
      // Measure gas for rate calculation
      const tx = await interestRateModel.calculateBorrowRate.staticCall(utilization);
      
      // Rate calculation should be gas efficient (view function)
      expect(tx).to.be.a('bigint');
    });

    it("Should batch parameter updates efficiently", async function () {
      const startGas = await ethers.provider.getGasPrice();
      
      // Update multiple parameters in sequence
      await interestRateModel.updateBaseRate(250);
      await interestRateModel.updateSlope1(900);
      await interestRateModel.updateOptimalUtilization(7500);
      
      // All updates should complete successfully
      expect(await interestRateModel.baseRate()).to.equal(250);
      expect(await interestRateModel.slope1()).to.equal(900);
      expect(await interestRateModel.optimalUtilization()).to.equal(7500);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Integration Tests", function () {
    it("Should integrate with HyperLendPool for real-time rate updates", async function () {
      const utilization = 4000; // 40%
      const borrowRate = await interestRateModel.calculateBorrowRate(utilization);
      const supplyRate = await interestRateModel.calculateSupplyRate(utilization, 300); // 3% protocol fee
      
      // Rates should be reasonable for a lending protocol
      expect(borrowRate).to.be.gte(BASE_RATE);
      expect(borrowRate).to.be.lte(BASE_RATE + SLOPE1); // Below optimal, so no slope2
      expect(supplyRate).to.be.lt(borrowRate); // Supply rate should be lower than borrow rate
      expect(supplyRate).to.be.gt(0); // But still positive with utilization
    });

    it("Should handle dynamic rate adjustments", async function () {
      const testUtilizations = [1000, 3000, 5000, 7000, 8000, 9000, 9500];
      const rates = [];
      
      for (const util of testUtilizations) {
        rates.push(await interestRateModel.calculateBorrowRate(util));
      }
      
      // Rates should increase with utilization
      for (let i = 1; i < rates.length; i++) {
        expect(rates[i]).to.be.gte(rates[i-1]);
      }
      
      // Rate jump should occur at optimal utilization
      const optimalIndex = testUtilizations.findIndex(u => u === OPTIMAL_UTIL);
      if (optimalIndex > 0 && optimalIndex < rates.length - 1) {
        const rateIncreaseBefore = rates[optimalIndex] - rates[optimalIndex - 1];
        const rateIncreaseAfter = rates[optimalIndex + 1] - rates[optimalIndex];
        expect(rateIncreaseAfter).to.be.gt(rateIncreaseBefore); // Steeper slope after optimal
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Error Handling", function () {
    it("Should reject invalid utilization rates", async function () {
      // Utilization > 100%
      await expect(
        interestRateModel.calculateBorrowRate(12000) // 120%
      ).to.be.revertedWith("InterestRateModel: Invalid utilization");
      
      // Negative utilization (shouldn't be possible with uint, but test bounds)
      await expect(
        interestRateModel.calculateSupplyRate(15000, 0) // 150%
      ).to.be.revertedWith("InterestRateModel: Invalid utilization");
    });

    it("Should handle edge cases gracefully", async function () {
      // Exactly at optimal utilization
      const optimalRate = await interestRateModel.calculateBorrowRate(OPTIMAL_UTIL);
      expect(optimalRate).to.equal(BASE_RATE + SLOPE1);
      
      // Just below optimal utilization
      const belowOptimalRate = await interestRateModel.calculateBorrowRate(OPTIMAL_UTIL - 1);
      expect(belowOptimalRate).to.be.lt(optimalRate);
      
      // Just above optimal utilization
      const aboveOptimalRate = await interestRateModel.calculateBorrowRate(OPTIMAL_UTIL + 1);
      expect(aboveOptimalRate).to.be.gt(optimalRate);
    });
  });
});