import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";

/**
 * @title Testnet Deployment Configuration
 * @dev Configuration for deploying HyperLend on Somnia Testnet
 * @notice Uses official DIA Oracle Testnet: 0x9206296ea3aee3e6bdc07f7aaef14dfcf33d865d
 */

// ═══════════════════════════════════════════════════════════════════════════════════
// OFFICIAL SOMNIA TESTNET CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════════

export const TESTNET_CONFIG = {
  // Network Information
  chainId: 50312,
  name: "Somnia Testnet",
  rpcUrl: "https://dream-rpc.somnia.network",
  
  // Official DIA Oracle (from DIA docs)
  diaOracle: "0x9206296ea3aee3e6bdc07f7aaef14dfcf33d865d",
  
  // Official Asset Adapters (from DIA docs)
  assetAdapters: {
    USDT: "0x67d2c2a87a17b7267a6dbb1a59575c0e9a1d1c3e",
    USDC: "0x235266D5ca6f19F134421C49834C108b32C2124e", 
    BTC: "0x4803db1ca3A1DA49c3DB991e1c390321c20e1f21",
    ARB: "0x74952812B6a9e4f826b2969C6D189c4425CBc19B",
    SOL: "0xD5Ea6C434582F827303423dA21729bEa4F87D519"
  },
  
  // DIA Oracle Configuration
  oracleConfig: {
    decimals: 8,
    deviationThreshold: 50, // 0.5% in basis points
    refreshFrequency: 120, // 2 minutes
    heartbeat: 86400, // 24 hours
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
// HYPERLEND PROTOCOL PARAMETERS (TESTNET)
// ═══════════════════════════════════════════════════════════════════════════════════

export const PROTOCOL_PARAMS = {
  // Interest Rate Model
  interestRateModel: {
    baseRate: 200, // 2% base rate
    slope1: 1000, // 10% slope 1
    slope2: 30000, // 300% slope 2
    optimalUtilization: 8000 // 80% optimal utilization
  },
  
  // Risk Management
  riskParameters: {
    defaultLTV: 7500, // 75% default LTV
    liquidationThreshold: 8500, // 85% liquidation threshold
    liquidationPenalty: 500, // 5% liquidation penalty
    maxLiquidationRatio: 5000, // 50% max liquidation
    minCollateralRatio: 11000 // 110% minimum collateral ratio
  },
  
  // Price Oracle
  priceOracle: {
    maxPriceDeviation: 1000, // 10% max deviation (production-safe)
    priceValidityPeriod: 3600, // 1 hour validity
    emergencyPriceValidityPeriod: 7200, // 2 hours emergency validity
    minimumUpdateInterval: 60 // 1 minute minimum update
  },
  
  // Protocol Settings
  protocol: {
    protocolFeeRate: 300, // 3% protocol fee
    reserveFactor: 1000, // 10% reserve factor
    maxBorrowingRate: 10000, // 100% max borrowing rate
    gracePeriod: 86400 // 24 hours grace period
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
  // Block confirmations to wait before verification
  confirmations: 2,
  
  // Whether to verify contracts on deployment
  autoVerify: true,
  
  // Gas settings for testnet
  gasSettings: {
    gasLimit: 8000000,
    gasPrice: ethers.utils.parseUnits("1", "gwei")
  }
};

// ═══════════════════════════════════════════════════════════════════════════════════
// SUPPORTED ASSETS CONFIGURATION
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
    ltv: 7500, // 75%
    liquidationThreshold: 8500, // 85%
    liquidationPenalty: 500 // 5%
  },
  {
    symbol: "USDT", 
    name: "Tether USD",
    address: "", // To be set based on deployment
    decimals: 6,
    diaKey: "USDT/USD",
    adapterAddress: "0x67d2c2a87a17b7267a6dbb1a59575c0e9a1d1c3e",
    isNative: false,
    ltv: 8000, // 80%
    liquidationThreshold: 8500, // 85%
    liquidationPenalty: 500 // 5%
  },
  {
    symbol: "USDC",
    name: "USD Coin", 
    address: "", // To be set based on deployment
    decimals: 6,
    diaKey: "USDC/USD",
    adapterAddress: "0x235266D5ca6f19F134421C49834C108b32C2124e",
    isNative: false,
    ltv: 8000, // 80%
    liquidationThreshold: 8500, // 85%
    liquidationPenalty: 500 // 5%
  },
  {
    symbol: "BTC",
    name: "Bitcoin",
    address: "", // To be set based on deployment
    decimals: 8,
    diaKey: "BTC/USD", 
    adapterAddress: "0x4803db1ca3A1DA49c3DB991e1c390321c20e1f21",
    isNative: false,
    ltv: 7000, // 70%
    liquidationThreshold: 8000, // 80%
    liquidationPenalty: 750 // 7.5%
  },
  {
    symbol: "ARB",
    name: "Arbitrum",
    address: "", // To be set based on deployment
    decimals: 18,
    diaKey: "ARB/USD",
    adapterAddress: "0x74952812B6a9e4f826b2969C6D189c4425CBc19B", 
    isNative: false,
    ltv: 6500, // 65%
    liquidationThreshold: 7500, // 75%
    liquidationPenalty: 1000 // 10%
  },
  {
    symbol: "SOL",
    name: "Solana",
    address: "", // To be set based on deployment
    decimals: 9,
    diaKey: "SOL/USD",
    adapterAddress: "0xD5Ea6C434582F827303423dA21729bEa4F87D519",
    isNative: false,
    ltv: 6500, // 65%
    liquidationThreshold: 7500, // 75%
    liquidationPenalty: 1000 // 10%
  }
];

// ═══════════════════════════════════════════════════════════════════════════════════
// DEPLOYMENT HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * @notice Validate deployment configuration
 */
export function validateTestnetConfig(): boolean {
  // Validate DIA Oracle address
  if (!ethers.utils.isAddress(TESTNET_CONFIG.diaOracle)) {
    throw new Error("Invalid DIA Oracle address");
  }
  
  // Validate adapter addresses
  for (const [asset, adapter] of Object.entries(TESTNET_CONFIG.assetAdapters)) {
    if (!ethers.utils.isAddress(adapter)) {
      throw new Error(`Invalid ${asset} adapter address: ${adapter}`);
    }
  }
  
  // Validate protocol parameters
  if (PROTOCOL_PARAMS.riskParameters.defaultLTV >= PROTOCOL_PARAMS.riskParameters.liquidationThreshold) {
    throw new Error("Default LTV must be less than liquidation threshold");
  }
  
  return true;
}

/**
 * @notice Get deployment configuration for testnet environment
 */
export function getTestnetDeploymentConfig() {
  validateTestnetConfig();
  
  return {
    network: TESTNET_CONFIG,
    protocol: PROTOCOL_PARAMS,
    verification: VERIFICATION_CONFIG,
    assets: SUPPORTED_ASSETS
  };
}
