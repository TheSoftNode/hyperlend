# Deploy and Verify A Smart Contract on Somnia using Hardhat

## Overview
This comprehensive guide teaches developers how to deploy and verify smart contracts on the Somnia Network using Hardhat development environment. The tutorial uses a "Buy Me Coffee" smart contract as an example to demonstrate the complete workflow from initialization to verification.

## What is Hardhat?
Hardhat is a development environment for EVM-compatible blockchains like Somnia. It provides:
- Smart contract compilation and debugging
- Local blockchain simulation
- Deployment automation
- Testing framework
- Plugin ecosystem
- Contract verification tools

## Prerequisites
- Basic Solidity programming knowledge
- MetaMask wallet installed and configured with Somnia Network
- STT (Somnia Test Tokens) in your wallet
- Hardhat installed on your local machine
- Node.js and npm installed

## Step 1: Initialize Hardhat Project

Create a new Hardhat project:

```bash
npx hardhat init
```

When prompted, select **"Create a TypeScript Project (with Viem)"**.

This command will:
- Install required dependencies
- Create project structure with `contracts`, `scripts`, `test`, and `ignition` directories
- Set up configuration files

## Step 2: Create the Smart Contract

### Delete Default Files
1. Navigate to the `contracts` directory
2. Delete the default `Lock.sol` file

### Create BuyMeCoffee Contract
Create a new file `BuyMeCoffee.sol` and add the following code:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract BuyMeCoffee {
    event CoffeeBought(
        address indexed supporter,
        uint256 amount,
        string message,
        uint256 timestamp
    );

    address public owner;

    struct Contribution {
        address supporter;
        uint256 amount;
        string message;
        uint256 timestamp;
    }

    Contribution[] public contributions;

    constructor() {
        owner = msg.sender;
    }

    function buyCoffee(string memory message) external payable {
        require(msg.value > 0, "Amount must be greater than zero.");
        
        contributions.push(
            Contribution(msg.sender, msg.value, message, block.timestamp)
        );
        
        emit CoffeeBought(msg.sender, msg.value, message, block.timestamp);
    }

    function withdraw() external {
        require(msg.sender == owner, "Only the owner can withdraw funds.");
        payable(owner).transfer(address(this).balance);
    }

    function getContributions() external view returns (Contribution[] memory) {
        return contributions;
    }

    function setOwner(address newOwner) external {
        require(msg.sender == owner, "Only the owner can set a new owner.");
        owner = newOwner;
    }
}
```

### Contract Explanation

#### State Variables
- `owner`: Address that deployed the contract and can withdraw funds
- `contributions`: Array storing all coffee purchases

#### Struct
- `Contribution`: Stores supporter address, amount, message, and timestamp

#### Functions
- **`buyCoffee(string memory message)`**: Accepts payment and records contribution
- **`withdraw()`**: Allows owner to withdraw collected funds
- **`getContributions()`**: Returns all contributions
- **`setOwner(address newOwner)`**: Transfers ownership

#### Events
- **`CoffeeBought`**: Emitted when someone buys coffee, logging supporter, amount, message, and timestamp

## Step 3: Compile the Smart Contract

### Configure Compiler
Ensure your `hardhat.config.js` has the correct Solidity version:

```javascript
module.exports = {
  solidity: "0.8.28",
  // ... other configurations
};
```

### Compile Command
```bash
npx hardhat compile
```

Expected output:
```
Compiling...
Compiled 1 contract successfully
```

This creates:
- Machine-readable bytecode
- Contract ABI (Application Binary Interface)
- Artifacts in the `artifacts` directory

## Step 4: Create Deployment Script

### Setup Ignition Module
1. Navigate to `ignition/modules` directory
2. Delete the default `Lock.ts` file
3. Create `deploy.ts` file:

```typescript
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const BuyMeCoffee = buildModule("BuyMeCoffee", (m) => {
  const contract = m.contract("BuyMeCoffee");
  return { contract };
});

module.exports = BuyMeCoffee;
```

### What are Ignition Modules?
Ignition Modules are abstractions in Hardhat that describe deployments. They're JavaScript/TypeScript functions that define how contracts should be deployed, making deployments repeatable and version-controlled.

## Step 5: Configure Network Settings

### Update hardhat.config.js
Add Somnia Network configuration:

```javascript
module.exports = {
  solidity: "0.8.28",
  networks: {
    somnia: {
      url: "https://dream-rpc.somnia.network",
      accounts: ["0xYOUR_PRIVATE_KEY"], // Replace with your private key
    },
  },
};
```

### Security Warning
- **Never commit private keys to version control**
- Use environment variables or `.env` files
- Ensure the account has sufficient STT tokens for gas fees

### Getting Your Private Key
1. Open MetaMask
2. Click on account menu
3. Go to Account Details
4. Export Private Key (enter password)
5. Copy the private key

## Step 6: Deploy to Somnia Network

Run the deployment command:

```bash
npx hardhat ignition deploy ./ignition/modules/deploy.ts --network somnia
```

### Deployment Process
1. Hardhat will prompt for confirmation to deploy to Somnia Network
2. Press 'y' to confirm
3. Transaction will be broadcast to the network
4. Contract address will be returned upon successful deployment

## Step 7: Verify Your Smart Contract

Contract verification makes your source code publicly viewable and verifiable on the Somnia Explorer.

### Install Verification Plugin
The Hardhat Verify plugin should be included in the toolbox, but ensure it's available:

```bash
npm install --save-dev @nomicfoundation/hardhat-verify
```

### Update Configuration for Verification

Create or update `hardhat.config.ts`:

```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    somnia: {
      url: "https://dream-rpc.somnia.network",
      accounts: ["YOUR_PRIVATE_KEY"],
    },
  },
  sourcify: {
    enabled: false,
  },
  etherscan: {
    apiKey: {
      somnia: "ETHERSCAN_API_KEY", // Can be any string for Somnia
    },
    customChains: [
      {
        network: "somnia",
        chainId: 50312,
        urls: {
          apiURL: "https://shannon-explorer.somnia.network/api",
          browserURL: "https://shannon-explorer.somnia.network",
        },
      },
    ],
  },
};

export default config;
```

### Run Verification Command

```bash
npx hardhat verify --network somnia DEPLOYED_CONTRACT_ADDRESS "ConstructorArgument1" ...
```

For the BuyMeCoffee contract (no constructor arguments):
```bash
npx hardhat verify --network somnia 0xYourContractAddress
```

### Verification Results
After successful verification:
1. Visit [Somnia Explorer](https://shannon-explorer.somnia.network)
2. Search for your contract address
3. Source code will appear under the "Contract" tab
4. Contract will show as "Verified" with a green checkmark

## Benefits of Contract Verification

### Transparency
- Source code becomes publicly accessible
- Users can review for bugs and malicious code
- Builds trust in the contract

### Interaction
- Users can interact directly with verified contracts through the explorer
- Read and write functions become available in the UI
- ABI is automatically available for integration

### Development
- Easier debugging and monitoring
- Better integration with tools and services
- Enhanced security through public scrutiny

## Network Details for Reference

| Parameter | Value |
|-----------|--------|
| Network Name | Somnia Testnet |
| RPC URL | https://dream-rpc.somnia.network |
| Chain ID | 50312 |
| Currency Symbol | STT |
| Explorer | https://shannon-explorer.somnia.network |

## Troubleshooting Common Issues

### Compilation Errors
- Ensure Solidity version matches in config file
- Check for syntax errors in contract code
- Verify all imports are correct

### Deployment Failures
- Confirm sufficient STT balance for gas fees
- Verify private key is correct and properly formatted
- Check network connectivity and RPC endpoint

### Verification Issues
- Ensure contract address is correct
- Match constructor arguments exactly
- Verify compiler settings match deployment
- Check API endpoints are accessible

## Best Practices

### Security
1. **Never hardcode private keys** - use environment variables
2. **Use .env files** for sensitive data
3. **Test thoroughly** before mainnet deployment
4. **Audit contracts** for security vulnerabilities

### Development
1. **Version control** - commit configuration files (without secrets)
2. **Document deployments** - keep track of contract addresses
3. **Test locally first** - use Hardhat's local network
4. **Use TypeScript** for better type safety

### Gas Optimization
1. **Optimize contract code** for lower gas usage
2. **Test gas estimates** before deployment
3. **Monitor network congestion** for optimal deployment timing

## Advanced Features

### Multiple Network Deployment
Configure multiple networks in hardhat.config.js for different environments:

```javascript
networks: {
  somnia: {
    url: "https://dream-rpc.somnia.network",
    accounts: [process.env.PRIVATE_KEY]
  },
  localhost: {
    url: "http://127.0.0.1:8545"
  }
}
```

### Environment Variables
Create a `.env` file:
```
PRIVATE_KEY=your_private_key_here
SOMNIA_RPC_URL=https://dream-rpc.somnia.network
```

Load in config:
```javascript
require('dotenv').config();

module.exports = {
  networks: {
    somnia: {
      url: process.env.SOMNIA_RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  }
};
```

### Testing
Write tests in the `test` directory:

```typescript
import { expect } from "chai";
import { ethers } from "hardhat";

describe("BuyMeCoffee", function () {
  it("Should accept coffee purchases", async function () {
    const BuyMeCoffee = await ethers.getContractFactory("BuyMeCoffee");
    const buyMeCoffee = await BuyMeCoffee.deploy();
    
    await buyMeCoffee.buyCoffee("Great work!", { value: ethers.parseEther("0.1") });
    
    const contributions = await buyMeCoffee.getContributions();
    expect(contributions.length).to.equal(1);
  });
});
```

Run tests:
```bash
npx hardhat test
```

## Conclusion

You've successfully learned how to:
1. **Initialize** a Hardhat project for Somnia development
2. **Create** and **compile** smart contracts
3. **Configure** Somnia network settings
4. **Deploy** contracts using Ignition modules
5. **Verify** contracts on Somnia Explorer

This workflow enables you to build, deploy, and verify sophisticated decentralized applications on Somnia's high-performance blockchain while maintaining full EVM compatibility and leveraging Hardhat's powerful development tools.