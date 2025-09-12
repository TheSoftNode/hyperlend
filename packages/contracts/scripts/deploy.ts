import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getMainnetDeploymentConfig } from "../deployments/mainnet/config";
import { getTestnetDeploymentConfig } from "../deployments/testnet/config";
import { saveDeploymentData, logWithTimestamp, executeWithRetry } from "./utils/helpers";
import { verifyContract, batchVerifyContracts } from "./utils/verify";
import { saveDeployment, DeploymentInfo } from "./utils/save-deployment";

/**
 * @title HyperLend Production Deployment Script
 * @dev Uses official Somnia addresses and configurations from /deployments/
 * @notice This script deploys HyperLend with real DIA Oracle integration
 */

async function deployHyperLend(hre: HardhatRuntimeEnvironment) {
  const { network } = hre;
  
  logWithTimestamp(`🚀 Deploying HyperLend to ${network.name}...`);
  
  const [deployer] = await ethers.getSigners();
  logWithTimestamp(`📍 Deployer: ${deployer.address}`);

  // Get the appropriate configuration based on network
  const isTestnet = network.name.includes('testnet') || network.name.includes('test');
  const config = isTestnet ? getTestnetDeploymentConfig() : getMainnetDeploymentConfig();
  
  logWithTimestamp(`⚡ Network: ${config.network.name} (Chain ID: ${config.network.chainId})`);
  logWithTimestamp(`🔮 DIA Oracle: ${config.network.diaOracle}`);

  const deployOptions = {
    gasLimit: config.verification.gasSettings.gasLimit,
    gasPrice: config.verification.gasSettings.gasPrice,
  };

  // Track contracts for verification and saving
  const contractsToVerify: Array<{ address: string; args: any[] }> = [];
  const deployedContracts: Record<string, string> = {};

  try {
    logWithTimestamp("📋 Phase 1: Core Infrastructure Deployment");
    
    // 1. Deploy DIAOracleLib
    logWithTimestamp("⏳ Deploying DIAOracleLib...");
    const DIAOracleLibFactory = await ethers.getContractFactory("DIAOracleLib");
    const diaOracleLib = await executeWithRetry(async () => {
      return await DIAOracleLibFactory.deploy(deployOptions);
    });
    await diaOracleLib.waitForDeployment();
    const diaOracleLibAddress = await diaOracleLib.getAddress();
    deployedContracts.diaOracleLib = diaOracleLibAddress;
    contractsToVerify.push({ address: diaOracleLibAddress, args: [] });
    logWithTimestamp(`✅ DIAOracleLib: ${diaOracleLibAddress}`);
    
    // 2. Deploy Interest Rate Model
    logWithTimestamp("⏳ Deploying InterestRateModel...");
    const InterestRateModelFactory = await ethers.getContractFactory("InterestRateModel");
    const interestRateModel = await executeWithRetry(async () => {
      return await InterestRateModelFactory.deploy(
        config.protocol.interestRateModel.baseRate,
        config.protocol.interestRateModel.slope1,
        config.protocol.interestRateModel.slope2,
        config.protocol.interestRateModel.optimalUtilization,
        deployOptions
      );
    });
    await interestRateModel.waitForDeployment();
    const interestRateModelAddress = await interestRateModel.getAddress();
    deployedContracts.interestRateModel = interestRateModelAddress;
    contractsToVerify.push({ 
      address: interestRateModelAddress, 
      args: [
        config.protocol.interestRateModel.baseRate,
        config.protocol.interestRateModel.slope1,
        config.protocol.interestRateModel.slope2,
        config.protocol.interestRateModel.optimalUtilization
      ] 
    });
    logWithTimestamp(`✅ InterestRateModel: ${interestRateModelAddress}`);

    // 3. Deploy Price Oracle with REAL DIA Oracle
    logWithTimestamp("⏳ Deploying PriceOracle with official DIA integration...");
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await executeWithRetry(async () => {
      return await PriceOracleFactory.deploy(
        deployer.address, // admin
        config.network.diaOracle, // Official DIA Oracle address
        deployOptions
      );
    });
    await priceOracle.waitForDeployment();
    const priceOracleAddress = await priceOracle.getAddress();
    deployedContracts.priceOracle = priceOracleAddress;
    contractsToVerify.push({ 
      address: priceOracleAddress, 
      args: [deployer.address, config.network.diaOracle] 
    });
    logWithTimestamp(`✅ PriceOracle: ${priceOracleAddress}`);
    logWithTimestamp(`   🔗 Connected to Official DIA Oracle: ${config.network.diaOracle}`);

    // 4. Deploy Risk Manager
    logWithTimestamp("⏳ Deploying RiskManager...");
    const RiskManagerFactory = await ethers.getContractFactory("RiskManager");
    const riskManager = await executeWithRetry(async () => {
      return await RiskManagerFactory.deploy(
        config.protocol.riskParameters.defaultLTV,
        config.protocol.riskParameters.liquidationThreshold,
        config.protocol.riskParameters.liquidationPenalty,
        deployOptions
      );
    });
    await riskManager.waitForDeployment();
    const riskManagerAddress = await riskManager.getAddress();
    deployedContracts.riskManager = riskManagerAddress;
    contractsToVerify.push({ 
      address: riskManagerAddress, 
      args: [
        config.protocol.riskParameters.defaultLTV,
        config.protocol.riskParameters.liquidationThreshold,
        config.protocol.riskParameters.liquidationPenalty
      ] 
    });
    logWithTimestamp(`✅ RiskManager: ${riskManagerAddress}`);

    // 5. Deploy Liquidation Engine
    logWithTimestamp("⏳ Deploying LiquidationEngine...");
    const LiquidationEngineFactory = await ethers.getContractFactory("LiquidationEngine");
    const liquidationEngine = await executeWithRetry(async () => {
      return await LiquidationEngineFactory.deploy(
        config.protocol.riskParameters.liquidationThreshold,
        config.protocol.riskParameters.liquidationPenalty,
        500, // 5% max slippage - Somnia optimized
        deployOptions
      );
    });
    await liquidationEngine.waitForDeployment();
    const liquidationEngineAddress = await liquidationEngine.getAddress();
    deployedContracts.liquidationEngine = liquidationEngineAddress;
    contractsToVerify.push({ 
      address: liquidationEngineAddress, 
      args: [
        config.protocol.riskParameters.liquidationThreshold,
        config.protocol.riskParameters.liquidationPenalty,
        500
      ] 
    });
    logWithTimestamp(`✅ LiquidationEngine: ${liquidationEngineAddress}`);

    // 6. Deploy Somnia Wrapper
    logWithTimestamp("⏳ Deploying SomniaWrapper...");
    const SomniaWrapperFactory = await ethers.getContractFactory("SomniaWrapper");
    const somniaWrapper = await executeWithRetry(async () => {
      return await SomniaWrapperFactory.deploy(deployOptions);
    });
    await somniaWrapper.waitForDeployment();
    const somniaWrapperAddress = await somniaWrapper.getAddress();
    deployedContracts.somniaWrapper = somniaWrapperAddress;
    contractsToVerify.push({ address: somniaWrapperAddress, args: [] });
    logWithTimestamp(`✅ SomniaWrapper: ${somniaWrapperAddress}`);

    logWithTimestamp("📋 Phase 2: Main Pool Deployment");

    // 7. Deploy HyperLend Pool
    logWithTimestamp("⏳ Deploying HyperLendPool...");
    const HyperLendPoolFactory = await ethers.getContractFactory("HyperLendPool");
    const hyperLendPool = await executeWithRetry(async () => {
      return await HyperLendPoolFactory.deploy(
        deployer.address, // admin
        interestRateModelAddress,
        liquidationEngineAddress,
        priceOracleAddress,
        riskManagerAddress,
        config.network.diaOracle, // Official DIA Oracle
        somniaWrapperAddress,
        deployOptions
      );
    });
    await hyperLendPool.waitForDeployment();
    const hyperLendPoolAddress = await hyperLendPool.getAddress();
    deployedContracts.hyperLendPool = hyperLendPoolAddress;
    contractsToVerify.push({ 
      address: hyperLendPoolAddress, 
      args: [
        deployer.address,
        interestRateModelAddress,
        liquidationEngineAddress,
        priceOracleAddress,
        riskManagerAddress,
        config.network.diaOracle,
        somniaWrapperAddress
      ] 
    });
    logWithTimestamp(`✅ HyperLendPool: ${hyperLendPoolAddress}`);

    logWithTimestamp("📋 Phase 3: Token Contracts");

    const HLTokenFactory = await ethers.getContractFactory("HLToken");
    const DebtTokenFactory = await ethers.getContractFactory("DebtToken");
    
    const deployedTokens = {
      hlTokens: {} as any,
      debtTokens: {} as any
    };
    
    for (const asset of config.assets) {
      logWithTimestamp(`⏳ Deploying tokens for ${asset.symbol}...`);
      
      const hlToken = await executeWithRetry(async () => {
        return await HLTokenFactory.deploy(
          `HyperLend ${asset.name}`,
          `hl${asset.symbol}`,
          deployOptions
        );
      });
      await hlToken.waitForDeployment();
      const hlTokenAddress = await hlToken.getAddress();
      deployedTokens.hlTokens[asset.symbol] = hlTokenAddress;
      contractsToVerify.push({ 
        address: hlTokenAddress, 
        args: [`HyperLend ${asset.name}`, `hl${asset.symbol}`] 
      });
      
      const debtToken = await executeWithRetry(async () => {
        return await DebtTokenFactory.deploy(
          `HyperLend Debt ${asset.name}`,
          `debt${asset.symbol}`,
          deployOptions
        );
      });
      await debtToken.waitForDeployment();
      const debtTokenAddress = await debtToken.getAddress();
      deployedTokens.debtTokens[asset.symbol] = debtTokenAddress;
      contractsToVerify.push({ 
        address: debtTokenAddress, 
        args: [`HyperLend Debt ${asset.name}`, `debt${asset.symbol}`] 
      });
      
      logWithTimestamp(`✅ ${asset.symbol} tokens deployed`);
    }

    logWithTimestamp("📋 Phase 4: Configuration");

    // Configure price oracle with DIA keys for supported assets
    for (const asset of config.assets) {
      if (asset.adapterAddress) {
        logWithTimestamp(`⏳ Setting DIA adapter for ${asset.symbol}: ${asset.adapterAddress}`);
        
        try {
          await executeWithRetry(async () => {
            return await priceOracle.setAssetDIAKey(
              asset.address || ethers.constants.AddressZero,
              asset.diaKey,
              asset.decimals,
              { gasLimit: 200000, gasPrice: config.verification.gasSettings.gasPrice }
            );
          });
          logWithTimestamp(`✅ ${asset.symbol} DIA configuration set`);
        } catch (error) {
          logWithTimestamp(`❌ Failed to configure ${asset.symbol}: ${error}`, 'error');
        }
      }
    }

    // Configure liquidation engine
    try {
      await executeWithRetry(async () => {
        return await liquidationEngine.setPoolAddress(hyperLendPoolAddress, {
          gasLimit: 200000,
          gasPrice: config.verification.gasSettings.gasPrice
        });
      });
      logWithTimestamp("✅ Liquidation engine configured");
    } catch (error) {
      logWithTimestamp(`❌ Failed to configure liquidation engine: ${error}`, 'error');
    }

    logWithTimestamp("📋 Phase 5: Saving Deployment Data");

    // Prepare deployment data
    const deploymentData = {
      network: config.network.name,
      chainId: config.network.chainId,
      timestamp: new Date().toISOString(),
      deployer: deployer.address,
      
      contracts: deployedContracts,
      tokens: deployedTokens,
      
      configuration: {
        diaOracle: config.network.diaOracle,
        officialTokens: (config.network as any).officialTokens || {},
        assetAdapters: config.network.assetAdapters,
        protocolParams: config.protocol,
        supportedAssets: config.assets
      },
      
      admin: deployer.address,
      transactionHashes: {},
      lastUpdated: new Date().toISOString()
    };

    // Save using both utility systems
    await saveDeploymentData(deploymentData, network.name);

    const deploymentInfo: DeploymentInfo = {
      network: network.name,
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      contracts: {
        ...deployedContracts,
        ...Object.fromEntries(
          Object.entries(deployedTokens.hlTokens).map(([k, v]) => [`hlToken_${k}`, v as string])
        ),
        ...Object.fromEntries(
          Object.entries(deployedTokens.debtTokens).map(([k, v]) => [`debtToken_${k}`, v as string])
        )
      } as Record<string, string>,
      configuration: deploymentData.configuration
    };

    await saveDeployment(deploymentInfo);

    logWithTimestamp("📋 Phase 6: Contract Verification");

    // Verify contracts (skip on local networks)
    if (network.name !== 'hardhat' && network.name !== 'localhost') {
      if (config.verification.autoVerify) {
        try {
          logWithTimestamp("🔍 Starting contract verification...");
          await batchVerifyContracts(contractsToVerify);
          logWithTimestamp("✅ All contracts verified successfully");
        } catch (error) {
          logWithTimestamp(`⚠️ Verification failed: ${error}`, 'warn');
          logWithTimestamp("ℹ️ Contracts can be verified manually later", 'info');
        }
      } else {
        logWithTimestamp("ℹ️ Auto-verification disabled", 'info');
      }
    } else {
      logWithTimestamp("ℹ️ Skipping verification on local network", 'info');
    }

    logWithTimestamp("🎉 HyperLend Successfully Deployed!");
    logWithTimestamp("===============================================");
    logWithTimestamp(`🏦 HyperLendPool: ${hyperLendPoolAddress}`);
    logWithTimestamp(`🔮 PriceOracle: ${priceOracleAddress} (DIA: ${config.network.diaOracle})`);
    logWithTimestamp(`📈 InterestRateModel: ${interestRateModelAddress}`);
    logWithTimestamp(`⚡ LiquidationEngine: ${liquidationEngineAddress}`);
    logWithTimestamp(`🛡️ RiskManager: ${riskManagerAddress}`);
    logWithTimestamp(`🌟 SomniaWrapper: ${somniaWrapperAddress}`);
    logWithTimestamp(`📚 DIAOracleLib: ${diaOracleLibAddress}`);
    
    if ((config.network as any).officialTokens) {
      logWithTimestamp("🪙 Official Somnia Tokens Available:");
      logWithTimestamp(`   USDC: ${(config.network as any).officialTokens.USDC}`);
      logWithTimestamp(`   USDT: ${(config.network as any).officialTokens.USDT}`);
      logWithTimestamp(`   WETH: ${(config.network as any).officialTokens.WETH}`);
      logWithTimestamp(`   WSOMI: ${(config.network as any).officialTokens.WSOMI}`);
    }
    
    logWithTimestamp("💡 Next Steps:");
    logWithTimestamp("   1. Check deployment files in /deployments folder");
    logWithTimestamp("   2. Test DIA Oracle price feeds with official adapters");
    logWithTimestamp("   3. Configure frontend with contract addresses");
    logWithTimestamp("   4. Add markets using official Somnia tokens");
    logWithTimestamp("   5. Set up LayerZero integration for cross-chain functionality");

    return deploymentData;

  } catch (error) {
    logWithTimestamp(`❌ Deployment failed: ${error}`, 'error');
    throw error;
  }
}

export default deployHyperLend;
