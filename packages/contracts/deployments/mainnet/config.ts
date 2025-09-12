import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";

/**
 * @title Mainnet Deployment Configuration
 * @dev Configuration for deploying HyperLend on Somnia Mainnet
 * @notice Uses official DIA Oracle Mainnet: 0xa93546947f3015c986695750b8bbea8e26d65856
 */

// ═══════════════════════════════════════════════════════════════════════════════════
// OFFICIAL SOMNIA MAINNET CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════════

export const MAINNET_CONFIG = {
  // Network Information
  chainId: 2648,
  name: "Somnia Mainnet",
  rpcUrl: "https://rpc.somnia.network",
  
  // Official DIA Oracle (from official Somnia docs)
  diaOracle: "0xbA0E0750A56e995506CA458b2BdD752754CF39C4",
  
  // Official Asset Adapters (from official Somnia docs)
  assetAdapters: {
    USDT: "0x936C4F07fD4d01485849ee0EE2Cdcea2373ba267",
    USDC: "0x5D4266f4DD721c1cD8367FEb23E4940d17C83C93",
    BTC: "0xb12e1d47b0022fA577c455E7df2Ca9943D0152bE",
    ARB: "0x6a96a0232402c2BC027a12C73f763b604c9F77a6",
    SOL: "0xa4a3a8B729939E2a79dCd9079cee7d84b0d96234"
  },
  
  // Official Token Addresses (from official Somnia docs)
  officialTokens: {
    USDC: "0x28bec7e30e6faee657a03e19bf1128aad7632a00",
    USDT: "0x67B302E35Aef5EEE8c32D934F5856869EF428330",
    WETH: "0x936Ab8C674bcb567CD5dEB85D8A216494704E9D8",
    WSOMI: "0x046EDe9564A72571df6F5e44d0405360c0f4dCab"
  },
  
  // Utility Contracts (from official Somnia docs)
  utilityContracts: {
    multiCallV3: "0x5e44F178E8cF9B2F5409B6f18ce936aB817C5a11"
  },
  
  // LayerZero Integration (from official Somnia docs)
  layerZero: {
    endpointV2: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
    chainId: 30380, // LayerZero EID
    sendUln302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    receiveUln302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
    executor: "0x4208D6E27538189bB48E603D6123A94b8Abe0A0b",
    deadDVN: "0x6788f52439ACA6BFF597d3eeC2DC9a44B8FEE842"
  },
  
  // DIA Oracle Configuration (Production Settings)
  oracleConfig: {
    decimals: 8,
    deviationThreshold: 25, // 0.25% in basis points (tighter for mainnet)
    refreshFrequency: 60, // 1 minute (faster for mainnet)
    heartbeat: 3600, // 1 hour (shorter for mainnet)
    methodology: "MAIR"
  },
  
  // Asset Price Keys for DIA Oracle
  priceKeys: {
    STT: "STT/USD",
    USDT: "USDT/USD",
    USDC: "USDC/USD", 
    BTC: "BTC/USD",
    ARB: "ARB/USD",
    SOL: "SOL/USD"
  }
};

// ═══════════════════════════════════════════════════════════════════════════════════
// HYPERLEND PROTOCOL PARAMETERS (MAINNET - PRODUCTION)
// ═══════════════════════════════════════════════════════════════════════════════════

export const PROTOCOL_PARAMS = {
  // Interest Rate Model (Conservative for mainnet)
  interestRateModel: {
    baseRate: 100, // 1% base rate (lower for mainnet)
    slope1: 800, // 8% slope 1
    slope2: 25000, // 250% slope 2
    optimalUtilization: 8500 // 85% optimal utilization
  },
  
  // Risk Management (Conservative for mainnet)
  riskParameters: {
    defaultLTV: 7000, // 70% default LTV (more conservative)
    liquidationThreshold: 8000, // 80% liquidation threshold
    liquidationPenalty: 750, // 7.5% liquidation penalty
    maxLiquidationRatio: 5000, // 50% max liquidation
    minCollateralRatio: 12500 // 125% minimum collateral ratio
  },
  
  // Price Oracle (Strict for mainnet)
  priceOracle: {
    maxPriceDeviation: 500, // 5% max deviation (stricter for mainnet)
    priceValidityPeriod: 1800, // 30 minutes validity
    emergencyPriceValidityPeriod: 3600, // 1 hour emergency validity
    minimumUpdateInterval: 30 // 30 seconds minimum update
  },
  
  // Protocol Settings
  protocol: {
    protocolFeeRate: 200, // 2% protocol fee (lower for mainnet)
    reserveFactor: 1500, // 15% reserve factor (higher for mainnet)
    maxBorrowingRate: 10000, // 100% max borrowing rate
    gracePeriod: 43200 // 12 hours grace period (shorter for mainnet)
  }
};

// ═══════════════════════════════════════════════════════════════════════════════════
// DEPLOYMENT ADDRESSES (to be populated after deployment)
// ═══════════════════════════════════════════════════════════════════════════════════

export interface DeploymentAddresses {
  hyperLendPool: string;
  priceOracle: string;
  interestRateModel: string;
  liquidationEngine: string;
  riskManager: string;
  somniaWrapper: string;
  
  // Token contracts
  hlTokens: {
    STT: string;
    USDT: string;
    USDC: string;
    BTC: string;
    ARB: string;
    SOL: string;
  };
  
  debtTokens: {
    STT: string;
    USDT: string;
    USDC: string;
    BTC: string;
    ARB: string;
    SOL: string;
  };
}

// ═══════════════════════════════════════════════════════════════════════════════════
// DEPLOYMENT VERIFICATION
// ═══════════════════════════════════════════════════════════════════════════════════

export const VERIFICATION_CONFIG = {
  // Block confirmations to wait before verification (higher for mainnet)
  confirmations: 5,
  
  // Whether to verify contracts on deployment
  autoVerify: true,
  
  // Gas settings for mainnet (optimized)
  gasSettings: {
    gasLimit: 6000000,
    gasPrice: ethers.utils.parseUnits("1", "gwei") // Will be adjusted based on network conditions
  }
};

// ═══════════════════════════════════════════════════════════════════════════════════
// SUPPORTED ASSETS CONFIGURATION (MAINNET - CONSERVATIVE)
// ═══════════════════════════════════════════════════════════════════════════════════

export const SUPPORTED_ASSETS = [
  {
    symbol: "STT",
    name: "Somnia Token",
    address: ethers.constants.AddressZero, // Native token
    decimals: 18,
    diaKey: "STT/USD",
    adapterAddress: "", // No adapter for native STT
    isNative: true,
    ltv: 7000, // 70% (conservative for mainnet)
    liquidationThreshold: 8000, // 80%
    liquidationPenalty: 750 // 7.5%
  },
  {
    symbol: "USDT",
    name: "Tether USD",
    address: "0x67B302E35Aef5EEE8c32D934F5856869EF428330", // Official Somnia USDT
    decimals: 6,
    diaKey: "USDT/USD",
    adapterAddress: "0x936C4F07fD4d01485849ee0EE2Cdcea2373ba267",
    isNative: false,
    ltv: 7500, // 75% (conservative)
    liquidationThreshold: 8500, // 85%
    liquidationPenalty: 500 // 5%
  },
  {
    symbol: "USDC",
    name: "USD Coin",
    address: "0x28bec7e30e6faee657a03e19bf1128aad7632a00", // Official Somnia USDC
    decimals: 6,
    diaKey: "USDC/USD",
    adapterAddress: "0x5D4266f4DD721c1cD8367FEb23E4940d17C83C93",
    isNative: false,
    ltv: 7500, // 75% (conservative)
    liquidationThreshold: 8500, // 85%
    liquidationPenalty: 500 // 5%
  },
  {
    symbol: "WETH",
    name: "Wrapped Ethereum",
    address: "0x936Ab8C674bcb567CD5dEB85D8A216494704E9D8", // Official Somnia WETH
    decimals: 18,
    diaKey: "ETH/USD",
    adapterAddress: "", // Need to check if there's a DIA adapter for ETH
    isNative: false,
    ltv: 7000, // 70% (conservative for volatile asset)
    liquidationThreshold: 8000, // 80%
    liquidationPenalty: 750 // 7.5%
  },
  {
    symbol: "BTC",
    name: "Bitcoin",
    address: "", // Wrapped BTC - to be deployed or use existing
    decimals: 8,
    diaKey: "BTC/USD",
    adapterAddress: "0xb12e1d47b0022fA577c455E7df2Ca9943D0152bE",
    isNative: false,
    ltv: 6500, // 65% (conservative for volatile asset)
    liquidationThreshold: 7500, // 75%
    liquidationPenalty: 1000 // 10%
  },
  {
    symbol: "ARB",
    name: "Arbitrum",
    address: "", // Wrapped ARB - to be deployed or use existing
    decimals: 18,
    diaKey: "ARB/USD",
    adapterAddress: "0x6a96a0232402c2BC027a12C73f763b604c9F77a6",
    isNative: false,
    ltv: 6000, // 60% (conservative for governance token)
    liquidationThreshold: 7000, // 70%
    liquidationPenalty: 1250 // 12.5%
  },
  {
    symbol: "SOL",
    name: "Solana",
    address: "", // Wrapped SOL - to be deployed or use existing
    decimals: 9,
    diaKey: "SOL/USD",
    adapterAddress: "0xa4a3a8B729939E2a79dCd9079cee7d84b0d96234",
    isNative: false,
    ltv: 6000, // 60% (conservative for volatile asset)
    liquidationThreshold: 7000, // 70%
    liquidationPenalty: 1250 // 12.5%
  }
];

// ═══════════════════════════════════════════════════════════════════════════════════
// SECURITY AND GOVERNANCE SETTINGS
// ═══════════════════════════════════════════════════════════════════════════════════

export const SECURITY_CONFIG = {
  // Multi-sig wallet addresses (to be set)
  governance: {
    admin: "", // Main admin multi-sig
    treasury: "", // Treasury multi-sig
    emergency: "", // Emergency pause multi-sig
    upgrader: "" // Contract upgrader multi-sig
  },
  
  // Emergency settings
  emergency: {
    pauseGuardian: "", // Emergency pause guardian
    maxEmergencyPauseDuration: 604800, // 7 days max pause
    emergencyWithdrawDelay: 86400 // 24 hours emergency withdraw delay
  },
  
  // Timelock settings
  timelock: {
    minDelay: 172800, // 48 hours minimum delay
    maxDelay: 2592000, // 30 days maximum delay
    gracePeriod: 1209600 // 14 days grace period
  }
};

// ═══════════════════════════════════════════════════════════════════════════════════
// DEPLOYMENT HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * @notice Validate mainnet deployment configuration
 */
export function validateMainnetConfig(): boolean {
  // Validate DIA Oracle address
  if (!ethers.utils.isAddress(MAINNET_CONFIG.diaOracle)) {
    throw new Error("Invalid DIA Oracle address");
  }
  
  // Validate adapter addresses
  for (const [asset, adapter] of Object.entries(MAINNET_CONFIG.assetAdapters)) {
    if (!ethers.utils.isAddress(adapter)) {
      throw new Error(`Invalid ${asset} adapter address: ${adapter}`);
    }
  }
  
  // Validate protocol parameters are conservative enough for mainnet
  if (PROTOCOL_PARAMS.riskParameters.defaultLTV >= PROTOCOL_PARAMS.riskParameters.liquidationThreshold) {
    throw new Error("Default LTV must be less than liquidation threshold");
  }
  
  if (PROTOCOL_PARAMS.riskParameters.defaultLTV > 7500) {
    throw new Error("Default LTV too high for mainnet (max 75%)");
  }
  
  if (PROTOCOL_PARAMS.priceOracle.maxPriceDeviation > 1000) {
    throw new Error("Price deviation tolerance too high for mainnet (max 10%)");
  }
  
  return true;
}

/**
 * @notice Get deployment configuration for mainnet environment
 */
export function getMainnetDeploymentConfig() {
  validateMainnetConfig();
  
  return {
    network: MAINNET_CONFIG,
    protocol: PROTOCOL_PARAMS,
    verification: VERIFICATION_CONFIG,
    assets: SUPPORTED_ASSETS,
    security: SECURITY_CONFIG
  };
}

/**
 * @notice Get gas price for mainnet deployment
 */
export async function getOptimalGasPrice(): Promise<string> {
  // This would typically fetch from gas price APIs
  // For now, return a conservative default in gwei
  return "2";
}
