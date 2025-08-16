# How to Setup MetaMask Authentication to Connect Somnia Network

## Overview
This comprehensive guide teaches developers how to implement MetaMask authentication in web applications to connect users to the Somnia Network. We'll build a Next.js application that demonstrates wallet connection, user authentication, and state management for decentralized applications.

## What is MetaMask Authentication?
MetaMask authentication is a process that allows web applications to:
- **Connect to user wallets** without handling private keys
- **Verify user identity** through wallet ownership
- **Enable transaction signing** for smart contract interactions
- **Provide secure access** to blockchain functionality

### Benefits of MetaMask Integration
- **Security**: No private key exposure to applications
- **User Control**: Users maintain full control of their assets
- **Standardization**: Follows EIP-1193 provider standard
- **Convenience**: Single sign-on for Web3 applications

## Prerequisites
- Node.js (v16 or higher)
- MetaMask browser extension installed
- Basic knowledge of React/Next.js
- Understanding of Ethereum wallet concepts

## Project Setup

### 1. Create Next.js Project
```bash
npx create-next-app metamask-example
```

### Configuration Options
When prompted, select:
- ✅ **TypeScript**: For type safety
- ✅ **Tailwind CSS**: For styling
- ✅ **Page Router**: For this tutorial
- ❌ **App Router**: Not needed for this example
- ❌ **ESLint**: Optional
- ❌ **src/ directory**: Keep default structure

### 2. Install Dependencies
```bash
cd metamask-example
npm install viem
npm install @types/window  # For TypeScript support
```

### 3. Project Structure
```
metamask-example/
├── pages/
│   ├── index.tsx
│   ├── _app.tsx
│   └── api/
├── styles/
│   └── globals.css
├── types/
│   └── window.d.ts
├── utils/
│   ├── wallet.ts
│   └── contracts.ts
├── hooks/
│   └── useWallet.ts
├── components/
│   ├── WalletConnect.tsx
│   └── UserProfile.tsx
└── package.json
```

## Basic Implementation

### 1. TypeScript Declarations (`types/window.d.ts`)
```typescript
interface Window {
  ethereum?: {
    isMetaMask?: boolean;
    request: (args: { method: string; params?: any[] }) => Promise<any>;
    on: (event: string, callback: (...args: any[]) => void) => void;
    removeListener: (event: string, callback: (...args: any[]) => void) => void;
    selectedAddress: string | null;
    chainId: string;
  };
}
```

### 2. Basic Implementation (`pages/index.tsx`)
```typescript
import { useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
} from "viem";
import { somniaTestnet } from "viem/chains";

export default function Home() {
  // State management
  const [address, setAddress] = useState<string>("");
  const [connected, setConnected] = useState<boolean>(false);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>("");

  // MetaMask connection function
  const connectToMetaMask = async () => {
    setLoading(true);
    setError("");

    // Check if running in browser and MetaMask is available
    if (typeof window !== "undefined" && window.ethereum !== undefined) {
      try {
        // Request account access
        await window.ethereum.request({ method: "eth_requestAccounts" });

        // Create wallet client
        const walletClient = createWalletClient({
          chain: somniaTestnet,
          transport: custom(window.ethereum),
        });

        // Get user addresses
        const [userAddress] = await walletClient.getAddresses();

        // Update state
        setAddress(userAddress);
        setConnected(true);

        console.log("Connected account:", userAddress);
      } catch (error: any) {
        console.error("User denied account access:", error);
        setError(error.message || "Failed to connect to MetaMask");
      }
    } else {
      const errorMsg = "MetaMask is not installed or not running in a browser environment!";
      console.log(errorMsg);
      setError(errorMsg);
    }

    setLoading(false);
  };

  // Disconnect function
  const disconnect = () => {
    setAddress("");
    setConnected(false);
    setError("");
  };

  return (
    <div className="min-h-screen bg-gray-100 flex items-center justify-center">
      <div className="bg-white p-8 rounded-lg shadow-md w-96">
        <h1 className="text-2xl font-bold mb-6 text-center">
          Somnia Network Connection
        </h1>

        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
            {error}
          </div>
        )}

        {!connected ? (
          <button
            onClick={connectToMetaMask}
            disabled={loading}
            className={`w-full font-bold py-2 px-4 rounded ${
              loading
                ? "bg-gray-400 cursor-not-allowed"
                : "bg-blue-500 hover:bg-blue-700 text-white"
            }`}
          >
            {loading ? "Connecting..." : "Connect Wallet"}
          </button>
        ) : (
          <div className="space-y-4">
            <div className="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">
              <p className="font-semibold">Connected Successfully!</p>
              <p className="text-sm break-all">Address: {address}</p>
            </div>
            <button
              onClick={disconnect}
              className="w-full bg-red-500 hover:bg-red-700 text-white font-bold py-2 px-4 rounded"
            >
              Disconnect
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
```

## Advanced Implementation

### 1. Custom Hook for Wallet Management (`hooks/useWallet.ts`)
```typescript
import { useState, useEffect, useCallback } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  type WalletClient,
  type PublicClient,
} from "viem";
import { somniaTestnet } from "viem/chains";

interface WalletState {
  address: string | null;
  connected: boolean;
  loading: boolean;
  error: string | null;
  chainId: string | null;
}

interface WalletActions {
  connect: () => Promise<void>;
  disconnect: () => void;
  switchToSomnia: () => Promise<void>;
  getBalance: () => Promise<bigint | null>;
}

export const useWallet = (): WalletState & WalletActions & {
  walletClient: WalletClient | null;
  publicClient: PublicClient;
} => {
  const [state, setState] = useState<WalletState>({
    address: null,
    connected: false,
    loading: false,
    error: null,
    chainId: null,
  });

  const [walletClient, setWalletClient] = useState<WalletClient | null>(null);

  // Create public client for read operations
  const publicClient = createPublicClient({
    chain: somniaTestnet,
    transport: http(),
  });

  // Check if already connected on mount
  useEffect(() => {
    checkConnection();
  }, []);

  // Listen for account and network changes
  useEffect(() => {
    if (typeof window !== "undefined" && window.ethereum) {
      const handleAccountsChanged = (accounts: string[]) => {
        if (accounts.length === 0) {
          disconnect();
        } else {
          setState(prev => ({
            ...prev,
            address: accounts[0],
            connected: true,
          }));
        }
      };

      const handleChainChanged = (chainId: string) => {
        setState(prev => ({
          ...prev,
          chainId,
        }));
      };

      window.ethereum.on("accountsChanged", handleAccountsChanged);
      window.ethereum.on("chainChanged", handleChainChanged);

      return () => {
        window.ethereum?.removeListener("accountsChanged", handleAccountsChanged);
        window.ethereum?.removeListener("chainChanged", handleChainChanged);
      };
    }
  }, []);

  const checkConnection = async () => {
    if (typeof window !== "undefined" && window.ethereum) {
      try {
        const accounts = await window.ethereum.request({
          method: "eth_accounts"
        });

        if (accounts.length > 0) {
          const client = createWalletClient({
            chain: somniaTestnet,
            transport: custom(window.ethereum),
          });

          setWalletClient(client);
          setState(prev => ({
            ...prev,
            address: accounts[0],
            connected: true,
            chainId: window.ethereum?.chainId || null,
          }));
        }
      } catch (error) {
        console.error("Error checking connection:", error);
      }
    }
  };

  const connect = useCallback(async () => {
    setState(prev => ({ ...prev, loading: true, error: null }));

    if (typeof window === "undefined" || !window.ethereum) {
      setState(prev => ({
        ...prev,
        loading: false,
        error: "MetaMask is not installed"
      }));
      return;
    }

    try {
      await window.ethereum.request({ method: "eth_requestAccounts" });

      const client = createWalletClient({
        chain: somniaTestnet,
        transport: custom(window.ethereum),
      });

      const [userAddress] = await client.getAddresses();

      setWalletClient(client);
      setState(prev => ({
        ...prev,
        address: userAddress,
        connected: true,
        loading: false,
        chainId: window.ethereum?.chainId || null,
      }));
    } catch (error: any) {
      setState(prev => ({
        ...prev,
        loading: false,
        error: error.message || "Failed to connect wallet"
      }));
    }
  }, []);

  const disconnect = useCallback(() => {
    setWalletClient(null);
    setState({
      address: null,
      connected: false,
      loading: false,
      error: null,
      chainId: null,
    });
  }, []);

  const switchToSomnia = useCallback(async () => {
    if (!window.ethereum) return;

    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0xC4B8" }], // 50312 in hex
      });
    } catch (switchError: any) {
      // Chain not added, try to add it
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
              chainId: "0xC4B8",
              chainName: "Somnia Testnet",
              nativeCurrency: {
                name: "STT",
                symbol: "STT",
                decimals: 18,
              },
              rpcUrls: ["https://dream-rpc.somnia.network"],
              blockExplorerUrls: ["https://shannon-explorer.somnia.network"],
            }],
          });
        } catch (addError) {
          setState(prev => ({
            ...prev,
            error: "Failed to add Somnia network"
          }));
        }
      } else {
        setState(prev => ({
          ...prev,
          error: "Failed to switch to Somnia network"
        }));
      }
    }
  }, []);

  const getBalance = useCallback(async (): Promise<bigint | null> => {
    if (!state.address) return null;

    try {
      return await publicClient.getBalance({
        address: state.address as `0x${string}`,
      });
    } catch (error) {
      console.error("Error getting balance:", error);
      return null;
    }
  }, [state.address, publicClient]);

  return {
    ...state,
    walletClient,
    publicClient,
    connect,
    disconnect,
    switchToSomnia,
    getBalance,
  };
};
```

### 2. Wallet Connect Component (`components/WalletConnect.tsx`)
```typescript
import { useEffect, useState } from "react";
import { useWallet } from "../hooks/useWallet";
import { formatEther } from "viem";

export const WalletConnect = () => {
  const {
    address,
    connected,
    loading,
    error,
    chainId,
    connect,
    disconnect,
    switchToSomnia,
    getBalance,
  } = useWallet();

  const [balance, setBalance] = useState<string>("0");
  const [balanceLoading, setBalanceLoading] = useState(false);

  // Fetch balance when connected
  useEffect(() => {
    if (connected && address) {
      fetchBalance();
    }
  }, [connected, address]);

  const fetchBalance = async () => {
    setBalanceLoading(true);
    try {
      const bal = await getBalance();
      if (bal !== null) {
        setBalance(formatEther(bal));
      }
    } catch (error) {
      console.error("Error fetching balance:", error);
    }
    setBalanceLoading(false);
  };

  const formatAddress = (addr: string) => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  };

  const isOnSomnia = chainId === "0xc4b8"; // 50312 in hex

  return (
    <div className="max-w-md mx-auto bg-white rounded-lg shadow-md p-6">
      <h2 className="text-2xl font-bold text-center mb-6">
        Somnia Wallet Connection
      </h2>

      {error && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          <p className="text-sm">{error}</p>
        </div>
      )}

      {!connected ? (
        <div className="space-y-4">
          <p className="text-gray-600 text-center">
            Connect your MetaMask wallet to interact with Somnia Network
          </p>
          <button
            onClick={connect}
            disabled={loading}
            className={`w-full font-bold py-3 px-4 rounded-lg transition-colors ${
              loading
                ? "bg-gray-400 cursor-not-allowed"
                : "bg-blue-500 hover:bg-blue-600 text-white"
            }`}
          >
            {loading ? (
              <span className="flex items-center justify-center">
                <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Connecting...
              </span>
            ) : (
              "Connect MetaMask"
            )}
          </button>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="bg-green-50 border border-green-200 rounded-lg p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-green-800 font-semibold">Connected</span>
              <div className="w-3 h-3 bg-green-500 rounded-full"></div>
            </div>
            <p className="text-sm text-gray-600 break-all">
              <strong>Address:</strong> {formatAddress(address!)}
            </p>
            <p className="text-sm text-gray-600">
              <strong>Balance:</strong> {balanceLoading ? "Loading..." : `${balance} STT`}
            </p>
          </div>

          {!isOnSomnia && (
            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <p className="text-yellow-800 text-sm mb-2">
                You're not connected to Somnia Network
              </p>
              <button
                onClick={switchToSomnia}
                className="w-full bg-yellow-500 hover:bg-yellow-600 text-white font-bold py-2 px-4 rounded"
              >
                Switch to Somnia
              </button>
            </div>
          )}

          <div className="flex space-x-2">
            <button
              onClick={fetchBalance}
              disabled={balanceLoading}
              className="flex-1 bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded"
            >
              Refresh Balance
            </button>
            <button
              onClick={disconnect}
              className="flex-1 bg-red-500 hover:bg-red-600 text-white font-bold py-2 px-4 rounded"
            >
              Disconnect
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
```

### 3. Enhanced Main Page (`pages/index.tsx`)
```typescript
import { WalletConnect } from "../components/WalletConnect";
import { useWallet } from "../hooks/useWallet";

export default function Home() {
  const { connected, address } = useWallet();

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div className="container mx-auto px-4 py-8">
        <header className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-800 mb-2">
            Somnia Network DApp
          </h1>
          <p className="text-gray-600">
            Connect your wallet to interact with the Somnia blockchain
          </p>
        </header>

        <div className="max-w-2xl mx-auto">
          <WalletConnect />

          {connected && (
            <div className="mt-8 bg-white rounded-lg shadow-md p-6">
              <h3 className="text-lg font-semibold mb-4">Quick Actions</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <button className="bg-purple-500 hover:bg-purple-600 text-white font-bold py-3 px-4 rounded-lg transition-colors">
                  View Transactions
                </button>
                <button className="bg-green-500 hover:bg-green-600 text-white font-bold py-3 px-4 rounded-lg transition-colors">
                  Send Tokens
                </button>
                <button className="bg-orange-500 hover:bg-orange-600 text-white font-bold py-3 px-4 rounded-lg transition-colors">
                  Contract Interaction
                </button>
                <button className="bg-pink-500 hover:bg-pink-600 text-white font-bold py-3 px-4 rounded-lg transition-colors">
                  NFT Gallery
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
```

## Security Best Practices

### 1. Input Validation
```typescript
const validateAddress = (address: string): boolean => {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
};

const validateChainId = (chainId: string): boolean => {
  return chainId === "0xc4b8"; // Somnia testnet
};
```

### 2. Error Handling
```typescript
enum WalletErrorCodes {
  USER_REJECTED = 4001,
  UNAUTHORIZED = 4100,
  UNSUPPORTED_METHOD = 4200,
  DISCONNECTED = 4900,
  CHAIN_DISCONNECTED = 4901,
}

const handleWalletError = (error: any) => {
  switch (error.code) {
    case WalletErrorCodes.USER_REJECTED:
      return "User rejected the request";
    case WalletErrorCodes.UNAUTHORIZED:
      return "The requested account has not been authorized";
    case WalletErrorCodes.UNSUPPORTED_METHOD:
      return "The requested method is not supported";
    case WalletErrorCodes.DISCONNECTED:
      return "The provider is disconnected from all chains";
    case WalletErrorCodes.CHAIN_DISCONNECTED:
      return "The provider is not connected to the requested chain";
    default:
      return error.message || "An unknown error occurred";
  }
};
```

### 3. Network Validation
```typescript
const SOMNIA_TESTNET = {
  chainId: "0xC4B8", // 50312
  chainName: "Somnia Testnet",
  nativeCurrency: {
    name: "STT",
    symbol: "STT",
    decimals: 18,
  },
  rpcUrls: ["https://dream-rpc.somnia.network"],
  blockExplorerUrls: ["https://shannon-explorer.somnia.network"],
};

const addSomniaNetwork = async () => {
  try {
    await window.ethereum?.request({
      method: "wallet_addEthereumChain",
      params: [SOMNIA_TESTNET],
    });
  } catch (error) {
    console.error("Failed to add Somnia network:", error);
  }
};
```

## Advanced Features

### 1. Transaction Signing
```typescript
const signMessage = async (message: string, walletClient: WalletClient) => {
  try {
    const signature = await walletClient.signMessage({
      message,
    });
    return signature;
  } catch (error) {
    console.error("Error signing message:", error);
    throw error;
  }
};
```

### 2. Contract Interaction Helper
```typescript
import { ABI } from "../utils/contractABI";

const interactWithContract = async (
  walletClient: WalletClient,
  contractAddress: string,
  functionName: string,
  args: any[]
) => {
  try {
    const hash = await walletClient.writeContract({
      address: contractAddress as `0x${string}`,
      abi: ABI,
      functionName,
      args,
    });
    
    return hash;
  } catch (error) {
    console.error("Contract interaction failed:", error);
    throw error;
  }
};
```

### 3. Event Listening
```typescript
const listenForEvents = (publicClient: any, contractAddress: string) => {
  const unwatch = publicClient.watchEvent({
    address: contractAddress,
    onLogs: (logs: any[]) => {
      console.log("New events:", logs);
    },
  });

  return unwatch;
};
```

## Testing the Application

### 1. Run Development Server
```bash
npm run dev
```

### 2. Test Scenarios
1. **Connect Wallet**: Click "Connect MetaMask" and approve in MetaMask
2. **Network Switch**: Test automatic Somnia network addition
3. **Balance Display**: Verify STT balance shows correctly
4. **Disconnect**: Test wallet disconnection functionality
5. **Account Changes**: Switch accounts in MetaMask and verify app updates

### 3. Error Testing
- Test with MetaMask locked
- Test network rejection
- Test on unsupported networks
- Test with insufficient funds

## Production Considerations

### 1. Environment Variables
```javascript
// next.config.js
module.exports = {
  env: {
    SOMNIA_RPC_URL: process.env.SOMNIA_RPC_URL,
    CONTRACT_ADDRESS: process.env.CONTRACT_ADDRESS,
  },
};
```

### 2. Error Monitoring
```typescript
const logError = (error: any, context: string) => {
  console.error(`[${context}]`, error);
  // Send to error monitoring service
  // analytics.track('wallet_error', { error: error.message, context });
};
```

### 3. Performance Optimization
```typescript
import { useMemo, useCallback } from "react";

const useOptimizedWallet = () => {
  const memoizedClient = useMemo(() => {
    return createPublicClient({
      chain: somniaTestnet,
      transport: http(),
    });
  }, []);

  const memoizedConnect = useCallback(async () => {
    // Connection logic
  }, []);

  return { client: memoizedClient, connect: memoizedConnect };
};
```

## Common Issues & Solutions

### Issue 1: MetaMask Not Detected
**Solution**: Add proper detection and fallback
```typescript
const detectMetaMask = () => {
  if (typeof window === "undefined") return false;
  return !!(window.ethereum && window.ethereum.isMetaMask);
};
```

### Issue 2: Wrong Network
**Solution**: Implement automatic network switching
```typescript
const ensureSomniaNetwork = async () => {
  const chainId = await window.ethereum?.request({ method: "eth_chainId" });
  if (chainId !== "0xc4b8") {
    await switchToSomnia();
  }
};
```

### Issue 3: Connection State Persistence
**Solution**: Use localStorage with proper hydration
```typescript
const usePersistedConnection = () => {
  const [isHydrated, setIsHydrated] = useState(false);
  
  useEffect(() => {
    setIsHydrated(true);
    // Check for existing connection
  }, []);

  return isHydrated;
};
```

## Conclusion

You have successfully learned how to:

1. **Set up MetaMask authentication** in a Next.js application
2. **Manage wallet connection state** with React hooks
3. **Handle network switching** and validation
4. **Implement security best practices** for Web3 applications
5. **Create reusable components** for wallet interaction
6. **Handle errors gracefully** with user-friendly messages
7. **Optimize performance** with memoization and callbacks

This implementation provides a solid foundation for building production-ready dApps on Somnia Network with secure, user-friendly wallet authentication. The modular approach makes it easy to extend functionality and integrate with smart contracts for full Web3 application development.

**Next Steps**: Integrate this authentication system with smart contract interactions using the Viem tutorial to build complete decentralized applications on Somnia's high-performance blockchain.