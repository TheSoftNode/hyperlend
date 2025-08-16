import * as fs from "fs";
import * as path from "path";

export interface DeploymentInfo {
  network: string;
  deployer: string;
  timestamp: string;
  contracts: Record<string, string>;
  configuration: Record<string, any>;
  transactions?: Record<string, any>;
}

/**
 * Save deployment information to a JSON file
 * @param deploymentInfo Deployment details
 */
export async function saveDeployment(deploymentInfo: DeploymentInfo): Promise<void> {
  const deploymentsDir = path.join(__dirname, "../../deployments");
  
  // Create deployments directory if it doesn't exist
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const filename = `${deploymentInfo.network}-${Date.now()}.json`;
  const filepath = path.join(deploymentsDir, filename);
  
  // Also save as latest
  const latestFilepath = path.join(deploymentsDir, `${deploymentInfo.network}-latest.json`);
  
  const deploymentData = {
    ...deploymentInfo,
    savedAt: new Date().toISOString(),
  };
  
  try {
    // Save timestamped version
    fs.writeFileSync(filepath, JSON.stringify(deploymentData, null, 2));
    
    // Save as latest
    fs.writeFileSync(latestFilepath, JSON.stringify(deploymentData, null, 2));
    
    console.log(`💾 Deployment info saved to: ${filename}`);
    console.log(`💾 Latest deployment saved to: ${deploymentInfo.network}-latest.json`);
  } catch (error) {
    console.error("❌ Failed to save deployment info:", error);
    throw error;
  }
}

/**
 * Load the latest deployment for a network
 * @param network Network name
 * @returns Deployment info or null if not found
 */
export function loadLatestDeployment(network: string): DeploymentInfo | null {
  const deploymentsDir = path.join(__dirname, "../../deployments");
  const filepath = path.join(deploymentsDir, `${network}-latest.json`);
  
  try {
    if (fs.existsSync(filepath)) {
      const data = fs.readFileSync(filepath, "utf8");
      return JSON.parse(data);
    }
  } catch (error) {
    console.error(`❌ Failed to load deployment for ${network}:`, error);
  }
  
  return null;
}

/**
 * List all deployments for a network
 * @param network Network name
 * @returns Array of deployment files
 */
export function listDeployments(network: string): string[] {
  const deploymentsDir = path.join(__dirname, "../../deployments");
  
  try {
    if (fs.existsSync(deploymentsDir)) {
      return fs
        .readdirSync(deploymentsDir)
        .filter(file => file.startsWith(`${network}-`) && file.endsWith(".json"))
        .filter(file => !file.includes("latest"));
    }
  } catch (error) {
    console.error(`❌ Failed to list deployments for ${network}:`, error);
  }
  
  return [];
}
