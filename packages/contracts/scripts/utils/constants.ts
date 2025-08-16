// Somnia-optimized deployment constants for HyperLend
export const SOMNIA_NETWORKS = {
  testnet: {
    chainId: 50312,
    name: "Somnia Testnet",
    rpcUrl: "https://rpc.somnia.network",
    explorerUrl: "https://somnium-explorer.io",
    nativeToken: "STT",
    gasLimit: 8000000,
    gasPrice: 100000000, // 0.1 gwei
    confirmations: 1,
  },
  devnet: {
    chainId: 50311,
    name: "Somnia Devnet", 
    rpcUrl: "https://rpc-devnet.somnia.network",
    explorerUrl: "https://somnium-explorer.io",
    nativeToken: "STT",
    gasLimit: 8000000,
    gasPrice: 100000000, // 0.1 gwei
    confirmations: 1,
  }
};

// Protocol parameters optimized for Somnia's features
export const PROTOCOL_CONFIG = {
  // Interest rate model (basis points)
  interestRate: {
    baseRate: 200,        // 2% base APR
    slope1: 800,          // 8% slope until optimal
    slope2: 25000,        // 250% jump rate after optimal
    optimalUtilization: 8000, // 80% optimal utilization
  },
  
  // Risk management (basis points)
  risk: {
    defaultLTV: 7000,            // 70% loan-to-value
    liquidationThreshold: 8000,   // 80% liquidation threshold
    liquidationPenalty: 500,      // 5% liquidation bonus
    protocolFeeRate: 300,         // 3% protocol fee
  },
  
  // Somnia-specific optimizations
  somnia: {
    liquidationDelay: 30,         // 30 seconds (sub-second finality)
    priceUpdateInterval: 15,      // 15 seconds (high TPS)
    maxSlippage: 300,            // 3% max slippage
    enableAccountAbstraction: true,
    enableGaslessTransactions: true,
  },
  
  // Token configurations
  tokens: {
    initialSupply: "1000000",     // 1M tokens (string for parseEther)
    hlTokenName: "HyperLend Token",
    hlTokenSymbol: "HLT",
    debtTokenName: "HyperLend Debt Token", 
    debtTokenSymbol: "HDT",
    rewardTokenName: "HyperLend Reward Token",
    rewardTokenSymbol: "HRT",
  }
};

// Oracle addresses for Somnia (update with actual addresses when available)
export const ORACLE_ADDRESSES = {
  // DIA Oracle integration for Somnia
  DIA_ORACLE: "0x1111111111111111111111111111111111111111", // Placeholder
  PROTOFIRE_ORACLE: "0x2222222222222222222222222222222222222222", // Placeholder
  
  // Price feeds
  STT_USD_FEED: "0x3333333333333333333333333333333333333333", // Native STT price feed
  USDC_USD_FEED: "0x4444444444444444444444444444444444444444", // USDC price feed
  WETH_USD_FEED: "0x5555555555555555555555555555555555555555", // WETH price feed
};

// Contract deployment order (important for dependencies)
export const DEPLOYMENT_ORDER = [
  "Math",               // Library first
  "InterestRateModel",  // Core contracts
  "PriceOracle",
  "RiskManager", 
  "LiquidationEngine",
  "HLToken",           // Token contracts
  "DebtToken",
  "RewardToken",
  "SomniaWrapper",     // Somnia-specific
  "HyperLendPool",     // Main contract last
];
