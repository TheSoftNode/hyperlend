import { ethers } from "hardhat";

export async function createUsers(count: number) {
  const signers = await ethers.getSigners();
  
  // If we need more users than available signers, create mock addresses
  if (count <= signers.length) {
    return signers.slice(0, count);
  }
  
  const users = [...signers];
  
  // Create additional mock user addresses
  for (let i = signers.length; i < count; i++) {
    const mockWallet = ethers.Wallet.createRandom();
    users.push(mockWallet);
  }
  
  return users.slice(0, count);
}

export async function setupUserBalances(
  users: any[],
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
  users: any[],
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