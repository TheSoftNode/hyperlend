# How To Build A User Interface For DAO Smart Contract - Part 3: WRITE Operations

## Overview
Part 3 focuses exclusively on implementing Write Operations—interacting with your smart contract to perform state-changing actions such as depositing funds, creating proposals, voting, and executing proposals. These operations require user signatures and gas fees.

## Learning Objectives
By the end of Part 3, you will be able to:
- Understand Write Operations necessary for DAO functionality
- Integrate write operations into Next.js pages with intuitive UI components
- Handle transaction states and provide comprehensive user feedback
- Implement proper error handling and loading states

## Prerequisites
- Complete Parts 1 and 2 of this series
- Have a deployed DAO Smart Contract with test data
- MetaMask connected with STT test tokens

## Understanding WRITE Operations

Write Operations modify blockchain state and require:
- **User Signatures**: MetaMask confirmation for each transaction
- **Gas Fees**: Cost paid in STT for transaction processing
- **Transaction Confirmation**: Wait time for blockchain confirmation
- **State Changes**: Permanent modifications to smart contract data

## Core DAO Write Operations

### 1. **Depositing Funds**: Adding STT to gain voting power
### 2. **Creating Proposals**: Submitting new governance proposals  
### 3. **Voting on Proposals**: Casting Yes/No votes
### 4. **Executing Proposals**: Implementing approved proposals

## Enhanced WalletContext with Write Functions

Update your existing `walletcontext.js` to include all write operations:

### Complete Enhanced walletcontext.js

```javascript
import { createContext, useContext, useState } from "react";
import { createPublicClient, createWalletClient, custom, http, parseEther } from "viem";
import { somnia } from "viem/chains";

// Create the context
const WalletContext = createContext();

// Contract configuration
const CONTRACT_ADDRESS = "0x7be249A360DB86E2Cf538A6893f37aFd89C70Ab4"; // Your DAO contract address
const CONTRACT_ABI = [
  // Add your complete DAO contract ABI here
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
  },
  {
    "inputs": [],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "string", "name": "_description", "type": "string"}],
    "name": "createProposal",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "uint256", "name": "_proposalId", "type": "uint256"},
      {"internalType": "bool", "name": "_support", "type": "bool"}
    ],
    "name": "vote",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "_proposalId", "type": "uint256"}],
    "name": "executeProposal",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];

// Create clients
const publicClient = createPublicClient({
  chain: somnia,
  transport: http()
});

export const useWallet = () => {
  const context = useContext(WalletContext);
  if (!context) {
    throw new Error("useWallet must be used within a WalletProvider");
  }
  return context;
};

export const WalletProvider = ({ children }) => {
  const [connected, setConnected] = useState(false);
  const [address, setAddress] = useState("");
  const [walletClient, setWalletClient] = useState(null);

  const connectToMetaMask = async () => {
    if (typeof window !== "undefined" && window.ethereum) {
      try {
        const accounts = await window.ethereum.request({
          method: "eth_requestAccounts",
        });
        
        const client = createWalletClient({
          chain: somnia,
          transport: custom(window.ethereum)
        });
        
        setAddress(accounts[0]);
        setConnected(true);
        setWalletClient(client);
      } catch (error) {
        console.error("Failed to connect to MetaMask:", error);
      }
    }
  };

  const disconnectWallet = () => {
    setConnected(false);
    setAddress("");
    setWalletClient(null);
  };

  // READ OPERATIONS (from Part 2)
  const fetchTotalProposals = async () => {
    try {
      const result = await publicClient.readContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: 'totalProposals',
      });
      return Number(result);
    } catch (error) {
      console.error("Error fetching total proposals:", error);
      throw error;
    }
  };

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

  // WRITE OPERATIONS

  // 1. DEPOSIT FUNCTION
  const deposit = async () => {
    if (!walletClient || !address) {
      throw new Error("Please connect your wallet first!");
    }

    try {
      const tx = await walletClient.writeContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: "deposit",
        value: parseEther("0.001"), // 0.001 STT
        account: address,
      });

      console.log("Deposit Transaction:", tx);
      return tx;
    } catch (error) {
      console.error("Deposit failed:", error);
      throw error;
    }
  };

  // 2. CREATE PROPOSAL FUNCTION
  const createProposal = async (description) => {
    if (!walletClient || !address) {
      throw new Error("Please connect your wallet first!");
    }

    try {
      const tx = await walletClient.writeContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: "createProposal",
        args: [description],
        account: address,
      });

      console.log("Create Proposal Transaction:", tx);
      return tx;
    } catch (error) {
      console.error("Create Proposal failed:", error);
      throw error;
    }
  };

  // 3. VOTE ON PROPOSAL FUNCTION
  const voteOnProposal = async (proposalId, support) => {
    if (!walletClient || !address) {
      throw new Error("Please connect your wallet first!");
    }

    try {
      const tx = await walletClient.writeContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: "vote",
        args: [BigInt(proposalId), support],
        account: address,
      });

      console.log("Vote Transaction:", tx);
      return tx;
    } catch (error) {
      console.error("Vote failed:", error);
      throw error;
    }
  };

  // 4. EXECUTE PROPOSAL FUNCTION
  const executeProposal = async (proposalId) => {
    if (!walletClient || !address) {
      throw new Error("Please connect your wallet first!");
    }

    try {
      const tx = await walletClient.writeContract({
        address: CONTRACT_ADDRESS,
        abi: CONTRACT_ABI,
        functionName: "executeProposal",
        args: [BigInt(proposalId)],
        account: address,
      });

      console.log("Execute Proposal Transaction:", tx);
      return tx;
    } catch (error) {
      console.error("Execute Proposal failed:", error);
      throw error;
    }
  };

  return (
    <WalletContext.Provider
      value={{
        // Wallet state
        connected,
        address,
        connectToMetaMask,
        disconnectWallet,
        // Read operations
        fetchTotalProposals,
        fetchProposal,
        // Write operations
        deposit,
        createProposal,
        voteOnProposal,
        executeProposal,
      }}
    >
      {children}
    </WalletContext.Provider>
  );
};
```

## Integrating Write Operations into Pages

### Enhanced Home Page with Deposit Functionality

Update `pages/index.js` to include deposit functionality:

```javascript
import { useWallet } from "../contexts/walletcontext";
import { useState, useEffect } from "react";

export default function Home() {
  const { 
    connected, 
    connectToMetaMask, 
    fetchTotalProposals, 
    deposit 
  } = useWallet();
  const [totalProposals, setTotalProposals] = useState(null);
  const [loading, setLoading] = useState(true);
  const [depositing, setDepositing] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

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

  const handleDeposit = async () => {
    setError("");
    setMessage("");
    setDepositing(true);

    try {
      const tx = await deposit();
      setMessage(`Deposit successful! Transaction hash: ${tx}`);
    } catch (err) {
      setError(err.message || "Deposit failed. Please try again.");
    } finally {
      setDepositing(false);
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

        {/* Messages */}
        {message && (
          <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg">
            <p className="text-green-800">{message}</p>
          </div>
        )}

        {error && (
          <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
            <p className="text-red-800">{error}</p>
          </div>
        )}

        {!connected ? (
          <div className="mb-8">
            <p className="mb-4 text-gray-600">
              Connect your wallet to participate in DAO governance
            </p>
            <ConnectButton />
          </div>
        ) : (
          <div className="space-y-4">
            <p className="text-green-600 font-semibold">Wallet Connected!</p>
            <div className="flex justify-center space-x-4">
              <button
                onClick={handleDeposit}
                disabled={depositing}
                className="px-6 py-3 bg-green-500 text-white rounded-lg hover:bg-green-600 disabled:bg-gray-300"
              >
                {depositing ? "Depositing..." : "Deposit 0.001 STT"}
              </button>
              <a
                href="/create-proposal"
                className="px-6 py-3 bg-purple-500 text-white rounded-lg hover:bg-purple-600"
              >
                Create Proposal
              </a>
              <a
                href="/fetch-proposal"
                className="px-6 py-3 bg-orange-500 text-white rounded-lg hover:bg-orange-600"
              >
                View Proposals
              </a>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
```

### Create Proposal Page

Create `pages/create-proposal.js`:

```javascript
import { useState } from "react";
import { useRouter } from "next/router";
import { useWallet } from "../contexts/walletcontext";

export default function CreateProposalPage() {
  const [description, setDescription] = useState("");
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState("");
  const [error, setError] = useState("");
  const { connected, createProposal, connectToMetaMask } = useWallet();
  const router = useRouter();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");

    if (!connected) {
      setError("You must connect your wallet first!");
      return;
    }

    if (!description.trim()) {
      setError("Proposal description cannot be empty!");
      return;
    }

    setLoading(true);

    try {
      const tx = await createProposal(description.trim());
      setSuccess(`Proposal created successfully! Transaction hash: ${tx}`);
      setDescription("");
      // Optionally redirect after success
      setTimeout(() => {
        router.push("/");
      }, 3000);
    } catch (err) {
      console.error("Error creating proposal:", err);
      setError(err.message || "Failed to create proposal. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto py-8 px-4">
      <h1 className="text-3xl font-bold mb-8 text-center">Create Proposal</h1>

      {!connected && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
          <p className="text-yellow-800 mb-4">
            Please connect your wallet to create proposals
          </p>
          <button
            onClick={connectToMetaMask}
            className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Connect Wallet
          </button>
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p className="text-red-800">
            <span className="font-medium">Error!</span> {error}
          </p>
        </div>
      )}

      {success && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
          <p className="text-green-800">
            <span className="font-medium">Success!</span> {success}
          </p>
        </div>
      )}

      <form onSubmit={handleSubmit} className="bg-white shadow-lg rounded-lg p-6">
        <div className="mb-6">
          <label htmlFor="proposal-description" className="block text-sm font-medium text-gray-700 mb-2">
            Proposal Description
          </label>
          <textarea
            id="proposal-description"
            rows="6"
            placeholder="Enter your proposal description here..."
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            required
          />
        </div>
        
        <button
          type="submit"
          disabled={loading || !connected}
          className="w-full px-4 py-3 bg-purple-500 text-white rounded-lg hover:bg-purple-600 disabled:bg-gray-300 disabled:cursor-not-allowed"
        >
          {loading ? "Submitting..." : "Submit Proposal"}
        </button>
      </form>
    </div>
  );
}
```

### Enhanced Fetch Proposal Page with Voting and Execution

Update `pages/fetch-proposal.js` to include voting and execution:

```javascript
import { useState } from "react";
import { useWallet } from "../contexts/walletcontext";

export default function FetchProposalPage() {
  const [proposalId, setProposalId] = useState("");
  const [proposalData, setProposalData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [voting, setVoting] = useState(false);
  const [executing, setExecuting] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const { 
    connected, 
    connectToMetaMask,
    fetchProposal, 
    voteOnProposal, 
    executeProposal 
  } = useWallet();

  const handleFetch = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    setProposalData(null);

    if (!connected) {
      setError("You must connect your wallet first!");
      return;
    }

    if (!proposalId.trim()) {
      setError("Please enter a proposal ID.");
      return;
    }

    setLoading(true);

    try {
      const data = await fetchProposal(proposalId);
      setProposalData(data);
    } catch (err) {
      console.error("Error fetching proposal:", err);
      setError("Failed to fetch proposal. Please check the proposal ID.");
    } finally {
      setLoading(false);
    }
  };

  const handleVote = async (support) => {
    setError("");
    setSuccess("");
    setVoting(true);

    try {
      const tx = await voteOnProposal(proposalId, support);
      setSuccess(`Successfully voted ${support ? "YES" : "NO"} on proposal #${proposalId}. Transaction: ${tx}`);
      
      // Refresh proposal data
      const updatedData = await fetchProposal(proposalId);
      setProposalData(updatedData);
    } catch (err) {
      console.error("Error voting:", err);
      setError(err.message || "Voting failed. Please try again.");
    } finally {
      setVoting(false);
    }
  };

  const handleExecute = async () => {
    setError("");
    setSuccess("");
    setExecuting(true);

    try {
      const tx = await executeProposal(proposalId);
      setSuccess(`Proposal #${proposalId} executed successfully. Transaction: ${tx}`);
      
      // Refresh proposal data
      const updatedData = await fetchProposal(proposalId);
      setProposalData(updatedData);
    } catch (err) {
      console.error("Error executing proposal:", err);
      setError(err.message || "Execution failed. Please try again.");
    } finally {
      setExecuting(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto py-8 px-4">
      <h1 className="text-3xl font-bold mb-8 text-center">Fetch Proposal</h1>

      {!connected && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
          <p className="text-yellow-800 mb-4">
            Please connect your wallet to interact with proposals
          </p>
          <button
            onClick={connectToMetaMask}
            className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Connect Wallet
          </button>
        </div>
      )}

      {/* Fetch Form */}
      <form onSubmit={handleFetch} className="bg-white shadow-lg rounded-lg p-6 mb-6">
        <div className="mb-4">
          <label htmlFor="proposal-id" className="block text-sm font-medium text-gray-700 mb-2">
            Proposal ID
          </label>
          <input
            type="number"
            id="proposal-id"
            value={proposalId}
            onChange={(e) => setProposalId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Enter proposal ID (e.g., 0, 1, 2...)"
            min="0"
            required
          />
        </div>
        
        <button
          type="submit"
          disabled={loading || !connected}
          className="w-full px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:bg-gray-300"
        >
          {loading ? "Fetching..." : "Fetch Proposal"}
        </button>
      </form>

      {/* Messages */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p className="text-red-800">
            <span className="font-medium">Error!</span> {error}
          </p>
        </div>
      )}

      {success && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
          <p className="text-green-800">
            <span className="font-medium">Success!</span> {success}
          </p>
        </div>
      )}

      {/* Proposal Details */}
      {proposalData && (
        <div className="bg-white shadow-lg rounded-lg p-6">
          <h2 className="text-2xl font-semibold mb-6">Proposal #{proposalId}</h2>
          
          <div className="space-y-4 mb-6">
            <div>
              <h3 className="font-medium text-gray-700">Description:</h3>
              <p className="text-gray-900">{proposalData.description}</p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <h3 className="font-medium text-gray-700">Yes Votes:</h3>
                <p className="text-green-600 font-semibold text-xl">{proposalData.yesVotes}</p>
              </div>
              <div>
                <h3 className="font-medium text-gray-700">No Votes:</h3>
                <p className="text-red-600 font-semibold text-xl">{proposalData.noVotes}</p>
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

          {/* Voting Buttons */}
          {connected && !proposalData.executed && (
            <div className="mb-4">
              <h3 className="font-medium text-gray-700 mb-2">Cast Your Vote:</h3>
              <div className="flex space-x-4">
                <button
                  onClick={() => handleVote(true)}
                  disabled={voting || executing}
                  className="flex-1 px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600 disabled:bg-gray-300"
                >
                  {voting ? "Processing..." : "Vote YES"}
                </button>
                <button
                  onClick={() => handleVote(false)}
                  disabled={voting || executing}
                  className="flex-1 px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 disabled:bg-gray-300"
                >
                  {voting ? "Processing..." : "Vote NO"}
                </button>
              </div>
            </div>
          )}

          {/* Execute Button */}
          {connected && !proposalData.executed && (
            <div>
              <h3 className="font-medium text-gray-700 mb-2">Execute Proposal:</h3>
              <button
                onClick={handleExecute}
                disabled={executing || voting}
                className="w-full px-4 py-2 bg-purple-500 text-white rounded-lg hover:bg-purple-600 disabled:bg-gray-300"
              >
                {executing ? "Executing..." : "Execute Proposal"}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
```

## Advanced User Feedback with Toast Notifications

For better user experience, implement toast notifications:

### Install react-toastify

```bash
npm install react-toastify
```

### Update _app.js

```javascript
import "../styles/globals.css";
import 'react-toastify/dist/ReactToastify.css';
import { WalletProvider } from "../contexts/walletcontext";
import NavBar from "../components/navbar";
import { ToastContainer } from 'react-toastify';

function MyApp({ Component, pageProps }) {
  return (
    <WalletProvider>
      <NavBar />
      <main className="pt-16">
        <Component {...pageProps} />
        <ToastContainer
          position="top-right"
          autoClose={5000}
          hideProgressBar={false}
          newestOnTop={false}
          closeOnClick
          rtl={false}
          pauseOnFocusLoss
          draggable
          pauseOnHover
        />
      </main>
    </WalletProvider>
  );
}

export default MyApp;
```

### Example Usage in Components

```javascript
import { toast } from 'react-toastify';

// Replace alert/setSuccess with toast notifications
const handleDeposit = async () => {
  try {
    const tx = await deposit();
    toast.success(`Deposit successful! Transaction: ${tx}`);
  } catch (err) {
    toast.error(err.message || "Deposit failed");
  }
};

const handleVote = async (support) => {
  try {
    const tx = await voteOnProposal(proposalId, support);
    toast.success(`Vote ${support ? 'YES' : 'NO'} cast successfully!`);
  } catch (err) {
    toast.error(err.message || "Voting failed");
  }
};
```

## Advanced Error Handling Patterns

### 1. Transaction Error Types

```javascript
const handleTransaction = async (operation) => {
  try {
    const tx = await operation();
    toast.success("Transaction successful!");
    return tx;
  } catch (error) {
    // Handle different error types
    if (error.code === 4001) {
      toast.error("Transaction rejected by user");
    } else if (error.code === -32603) {
      toast.error("Transaction failed - insufficient funds");
    } else if (error.message.includes("execution reverted")) {
      toast.error("Smart contract execution failed");
    } else {
      toast.error("Unknown error occurred");
    }
    console.error("Transaction error:", error);
    throw error;
  }
};
```

### 2. Network Error Handling

```javascript
const checkNetworkAndConnection = async () => {
  if (!window.ethereum) {
    throw new Error("MetaMask is not installed");
  }

  const chainId = await window.ethereum.request({ method: 'eth_chainId' });
  if (chainId !== '0x...') { // Replace with Somnia chain ID
    throw new Error("Please switch to Somnia network");
  }

  if (!connected) {
    throw new Error("Please connect your wallet first");
  }
};
```

## Testing Write Operations

### Complete Testing Checklist

1. **Setup Test Environment**
   ```bash
   npm run dev
   # Navigate to http://localhost:3000
   ```

2. **Obtain Test Tokens**
   - Get STT from Somnia faucet
   - Ensure MetaMask is connected to Somnia testnet

3. **Test Deposit**
   - Connect wallet on Home page
   - Click "Deposit 0.001 STT" button
   - Confirm transaction in MetaMask
   - Verify success message

4. **Test Create Proposal**
   - Navigate to Create Proposal page
   - Enter proposal description
   - Submit and confirm in MetaMask
   - Check for success confirmation

5. **Test Voting**
   - Go to Fetch Proposal page
   - Enter valid proposal ID
   - Click Vote YES/NO
   - Confirm in MetaMask
   - Verify updated vote counts

6. **Test Execution**
   - After proposal deadline passes
   - Click Execute Proposal
   - Confirm in MetaMask
   - Verify execution status update

### Debugging Tips

- Monitor browser console for errors
- Check MetaMask for transaction history
- Verify contract state changes in block explorer
- Test edge cases (invalid IDs, insufficient funds, etc.)

## Security Best Practices

### 1. Input Validation

```javascript
const validateProposalInput = (description) => {
  if (!description || description.trim().length === 0) {
    throw new Error("Proposal description cannot be empty");
  }
  
  if (description.length > 1000) {
    throw new Error("Proposal description too long (max 1000 characters)");
  }
  
  // Sanitize HTML and dangerous characters
  const sanitized = description.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
  return sanitized.trim();
};
```

### 2. Transaction Validation

```javascript
const validateTransactionParams = (proposalId, amount = null) => {
  if (proposalId < 0 || !Number.isInteger(Number(proposalId))) {
    throw new Error("Invalid proposal ID");
  }
  
  if (amount !== null) {
    const numAmount = Number(amount);
    if (numAmount <= 0 || numAmount > 1) {
      throw new Error("Invalid deposit amount");
    }
  }
};
```

## Key Features Implemented

### 1. Complete CRUD Operations
- **Create**: New proposals
- **Read**: Proposal data and counts (from Part 2)
- **Update**: Vote counts and execution status
- **Delete**: Not applicable for immutable blockchain data

### 2. Transaction State Management
- Loading states for all operations
- Error handling with descriptive messages
- Success confirmations with transaction hashes
- Disabled buttons during processing

### 3. User Experience Enhancements
- Toast notifications for non-intrusive feedback
- Form validation and input sanitization
- Responsive design for mobile compatibility
- Clear visual indicators for transaction states

### 4. Security Implementation
- Wallet connection validation before operations
- Input validation and sanitization
- Error boundary implementation
- Proper handling of async operations

## Production Deployment

### Environment Configuration

Create `.env.local`:

```env
NEXT_PUBLIC_CONTRACT_ADDRESS=0x7be249A360DB86E2Cf538A6893f37aFd89C70Ab4
NEXT_PUBLIC_SOMNIA_RPC_URL=https://rpc.somnia.network
NEXT_PUBLIC_CHAIN_ID=0x...
```

### Build for Production

```bash
# Build for production
npm run build

# Start production server
npm start

# Or deploy to Vercel
npx vercel --prod
```

## Conclusion

Congratulations! You have successfully implemented all WRITE operations for your DAO interface. Your application now supports:

✅ **Complete DAO Functionality**
- Fund deposits for voting power
- Proposal creation and management
- Democratic voting system
- Proposal execution capabilities

✅ **Professional User Experience**
- Real-time transaction feedback
- Comprehensive error handling
- Loading states and visual indicators
- Toast notifications for better UX

✅ **Production-Ready Features**
- Security best practices
- Input validation and sanitization
- Responsive design
- Proper state management

Your DAO dApp is now fully functional and ready for real-world deployment. Users can participate in decentralized governance through an intuitive, secure, and professional interface built on the Somnia Network.

**Happy building! 🚀**