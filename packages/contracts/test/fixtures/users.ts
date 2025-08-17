import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export async function createUsers(count: number): Promise<SignerWithAddress[]> {
  const signers = await ethers.getSigners();
  
  // If we need more users than available signers, return available signers
  // In Hardhat, we typically have 20 signers available by default
  if (count <= signers.length) {
    return signers.slice(0, count);
  }
  
  // For testing purposes, we'll use the available signers and repeat if needed
  const users: SignerWithAddress[] = [];
  for (let i = 0; i < count; i++) {
    const signerIndex = i % signers.length;
    users.push(signers[signerIndex]);
  }
  
  return users.slice(0, count);
}

export async function setupUserBalances(
  users: SignerWithAddress[],
  tokens: any[],
  amounts: string[]
) {
  for (const user of users) {
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i] && amounts[i]) {
        await tokens[i].transfer(user.address, ethers.utils.parseEther(amounts[i]));
      }
    }
  }
}

export async function approveTokens(
  users: SignerWithAddress[],
  tokens: any[],
  spender: string
) {
  for (const user of users) {
    for (const token of tokens) {
      if (token) {
        await token.connect(user).approve(spender, ethers.constants.MaxUint256);
      }
    }
  }
}

export async function fundUsersWithETH(
  users: SignerWithAddress[],
  amount: string = "100"
) {
  const [deployer] = await ethers.getSigners();
  
  for (const user of users) {
    // Skip if user is the deployer (already has ETH)
    if (user.address !== deployer.address) {
      await deployer.sendTransaction({
        to: user.address,
        value: ethers.utils.parseEther(amount)
      });
    }
  }
}

export async function getUserBalances(
  users: SignerWithAddress[],
  tokens: any[]
) {
  const balances: any = {};
  
  for (const user of users) {
    balances[user.address] = {
      eth: await user.getBalance(),
      tokens: {}
    };
    
    for (const token of tokens) {
      if (token) {
        balances[user.address].tokens[await token.symbol()] = await token.balanceOf(user.address);
      }
    }
  }
  
  return balances;
}