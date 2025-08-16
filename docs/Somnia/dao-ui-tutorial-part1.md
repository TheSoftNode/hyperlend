# How To Build A User Interface For DAO Smart Contract - Part 1

## Overview
This tutorial teaches developers how to build a user interface for a DAO Smart Contract using Next.js and React Context. It's the first part of a three-part series that focuses on creating the foundational structure of a decentralized application (DApp).

## Learning Objectives
By the end of this tutorial, you will learn how to:
- Initialize a Next.js project
- Set up global state management using React Context API (`useContext` hook)
- Add a global NavBar in `_app.js` that appears on every page
- Create a basic DApp skeleton ready for READ/WRITE operations and UI components

## Prerequisites
- JavaScript programming knowledge
- MetaMask wallet installed
- Somnia Network added to MetaMask network list

## Step 1: Create Your Next.js Project

Create a new Next.js application:
```bash
npx create-next-app my-dapp-ui
```

Accept all prompts and navigate to the project directory after completion.

## Step 2: Optional - Add Tailwind CSS

If you want to use Tailwind CSS for styling:

1. Install Tailwind and dependencies:
```bash
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

2. Configure `tailwind.config.js`:
```javascript
module.exports = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx}",
    "./components/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

3. Add Tailwind directives to `styles/globals.css`:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

## Step 3: Setting Up React Context for Global State

### Create the Wallet Context

1. Create a `contexts` folder at the project root or inside the `pages` directory
2. Create `walletcontext.js` file with the following code:

```javascript
import { createContext, useContext, useState } from "react";

// Create the context
const WalletContext = createContext();

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

  return (
    <WalletContext.Provider
      value={{
        connected,
        address,
        connectToMetaMask,
        disconnectWallet,
      }}
    >
      {children}
    </WalletContext.Provider>
  );
};
```

### Key Components Explained:
- **`createContext`**: Creates a context that components can provide or read
- **`useWallet()`**: Custom hook allowing components to access global wallet state
- **`connectToMetaMask()`**: Triggers the MetaMask connection flow
- **`WalletProvider`**: Manages state and methods throughout the application

## Step 4: Creating a Global NavBar in _app.js

Create or modify `pages/_app.js`:

```javascript
import "../styles/globals.css";
import { WalletProvider } from "../contexts/walletcontext";
import NavBar from "../components/navbar";

function MyApp({ Component, pageProps }) {
  return (
    <WalletProvider>
      <NavBar />
      <main className="pt-16">
        <Component {...pageProps} />
      </main>
    </WalletProvider>
  );
}

export default MyApp;
```

### Key Features:
- **`<WalletProvider>`**: Wraps the entire component tree for shared wallet state
- **`<NavBar />`**: Placed above main content, visible on all pages
- **`pt-16` class**: Adds top padding to prevent content hiding behind fixed navbar

## Step 5: Create the NavBar Component

1. Create a `components` subdirectory
2. Create `navbar.js` file:

```javascript
import { useWallet } from "../contexts/walletcontext";
import Link from "next/link";

export default function NavBar() {
  const { connected, address, disconnectWallet } = useWallet();

  return (
    <nav className="fixed w-full bg-white shadow z-50">
      <div className="mx-auto max-w-7xl px-4 flex h-16 items-center justify-between">
        <Link href="/">
          <h1 className="text-xl font-bold text-blue-600">MyDAO</h1>
        </Link>
        <div>
          {connected ? (
            <div className="flex items-center space-x-4 text-blue-500">
              <span>{address.slice(0, 6)}...{address.slice(-4)}</span>
              <button 
                onClick={disconnectWallet} 
                className="px-4 py-2 bg-red-500 text-white rounded"
              >
                Logout
              </button>
            </div>
          ) : (
            <span className="text-gray-500">Not connected</span>
          )}
        </div>
      </div>
    </nav>
  );
}
```

### NavBar Features:
- Uses `useWallet()` hook to access global state
- Displays truncated wallet address when connected
- Shows "Not connected" status when wallet isn't connected
- Includes logout functionality

## Step 6: Test Your Setup

Start the development server:
```bash
npm run dev
```

Open `http://localhost:3000` in your web browser. You should see:
- The NavBar at the top of the page
- "Not connected" status (initially)
- A blank home page (expected at this stage)

## Project Structure

After completing this tutorial, your project structure should look like:

```
my-dapp-ui/
├── components/
│   └── navbar.js
├── contexts/
│   └── walletcontext.js
├── pages/
│   └── _app.js
├── styles/
│   └── globals.css
└── tailwind.config.js (if using Tailwind)
```

## What You've Accomplished

1. **Foundation Setup**: Created a Next.js project with optional Tailwind CSS
2. **Global State Management**: Implemented React Context for wallet connection state
3. **Navigation Structure**: Added a persistent NavBar across all pages
4. **Wallet Integration**: Set up MetaMask connection functionality
5. **Responsive Design**: Created a clean, professional-looking interface

## Next Steps

- **Part 2**: Implement READ/WRITE operations (deposit, create proposals, vote) across different Next.js pages using the same WalletContext for contract calls
- **Part 3**: Focus on UI components, forms, buttons, and event handling to create a polished user interface

## Technical Notes

- The tutorial uses React functional components with hooks
- Context API eliminates prop drilling for wallet state management
- The setup is optimized for blockchain interactions with MetaMask
- The foundation supports future integration with DAO smart contracts

This tutorial provides a solid foundation for building decentralized applications on the Somnia Network, with proper separation of concerns and scalable architecture patterns.