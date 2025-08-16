import { run } from "hardhat";

/**
 * Verify a contract on the block explorer
 * @param address Contract address
 * @param constructorArguments Constructor arguments
 */
export async function verifyContract(
  address: string,
  constructorArguments: any[] = []
): Promise<void> {
  try {
    console.log(`🔍 Verifying contract at ${address}...`);
    
    await run("verify:verify", {
      address,
      constructorArguments,
    });
    
    console.log(`✅ Contract verified: ${address}`);
  } catch (error: any) {
    if (error.message.toLowerCase().includes("already verified")) {
      console.log(`ℹ️ Contract already verified: ${address}`);
    } else {
      console.error(`❌ Verification failed for ${address}:`, error.message);
      throw error;
    }
  }
}

/**
 * Batch verify multiple contracts
 * @param contracts Array of {address, args} objects
 */
export async function batchVerifyContracts(
  contracts: Array<{ address: string; args: any[] }>
): Promise<void> {
  console.log(`🔍 Batch verifying ${contracts.length} contracts...`);
  
  for (const contract of contracts) {
    await verifyContract(contract.address, contract.args);
  }
  
  console.log("✅ Batch verification complete");
}
