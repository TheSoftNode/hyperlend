// packages/contracts/scripts/utils/helpers.ts
import { ethers } from "hardhat";
import { writeFileSync, readFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

// ═══════════════════════════════════════════════════════════════════════════════════
// TYPE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════════════

export interface DeploymentData {
  network: string;
  chainId?: number;
  timestamp: string;
  blockNumber?: number;
  gasPrice?: string;
  contracts: {
    [contractName: string]: string;
  };
  tokens?: {
    testTokens?: { [symbol: string]: string };
    marketTokens?: { [symbol: string]: { hlToken: string; debtToken: string } };
    [key: string]: any;
  };
  configuration?: any;
  initialization?: any;
  deployer: string;
  admin: string;
  lastUpdated?: string;
  transactionHashes?: { [key: string]: string };
}

export interface NetworkConfig {
  chainId: number;
  rpcUrl: string;
  blockExplorer: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  contracts?: {
    multicall?: string;
    [key: string]: string | undefined;
  };
}

export interface ContractVerificationData {
  address: string;
  constructorArguments: any[];
  contract?: string;
  libraries?: { [libraryName: string]: string };
}

// ═══════════════════════════════════════════════════════════════════════════════════
// FILE SYSTEM UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Get deployments directory path
 */
export function getDeploymentsDir(): string {
  const deploymentsDir = join(process.cwd(), "deployments");
  if (!existsSync(deploymentsDir)) {
    mkdirSync(deploymentsDir, { recursive: true });
  }
  return deploymentsDir;
}

/**
 * Get deployment file path for a specific network
 */
export function getDeploymentPath(networkName: string): string {
  return join(getDeploymentsDir(), `${networkName}.json`);
}

/**
 * Save deployment data to file
 */
export async function saveDeploymentData(data: DeploymentData, networkName: string): Promise<void> {
  const filePath = getDeploymentPath(networkName);
  const jsonData = JSON.stringify(data, null, 2);
  
  writeFileSync(filePath, jsonData);
  console.log(`📁 Deployment data saved to: ${filePath}`);
}

/**
 * Load deployment data from file
 */
export async function loadDeploymentData(networkName: string): Promise<DeploymentData | null> {
  const filePath = getDeploymentPath(networkName);
  
  if (!existsSync(filePath)) {
    console.log(`⚠️  No deployment file found for network: ${networkName}`);
    return null;
  }
  
  try {
    const fileContent = readFileSync(filePath, "utf8");
    return JSON.parse(fileContent) as DeploymentData;
  } catch (error) {
    console.error(`❌ Error loading deployment data for ${networkName}:`, error);
    return null;
  }
}

/**
 * Update specific field in deployment data
 */
export async function updateDeploymentData(
  networkName: string,
  updates: Partial<DeploymentData>
): Promise<void> {
  const existingData = await loadDeploymentData(networkName);
  if (!existingData) {
    throw new Error(`No existing deployment data found for ${networkName}`);
  }
  
  const updatedData: DeploymentData = {
    ...existingData,
    ...updates,
    lastUpdated: new Date().toISOString(),
  };
  
  await saveDeploymentData(updatedData, networkName);
}

// ═══════════════════════════════════════════════════════════════════════════════════
// NETWORK UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Get network configuration
 */
export function getNetworkConfig(networkName: string): NetworkConfig {
  const configs: { [key: string]: NetworkConfig } = {
    "somnia-testnet": {
      chainId: 50312,
      rpcUrl: "https://testnet.somnia.network/",
      blockExplorer: "https://testnet-explorer.somnia.network",
      nativeCurrency: {
        name: "Somnia Test Token",
        symbol: "STT",
        decimals: 18,
      },
    },
    "somnia-devnet": {
      chainId: 50311,
      rpcUrl: "https://devnet.somnia.network/",
      blockExplorer: "https://devnet-explorer.somnia.network",
      nativeCurrency: {
        name: "Somnia Dev Token",
        symbol: "SDT", 
        decimals: 18,
      },
    },
    localhost: {
      chainId: 31337,
      rpcUrl: "http://127.0.0.1:8545",
      blockExplorer: "http://localhost:8545",
      nativeCurrency: {
        name: "Ethereum",
        symbol: "ETH",
        decimals: 18,
      },
    },
    hardhat: {
      chainId: 31337,
      rpcUrl: "http://127.0.0.1:8545",
      blockExplorer: "http://localhost:8545",
      nativeCurrency: {
        name: "Ethereum",
        symbol: "ETH",
        decimals: 18,
      },
    },
  };
  
  return configs[networkName] || configs.localhost;
}

/**
 * Check if network is a testnet
 */
export function isTestnet(networkName: string): boolean {
  return networkName.includes("test") || networkName.includes("dev") || 
         networkName === "localhost" || networkName === "hardhat";
}

/**
 * Check if network is live/mainnet
 */
export function isMainnet(networkName: string): boolean {
  return !isTestnet(networkName);
}

// ═══════════════════════════════════════════════════════════════════════════════════
// CONTRACT UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Wait for transaction with retry logic
 */
export async function waitForTransaction(
  txHash: string, 
  confirmations: number = 1,
  timeout: number = 300000 // 5 minutes
): Promise<ethers.TransactionReceipt> {
  const startTime = Date.now();
  
  while (Date.now() - startTime < timeout) {
    try {
      const receipt = await ethers.provider.getTransactionReceipt(txHash);
      if (receipt && receipt.confirmations >= confirmations) {
        return receipt;
      }
      
      // Wait 2 seconds before next check
      await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (error) {
      console.log(`⏳ Waiting for transaction ${txHash}...`);
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
  
  throw new Error(`Transaction ${txHash} timed out after ${timeout}ms`);
}

/**
 * Get contract creation block number
 */
export async function getContractCreationBlock(contractAddress: string): Promise<number> {
  // Binary search to find creation block
  let low = 0;
  let high = await ethers.provider.getBlockNumber();
  
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    const code = await ethers.provider.getCode(contractAddress, mid);
    
    if (code === "0x") {
      low = mid + 1;
    } else {
      // Check if contract exists in previous block
      const prevCode = mid > 0 ? await ethers.provider.getCode(contractAddress, mid - 1) : "0x";
      if (prevCode === "0x") {
        return mid;
      }
      high = mid - 1;
    }
  }
  
  return low;
}

/**
 * Estimate gas with buffer
 */
export async function estimateGasWithBuffer(
  contract: ethers.Contract,
  methodName: string,
  args: any[],
  bufferPercent: number = 20
): Promise<bigint> {
  const estimated = await contract[methodName].estimateGas(...args);
  const buffer = (estimated * BigInt(bufferPercent)) / 100n;
  return estimated + buffer;
}

/**
 * Execute transaction with retry logic
 */
export async function executeWithRetry<T>(
  operation: () => Promise<T>,
  maxRetries: number = 3,
  delay: number = 1000
): Promise<T> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await operation();
    } catch (error) {
      console.log(`⚠️  Attempt ${i + 1} failed:`, error.message);
      
      if (i === maxRetries - 1) {
        throw error;
      }
      
      console.log(`⏳ Retrying in ${delay}ms...`);
      await new Promise(resolve => setTimeout(resolve, delay));
      delay *= 2; // Exponential backoff
    }
  }
  
  throw new Error("Max retries exceeded");
}

// ═══════════════════════════════════════════════════════════════════════════════════
// ADDRESS UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Check if address is a contract
 */
export async function isContract(address: string): Promise<boolean> {
  const code = await ethers.provider.getCode(address);
  return code !== "0x";
}

/**
 * Get contract ABI from deployment data
 */
export async function getContractABI(contractName: string): Promise<any[]> {
  const artifactPath = join(process.cwd(), "artifacts", "contracts", `${contractName}.sol`, `${contractName}.json`);
  
  if (!existsSync(artifactPath)) {
    throw new Error(`Artifact not found for contract: ${contractName}`);
  }
  
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

/**
 * Generate deterministic address for CREATE2
 */
export function calculateCreate2Address(
  deployer: string,
  salt: string,
  bytecode: string
): string {
  const create2Hash = ethers.solidityPackedKeccak256(
    ["bytes1", "address", "bytes32", "bytes32"],
    ["0xff", deployer, salt, ethers.keccak256(bytecode)]
  );
  
  return ethers.getAddress(`0x${create2Hash.slice(-40)}`);
}

// ═══════════════════════════════════════════════════════════════════════════════════
// FORMATTING UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Format ETH amount for display
 */
export function formatEther(amount: bigint | string, decimals: number = 4): string {
  const formatted = ethers.formatEther(amount);
  const num = parseFloat(formatted);
  return num.toFixed(decimals);
}

/**
 * Format token amount for display
 */
export function formatTokenAmount(
  amount: bigint | string,
  tokenDecimals: number,
  displayDecimals: number = 4
): string {
  const formatted = ethers.formatUnits(amount, tokenDecimals);
  const num = parseFloat(formatted);
  return num.toFixed(displayDecimals);
}

/**
 * Format USD amount
 */
export function formatUSD(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

/**
 * Format percentage
 */
export function formatPercent(value: number, decimals: number = 2): string {
  return `${(value * 100).toFixed(decimals)}%`;
}

/**
 * Format large numbers with K/M/B suffixes
 */
export function formatLargeNumber(num: number): string {
  const units = ['', 'K', 'M', 'B', 'T'];
  let unitIndex = 0;
  
  while (num >= 1000 && unitIndex < units.length - 1) {
    num /= 1000;
    unitIndex++;
  }
  
  return `${num.toFixed(unitIndex > 0 ? 1 : 0)}${units[unitIndex]}`;
}

// ═══════════════════════════════════════════════════════════════════════════════════
// TIME UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Convert seconds to human readable format
 */
export function formatDuration(seconds: number): string {
  const units = [
    { label: 'day', seconds: 86400 },
    { label: 'hour', seconds: 3600 },
    { label: 'minute', seconds: 60 },
    { label: 'second', seconds: 1 },
  ];
  
  for (const unit of units) {
    const count = Math.floor(seconds / unit.seconds);
    if (count > 0) {
      return `${count} ${unit.label}${count !== 1 ? 's' : ''}`;
    }
  }
  
  return '0 seconds';
}

/**
 * Get current timestamp
 */
export function getCurrentTimestamp(): number {
  return Math.floor(Date.now() / 1000);
}

/**
 * Add time to current timestamp
 */
export function addTimeToTimestamp(baseTimestamp: number, additionalSeconds: number): number {
  return baseTimestamp + additionalSeconds;
}

// ═══════════════════════════════════════════════════════════════════════════════════
// VALIDATION UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Validate Ethereum address
 */
export function isValidAddress(address: string): boolean {
  try {
    ethers.getAddress(address);
    return true;
  } catch {
    return false;
  }
}

/**
 * Validate private key
 */
export function isValidPrivateKey(privateKey: string): boolean {
  try {
    new ethers.Wallet(privateKey);
    return true;
  } catch {
    return false;
  }
}

/**
 * Validate amount string
 */
export function isValidAmount(amount: string): boolean {
  try {
    const parsed = ethers.parseEther(amount);
    return parsed >= 0n;
  } catch {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════
// MATH UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Calculate percentage
 */
export function calculatePercentage(part: bigint, total: bigint): number {
  if (total === 0n) return 0;
  return Number((part * 10000n) / total) / 100; // 2 decimal places
}

/**
 * Calculate APY from rate per second
 */
export function calculateAPY(ratePerSecond: bigint): number {
  const secondsPerYear = 365 * 24 * 60 * 60;
  const annualRate = Number(ratePerSecond) * secondsPerYear;
  return annualRate / 1e18; // Assuming 18 decimals
}

/**
 * Calculate compound interest
 */
export function calculateCompoundInterest(
  principal: number,
  rate: number,
  periods: number
): number {
  return principal * Math.pow(1 + rate, periods);
}

// ═══════════════════════════════════════════════════════════════════════════════════
// LOGGING UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Log with timestamp
 */
export function logWithTimestamp(message: string, level: 'info' | 'warn' | 'error' = 'info'): void {
  const timestamp = new Date().toISOString();
  const prefix = level === 'error' ? '❌' : level === 'warn' ? '⚠️' : 'ℹ️';
  console.log(`${prefix} [${timestamp}] ${message}`);
}

/**
 * Log transaction details
 */
export function logTransaction(
  operation: string,
  txHash: string,
  gasUsed?: bigint,
  gasPrice?: bigint
): void {
  console.log(`📝 ${operation}`);
  console.log(`   Transaction: ${txHash}`);
  if (gasUsed) console.log(`   Gas Used: ${gasUsed.toString()}`);
  if (gasPrice) console.log(`   Gas Price: ${formatEther(gasPrice)} ETH`);
}

/**
 * Create progress bar
 */
export function createProgressBar(current: number, total: number, width: number = 40): string {
  const progress = Math.min(current / total, 1);
  const filled = Math.floor(progress * width);
  const empty = width - filled;
  
  const bar = '█'.repeat(filled) + '░'.repeat(empty);
  const percentage = Math.floor(progress * 100);
  
  return `[${bar}] ${percentage}% (${current}/${total})`;
}

// ═══════════════════════════════════════════════════════════════════════════════════
// ERROR HANDLING UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * Parse revert reason from error
 */
export function parseRevertReason(error: any): string {
  if (error.reason) return error.reason;
  if (error.message) {
    const match = error.message.match(/revert (.+)/);
    if (match) return match[1];
  }
  return "Unknown error";
}

/**
 * Check if error is due to insufficient gas
 */
export function isInsufficientGasError(error: any): boolean {
  const message = error.message?.toLowerCase() || '';
  return message.includes('out of gas') || 
         message.includes('insufficient gas') ||
         message.includes('gas limit');
}

/**
 * Check if error is due to nonce issues
 */
export function isNonceError(error: any): boolean {
  const message = error.message?.toLowerCase() || '';
  return message.includes('nonce') || message.includes('replacement');
}

// ═══════════════════════════════════════════════════════════════════════════════════
// EXPORT ALL UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════════

export const helpers = {
  // File system
  saveDeploymentData,
  loadDeploymentData,
  updateDeploymentData,
  getDeploymentsDir,
  getDeploymentPath,
  
  // Network
  getNetworkConfig,
  isTestnet,
  isMainnet,
  
  // Contract
  waitForTransaction,
  getContractCreationBlock,
  estimateGasWithBuffer,
  executeWithRetry,
  isContract,
  getContractABI,
  calculateCreate2Address,
  
  // Formatting
  formatEther,
  formatTokenAmount,
  formatUSD,
  formatPercent,
  formatLargeNumber,
  formatDuration,
  
  // Time
  getCurrentTimestamp,
  addTimeToTimestamp,
  
  // Validation
  isValidAddress,
  isValidPrivateKey,
  isValidAmount,
  
  // Math
  calculatePercentage,
  calculateAPY,
  calculateCompoundInterest,
  
  // Logging
  logWithTimestamp,
  logTransaction,
  createProgressBar,
  
  // Error handling
  parseRevertReason,
  isInsufficientGasError,
  isNonceError,
};

export default helpers;