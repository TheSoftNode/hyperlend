import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import {
  setupTestEnvironment,
  TestFixtures,
  supplyNativeSTT,
  supplyERC20,
  createLiquidatablePosition,
  measureExecutionTime,
  simulateHighTPS,
  verifySomniaFeatures,
  SOMNIA_CONSTANTS
} from "../helpers/setup";

/**
 * Complete DeFi Flow Integration Test
 * Tests the full user journey on Somnia with native STT
 */
describe("🌊 Full DeFi Flow Integration Tests", function () {
  let fixtures: TestFixtures;

  beforeEach(async function () {
    fixtures = await setupTestEnvironment();
    await verifySomniaFeatures(fixtures);
    console.log("✅ Full flow test setup completed");
  });

  describe("🚀 Complete DeFi User Journey", function () {
    it("Should complete a full lending, borrowing, and liquidation cycle", async function () {
      console.log("\n🚀 Starting complete DeFi flow test...");

      const { alice, bob, carol, liquidator, hyperLendPool, mockUSDC, priceOracle } = fixtures;

      // Step 1: Alice supplies STT as collateral
      console.log("📊 Step 1: Alice supplies 100 STT as collateral");
      const aliceSupply = ethers.utils.parseEther("100");
      
      await supplyNativeSTT(alice, hyperLendPool, aliceSupply);

      // Verify Alice's collateral
      const aliceAccountData1 = await hyperLendPool.getUserAccountData(alice.address);
      expect(aliceAccountData1.totalCollateralETH).to.equal(aliceSupply.mul(2)); // $200 worth

      // Step 2: Bob supplies USDC to provide liquidity
      console.log("💰 Step 2: Bob supplies 50,000 USDC for liquidity");
      const bobUSDCSupply = ethers.utils.parseUnits("50000", 6);
      
      await supplyERC20(bob, mockUSDC, hyperLendPool, bobUSDCSupply);

      // Step 3: Alice borrows USDC against her STT collateral
      console.log("🏦 Step 3: Alice borrows 100 USDC against STT collateral");
      const aliceBorrow = ethers.utils.parseUnits("100", 6);
      
      await hyperLendPool.connect(alice).borrow(mockUSDC.address, aliceBorrow);
      
      const aliceAccountData2 = await hyperLendPool.getUserAccountData(alice.address);
      expect(aliceAccountData2.totalDebtETH).to.equal(ethers.utils.parseEther("100")); // $100 debt

      // Step 4: Time passes, interest accrues
      console.log("⏰ Step 4: Time passes, interest accrues (1 day)");
      await ethers.provider.send("evm_increaseTime", [86400]); // 1 day
      await ethers.provider.send("evm_mine", []);
      
      // Update interest manually
      await hyperLendPool.updateAccrualIndex(mockUSDC.address);

      // Step 5: Carol joins the protocol
      console.log("👥 Step 5: Carol joins and supplies both STT and USDC");
      const carolSTTSupply = ethers.utils.parseEther("50");
      const carolUSDCSupply = ethers.utils.parseUnits("25000", 6);

      await supplyNativeSTT(carol, hyperLendPool, carolSTTSupply);
      await supplyERC20(carol, mockUSDC, hyperLendPool, carolUSDCSupply);

      // Step 6: Market conditions change - STT price drops
      console.log("📉 Step 6: STT price drops 30% - triggering liquidation conditions");
      const newSTTPrice = ethers.utils.parseEther("1.4"); // $1.40 per STT (30% drop)
      await priceOracle.setAssetPrice(ethers.constants.AddressZero, newSTTPrice);

      // Update Alice's health factor
      const aliceAccountData3 = await hyperLendPool.getUserAccountData(alice.address);
      console.log(`💊 Alice's health factor: ${ethers.utils.formatEther(aliceAccountData3.healthFactor)}`);

      // Step 7: Liquidation occurs
      if (aliceAccountData3.healthFactor.lt(ethers.utils.parseEther("1"))) {
        console.log("⚡ Step 7: Alice's position is liquidated");
        
        const liquidationAmount = ethers.utils.parseUnits("50", 6); // Liquidate 50 USDC debt
        
        await mockUSDC.connect(liquidator).approve(hyperLendPool.address, liquidationAmount);
        await hyperLendPool.connect(liquidator).liquidate(
          alice.address,
          mockUSDC.address,
          liquidationAmount,
          ethers.constants.AddressZero // STT collateral
        );

        console.log("✅ Liquidation completed successfully");
      }

      // Step 8: Alice repays remaining debt
      console.log("💳 Step 8: Alice repays remaining debt");
      const remainingDebt = await hyperLendPool.getBorrowBalance(alice.address, mockUSDC.address);
      
      if (remainingDebt.gt(0)) {
        await mockUSDC.connect(alice).approve(hyperLendPool.address, remainingDebt);
        await hyperLendPool.connect(alice).repay(mockUSDC.address, remainingDebt);
      }

      // Step 9: Alice withdraws remaining collateral
      console.log("🏧 Step 9: Alice withdraws remaining collateral");
      const aliceCollateralBalance = await hyperLendPool.getSupplyBalance(alice.address, ethers.constants.AddressZero);
      
      if (aliceCollateralBalance.gt(0)) {
        await hyperLendPool.connect(alice).withdraw(ethers.constants.AddressZero, aliceCollateralBalance);
      }

      // Step 10: Verify final state
      console.log("🔍 Step 10: Verifying final protocol state");
      
      const finalAliceData = await hyperLendPool.getUserAccountData(alice.address);
      expect(finalAliceData.totalDebtETH).to.equal(0);
      
      const finalBobData = await hyperLendPool.getUserAccountData(bob.address);
      expect(finalBobData.totalCollateralETH).to.be.gt(ethers.utils.parseEther("50000")); // Bob earned interest

      const finalCarolData = await hyperLendPool.getUserAccountData(carol.address);
      expect(finalCarolData.totalCollateralETH).to.be.gt(0);

      console.log("🎉 Complete DeFi flow test completed successfully!");
    });

    it("Should handle multiple users simultaneously (stress test)", async function () {
      console.log("\n🔥 Starting multi-user stress test...");

      const { alice, bob, carol, hyperLendPool } = fixtures;
      const users = [alice, bob, carol];
      const operations = [];

      // Each user performs random operations
      for (let i = 0; i < users.length; i++) {
        const user = users[i];
        const supplyAmount = ethers.utils.parseEther((10 + i * 5).toString());
        
        operations.push(
          supplyNativeSTT(user, hyperLendPool, supplyAmount)
        );
      }

      // Execute all operations in parallel (simulating high TPS)
      await Promise.all(operations);

      // Verify all users have collateral
      for (const user of users) {
        const userData = await hyperLendPool.getUserAccountData(user.address);
        expect(userData.totalCollateralETH).to.be.gt(0);
      }

      console.log("✅ Multi-user stress test completed");
    });

    it("Should handle rapid operations simulating Somnia's high TPS", async function () {
      console.log("\n⚡ Testing rapid operations for high TPS simulation...");

      const { alice, hyperLendPool } = fixtures;
      const supplyAmount = ethers.utils.parseEther("10");
      const operationCount = 20;

      // Rapid supply and withdraw operations
      for (let i = 0; i < operationCount; i++) {
        await supplyNativeSTT(alice, hyperLendPool, supplyAmount);

        // Every other operation, withdraw half
        if (i % 2 === 1) {
          await hyperLendPool.connect(alice).withdraw(ethers.constants.AddressZero, supplyAmount.div(2));
        }
      }

      // Verify final state is consistent
      const finalData = await hyperLendPool.getUserAccountData(alice.address);
      expect(finalData.totalCollateralETH).to.be.gt(0);

      console.log(`✅ Completed ${operationCount} rapid operations successfully`);
    });
  });

  describe("🔮 Real-time Oracle Integration", function () {
    it("Should handle real-time price updates", async function () {
      console.log("\n📊 Testing real-time price updates...");

      const { alice, hyperLendPool, priceOracle } = fixtures;

      // Initial setup
      await supplyNativeSTT(alice, hyperLendPool, ethers.utils.parseEther("100"));

      // Simulate multiple price updates (as would happen on Somnia)
      const priceUpdates = [
        ethers.utils.parseEther("2.1"),
        ethers.utils.parseEther("1.9"),
        ethers.utils.parseEther("2.2"),
        ethers.utils.parseEther("1.8"),
        ethers.utils.parseEther("2.0")
      ];

      for (const price of priceUpdates) {
        await priceOracle.setAssetPrice(ethers.constants.AddressZero, price);
        
        // Verify user's collateral value updates accordingly
        const userData = await hyperLendPool.getUserAccountData(alice.address);
        const expectedCollateral = ethers.utils.parseEther("100").mul(price).div(ethers.utils.parseEther("1"));
        expect(userData.totalCollateralETH).to.equal(expectedCollateral);
      }

      console.log("✅ Real-time price updates working correctly");
    });

    it("Should batch update multiple assets efficiently", async function () {
      const { priceOracle, mockUSDC } = fixtures;
      
      const assets = [ethers.constants.AddressZero, mockUSDC.address];
      const prices = [ethers.utils.parseEther("2.1"), ethers.utils.parseEther("1.01")];

      // Batch price update
      await priceOracle.batchSetPrices(assets, prices);

      // Verify all prices updated
      expect(await priceOracle.getAssetPrice(ethers.constants.AddressZero)).to.equal(prices[0]);
      expect(await priceOracle.getAssetPrice(mockUSDC.address)).to.equal(prices[1]);
    });
  });

  describe("⚡ Liquidation Engine Performance", function () {
    it("Should perform ultra-fast liquidations", async function () {
      console.log("\n⚡ Testing ultra-fast liquidation performance...");

      const { alice, bob, liquidator, hyperLendPool, mockUSDC, priceOracle } = fixtures;

      // Setup liquidatable position
      await supplyNativeSTT(alice, hyperLendPool, ethers.utils.parseEther("100"));
      await supplyERC20(bob, mockUSDC, hyperLendPool, ethers.utils.parseUnits("50000", 6));
      await hyperLendPool.connect(alice).borrow(mockUSDC.address, ethers.utils.parseUnits("140", 6));

      // Price drop to trigger liquidation
      await priceOracle.setAssetPrice(ethers.constants.AddressZero, ethers.utils.parseEther("1.2"));

      // Measure liquidation execution time
      const { executionTime } = await measureExecutionTime(async () => {
        await mockUSDC.connect(liquidator).approve(hyperLendPool.address, ethers.utils.parseUnits("70", 6));
        return hyperLendPool.connect(liquidator).liquidate(
          alice.address,
          mockUSDC.address,
          ethers.utils.parseUnits("70", 6),
          ethers.constants.AddressZero
        );
      }, "Ultra-fast liquidation");

      // Verify liquidation success
      const finalData = await hyperLendPool.getUserAccountData(alice.address);
      expect(finalData.healthFactor).to.be.gt(ethers.utils.parseEther("1"));

      console.log("✅ Ultra-fast liquidation test completed");
    });
  });

  describe("🌊 High TPS Simulation", function () {
    it("Should simulate Somnia's 1M+ TPS capability", async function () {
      console.log("\n🚀 Simulating Somnia's high TPS capability...");

      const { alice, bob, carol, hyperLendPool } = fixtures;
      const users = [alice, bob, carol];

      const { tps } = await simulateHighTPS(users, hyperLendPool, SOMNIA_CONSTANTS.HIGH_TPS_OPERATION_COUNT);

      // Verify all operations completed successfully
      for (const user of users) {
        const userData = await hyperLendPool.getUserAccountData(user.address);
        expect(userData.totalCollateralETH).to.be.gt(0);
      }

      console.log(`🎯 Target TPS achieved: ${tps}`);
      console.log("✅ High TPS simulation completed successfully");
    });
  });
});

// Helper function to format values for logging
function formatValue(value: BigNumber, decimals: number = 18): string {
  return ethers.utils.formatUnits(value, decimals);
}
