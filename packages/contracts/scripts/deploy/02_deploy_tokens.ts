import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { verify } from "../utils/verification";
import { saveDeploymentData, loadDeploymentData } from "../utils/helpers";
import { TEST_TOKENS_CONFIG } from "../utils/constants";

const deployTokens: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy } = deployments;
  const { deployer, admin } = await getNamedAccounts();

  console.log("🪙 Deploying Token Contracts...");
  console.log("Network:", network.name);
  console.log("Deployer:", deployer);

  // Load core deployment data
  const coreDeployment = await loadDeploymentData(network.name);
  if (!coreDeployment) {
    throw new Error("Core contracts not deployed. Run deploy:core first.");
  }

  const hyperLendPoolAddress = coreDeployment.contracts.HyperLendPool;
  console.log("HyperLend Pool:", hyperLendPoolAddress);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY TOKEN IMPLEMENTATIONS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n📝 Deploying Token Implementations...");

  // Deploy HLToken implementation
  const hlTokenImpl = await deploy("HLToken", {
    from: deployer,
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  // Deploy DebtToken implementation
  const debtTokenImpl = await deploy("DebtToken", {
    from: deployer,
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  // Deploy RewardToken
  const rewardToken = await deploy("RewardToken", {
    from: deployer,
    args: [
      "HyperLend Reward Token",
      "HLR",
      ethers.parseEther("1000000"), // 1M total supply
      admin
    ],
    log: true,
    waitConfirmations: network.live ? 5 : 1,
  });

  console.log("✅ Token implementations deployed");
  console.log("  HLToken Implementation:", hlTokenImpl.address);
  console.log("  DebtToken Implementation:", debtTokenImpl.address);
  console.log("  Reward Token:", rewardToken.address);

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY TEST TOKENS (TESTNET/LOCAL ONLY)
  // ═══════════════════════════════════════════════════════════════════════════════════

  const testTokens: { [key: string]: string } = {};

  if (!network.live || network.name.includes("test")) {
    console.log("\n🧪 Deploying Test Tokens...");
    
    const testTokenConfigs = TEST_TOKENS_CONFIG[network.name] || TEST_TOKENS_CONFIG.default;
    
    for (const tokenConfig of testTokenConfigs) {
      console.log(`  Deploying ${tokenConfig.name}...`);
      
      const testToken = await deploy(`MockERC20_${tokenConfig.symbol}`, {
        contract: "MockERC20",
        from: deployer,
        args: [
          tokenConfig.name,
          tokenConfig.symbol,
          tokenConfig.decimals,
          ethers.parseUnits(tokenConfig.initialSupply, tokenConfig.decimals),
        ],
        log: true,
        waitConfirmations: network.live ? 5 : 1,
      });
      
      testTokens[tokenConfig.symbol] = testToken.address;
      console.log(`    ${tokenConfig.symbol}: ${testToken.address}`);
    }
    
    console.log("✅ Test tokens deployed");
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOY MARKET TOKENS FOR EACH ASSET
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🏭 Deploying Market Tokens...");

  const marketTokens: { [key: string]: { hlToken: string; debtToken: string } } = {};
  
  // Get tokens to create markets for
  const tokensToProcess = network.live && !network.name.includes("test") 
    ? [] // On mainnet, would use real token addresses
    : Object.entries(testTokens);

  for (const [symbol, tokenAddress] of tokensToProcess) {
    console.log(`  Creating market tokens for ${symbol}...`);
    
    // Deploy HLToken for this market
    const hlToken = await deploy(`HLToken_${symbol}`, {
      contract: "HLToken",
      from: deployer,
      args: [
        `HyperLend ${symbol}`,
        `hl${symbol}`,
        tokenAddress,
        hyperLendPoolAddress,
        admin,
      ],
      log: true,
      waitConfirmations: network.live ? 5 : 1,
    });

    // Deploy DebtToken for this market
    const debtToken = await deploy(`DebtToken_${symbol}`, {
      contract: "DebtToken",
      from: deployer,
      args: [
        `HyperLend ${symbol} Debt`,
        `debt${symbol}`,
        tokenAddress,
        hyperLendPoolAddress,
        admin,
      ],
      log: true,
      waitConfirmations: network.live ? 5 : 1,
    });

    marketTokens[symbol] = {
      hlToken: hlToken.address,
      debtToken: debtToken.address,
    };

    console.log(`    hl${symbol}: ${hlToken.address}`);
    console.log(`    debt${symbol}: ${debtToken.address}`);
  }

  console.log("✅ Market tokens deployed");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // CONFIGURE POOL WITH MARKETS
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n⚙️  Adding markets to pool...");

  const hyperLendPool = await ethers.getContractAt("HyperLendPool", hyperLendPoolAddress);

  for (const [symbol, tokenAddress] of tokensToProcess) {
    const marketToken = marketTokens[symbol];
    
    console.log(`  Adding ${symbol} market...`);
    
    try {
      const tx = await hyperLendPool.addMarket(
        tokenAddress,
        marketToken.hlToken,
        marketToken.debtToken,
        ethers.parseEther("0.85"), // 85% liquidation threshold
        ethers.parseEther("0.05"), // 5% liquidation bonus
        ethers.parseEther("1000000"), // 1M borrow cap
        ethers.parseEther("10000000") // 10M supply cap
      );
      
      await tx.wait();
      console.log(`    ✓ ${symbol} market added`);
    } catch (error) {
      console.log(`    ⚠️  Failed to add ${symbol} market:`, error.message);
    }
  }

  console.log("✅ Markets configured in pool");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SETUP PRICE FEEDS (MOCK DATA FOR TESTING)
  // ═══════════════════════════════════════════════════════════════════════════════════

  if (!network.live || network.name.includes("test")) {
    console.log("\n📊 Setting up mock price feeds...");
    
    const priceOracle = await ethers.getContractAt("PriceOracle", coreDeployment.contracts.PriceOracle);
    
    const mockPrices = {
      TUSDC: ethers.parseEther("1"), // $1
      TWETH: ethers.parseEther("2000"), // $2000
      TBTC: ethers.parseEther("45000"), // $45000
      TLINK: ethers.parseEther("15"), // $15
      TUNI: ethers.parseEther("8"), // $8
    };

    for (const [symbol, price] of Object.entries(mockPrices)) {
      if (testTokens[symbol]) {
        try {
          await priceOracle.setEmergencyPrice(
            testTokens[symbol],
            price,
            "Initial test price"
          );
          console.log(`    ✓ Set ${symbol} price to ${ethers.formatEther(price)} USD`);
        } catch (error) {
          console.log(`    ⚠️  Failed to set ${symbol} price:`, error.message);
        }
      }
    }
    
    console.log("✅ Mock price feeds configured");
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DISTRIBUTE TEST TOKENS TO ACCOUNTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  if (!network.live || network.name.includes("test")) {
    console.log("\n💰 Distributing test tokens...");
    
    // Get test accounts
    const accounts = await ethers.getSigners();
    const testAccounts = accounts.slice(1, 6); // Skip deployer, take next 5
    
    for (const [symbol, tokenAddress] of Object.entries(testTokens)) {
      const token = await ethers.getContractAt("MockERC20", tokenAddress);
      const decimals = await token.decimals();
      
      for (let i = 0; i < testAccounts.length; i++) {
        const account = testAccounts[i];
        const amount = ethers.parseUnits("10000", decimals); // 10,000 tokens each
        
        try {
          await token.transfer(account.address, amount);
          console.log(`    ✓ Sent ${ethers.formatUnits(amount, decimals)} ${symbol} to ${account.address}`);
        } catch (error) {
          console.log(`    ⚠️  Failed to send ${symbol} to ${account.address}`);
        }
      }
    }
    
    console.log("✅ Test tokens distributed");
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // SAVE DEPLOYMENT DATA
  // ═══════════════════════════════════════════════════════════════════════════════════

  const tokenDeploymentData = {
    network: network.name,
    timestamp: new Date().toISOString(),
    blockNumber: await ethers.provider.getBlockNumber(),
    contracts: {
      // Token implementations
      HLTokenImplementation: hlTokenImpl.address,
      DebtTokenImplementation: debtTokenImpl.address,
      RewardToken: rewardToken.address,
      
      // Test tokens
      testTokens,
      
      // Market tokens
      marketTokens,
    },
    deployer,
    admin,
  };

  // Merge with existing deployment data
  const updatedDeployment = {
    ...coreDeployment,
    tokens: tokenDeploymentData,
    lastUpdated: new Date().toISOString(),
  };

  await saveDeploymentData(updatedDeployment, network.name);
  console.log("✅ Token deployment data saved");

  // ═══════════════════════════════════════════════════════════════════════════════════
  // VERIFY CONTRACTS
  // ═══════════════════════════════════════════════════════════════════════════════════

  if (network.live && process.env.VERIFY_CONTRACTS === "true") {
    console.log("\n🔍 Verifying token contracts...");
    
    try {
      // Verify RewardToken
      await verify(rewardToken.address, [
        "HyperLend Reward Token",
        "HLR",
        ethers.parseEther("1000000"),
        admin
      ]);
      console.log("  ✓ RewardToken verified");
      
      // Verify market tokens
      for (const [symbol, tokenAddress] of tokensToProcess) {
        const marketToken = marketTokens[symbol];
        
        await verify(marketToken.hlToken, [
          `HyperLend ${symbol}`,
          `hl${symbol}`,
          tokenAddress,
          hyperLendPoolAddress,
          admin,
        ]);
        console.log(`  ✓ hl${symbol} verified`);
        
        await verify(marketToken.debtToken, [
          `HyperLend ${symbol} Debt`,
          `debt${symbol}`,
          tokenAddress,
          hyperLendPoolAddress,
          admin,
        ]);
        console.log(`  ✓ debt${symbol} verified`);
      }
      
    } catch (error) {
      console.log("  ⚠️  Token verification failed:", error.message);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════════
  // DEPLOYMENT SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════════════

  console.log("\n🎉 TOKEN DEPLOYMENT COMPLETED! 🎉");
  console.log("=====================================");
  console.log("Network:", network.name);
  console.log("=====================================");
  console.log("📋 Token Contracts:");
  console.log("  Reward Token:", rewardToken.address);
  
  if (Object.keys(testTokens).length > 0) {
    console.log("\n🧪 Test Tokens:");
    Object.entries(testTokens).forEach(([symbol, address]) => {
      console.log(`  ${symbol}: ${address}`);
    });
  }
  
  if (Object.keys(marketTokens).length > 0) {
    console.log("\n🏭 Market Tokens:");
    Object.entries(marketTokens).forEach(([symbol, tokens]) => {
      console.log(`  ${symbol}:`);
      console.log(`    hl${symbol}: ${tokens.hlToken}`);
      console.log(`    debt${symbol}: ${tokens.debtToken}`);
    });
  }
  
  console.log("=====================================");
  console.log("🔧 Next steps:");
  console.log("  1. Run: npm run configure:system");
  console.log("  2. Run: npm run initialize:pools");
  console.log("  3. Start testing with: npm run test");
  console.log("=====================================");
  
  return true;
};

export default deployTokens;
deployTokens.tags = ["Tokens", "HyperLend"];
deployTokens.dependencies = ["Core"];