# How to Connect to Somnia Network via Viem Library

## Overview
This comprehensive guide teaches developers how to use the Viem library to connect frontend applications to smart contracts deployed on the Somnia Network. You'll learn to perform both READ and WRITE operations, handle transactions, and manage wallet connections.

## What is Viem?
[Viem](https://viem.sh) is a TypeScript interface for Ethereum that provides low-level stateless primitives for interacting with Ethereum-compatible networks. It's designed to be:
- **Type-safe**: Built with TypeScript for better developer experience
- **Modular**: Composable APIs for different use cases
- **Lightweight**: Tree-shakeable with minimal dependencies
- **Fast**: Optimized for performance
- **Modern**: Uses modern JavaScript features

## Understanding Smart Contract Interaction

### The Compilation Process
When smart contracts are compiled, they produce:
1. **Bytecode**: Machine-readable code deployed to the blockchain
2. **ABI (Application Binary Interface)**: JSON interface defining contract methods

### ABI as an Interface
Think of ABI as the bridge between your frontend and smart contract, similar to how APIs connect frontend and backend in Web2 applications.

## Example Smart Contract

Let's start with a simple Greeter contract:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract Greeter {
    string public name;
    address public owner;

    event NameChanged(string oldName, string newName);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    constructor(string memory _initialName) {
        name = _initialName;
        owner = msg.sender;
    }

    function changeName(string memory _newName) external onlyOwner {
        string memory oldName = name;
        name = _newName;
        emit NameChanged(oldName, _newName);
    }

    function greet() external view returns (string memory) {
        return string(abi.encodePacked("Hello, ", name, "!"));
    }
}
```

### Contract Analysis
- **State Variables**: `name` (string), `owner` (address)
- **View Function**: `greet()` - reads data without changing state
- **Write Function**: `changeName()` - modifies contract state
- **Access Control**: `onlyOwner` modifier restricts certain functions
- **Events**: `NameChanged` - logs state changes

## Understanding the ABI

When compiled, the Greeter contract produces an ABI like this:

```json
[
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "_initialName",
        "type": "string"
      }
    ],
    "stateMutability": "nonpayable",
    "type": "constructor"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": false,
        "internalType": "string",
        "name": "oldName",
        "type": "string"
      },
      {
        "indexed": false,
        "internalType": "string",
        "name": "newName",
        "type": "string"
      }
    ],
    "name": "NameChanged",
    "type": "event"
  },
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "_newName",
        "type": "string"
      }
    ],
    "name": "changeName",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "greet",
    "outputs": [
      {
        "internalType": "string",
        "name": "",
        "type": "string"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "name",
    "outputs": [
      {
        "internalType": "string",
        "name": "",
        "type": "string"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "owner",
    "outputs": [
      {
        "internalType": "address",
        "name": "",
        "type": "address"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
]
```

### ABI Structure Analysis
Each ABI entry contains:
- **inputs**: Function parameters and their types
- **outputs**: Return values and their types
- **stateMutability**: How the function interacts with blockchain state
  - `view`: Reads state, no modifications
  - `nonpayable`: Modifies state, no Ether required
  - `payable`: Can receive Ether
- **type**: Entry type (function, constructor, event, etc.)

## Project Setup

### 1. Initialize Project
```bash
mkdir viem-example && cd viem-example
npm init -y
```

### 2. Install Dependencies
```bash
npm install viem
npm install dotenv  # For environment variables
```

### 3. Project Structure
```
viem-example/
├── package.json
├── .env
├── index.js
├── abi.js
└── config.js
```

## Implementation Guide

### 1. Create ABI File (`abi.js`)
```javascript
export const ABI = [
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "_initialName",
        "type": "string"
      }
    ],
    "stateMutability": "nonpayable",
    "type": "constructor"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": false,
        "internalType": "string",
        "name": "oldName",
        "type": "string"
      },
      {
        "indexed": false,
        "internalType": "string",
        "name": "newName",
        "type": "string"
      }
    ],
    "name": "NameChanged",
    "type": "event"
  },
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "_newName",
        "type": "string"
      }
    ],
    "name": "changeName",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "greet",
    "outputs": [
      {
        "internalType": "string",
        "name": "",
        "type": "string"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "name",
    "outputs": [
      {
        "internalType": "string",
        "name": "",
        "type": "string"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "owner",
    "outputs": [
      {
        "internalType": "address",
        "name": "",
        "type": "address"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];
```

### 2. Environment Configuration (`.env`)
```bash
PRIVATE_KEY=0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
CONTRACT_ADDRESS=0x2e7f682863a9dcb32dd298ccf8724603728d0edd
```

### 3. Main Implementation (`index.js`)

```javascript
import { createPublicClient, createWalletClient, http } from "viem";
import { somniaTestnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { ABI } from "./abi.js";
import dotenv from "dotenv";

dotenv.config();

// Configuration
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

// Create Public Client for READ operations
const publicClient = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});

// Create Wallet Client for WRITE operations
const walletClient = createWalletClient({
  account: privateKeyToAccount(PRIVATE_KEY),
  chain: somniaTestnet,
  transport: http(),
});

// READ Operations Function
const performReadOperations = async () => {
  try {
    console.log("=== READ OPERATIONS ===");
    
    // Read the greeting
    const greeting = await publicClient.readContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: "greet",
    });
    console.log("Current greeting:", greeting);

    // Read the name
    const name = await publicClient.readContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: "name",
    });
    console.log("Current name:", name);

    // Read the owner
    const owner = await publicClient.readContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: "owner",
    });
    console.log("Contract owner:", owner);

    return { greeting, name, owner };
  } catch (error) {
    console.error("Error in READ operations:", error);
  }
};

// WRITE Operations Function
const performWriteOperations = async (newName) => {
  try {
    console.log("\n=== WRITE OPERATIONS ===");
    console.log(`Changing name to: ${newName}`);

    // Write to the "changeName" function
    const txHash = await walletClient.writeContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: "changeName",
      args: [newName],
    });

    console.log("Transaction sent. Hash:", txHash);
    console.log("Waiting for transaction confirmation...");

    // Wait for transaction confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash: txHash 
    });

    console.log("Transaction confirmed!");
    console.log("Block number:", receipt.blockNumber);
    console.log("Gas used:", receipt.gasUsed);

    // Read the updated greeting
    const updatedGreeting = await publicClient.readContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: "greet",
    });

    console.log("Updated greeting:", updatedGreeting);
    return { txHash, receipt, updatedGreeting };
  } catch (error) {
    console.error("Error in WRITE operations:", error);
  }
};

// Event Listening Function
const listenToEvents = async () => {
  try {
    console.log("\n=== LISTENING TO EVENTS ===");
    
    // Get past NameChanged events
    const logs = await publicClient.getLogs({
      address: CONTRACT_ADDRESS,
      event: {
        type: 'event',
        name: 'NameChanged',
        inputs: [
          { name: 'oldName', type: 'string', indexed: false },
          { name: 'newName', type: 'string', indexed: false }
        ]
      },
      fromBlock: "earliest",
      toBlock: "latest"
    });

    console.log("Past NameChanged events:", logs.length);
    logs.forEach((log, index) => {
      console.log(`Event ${index + 1}:`, log.args);
    });
  } catch (error) {
    console.error("Error listening to events:", error);
  }
};

// Main execution function
const main = async () => {
  console.log("🚀 Starting Viem interaction with Somnia Network");
  
  // Perform READ operations
  await performReadOperations();
  
  // Perform WRITE operations
  await performWriteOperations("Alice");
  
  // Listen to events
  await listenToEvents();
  
  // Perform READ operations again to see changes
  console.log("\n=== FINAL STATE ===");
  await performReadOperations();
};

// Execute main function
main().catch(console.error);
```

### 4. Alternative Modular Approach

Create separate modules for better organization:

#### `config.js`
```javascript
import dotenv from "dotenv";
dotenv.config();

export const config = {
  contractAddress: process.env.CONTRACT_ADDRESS,
  privateKey: process.env.PRIVATE_KEY,
  rpcUrl: "https://dream-rpc.somnia.network",
};
```

#### `clients.js`
```javascript
import { createPublicClient, createWalletClient, http } from "viem";
import { somniaTestnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { config } from "./config.js";

export const publicClient = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});

export const walletClient = createWalletClient({
  account: privateKeyToAccount(config.privateKey),
  chain: somniaTestnet,
  transport: http(),
});
```

#### `contractInteractions.js`
```javascript
import { publicClient, walletClient } from "./clients.js";
import { ABI } from "./abi.js";
import { config } from "./config.js";

export class GreeterContract {
  constructor() {
    this.address = config.contractAddress;
    this.abi = ABI;
  }

  async greet() {
    return await publicClient.readContract({
      address: this.address,
      abi: this.abi,
      functionName: "greet",
    });
  }

  async getName() {
    return await publicClient.readContract({
      address: this.address,
      abi: this.abi,
      functionName: "name",
    });
  }

  async getOwner() {
    return await publicClient.readContract({
      address: this.address,
      abi: this.abi,
      functionName: "owner",
    });
  }

  async changeName(newName) {
    const txHash = await walletClient.writeContract({
      address: this.address,
      abi: this.abi,
      functionName: "changeName",
      args: [newName],
    });

    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash: txHash 
    });

    return { txHash, receipt };
  }

  async getNameChangedEvents() {
    return await publicClient.getLogs({
      address: this.address,
      event: {
        type: 'event',
        name: 'NameChanged',
        inputs: [
          { name: 'oldName', type: 'string', indexed: false },
          { name: 'newName', type: 'string', indexed: false }
        ]
      },
      fromBlock: "earliest",
      toBlock: "latest"
    });
  }
}
```

## Running the Application

### Basic Execution
```bash
node index.js
```

### Expected Output
```
🚀 Starting Viem interaction with Somnia Network

=== READ OPERATIONS ===
Current greeting: Hello, World!
Current name: World
Contract owner: 0x742d35Cc6634C0532925a3b8D93D2e6E9C747f58

=== WRITE OPERATIONS ===
Changing name to: Alice
Transaction sent. Hash: 0x1234567890abcdef...
Waiting for transaction confirmation...
Transaction confirmed!
Block number: 12345n
Gas used: 45678n
Updated greeting: Hello, Alice!

=== LISTENING TO EVENTS ===
Past NameChanged events: 1
Event 1: { oldName: 'World', newName: 'Alice' }

=== FINAL STATE ===
Current greeting: Hello, Alice!
Current name: Alice
Contract owner: 0x742d35Cc6634C0532925a3b8D93D2e6E9C747f58
```

## Advanced Features

### 1. Error Handling
```javascript
const safeContractRead = async (functionName, args = []) => {
  try {
    const result = await publicClient.readContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName,
      args,
    });
    return { success: true, data: result };
  } catch (error) {
    return { 
      success: false, 
      error: error.message,
      details: error 
    };
  }
};

const safeContractWrite = async (functionName, args = []) => {
  try {
    const txHash = await walletClient.writeContract({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName,
      args,
    });
    
    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash: txHash 
    });
    
    return { 
      success: true, 
      txHash, 
      receipt 
    };
  } catch (error) {
    return { 
      success: false, 
      error: error.message,
      details: error 
    };
  }
};
```

### 2. Gas Estimation
```javascript
const estimateGas = async (functionName, args = []) => {
  try {
    const gasEstimate = await publicClient.estimateContractGas({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName,
      args,
      account: walletClient.account,
    });
    
    console.log(`Estimated gas for ${functionName}:`, gasEstimate);
    return gasEstimate;
  } catch (error) {
    console.error("Gas estimation failed:", error);
  }
};
```

### 3. Real-time Event Monitoring
```javascript
const watchEvents = () => {
  const unwatch = publicClient.watchEvent({
    address: CONTRACT_ADDRESS,
    event: {
      type: 'event',
      name: 'NameChanged',
      inputs: [
        { name: 'oldName', type: 'string', indexed: false },
        { name: 'newName', type: 'string', indexed: false }
      ]
    },
    onLogs: (logs) => {
      console.log("New NameChanged event detected:", logs);
    },
  });

  // To stop watching later
  // unwatch();
  
  return unwatch;
};
```

### 4. Multiple Contract Instances
```javascript
const batchRead = async (contracts) => {
  const results = await publicClient.multicall({
    contracts: contracts.map(contract => ({
      address: contract.address,
      abi: contract.abi,
      functionName: contract.functionName,
      args: contract.args || [],
    })),
  });
  
  return results;
};

// Usage
const contracts = [
  {
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: "name",
  },
  {
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: "owner",
  },
  {
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: "greet",
  },
];

const batchResults = await batchRead(contracts);
console.log("Batch read results:", batchResults);
```

## Integration with Frontend Frameworks

### React Integration Example
```javascript
// hooks/useGreeterContract.js
import { useState, useEffect } from 'react';
import { publicClient, walletClient } from '../utils/clients';
import { ABI } from '../utils/abi';

export const useGreeterContract = (contractAddress) => {
  const [greeting, setGreeting] = useState('');
  const [name, setName] = useState('');
  const [owner, setOwner] = useState('');
  const [loading, setLoading] = useState(false);

  const readContractData = async () => {
    setLoading(true);
    try {
      const [greetingResult, nameResult, ownerResult] = await Promise.all([
        publicClient.readContract({
          address: contractAddress,
          abi: ABI,
          functionName: 'greet',
        }),
        publicClient.readContract({
          address: contractAddress,
          abi: ABI,
          functionName: 'name',
        }),
        publicClient.readContract({
          address: contractAddress,
          abi: ABI,
          functionName: 'owner',
        }),
      ]);

      setGreeting(greetingResult);
      setName(nameResult);
      setOwner(ownerResult);
    } catch (error) {
      console.error('Error reading contract:', error);
    } finally {
      setLoading(false);
    }
  };

  const changeName = async (newName) => {
    try {
      const txHash = await walletClient.writeContract({
        address: contractAddress,
        abi: ABI,
        functionName: 'changeName',
        args: [newName],
      });

      await publicClient.waitForTransactionReceipt({ hash: txHash });
      await readContractData(); // Refresh data
      
      return txHash;
    } catch (error) {
      console.error('Error changing name:', error);
      throw error;
    }
  };

  useEffect(() => {
    if (contractAddress) {
      readContractData();
    }
  }, [contractAddress]);

  return {
    greeting,
    name,
    owner,
    loading,
    changeName,
    refreshData: readContractData,
  };
};
```

## Best Practices

### 1. Security
- **Never expose private keys** in client-side code
- **Use environment variables** for sensitive data
- **Validate user inputs** before sending transactions
- **Handle errors gracefully** to prevent crashes

### 2. Performance
- **Use batch calls** for multiple reads
- **Cache frequently accessed data**
- **Implement loading states** for better UX
- **Optimize gas usage** with estimations

### 3. Error Handling
- **Wrap all async calls** in try-catch blocks
- **Provide meaningful error messages** to users
- **Log errors** for debugging
- **Implement retry mechanisms** for failed transactions

### 4. Code Organization
- **Separate concerns** (clients, contracts, utilities)
- **Use TypeScript** for better type safety
- **Document functions** with JSDoc
- **Follow consistent naming conventions**

## Network Configuration

| Parameter | Value |
|-----------|--------|
| Network Name | Somnia Testnet |
| RPC URL | https://dream-rpc.somnia.network |
| Chain ID | 50312 |
| Currency Symbol | STT |
| Block Explorer | https://shannon-explorer.somnia.network |

## Troubleshooting

### Common Issues

#### 1. "Contract not found" Error
- Verify contract address is correct
- Ensure contract is deployed on the correct network
- Check network connection

#### 2. "Insufficient funds" Error
- Verify account has enough STT for gas fees
- Get tokens from the [Somnia Faucet](https://testnet.somnia.network/)

#### 3. "Function not found" Error
- Verify ABI matches deployed contract
- Check function name spelling
- Ensure function visibility is correct

#### 4. Transaction Failures
- Check gas limits and prices
- Verify function requirements are met
- Review contract state and permissions

### Debug Commands
```javascript
// Check account balance
const balance = await publicClient.getBalance({
  address: walletClient.account.address,
});

// Get transaction details
const tx = await publicClient.getTransaction({
  hash: '0x...',
});

// Check network status
const blockNumber = await publicClient.getBlockNumber();
```

## Conclusion

You have successfully learned how to:

1. **Set up Viem** for Somnia Network integration
2. **Create clients** for READ and WRITE operations
3. **Interact with smart contracts** using ABI
4. **Handle transactions** and wait for confirmations
5. **Listen to events** and monitor contract activity
6. **Implement error handling** and best practices
7. **Integrate with frontend frameworks**

Viem provides a powerful, type-safe interface for building sophisticated dApps on Somnia's high-performance blockchain. Its modular architecture and modern JavaScript features make it an excellent choice for developers building scalable applications that can handle Somnia's impressive 1M+ TPS capabilities.

**Next Steps**: Explore Viem's advanced features like contract deployment, event filtering, and integration with wallet connection libraries for production applications.