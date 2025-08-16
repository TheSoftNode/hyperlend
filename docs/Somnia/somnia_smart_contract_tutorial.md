# How to Deploy Your First Smart Contract to Somnia Network

## Overview
This tutorial teaches developers how to deploy their first smart contract to the Somnia Network using Remix IDE. The guide focuses on deploying a "Greeter" smart contract that can update its state to say "Hello" + a name.

## Prerequisites
- Basic Solidity programming knowledge (this is NOT an intro to Solidity)
- MetaMask wallet installed and configured
- Somnia Network added to MetaMask
- STT (Somnia Test Tokens) in your wallet from the faucet
- Active connection to Somnia Testnet

## What is Remix IDE?
Remix is an integrated development environment (IDE) for smart contract development that includes:
- Compilation
- Deployment
- Testing
- Debugging capabilities

It simplifies the process of creating, debugging, and deploying smart contracts to the Somnia Network.

## Step-by-Step Deployment Process

### Step 1: Setup
- Ensure you're logged into MetaMask
- Confirm connection to Somnia Testnet
- Verify you have STT tokens in your wallet

### Step 2: Create Smart Contract
- Go to Remix IDE
- Create a new file
- Paste the Greeter smart contract code (example contract provided)

### Step 3: Compile Contract
- Click "Solidity Compiler" in the left tab
- Click "Compile Greeter.sol" button
- This converts Solidity code into machine-readable bytecode
- Creates the Application Binary Interface (ABI)

### Step 4: Deploy Contract
- Click "Deploy and run transactions" in the left tab
- In Environment dropdown, select "Injected Provider - MetaMask"
- Select your MetaMask account with STT tokens
- In the "DEPLOY" field, enter a value for the "_INITIALNAME" variable
- Click deploy

### Step 5: Approve and Confirm
- Approve the contract deployment in MetaMask when prompted
- Check terminal for deployment response and contract address
- Interact with the deployed contract via Remix IDE
- Test by sending transactions to change the name

## Key Features of the Greeter Contract
- Simple state management
- Ability to update the greeting message
- Demonstrates basic READ and WRITE operations
- Perfect example for first-time Somnia developers

## Success Outcome
Upon completion, you will have:
- Successfully deployed a smart contract to Somnia Network
- Obtained a deployed contract address
- Ability to interact with the contract through Remix IDE
- Understanding of the basic deployment workflow on Somnia

## Important Notes
- This tutorial assumes familiarity with Solidity programming
- MetaMask setup and Somnia network configuration must be completed beforehand
- STT tokens are required for gas fees during deployment
- The process leverages Somnia's high-performance capabilities while maintaining EVM compatibility