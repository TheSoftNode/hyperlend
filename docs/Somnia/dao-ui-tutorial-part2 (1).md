# How To Build A User Interface For DAO Smart Contract - Part 2: READ Operations

## Overview
Part 2 focuses exclusively on implementing Read Operations to fetch data from your deployed DAO Smart Contract. These operations allow you to display dynamic blockchain data in your Next.js application without requiring transactions or gas costs.

## Learning Objectives
By the end of Part 2, you will be able to:
- Understand how to read data from smart contracts using the viem library
- Implement functions to fetch total number of proposals and specific proposal details
- Integrate READ operations into Next.js pages to display dynamic data

## Prerequisites
- Complete Part 1 of this series
- Have a deployed DAO Smart Contract on Somnia Network
- Basic understanding of blockchain read operations

## Understanding READ Operations

Read Operations in dApps involve fetching data from the blockchain without altering its state. Key characteristics:
- **Gas-free**: No transaction costs since no state changes occur
- **No signatures required**: Users don't need to approve transactions
- **Real-time data**: Fetch current blockchain state
- **Common use cases**: Display proposal counts, user balances, voting results

## Expanding walletcontext.js for Read Operations

Add these two primary READ functions to your existing `walletcontext.js`:

### Complete Updated walletcontext.js

```javascript
import { createContext, useContext, useState } from "react";
import { createPublicClient, http, formatEther } from "viem";
import { somnia } from "viem/chains"; // Assuming Somnia chain is available

// Create the context
const WalletContext = createContext();

// Contract configuration
const CONTRACT_ADDRESS = "YOUR_DAO_CONTRACT_ADDRESS_HERE";
const CONTRACT_ABI = [
  // Add your DAO contract ABI here
  {
    "inputs": [],
    "name": "totalProposals",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "name": "proposals",
    "outputs": [
      {"internalType": "string", "name": "description", "type": "string"},
      {"internalType": "uint256", "name": "deadline", "type": "uint256"},
      {"internalType": "uint256", "name": "yesVotes", "type": "uint256"},
      {"internalType": "uint256", "name": "noVotes", "type": "uint256"},
      {"internalType": "bool", "name": "executed", "type": "bool"},
      {"internalType": "address", "name": "proposer", "type": "address"}
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

// Create public client for read operations
const publicClient = createPublicClient({
  chain: somnia,
  transport: http()
});

// Custom hook to use the wallet context
export const useWallet = () => {
  const context = useContext(WalletContext);
  if (!context) {
    throw new Error("useWallet must be used within a WalletProvider");
  }
  return context;
};

// Wallet Provider component
export const WalletProvider = ({ children }) => {
  const [connected, setConnected] = useState(false);
  const [address, setAddress] = useState("");

  const connectToMetaMask = async () => {
    if (typeof window !== "undefined" && window.ethereum) {
      try {
        const accounts = await window.ethereum.request({
          method: "eth_requestAccounts",
        });
        setAddress(accounts[0]);
        setConnected(true);
      } catch (error) {
        console.error("Failed to connect to MetaMask:", error);
      }
    }
  };

  const disconnectWallet = () => {
    setConnected(false);
    setAddress("");
  };

  // READ OPERATION: Fetch Total Proposals
  const fetchTotalProposals = async () => {
    try {
      const result = await publicClient.readContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: 'totalProposals',
      });
      return Number(result); // Convert BigInt to number
    } catch (error) {
      console.error("Error fetching total proposals:", error);
      throw error;
    }
  };

  // READ OPERATION: Fetch Specific Proposal Details
  const fetchProposal = async (proposalId) => {
    try {
      const result = await publicClient.readContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: 'proposals',
        args: [BigInt(proposalId)],
      });

      return {
        description: result[0],
        deadline: Number(result[1]),
        yesVotes: Number(result[2]),
        noVotes: Number(result[3]),
        executed: result[4],
        proposer: result[5]
      };
    } catch (error) {
      console.error("Error fetching proposal:", error);
      throw error;
    }
  };

  return (
    <WalletContext.Provider
      value={{
        connected,
        address,
        connectToMetaMask,
        disconnectWallet,
        fetchTotalProposals,
        fetchProposal,
      }}
    >
      {children}
    </WalletContext.Provider>
  );
};
```

## Integrating Read Operations into Pages

### Home Page (pages/index.js)

Update your home page to display the total number of proposals:

```javascript
import { useWallet } from "../contexts/walletcontext";
import { useState, useEffect } from "react";

export default function Home() {
  const { connected, connectToMetaMask, fetchTotalProposals } = useWallet();
  const [totalProposals, setTotalProposals] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const loadTotalProposals = async () => {
      try {
        const total = await fetchTotalProposals();
        setTotalProposals(total);
      } catch (error) {
        console.error("Failed to fetch total proposals:", error);
      } finally {
        setLoading(false);
      }
    };

    loadTotalProposals();
  }, []);

  const ConnectButton = () => (
    <button
      onClick={connectToMetaMask}
      className="px-6 py-3 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
    >
      Connect Wallet
    </button>
  );

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="text-center">
        <h1 className="text-4xl font-bold mb-8 text-gray-800">Welcome to MyDAO</h1>
        
        <div className="bg-white shadow-lg rounded-lg p-8 mb-8 max-w-md mx-auto">
          <h2 className="text-2xl font-semibold mb-4">DAO Statistics</h2>
          {loading ? (
            <p className="text-gray-600">Loading proposals...</p>
          ) : (
            <div>
              <p className="text-3xl font-bold text-blue-600 mb-2">
                {totalProposals}
              </p>
              <p className="text-gray-600">Total Proposals Created</p>
            </div>
          )}
        </div>

        {!connected && (
          <div className="mb-8">
            <p className="mb-4 text-gray-600">
              Connect your wallet to participate in DAO governance
            </p>
            <ConnectButton />
          </div>
        )}
      </div>
    </div>
  );
}
```

### Fetch Proposal Page (pages/fetch-proposal.js)

Create a new page to fetch and display specific proposal details:

```javascript
import { useWallet } from "../contexts/walletcontext";
import { useState } from "react";

export default function FetchProposal() {
  const { connected, connectToMetaMask, fetchProposal } = useWallet();
  const [proposalId, setProposalId] = useState("");
  const [proposalData, setProposalData] = useState(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setProposalData(null);

    // Validation
    if (!proposalId.trim()) {
      setError("Please enter a proposal ID");
      return;
    }

    if (!connected) {
      setError("Please connect your wallet first");
      return;
    }

    setLoading(true);

    try {
      const data = await fetchProposal(parseInt(proposalId));
      setProposalData(data);
    } catch (err) {
      setError("Failed to fetch proposal. Please check the proposal ID.");
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const ConnectButton = () => (
    <button
      onClick={connectToMetaMask}
      className="px-6 py-3 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
    >
      Connect Wallet
    </button>
  );

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <h1 className="text-3xl font-bold mb-8 text-center">Fetch Proposal Details</h1>

      {/* Connection Status */}
      {!connected && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
          <p className="text-yellow-800 mb-4">
            Please connect your wallet to fetch proposal details
          </p>
          <ConnectButton />
        </div>
      )}

      {/* Fetch Form */}
      <form onSubmit={handleSubmit} className="bg-white shadow-lg rounded-lg p-6 mb-6">
        <div className="mb-4">
          <label htmlFor="proposalId" className="block text-sm font-medium text-gray-700 mb-2">
            Proposal ID
          </label>
          <input
            type="number"
            id="proposalId"
            value={proposalId}
            onChange={(e) => setProposalId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Enter proposal ID (e.g., 0, 1, 2...)"
            min="0"
          />
        </div>
        
        <button
          type="submit"
          disabled={!connected || loading}
          className="w-full px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed"
        >
          {loading ? "Fetching..." : "Fetch Proposal"}
        </button>
      </form>

      {/* Error Display */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p className="text-red-800">{error}</p>
        </div>
      )}

      {/* Proposal Details */}
      {proposalData && (
        <div className="bg-white shadow-lg rounded-lg p-6">
          <h2 className="text-2xl font-semibold mb-4">Proposal #{proposalId}</h2>
          
          <div className="space-y-4">
            <div>
              <h3 className="font-medium text-gray-700">Description:</h3>
              <p className="text-gray-900">{proposalData.description}</p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <h3 className="font-medium text-gray-700">Yes Votes:</h3>
                <p className="text-green-600 font-semibold">{proposalData.yesVotes}</p>
              </div>
              <div>
                <h3 className="font-medium text-gray-700">No Votes:</h3>
                <p className="text-red-600 font-semibold">{proposalData.noVotes}</p>
              </div>
            </div>

            <div>
              <h3 className="font-medium text-gray-700">Proposer:</h3>
              <p className="text-gray-900 font-mono text-sm">
                {proposalData.proposer}
              </p>
            </div>

            <div>
              <h3 className="font-medium text-gray-700">Deadline:</h3>
              <p className="text-gray-900">
                {new Date(proposalData.deadline * 1000).toLocaleString()}
              </p>
            </div>

            <div>
              <h3 className="font-medium text-gray-700">Status:</h3>
              <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                proposalData.executed 
                  ? 'bg-green-100 text-green-800' 
                  : 'bg-yellow-100 text-yellow-800'
              }`}>
                {proposalData.executed ? 'Executed' : 'Pending'}
              </span>
            </div>
          </div>

          {/* Vote and Execute Buttons (placeholder for Part 3) */}
          <div className="mt-6 flex space-x-4">
            <button 
              className="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600"
              disabled
            >
              Vote Yes
            </button>
            <button 
              className="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
              disabled
            >
              Vote No
            </button>
            <button 
              className="px-4 py-2 bg-purple-500 text-white rounded hover:bg-purple-600"
              disabled
            >
              Execute Proposal
            </button>
          </div>
          <p className="text-sm text-gray-500 mt-2">
            *Voting and execution functionality will be covered in Part 3
          </p>
        </div>
      )}
    </div>
  );
}
```

## Testing READ Operations

### 1. Populate Test Data
Before testing, ensure you have some proposals in your contract:
- Load your Smart Contract in Remix IDE
- Deposit 0.001 ETH to gain voting power
- Create one or more proposals

### 2. Verify Operations
Run your application:
```bash
npm run dev
```

Navigate to `http://localhost:3000` and verify:
- **Home Page**: Total proposals count matches your contract
- **Fetch Proposal Page**: Input valid proposal IDs (0, 1, 2...) and verify details

### 3. Error Handling
The implementation includes:
- Loading states while fetching data
- Error messages for invalid inputs
- Connection validation
- Proper error logging in console

## Key Features Implemented

### 1. Read Operations
- `fetchTotalProposals()`: Gets total proposal count
- `fetchProposal(proposalId)`: Retrieves specific proposal details

### 2. State Management
- Loading states for better UX
- Error handling and display
- Form validation

### 3. UI Components
- Responsive design with Tailwind CSS
- Connected/disconnected states
- Professional card layouts
- Status indicators

## Technical Implementation Details

### Viem Library Integration
- Uses `createPublicClient` for read-only operations
- Implements `readContract` method for smart contract calls
- Handles BigInt conversion for JavaScript compatibility

### React Patterns
- `useEffect` for component mounting data fetches
- `useState` for local component state
- Custom hooks (`useWallet`) for global state access

### Error Boundaries
- Try-catch blocks for async operations
- User-friendly error messages
- Console logging for debugging

## Next Steps

**Part 3 Preview**: The next tutorial will focus on:
- UI Components: Enhanced forms, buttons, and styling
- WRITE Operations: Voting, proposal creation, execution
- Event Handling: Real-time updates and transaction feedback
- Advanced Features: Transaction status, confirmation dialogs

## Conclusion

Part 2 successfully implements READ operations for your DAO dApp, enabling you to:
- Display real-time blockchain data
- Create interactive proposal browsing
- Maintain proper error handling and loading states
- Build a foundation for upcoming WRITE operations