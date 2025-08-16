# How To Build A User Interface For DAO Smart Contract p2

This guide will focus exclusively on implementing Read Operations, which fetches data from your deployed [DAO Smart Contract](build-a-simple-dao-smart-contract). By the end of this article, you’ll be able to:

1. Understand how to read data from your smart contract using [viem](how-to-connect-to-somnia-network-via-viem-library).
2. Implement functions to fetch the total number of proposals and specific proposal details.
3. Integrate these READ operations into your Next.js pages to display dynamic data.

Prerequisite:\
Ensure you’ve completed [Part 1](how-to-build-a-user-interface-for-dao-smart-contract-p1) of this series, where you initialized a Next.js project, set up a **`WalletContext`** for global state management, and added a global **`NavBar`**.

***

## Understand READ Operations

In decentralized applications (dApps), Read Operations involve fetching data from the blockchain without altering its state. In the example DAO Smart Contract, this is crucial for displaying dynamic information such as:

* **Total Number of Proposals**: How many proposals have been created.
* **Proposal Details**: Information about a specific proposal, including its description, votes, and execution status.

These operations are read-only and do not require the user to sign any transactions, making them free of gas costs.

We’ll use the viem library to interact with our smart contract and perform these READ operations.

***

## Expand walletcontext.js for Read Operations

**`walletcontext.js`** is the central hub for managing wallet connections and interacting with your Smart Contract. We’ll add two primary READ functions:

1. **`fetchTotalProposals()`**: Retrieves the total number of proposals created.
2. **`fetchProposal(proposalId)`**: Fetches details of a specific proposal by its ID.

### Fetch Total Proposals

Functionality: This function calls the **`totalProposals`** method in your smart contract to determine how many proposals have been created so far.

<details>

<summary>contexts/walletcontext.js</summary>

```javascript
import { createContext, useContext, useState } from "react";
import {
  defineChain,
  createPublicClient,
  createWalletClient,
  http,
  custom,
  parseEther,
} from "viem";
import { ABI } from "../../abi"; // Adjust the path as necessary
// Define Somnia Chain
const SOMNIA = defineChain({
  id: 50312,
  name: "Somnia Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "Ether",
    symbol: "STT",
  },
  rpcUrls: {
    default: {
      http: ["https://dream-rpc.somnia.network"],
    },
  },
  blockExplorers: {
    default: { name: "Explorer", url: "https://somnia-devnet.socialscan.io" },
  },
});
// Create a public client for read operations
const publicClient = createPublicClient({
  chain: SOMNIA,
  transport: http(),
});

const WalletContext = createContext();

export function WalletProvider({ children }) {
  // ---------- STATE ------------
  const [connected, setConnected] = useState(false);
  const [address, setAddress] = useState("");
  const [client, setClient] = useState(null);
  
   // Fetch Total Proposals
  async function fetchTotalProposals() {
    try {
      const result = await publicClient.readContract({
        address: "0x7be249A360DB86E2Cf538A6893f37aFd89C70Ab4",
        abi: ABI,
        functionName: "totalProposals",
      });
      return result; // Returns a BigInt
    } catch (error) {
      console.error("Error fetching totalProposals:", error);
      throw error;
    }
  }


  // Fetch Proposal Details
  async function fetchProposal(proposalId) {
    try {
      const result = await publicClient.readContract({
        address: "0x7be249A360DB86E2Cf538A6893f37aFd89C70Ab4",
        abi: ABI,
        functionName: "proposals",
        args: [parseInt(proposalId)],
      });
      console.log(result);
      return result; // Returns the Proposal struct
    } catch (error) {
      console.error("Error fetching proposal:", error);
      throw error;
    }
  }


  // Provider's value
  return (
    <WalletContext.Provider
      value={{
        connected,
        address,
        client,
        connectToMetaMask,
        disconnectWallet,
        fetchTotalProposals,
        fetchProposal,
      }}
    >
      {children}
    </WalletContext.Provider>
  );
}

// Custom hook to consume context
export function useWallet() {
  return useContext(WalletContext);
}
```

</details>

**`fetchTotalProposals()`** uses **`publicClient.readContract`** to call the **`totalProposals`** function in the Smart Contract. This function returns a `BigInt` representing the total number of proposals.\
\
&#xNAN;**`fetchProposal(proposalId)`** calls the proposals mapping in your contract to retrieve details of a specific proposal by its `ID`. It returns a struct containing the proposal's **description**, **deadline**, **votes**, **execution status**, and **proposer**.

***

## Integrate Read Operations into Pages

With the read functions in place, let’s integrate them into Next.js pages to display dynamic data.

### Home Page

Update the `index.js` page to show the total number of proposals created in your DAO on the home page.

<details>

<summary>pages/index.js</summary>

```javascript
import { useState, useEffect } from "react";
import ConnectButton from "../components/connectbutton";
import { useWallet } from "../contexts/walletcontext";

export default function Home() {
  const { fetchTotalProposals } = useWallet();
  const [totalProposals, setTotalProposals] = useState(null);
  
    useEffect(() => {
    async function loadData() {
      try {
        const count = await fetchTotalProposals();
        setTotalProposals(count);
      } catch (error) {
        console.error("Failed to fetch total proposals:", error);
      }
    }
    loadData();
  }, [fetchTotalProposals]);
  return (
    <div
      className={`${geistSans.variable} ${geistMono.variable} 
        grid grid-rows-[20px_1fr_20px] items-center justify-items-center 
        min-h-screen p-8 pb-20 gap-16 sm:p-20 
        font-[family-name:var(--font-geist-sans)]`}
    >
      {/* The NavBar is already rendered in _app.js */}
      <main className="flex flex-col gap-8 row-start-2 items-center sm:items-start">
        <h1 className="text-3xl font-bold">Welcome to MyDAO</h1>


        {totalProposals !== null ? (
          <p className="text-lg">
            Total proposals created: {totalProposals.toString()}
          </p>
        ) : (
          <p>Loading total proposals...</p>
        )}

        <ConnectButton />
      </main>
    </div>
  );
}
```

</details>

Here we set the `totalProposals` state variable to store the fetched total number of proposals.\
The **`ConnectButton`** implements the MetaMask authentication. The useWallet hook parse the function from **`WalletContext.`**

The **`useEffect`** Hook is applied on component mount, **`fetchTotalProposals()`** is then called to retrieve the total number of proposals from the Smart Contract.

The page displays a loading message until totalProposals is fetched. Once fetched, it displays the total number of proposals. Users will have to click the **ConnectButton** to connect their wallets for WRITE operations. See part 3.

***

### Fetch-Proposal Page

This page allow users to input a proposal ID, fetch its details, and display them. Additionally, on the page users are provided options for voting on or executing the proposal.

Implementation:

<details>

<summary>pages/fetch-proposal.js</summary>

```javascript
import { useState, useEffect } from "react";
import { useRouter } from "next/router";
import { useWallet } from "../contexts/walletcontext";
import { Button, Card, Label, TextInput } from "flowbite-react"; // Optional Flowbite imports

export default function FetchProposalPage() {
  const [proposalId, setProposalId] = useState("");
  const [proposalData, setProposalData] = useState(null);
  const [error, setError] = useState("");
  
  const { connected, fetchProposal, voteOnProposal, executeProposal } = useWallet();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(""); // Clear previous errors

    if (!connected) {
      alert("You must connect your wallet first!");
      return;
    }
    if (!proposalId.trim()) {
      setError("Please enter a proposal ID.");
      return;
    }

    try {
      // Fetch the proposal from the contract
      const result = await fetchProposal(proposalId);
      console.log("Fetched Proposal:", result);
      setProposalData(result);
    } catch (err) {
      console.error("Error fetching proposal:", err);
      setError("Failed to fetch proposal. Check console for details.");
    }
  };
  
  useEffect(() => {
    if (proposalData !== null) {
      console.log("Updated Proposal Data:", proposalData);
    }
  }, [proposalData]);

  return (
    <div className="max-w-2xl mx-auto mt-20 p-4">
      <h1 className="text-2xl font-bold mb-4">Fetch a Proposal</h1>

      {/* Form to input Proposal ID */}
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <Label htmlFor="proposal-id" value="Proposal ID" />
          <TextInput
            id="proposal-id"
            type="number"
            placeholder="Enter proposal ID"
            value={proposalId}
            onChange={(e) => setProposalId(e.target.value)}
            required
          />
        </div>

        <Button type="submit" color="blue">
          Fetch
        </Button>
      </form>

      {/* Display Errors */}
      {error && <div className="mt-4 text-red-600">{error}</div>}

      {/* Display Proposal Details */}
      {proposalData && (
        <Card className="mt-8">
          <h2 className="text-xl font-bold mb-2">Proposal #{proposalId}</h2>
          <ul className="list-disc list-inside space-y-1">
            <li>
              <strong>Description:</strong> {proposalData[0]}
            </li>
            <li>
              <strong>Deadline:</strong> {new Date(proposalData[1] * 1000).toLocaleString()}
            </li>
            <li>
              <strong>Yes Votes:</strong> {proposalData[2].toString()}
            </li>
            <li>
              <strong>No Votes:</strong> {proposalData[3].toString()}
            </li>
            <li>
              <strong>Executed:</strong> {proposalData[4] ? "Yes" : "No"}
            </li>
            <li>
              <strong>Proposer:</strong> {proposalData[5]}
            </li>
          </ul>
          </div>
        </Card>
      )}
    </div>
  );
}
```

</details>

The following React states are implemented

* `proposalId`: Stores the user-inputted proposal ID.
* `proposalData`: Stores the fetched proposal details.
* `error`: Captures any errors during fetch, vote, or execute operations.

The **`handleSubmit`** function is used to validate the input and connection status. It then calls the **`fetchProposal(proposalId)`** to retrieve proposal details.

We use a **Form** element for users to input a proposal ID and fetch its details. The **Error** Display is implemented to show any errors that occur during operations. The **Proposal Details** displays the fetched proposal information in a styled card.

The card contains **Vote** and **Execute b**uttons for users to vote **YES/NO** or execute the proposal if eligible.

***

## Edge Cases and Errors

For better UX, consider adding loading indicators while fetching data or awaiting transaction confirmations.

Example:

<details>

<summary>pages/fetch-proposal.js</summary>

```javascript
const [loading, setLoading] = useState(false);

// In handleSubmit
const handleSubmit = async (e) => {
  e.preventDefault();
  setError("");
  setLoading(true);
  // ... rest of the code
  setLoading(false);
};


// In the button
<Button type="submit" color="blue" disabled={loading}>
  {loading ? "Fetching..." : "Fetch"}
</Button>
```

</details>



***

## Test Read Operations

### Populate Some Data

Before testing read operations, make sure there are some proposals created:

1. Load your Smart Contract on the [Remix IDE](create-and-deploy-your-erc20-smart-contract-to-somnia-network).
2. Deposit 0.001 ETH to gain voting power.
3. Create one or more proposals via the Create Proposal page.

### Verify Read Operations

Run your application using the command:

```
npm run dev
```

Your application will be running on **`localhost:3000`** in your web browser. Check for the following in the User Interface:

1. Total Proposals: On the Home page, verify that the total number of proposals matches the number you’ve created via Remix IDE.
2. Fetch Proposal Details:\
   \- Navigate to the Fetch-Proposal page.\
   \- Input a valid proposalId (e.g., 0 for the first proposal).\
   \- Verify that all proposal details are accurately displayed.

Monitor the browser console for any errors or logs that can help in debugging.

***

## Conclusion and Next Steps

In Part 2, you successfully implemented Read Operations in your DAO front end:

* **`fetchTotalProposals()`**: Displayed the total number of proposals on the Home page.
* **fetchProposal(proposalId)**: Retrieved and displayed specific proposal details on the Fetch-Proposal page.

#### What's Next?

Stay tuned for Part 3 of this series, where we’ll dive into building UI Components—crafting forms, buttons, and enhancing event handling to create a more polished and user-friendly interface for your DAO dApp.

***

Congratulations! You’ve now built a robust foundation for reading data from your DAO smart contract within your Next.js front end. Keep experimenting and enhancing your dApp’s capabilities in the upcoming sections!

\
