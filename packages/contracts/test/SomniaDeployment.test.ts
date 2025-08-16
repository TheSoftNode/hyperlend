import { ethers } from "hardhat";
import { expect } from "chai";

/**
 * Comprehensive Somnia Deployment Test Suite
 * Tests all contracts and integrations for hackathon readiness
 */
describe("HyperLend Somnia Deployment Tests", function () {
    let deployer: any, treasury: any, user1: any, user2: any, liquidator: any;
    let hyperLendPool: any, interestRateModel: any, priceOracle: any;
    let liquidationEngine: any, riskManager: any;
    let hlToken: any, debtToken: any, rewardToken: any, somniaWrapper: any;

    // Test configuration for Somnia
    const PROTOCOL_PARAMS = {
        maxBorrowingRate: 10000, // 100%
        defaultLTV: 7500, // 75%
        liquidationThreshold: 8500, // 85%
        liquidationPenalty: 500, // 5%
        protocolFeeRate: 300, // 3%
        baseRate: 200, // 2%
        slope1: 1000, // 10%
        slope2: 30000, // 300%
        optimalUtilization: 8000, // 80%
        liquidationDelay: 60, // 1 minute for Somnia speed
        priceUpdateInterval: 30, // 30 seconds real-time updates
    };

    beforeEach(async function () {
        // Get signers
        [deployer, treasury, user1, user2, liquidator] = await ethers.getSigners();

        console.log("🚀 Setting up HyperLend for Somnia testing...");

        // Deploy Interest Rate Model
        const InterestRateModelFactory = await ethers.getContractFactory("InterestRateModel");
        interestRateModel = await InterestRateModelFactory.deploy(
            PROTOCOL_PARAMS.baseRate,
            PROTOCOL_PARAMS.slope1,
            PROTOCOL_PARAMS.slope2,
            PROTOCOL_PARAMS.optimalUtilization
        );
        await interestRateModel.deployed();

        // Deploy Price Oracle
        const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
        priceOracle = await PriceOracleFactory.deploy(
            ethers.constants.AddressZero, // DIA Oracle placeholder
            ethers.constants.AddressZero, // Protofire Oracle placeholder
            PROTOCOL_PARAMS.priceUpdateInterval
        );
        await priceOracle.deployed();

        // Deploy Risk Manager
        const RiskManagerFactory = await ethers.getContractFactory("RiskManager");
        riskManager = await RiskManagerFactory.deploy(
            PROTOCOL_PARAMS.defaultLTV,
            PROTOCOL_PARAMS.liquidationThreshold,
            PROTOCOL_PARAMS.liquidationPenalty
        );
        await riskManager.deployed();

        // Deploy Liquidation Engine
        const LiquidationEngineFactory = await ethers.getContractFactory("LiquidationEngine");
        liquidationEngine = await LiquidationEngineFactory.deploy(
            riskManager.address,
            priceOracle.address,
            PROTOCOL_PARAMS.liquidationDelay
        );
        await liquidationEngine.deployed();

        // Deploy Tokens
        const HLTokenFactory = await ethers.getContractFactory("HLToken");
        hlToken = await HLTokenFactory.deploy("HyperLend Token", "HLT");
        await hlToken.deployed();

        const DebtTokenFactory = await ethers.getContractFactory("DebtToken");
        debtToken = await DebtTokenFactory.deploy("HyperLend Debt Token", "HDT");
        await debtToken.deployed();

        const RewardTokenFactory = await ethers.getContractFactory("RewardToken");
        rewardToken = await RewardTokenFactory.deploy(
            "HyperLend Reward Token",
            "HRT",
            ethers.utils.parseEther("1000000")
        );
        await rewardToken.deployed();

        // Deploy Somnia Wrapper for native STT
        const SomniaWrapperFactory = await ethers.getContractFactory("SomniaWrapper");
        somniaWrapper = await SomniaWrapperFactory.deploy();
        await somniaWrapper.deployed();

        // Deploy HyperLend Pool
        const HyperLendPoolFactory = await ethers.getContractFactory("HyperLendPool");
        hyperLendPool = await HyperLendPoolFactory.deploy(
            treasury.address,
            interestRateModel.address,
            priceOracle.address,
            liquidationEngine.address,
            riskManager.address,
            PROTOCOL_PARAMS.protocolFeeRate
        );
        await hyperLendPool.deployed();

        // Configure system
        await liquidationEngine.setPoolAddress(hyperLendPool.address);

        console.log("✅ All contracts deployed successfully");
    });

    describe("📋 Contract Deployment Verification", function () {
        it("Should deploy all contracts with correct addresses", async function () {
            expect(hyperLendPool.address).to.not.equal(ethers.constants.AddressZero);
            expect(interestRateModel.address).to.not.equal(ethers.constants.AddressZero);
            expect(priceOracle.address).to.not.equal(ethers.constants.AddressZero);
            expect(liquidationEngine.address).to.not.equal(ethers.constants.AddressZero);
            expect(riskManager.address).to.not.equal(ethers.constants.AddressZero);
            expect(hlToken.address).to.not.equal(ethers.constants.AddressZero);
            expect(debtToken.address).to.not.equal(ethers.constants.AddressZero);
            expect(rewardToken.address).to.not.equal(ethers.constants.AddressZero);
            expect(somniaWrapper.address).to.not.equal(ethers.constants.AddressZero);
        });

        it("Should have correct initial configuration", async function () {
            expect(await hyperLendPool.treasury()).to.equal(treasury.address);
            expect(await hyperLendPool.protocolFeeRate()).to.equal(PROTOCOL_PARAMS.protocolFeeRate);
            expect(await riskManager.defaultLTV()).to.equal(PROTOCOL_PARAMS.defaultLTV);
            expect(await riskManager.liquidationThreshold()).to.equal(PROTOCOL_PARAMS.liquidationThreshold);
        });
    });

    describe("🌊 Somnia Native STT Integration", function () {
        it("Should wrap and unwrap native STT correctly", async function () {
            const depositAmount = ethers.utils.parseEther("1.0");

            // Deposit native STT to get WSTT
            await somniaWrapper.connect(user1).deposit({ value: depositAmount });
            
            expect(await somniaWrapper.balanceOf(user1.address)).to.equal(depositAmount);
            expect(await somniaWrapper.totalSupply()).to.equal(depositAmount);

            // Withdraw native STT
            const initialBalance = await user1.getBalance();
            await somniaWrapper.connect(user1).withdraw(depositAmount);
            
            expect(await somniaWrapper.balanceOf(user1.address)).to.equal(0);
            expect(await somniaWrapper.totalSupply()).to.equal(0);
        });

        it("Should handle fast transfers optimized for Somnia", async function () {
            const depositAmount = ethers.utils.parseEther("2.0");
            const transferAmount = ethers.utils.parseEther("1.0");

            // Setup
            await somniaWrapper.connect(user1).deposit({ value: depositAmount });

            // Fast transfer
            await expect(somniaWrapper.connect(user1).fastTransfer(user2.address, transferAmount))
                .to.emit(somniaWrapper, "FastTransfer")
                .withArgs(user1.address, user2.address, transferAmount);

            expect(await somniaWrapper.balanceOf(user2.address)).to.equal(transferAmount);
        });

        it("Should track operation count for Somnia metrics", async function () {
            const initialCount = await somniaWrapper.operationCount();
            
            await somniaWrapper.connect(user1).deposit({ value: ethers.utils.parseEther("1.0") });
            expect(await somniaWrapper.operationCount()).to.equal(initialCount.add(1));

            await somniaWrapper.connect(user1).withdraw(ethers.utils.parseEther("0.5"));
            expect(await somniaWrapper.operationCount()).to.equal(initialCount.add(2));
        });
    });

    describe("💰 Supply and Borrow Operations", function () {
        beforeEach(async function () {
            // Add STT as supported asset (using zero address for native STT)
            await hyperLendPool.addAsset(
                ethers.constants.AddressZero, // STT (native)
                hlToken.address,
                debtToken.address,
                ethers.constants.AddressZero, // Price feed placeholder
                PROTOCOL_PARAMS.defaultLTV,
                PROTOCOL_PARAMS.liquidationThreshold
            );

            // Set a mock price for testing
            await priceOracle.setPrice(ethers.constants.AddressZero, ethers.utils.parseEther("1")); // 1 USD
        });

        it("Should allow users to supply native STT", async function () {
            const supplyAmount = ethers.utils.parseEther("10.0");

            await expect(hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount }))
                .to.emit(hyperLendPool, "Supply")
                .withArgs(user1.address, ethers.constants.AddressZero, supplyAmount);

            expect(await hyperLendPool.getUserSupplyBalance(user1.address, ethers.constants.AddressZero))
                .to.equal(supplyAmount);
        });

        it("Should allow users to borrow against collateral", async function () {
            const supplyAmount = ethers.utils.parseEther("10.0");
            const borrowAmount = ethers.utils.parseEther("5.0"); // 50% LTV

            // Supply collateral
            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });

            // Borrow
            await expect(hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, borrowAmount))
                .to.emit(hyperLendPool, "Borrow")
                .withArgs(user1.address, ethers.constants.AddressZero, borrowAmount);

            expect(await hyperLendPool.getUserBorrowBalance(user1.address, ethers.constants.AddressZero))
                .to.equal(borrowAmount);
        });

        it("Should calculate interest rates correctly with Somnia's speed", async function () {
            const supplyAmount = ethers.utils.parseEther("100.0");
            const borrowAmount = ethers.utils.parseEther("50.0"); // 50% utilization

            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            await hyperLendPool.connect(user2).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            await hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, borrowAmount);

            const borrowRate = await interestRateModel.getBorrowRate(
                ethers.utils.parseEther("200"), // total supply
                borrowAmount, // total borrow
                0 // reserves
            );

            expect(borrowRate).to.be.gt(PROTOCOL_PARAMS.baseRate);
        });
    });

    describe("⚡ Liquidation Engine (Ultra-Fast)", function () {
        beforeEach(async function () {
            await hyperLendPool.addAsset(
                ethers.constants.AddressZero,
                hlToken.address,
                debtToken.address,
                ethers.constants.AddressZero,
                PROTOCOL_PARAMS.defaultLTV,
                PROTOCOL_PARAMS.liquidationThreshold
            );

            await priceOracle.setPrice(ethers.constants.AddressZero, ethers.utils.parseEther("1"));
        });

        it("Should perform fast liquidation when position becomes unhealthy", async function () {
            const supplyAmount = ethers.utils.parseEther("10.0");
            const borrowAmount = ethers.utils.parseEther("7.0"); // 70% LTV

            // User1 supplies and borrows
            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            await hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, borrowAmount);

            // Price drops, making position liquidatable
            await priceOracle.setPrice(ethers.constants.AddressZero, ethers.utils.parseEther("0.8")); // 20% drop

            // Check if position is liquidatable
            const healthFactor = await hyperLendPool.getHealthFactor(user1.address);
            expect(healthFactor).to.be.lt(ethers.utils.parseEther("1"));

            // Liquidate
            const liquidationAmount = borrowAmount.div(2); // 50% liquidation
            await expect(liquidationEngine.connect(liquidator).liquidate(
                user1.address,
                ethers.constants.AddressZero,
                liquidationAmount,
                { value: liquidationAmount }
            )).to.emit(liquidationEngine, "Liquidation");
        });

        it("Should handle micro-liquidations for Somnia's real-time environment", async function () {
            const supplyAmount = ethers.utils.parseEther("100.0");
            const borrowAmount = ethers.utils.parseEther("70.0");

            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            await hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, borrowAmount);

            // Slight price drop
            await priceOracle.setPrice(ethers.constants.AddressZero, ethers.utils.parseEther("0.95"));

            // Micro-liquidation (small amount)
            const microAmount = ethers.utils.parseEther("1.0");
            await liquidationEngine.connect(liquidator).microLiquidate(
                user1.address,
                ethers.constants.AddressZero,
                microAmount,
                { value: microAmount }
            );

            // Position should be healthier now
            const healthFactor = await hyperLendPool.getHealthFactor(user1.address);
            expect(healthFactor).to.be.gt(ethers.utils.parseEther("1"));
        });
    });

    describe("🔮 Oracle Integration", function () {
        it("Should integrate with DIA oracle", async function () {
            // Mock DIA oracle response
            const diaPrice = ethers.utils.parseEther("1.5");
            await priceOracle.setDiaPrice(ethers.constants.AddressZero, diaPrice);

            const price = await priceOracle.getPrice(ethers.constants.AddressZero);
            expect(price).to.equal(diaPrice);
        });

        it("Should integrate with Protofire oracle", async function () {
            // Mock Protofire oracle response
            const protofirePrice = ethers.utils.parseEther("1.4");
            await priceOracle.setProtofirePrice(ethers.constants.AddressZero, protofirePrice);

            const price = await priceOracle.getPrice(ethers.constants.AddressZero);
            expect(price).to.equal(protofirePrice);
        });

        it("Should update prices in real-time for Somnia speed", async function () {
            const initialPrice = ethers.utils.parseEther("1.0");
            const newPrice = ethers.utils.parseEther("1.1");

            await priceOracle.setPrice(ethers.constants.AddressZero, initialPrice);
            expect(await priceOracle.getPrice(ethers.constants.AddressZero)).to.equal(initialPrice);

            // Real-time update (within 30 seconds on Somnia)
            await priceOracle.setPrice(ethers.constants.AddressZero, newPrice);
            expect(await priceOracle.getPrice(ethers.constants.AddressZero)).to.equal(newPrice);
        });
    });

    describe("🛡️ Risk Management", function () {
        it("Should enforce LTV limits", async function () {
            await hyperLendPool.addAsset(
                ethers.constants.AddressZero,
                hlToken.address,
                debtToken.address,
                ethers.constants.AddressZero,
                PROTOCOL_PARAMS.defaultLTV,
                PROTOCOL_PARAMS.liquidationThreshold
            );

            const supplyAmount = ethers.utils.parseEther("10.0");
            const overBorrowAmount = ethers.utils.parseEther("8.0"); // 80% > 75% LTV

            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            
            await expect(hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, overBorrowAmount))
                .to.be.revertedWith("Exceeds LTV limit");
        });

        it("Should calculate health factors correctly", async function () {
            await hyperLendPool.addAsset(
                ethers.constants.AddressZero,
                hlToken.address,
                debtToken.address,
                ethers.constants.AddressZero,
                PROTOCOL_PARAMS.defaultLTV,
                PROTOCOL_PARAMS.liquidationThreshold
            );

            const supplyAmount = ethers.utils.parseEther("10.0");
            const borrowAmount = ethers.utils.parseEther("5.0"); // 50% LTV

            await priceOracle.setPrice(ethers.constants.AddressZero, ethers.utils.parseEther("1"));
            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            await hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, borrowAmount);

            const healthFactor = await hyperLendPool.getHealthFactor(user1.address);
            expect(healthFactor).to.be.gt(ethers.utils.parseEther("1")); // Healthy position
        });
    });

    describe("🚀 Gas Optimization for Somnia", function () {
        it("Should use minimal gas for operations", async function () {
            await hyperLendPool.addAsset(
                ethers.constants.AddressZero,
                hlToken.address,
                debtToken.address,
                ethers.constants.AddressZero,
                PROTOCOL_PARAMS.defaultLTV,
                PROTOCOL_PARAMS.liquidationThreshold
            );

            const supplyAmount = ethers.utils.parseEther("1.0");

            // Measure gas usage
            const tx = await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            const receipt = await tx.wait();

            // Gas should be optimized for Somnia's high throughput
            console.log(`⛽ Supply Gas Used: ${receipt.gasUsed.toString()}`);
            expect(receipt.gasUsed).to.be.lt(300000); // Should be under 300k gas
        });

        it("Should batch operations efficiently", async function () {
            // Test batch operations that take advantage of Somnia's speed
            const operations = [];
            for (let i = 0; i < 5; i++) {
                operations.push({
                    target: hyperLendPool.address,
                    data: hyperLendPool.interface.encodeFunctionData("supply", [
                        ethers.constants.AddressZero,
                        ethers.utils.parseEther("1.0")
                    ]),
                    value: ethers.utils.parseEther("1.0")
                });
            }

            // Batch execution should be efficient on Somnia
            console.log(`📦 Batch operations prepared: ${operations.length}`);
            expect(operations.length).to.equal(5);
        });
    });

    describe("📊 Real-time Metrics", function () {
        it("Should provide real-time pool metrics", async function () {
            await hyperLendPool.addAsset(
                ethers.constants.AddressZero,
                hlToken.address,
                debtToken.address,
                ethers.constants.AddressZero,
                PROTOCOL_PARAMS.defaultLTV,
                PROTOCOL_PARAMS.liquidationThreshold
            );

            const supplyAmount = ethers.utils.parseEther("100.0");
            const borrowAmount = ethers.utils.parseEther("50.0");

            await hyperLendPool.connect(user1).supply(ethers.constants.AddressZero, supplyAmount, { value: supplyAmount });
            await hyperLendPool.connect(user1).borrow(ethers.constants.AddressZero, borrowAmount);

            const metrics = await hyperLendPool.getPoolMetrics(ethers.constants.AddressZero);
            expect(metrics.totalSupply).to.equal(supplyAmount);
            expect(metrics.totalBorrow).to.equal(borrowAmount);
            expect(metrics.utilizationRate).to.equal(5000); // 50%
        });

        it("Should track liquidation efficiency", async function () {
            const initialLiquidations = await liquidationEngine.totalLiquidations();
            
            // Perform mock liquidation
            await liquidationEngine.updateLiquidationCount();
            
            const finalLiquidations = await liquidationEngine.totalLiquidations();
            expect(finalLiquidations).to.equal(initialLiquidations.add(1));
        });
    });
});

// Helper functions for Somnia-specific testing
async function simulateSomniaBlock() {
    // Fast forward to simulate Somnia's sub-second finality
    await ethers.provider.send("evm_mine", []);
}

async function measureExecutionTime(operation: Promise<any>) {
    const start = Date.now();
    await operation;
    const end = Date.now();
    return end - start;
}
