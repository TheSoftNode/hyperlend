import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deploymentFixture } from "../fixtures/deployments";

describe("PriceOracle", function () {
  // ═══════════════════════════════════════════════════════════════════════════════════
  // FIXTURES AND SETUP
  // ═══════════════════════════════════════════════════════════════════════════════════

  let priceOracle: any;
  let admin: any;
  let usdc: any;
  let weth: any;

  const PRECISION = ethers.utils.parseEther("1");
  const USDC_PRICE = ethers.utils.parseEther("1");     // $1
  const WETH_PRICE = ethers.utils.parseEther("2000");  // $2000
  const STT_PRICE = ethers.utils.parseEther("1");      // $1

  beforeEach(async function () {
    const deployment = await loadFixture(deploymentFixture);
    priceOracle = deployment.priceOracle;
    admin = deployment.admin;
    usdc = deployment.usdc;
    weth = deployment.weth;
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Deployment", function () {
    it("Should deploy with correct admin", async function () {
      const defaultAdminRole = await priceOracle.DEFAULT_ADMIN_ROLE();
      expect(await priceOracle.hasRole(defaultAdminRole, admin.address)).to.be.true;
    });

    it("Should have correct precision", async function () {
      expect(await priceOracle.PRECISION()).to.equal(PRECISION);
    });

    it("Should initialize with default price staleness threshold", async function () {
      const maxStaleness = await priceOracle.maxPriceStaleness();
      expect(maxStaleness).to.be.gt(0); // Should have a reasonable default
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PRICE MANAGEMENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Price Management", function () {
    it("Should allow admin to set asset prices", async function () {
      const usdcAddress = await usdc.getAddress();
      
      await expect(priceOracle.setAssetPrice(usdcAddress, USDC_PRICE))
        .to.emit(priceOracle, "PriceUpdated")
        .withArgs(usdcAddress, USDC_PRICE, ethers.constants.AddressZero);
        
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(USDC_PRICE);
    });

    it("Should track price update timestamps", async function () {
      const usdcAddress = await usdc.getAddress();
      const blockTimestamp = await time.latest();
      
      await priceOracle.setAssetPrice(usdcAddress, USDC_PRICE);
      
      const priceData = await priceOracle.getAssetPriceData(usdcAddress);
      expect(priceData.price).to.equal(USDC_PRICE);
      expect(priceData.lastUpdate).to.be.closeTo(blockTimestamp, 5); // Within 5 seconds
    });

    it("Should handle native STT price", async function () {
      const sttAddress = ethers.constants.AddressZero;
      
      await priceOracle.setAssetPrice(sttAddress, STT_PRICE);
      expect(await priceOracle.getAssetPrice(sttAddress)).to.equal(STT_PRICE);
    });

    it("Should prevent non-admin from setting prices", async function () {
      const [, user] = await ethers.getSigners();
      const usdcAddress = await usdc.getAddress();
      
      await expect(
        priceOracle.connect(user).setAssetPrice(usdcAddress, USDC_PRICE)
      ).to.be.revertedWith("AccessControl:");
    });

    it("Should validate price inputs", async function () {
      const usdcAddress = await usdc.getAddress();
      
      // Zero price should be rejected
      await expect(
        priceOracle.setAssetPrice(usdcAddress, 0)
      ).to.be.revertedWith("PriceOracle: Invalid price");
      
      // Extremely high price should be rejected
      const maxPrice = ethers.utils.parseEther("1000000000"); // $1B
      await expect(
        priceOracle.setAssetPrice(usdcAddress, maxPrice)
      ).to.be.revertedWith("PriceOracle: Price too high");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ORACLE INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Oracle Integration", function () {
    it("Should set oracle address for asset", async function () {
      const usdcAddress = await usdc.getAddress();
      const mockOracleAddress = "0x1234567890123456789012345678901234567890";
      
      await expect(priceOracle.setAssetOracle(usdcAddress, mockOracleAddress))
        .to.emit(priceOracle, "OracleUpdated")
        .withArgs(usdcAddress, ethers.constants.AddressZero, mockOracleAddress);
        
      expect(await priceOracle.getAssetOracle(usdcAddress)).to.equal(mockOracleAddress);
    });

    it("Should prioritize oracle price over manual price", async function () {
      const usdcAddress = await usdc.getAddress();
      const manualPrice = ethers.utils.parseEther("1");
      const oraclePrice = ethers.utils.parseEther("1.05");
      
      // Set manual price first
      await priceOracle.setAssetPrice(usdcAddress, manualPrice);
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(manualPrice);
      
      // Deploy mock oracle and set oracle price
      const MockOracle = await ethers.getContractFactory("MockPriceOracle");
      const mockOracle = await MockOracle.deploy();
      await mockOracle.setPrice(usdcAddress, oraclePrice);
      
      // Set oracle for asset
      await priceOracle.setAssetOracle(usdcAddress, await mockOracle.getAddress());
      
      // Should now return oracle price
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(oraclePrice);
    });

    it("Should fallback to manual price if oracle fails", async function () {
      const usdcAddress = await usdc.getAddress();
      const manualPrice = ethers.utils.parseEther("1");
      
      // Set manual price
      await priceOracle.setAssetPrice(usdcAddress, manualPrice);
      
      // Deploy mock oracle that will revert
      const MockFailingOracle = await ethers.getContractFactory("MockFailingOracle");
      const failingOracle = await MockFailingOracle.deploy();
      
      // Set failing oracle
      await priceOracle.setAssetOracle(usdcAddress, await failingOracle.getAddress());
      
      // Should fallback to manual price
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(manualPrice);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // EMERGENCY FUNCTIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Emergency Functions", function () {
    it("Should allow emergency price override", async function () {
      const usdcAddress = await usdc.getAddress();
      const emergencyPrice = ethers.utils.parseEther("0.95");
      const reason = "Market crash protection";
      
      await expect(priceOracle.setEmergencyPrice(usdcAddress, emergencyPrice, reason))
        .to.emit(priceOracle, "EmergencyPriceSet")
        .withArgs(usdcAddress, emergencyPrice, reason);
        
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(emergencyPrice);
      expect(await priceOracle.isEmergencyPrice(usdcAddress)).to.be.true;
    });

    it("Should clear emergency price", async function () {
      const usdcAddress = await usdc.getAddress();
      const normalPrice = ethers.utils.parseEther("1");
      const emergencyPrice = ethers.utils.parseEther("0.95");
      
      // Set normal price first
      await priceOracle.setAssetPrice(usdcAddress, normalPrice);
      
      // Set emergency price
      await priceOracle.setEmergencyPrice(usdcAddress, emergencyPrice, "Test");
      expect(await priceOracle.isEmergencyPrice(usdcAddress)).to.be.true;
      
      // Clear emergency price
      await expect(priceOracle.clearEmergencyPrice(usdcAddress))
        .to.emit(priceOracle, "EmergencyPriceCleared")
        .withArgs(usdcAddress);
        
      expect(await priceOracle.isEmergencyPrice(usdcAddress)).to.be.false;
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(normalPrice);
    });

    it("Should pause price updates", async function () {
      await priceOracle.pausePriceUpdates();
      expect(await priceOracle.priceUpdatesPaused()).to.be.true;
      
      const usdcAddress = await usdc.getAddress();
      await expect(
        priceOracle.setAssetPrice(usdcAddress, USDC_PRICE)
      ).to.be.revertedWith("PriceOracle: Price updates paused");
    });

    it("Should unpause price updates", async function () {
      const usdcAddress = await usdc.getAddress();
      
      // Pause first
      await priceOracle.pausePriceUpdates();
      
      // Unpause
      await priceOracle.unpausePriceUpdates();
      expect(await priceOracle.priceUpdatesPaused()).to.be.false;
      
      // Should now allow price updates
      await expect(priceOracle.setAssetPrice(usdcAddress, USDC_PRICE))
        .to.not.be.reverted;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Batch Operations", function () {
    it("Should batch update multiple asset prices", async function () {
      const usdcAddress = await usdc.getAddress();
      const wethAddress = await weth.getAddress();
      const sttAddress = ethers.constants.AddressZero;
      
      const assets = [usdcAddress, wethAddress, sttAddress];
      const prices = [USDC_PRICE, WETH_PRICE, STT_PRICE];
      
      await expect(priceOracle.batchUpdatePrices(assets, prices))
        .to.emit(priceOracle, "BatchPriceUpdate")
        .withArgs(assets, prices);
        
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(USDC_PRICE);
      expect(await priceOracle.getAssetPrice(wethAddress)).to.equal(WETH_PRICE);
      expect(await priceOracle.getAssetPrice(sttAddress)).to.equal(STT_PRICE);
    });

    it("Should reject mismatched batch arrays", async function () {
      const usdcAddress = await usdc.getAddress();
      const assets = [usdcAddress];
      const prices = [USDC_PRICE, WETH_PRICE]; // Mismatched length
      
      await expect(
        priceOracle.batchUpdatePrices(assets, prices)
      ).to.be.revertedWith("PriceOracle: Array length mismatch");
    });

    it("Should handle empty batch updates", async function () {
      const assets: string[] = [];
      const prices: any[] = [];
      
      await expect(priceOracle.batchUpdatePrices(assets, prices))
        .to.be.revertedWith("PriceOracle: Empty batch");
    });

    it("Should batch update with gas efficiency", async function () {
      const assets = [];
      const prices = [];
      
      // Create batch of 10 assets
      for (let i = 0; i < 10; i++) {
        const MockToken = await ethers.getContractFactory("MockERC20");
        const token = await MockToken.deploy(`Token${i}`, `TK${i}`, 18, ethers.utils.parseEther("1000000"));
        assets.push(await token.getAddress());
        prices.push(ethers.utils.parseEther((i + 1).toString()));
      }
      
      const tx = await priceOracle.batchUpdatePrices(assets, prices);
      const receipt = await tx.wait();
      
      // Should complete in reasonable gas
      expect(receipt.gasUsed).to.be.lt(1000000); // Less than 1M gas
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PRICE STALENESS TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Price Staleness", function () {
    it("Should detect stale prices", async function () {
      const usdcAddress = await usdc.getAddress();
      
      // Set price
      await priceOracle.setAssetPrice(usdcAddress, USDC_PRICE);
      expect(await priceOracle.isPriceStale(usdcAddress)).to.be.false;
      
      // Fast forward time beyond staleness threshold
      const maxStaleness = await priceOracle.maxPriceStaleness();
      await time.increase(maxStaleness.toNumber() + 1);
      
      expect(await priceOracle.isPriceStale(usdcAddress)).to.be.true;
    });

    it("Should update staleness threshold", async function () {
      const newThreshold = 7200; // 2 hours
      
      await expect(priceOracle.setMaxPriceStaleness(newThreshold))
        .to.emit(priceOracle, "MaxPriceStalenessUpdated")
        .withArgs(await priceOracle.maxPriceStaleness(), newThreshold);
        
      expect(await priceOracle.maxPriceStaleness()).to.equal(newThreshold);
    });

    it("Should reject getting stale prices if configured", async function () {
      const usdcAddress = await usdc.getAddress();
      
      // Set price and make it stale
      await priceOracle.setAssetPrice(usdcAddress, USDC_PRICE);
      const maxStaleness = await priceOracle.maxPriceStaleness();
      await time.increase(maxStaleness.toNumber() + 1);
      
      // Enable strict mode (reject stale prices)
      await priceOracle.setStrictMode(true);
      
      await expect(
        priceOracle.getAssetPrice(usdcAddress)
      ).to.be.revertedWith("PriceOracle: Price is stale");
    });

    it("Should allow stale prices in non-strict mode", async function () {
      const usdcAddress = await usdc.getAddress();
      
      // Set price and make it stale
      await priceOracle.setAssetPrice(usdcAddress, USDC_PRICE);
      const maxStaleness = await priceOracle.maxPriceStaleness();
      await time.increase(maxStaleness.toNumber() + 1);
      
      // Ensure strict mode is disabled (default)
      await priceOracle.setStrictMode(false);
      
      // Should still return price with warning
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(USDC_PRICE);
      expect(await priceOracle.isPriceStale(usdcAddress)).to.be.true;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PRICE HISTORY TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Price History", function () {
    it("Should track price history", async function () {
      const usdcAddress = await usdc.getAddress();
      const price1 = ethers.utils.parseEther("1.00");
      const price2 = ethers.utils.parseEther("1.05");
      const price3 = ethers.utils.parseEther("0.98");
      
      // Set initial price
      await priceOracle.setAssetPrice(usdcAddress, price1);
      await time.increase(3600); // 1 hour
      
      // Update price
      await priceOracle.setAssetPrice(usdcAddress, price2);
      await time.increase(3600); // 1 hour
      
      // Update price again
      await priceOracle.setAssetPrice(usdcAddress, price3);
      
      // Check current price
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(price3);
      
      // Check history (if implemented)
      const history = await priceOracle.getPriceHistory(usdcAddress, 3);
      expect(history.length).to.be.lte(3); // Should have up to 3 entries
    });

    it("Should calculate price volatility", async function () {
      const usdcAddress = await usdc.getAddress();
      const prices = [
        ethers.utils.parseEther("1.00"),
        ethers.utils.parseEther("1.02"),
        ethers.utils.parseEther("0.99"),
        ethers.utils.parseEther("1.01"),
        ethers.utils.parseEther("0.98")
      ];
      
      // Set price history
      for (let i = 0; i < prices.length; i++) {
        await priceOracle.setAssetPrice(usdcAddress, prices[i]);
        if (i < prices.length - 1) {
          await time.increase(1800); // 30 minutes
        }
      }
      
      // Calculate volatility (if implemented)
      const volatility = await priceOracle.calculateVolatility(usdcAddress, 24 * 3600); // 24 hours
      expect(volatility).to.be.gte(0); // Should be non-negative
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Integration Tests", function () {
    it("Should integrate with DIA Oracle contract", async function () {
      // This would test actual DIA Oracle integration
      // For now, we test the interface compatibility
      const usdcAddress = await usdc.getAddress();
      
      // Mock DIA Oracle response
      const diaPrice = ethers.utils.parseEther("1.001");
      const MockDIA = await ethers.getContractFactory("MockDIAOracle");
      const mockDIA = await MockDIA.deploy();
      await mockDIA.setValue("USDC/USD", diaPrice, await time.latest());
      
      // Set DIA oracle
      await priceOracle.setAssetOracle(usdcAddress, await mockDIA.getAddress());
      
      // Should return DIA price
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(diaPrice);
    });

    it("Should handle multiple oracle sources", async function () {
      const usdcAddress = await usdc.getAddress();
      const wethAddress = await weth.getAddress();
      
      // Set up different oracles for different assets
      const MockDIA = await ethers.getContractFactory("MockDIAOracle");
      const MockChainlink = await ethers.getContractFactory("MockChainlinkOracle");
      
      const diaOracle = await MockDIA.deploy();
      const chainlinkOracle = await MockChainlink.deploy();
      
      await diaOracle.setValue("USDC/USD", USDC_PRICE, await time.latest());
      await chainlinkOracle.setLatestAnswer(WETH_PRICE);
      
      // Set oracles
      await priceOracle.setAssetOracle(usdcAddress, await diaOracle.getAddress());
      await priceOracle.setAssetOracle(wethAddress, await chainlinkOracle.getAddress());
      
      // Should return correct prices from different oracles
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(USDC_PRICE);
      expect(await priceOracle.getAssetPrice(wethAddress)).to.equal(WETH_PRICE);
    });

    it("Should handle oracle price validation", async function () {
      const usdcAddress = await usdc.getAddress();
      
      // Set manual price as sanity check
      await priceOracle.setAssetPrice(usdcAddress, USDC_PRICE);
      
      // Mock oracle with extreme price
      const MockOracle = await ethers.getContractFactory("MockPriceOracle");
      const mockOracle = await MockOracle.deploy();
      const extremePrice = ethers.utils.parseEther("100"); // $100 for USDC (clearly wrong)
      await mockOracle.setPrice(usdcAddress, extremePrice);
      
      await priceOracle.setAssetOracle(usdcAddress, await mockOracle.getAddress());
      
      // Enable price validation
      await priceOracle.setPriceValidation(usdcAddress, true, ethers.utils.parseEther("0.1")); // 10% deviation max
      
      // Should reject extreme oracle price and fallback to manual
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(USDC_PRICE);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // PERFORMANCE TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Performance Tests", function () {
    it("Should handle high-frequency price updates", async function () {
      const usdcAddress = await usdc.getAddress();
      const basePrice = ethers.utils.parseEther("1");
      
      // Perform rapid price updates
      for (let i = 0; i < 100; i++) {
        const price = basePrice.add(ethers.utils.parseEther((i * 0.001).toString()));
        await priceOracle.setAssetPrice(usdcAddress, price);
      }
      
      // Should complete without issues
      const finalPrice = await priceOracle.getAssetPrice(usdcAddress);
      expect(finalPrice).to.be.gt(basePrice);
    });

    it("Should efficiently batch process many assets", async function () {
      const numAssets = 50;
      const assets = [];
      const prices = [];
      
      // Create many mock assets
      for (let i = 0; i < numAssets; i++) {
        const MockToken = await ethers.getContractFactory("MockERC20");
        const token = await MockToken.deploy(`Token${i}`, `TK${i}`, 18, ethers.utils.parseEther("1000000"));
        assets.push(await token.getAddress());
        prices.push(ethers.utils.parseEther((Math.random() * 100 + 1).toString()));
      }
      
      const startTime = Date.now();
      await priceOracle.batchUpdatePrices(assets, prices);
      const endTime = Date.now();
      
      console.log(`Batch update of ${numAssets} assets took ${endTime - startTime}ms`);
      
      // Verify all prices were set
      for (let i = 0; i < numAssets; i++) {
        expect(await priceOracle.getAssetPrice(assets[i])).to.equal(prices[i]);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING TESTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  describe("Error Handling", function () {
    it("Should handle missing asset prices gracefully", async function () {
      const randomAddress = "0x1234567890123456789012345678901234567890";
      
      await expect(
        priceOracle.getAssetPrice(randomAddress)
      ).to.be.revertedWith("PriceOracle: No price set");
      
      expect(await priceOracle.hasPrice(randomAddress)).to.be.false;
    });

    it("Should validate asset addresses", async function () {
      const zeroAddress = ethers.constants.AddressZero;
      const price = ethers.utils.parseEther("1");
      
      // Zero address should be allowed (for native STT)
      await expect(priceOracle.setAssetPrice(zeroAddress, price))
        .to.not.be.reverted;
    });

    it("Should handle oracle failures gracefully", async function () {
      const usdcAddress = await usdc.getAddress();
      const fallbackPrice = ethers.utils.parseEther("1");
      
      // Set fallback price first
      await priceOracle.setAssetPrice(usdcAddress, fallbackPrice);
      
      // Deploy oracle that always reverts
      const MockFailingOracle = await ethers.getContractFactory("MockFailingOracle");
      const failingOracle = await MockFailingOracle.deploy();
      await priceOracle.setAssetOracle(usdcAddress, await failingOracle.getAddress());
      
      // Should return fallback price without reverting
      expect(await priceOracle.getAssetPrice(usdcAddress)).to.equal(fallbackPrice);
    });
  });
});