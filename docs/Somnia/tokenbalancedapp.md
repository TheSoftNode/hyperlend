# How to Build a Token Balance dApp on Somnia Network

The Somnia mission is to enable the building of mass-consumer real-time applications. As a Developer, you need to understand how to interact with onchain data to build UIs. This guide will teach you how to build a Token Balance dApp that fetches and displays ERC20 token balances from the Somnia Network using Next.js and the Ormi Data APIs.

## Prerequisites

To complete this guide, you will need:

- Basic understanding of React and TypeScript
- An Ormi API key. Get one at[ ](https://ormi.xyz/)[https://subgraph.somnia.network/dashboard/api](https://subgraph.somnia.network/dashboard/api).

## What is Ormi Data API?

[Ormi](https://docs.ormilabs.com/dedicated-env/somnia/data-apis/overview) provides a unified crypto data infrastructure for live and historical blockchain data. The Data APIs allow developers to query blockchain data without running their own nodes, making it easy to build data-rich applications on the Somnia Network.

#### API Base URL

The Ormi Data API for Somnia Network uses the following base URL:

```
https://api.subgraph.somnia.network/public_api/data_api
```

#### API Endpoints

The API follows a RESTful structure. For fetching ERC20 token balances, the endpoint structure is:

```
/somnia/v1/address/{walletAddress}/balance/erc20
```

Where:

- `somnia` - The network identifier
- `v1` - API version
- `{walletAddress}` - The wallet address you want to query
- `balance/erc20` - Specifies that you want ERC-20 token balances

#### Authentication

The Ormi API requires authentication using a Bearer token. Every request must include an Authorization header:

```
Authorization: Bearer YOUR_API_KEY
```

**Important**: Never expose your API key in client-side code. Always make API calls from a server-side route to keep your key secure.

#### Example API Request

Here's an example of how to make a direct API call using curl:

```bash
curl -X GET "https://api.subgraph.somnia.network/public_api/data_api/somnia/v1/address/0xYOUR_WALLET_ADDRESS/balance/erc20" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json"
```

## Set up the Project

Create a new Next.js application with TypeScript and Tailwind CSS:

```bash
npx create-next-app@latest somnia-balance-demo --typescript --tailwind --app
cd somnia-balance-demo
```

## Create the Type Definitions

First, we need to define TypeScript interfaces for the API response. Update `app/page.tsx`:

```typescript
"use client";
import { useState, FormEvent } from "react";
// Type definitions for the API response
interface TokenBalance {
  balance: string;
  contract: {
    address: string;
    decimals: number;
    erc_type: string;
    logoUri: string | null;
    name: string;
    symbol: string;
  };
  raw_balance: string;
}

interface BalanceResponse {
  erc20TokenBalances: TokenBalance[];
  resultCount: number;
}
```

## Build the User Interface

Now, let's create the main component with an input field and button. Update your `app/page.tsx`:

```typescript
export default function Home() {
  const [walletAddress, setWalletAddress] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(false);
  const [data, setData] = useState<BalanceResponse | null>(null);
  const [error, setError] = useState<string>("");

  return (
    <main className="min-h-screen bg-white p-8">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold mb-8">Somnia Network Balance Demo</h1>

        <form className="mb-8">
          <div className="flex gap-4">
            <input
              type="text"
              value={walletAddress}
              onChange={(e) => setWalletAddress(e.target.value)}
              placeholder="Enter wallet address (0x...)"
              className="flex-1 px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <button
              type="submit"
              disabled={loading}
              className="px-6 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600 disabled:bg-gray-400 disabled:cursor-not-allowed"
            >
              {loading ? "Loading..." : "Fetch Balance"}
            </button>
          </div>
        </form>
      </div>
    </main>
  );
}
```

## Create a `.env` file

The `.env` is for keeping secrets such as the Ormi API KEY. Add the API KEY:

```bash
PRIVATE_KEY=YOUR_API_KEY_HERE
```

## Create the API Route

To avoid CORS issues and keep your API key secure, we'll create an API route. Create a directory and a new file `app/api/balance/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const walletAddress = searchParams.get("address");

    if (!walletAddress) {
      return NextResponse.json(
        { error: "Wallet address is required" },
        { status: 400 }
      );
    }

    const apiKey = process.env.PRIVATE_KEY;
    const baseUrl = "https://api.subgraph.somnia.network/public_api/data_api";

    const response = await fetch(
      `${baseUrl}/somnia/v1/address/${walletAddress}/balance/erc20`,
      {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      }
    );

    const data = await response.json();

    if (!response.ok) {
      return NextResponse.json(
        { error: "Failed to fetch data from Ormi API", details: data },
        { status: response.status }
      );
    }

    return NextResponse.json(data);
  } catch (error) {
    console.error("API Error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
```

Important: Replace `YOUR_API_KEY_HERE` with your actual Ormi API key.

## Implement the Fetch Function

Add the fetch function to handle form submission. Update your `app/page.tsx`:

```typescript
const fetchBalance = async (e: FormEvent<HTMLFormElement>) => {
  e.preventDefault();

  if (!walletAddress) {
    setError("Please enter a wallet address");
    return;
  }

  setLoading(true);
  setError("");
  setData(null);

  try {
    const response = await fetch(`/api/balance?address=${walletAddress}`, {
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ walletAddress }),
    });

    const result = await response.json();

    if (!response.ok) {
      throw new Error(result.error || "Failed to fetch balance");
    }

    setData(result);
  } catch (err) {
    setError(err instanceof Error ? err.message : "An error occurred");
  } finally {
    setLoading(false);
  }
};
```

Don't forget to add the onSubmit handler to your form:

```typescript
<form onSubmit={fetchBalance} className="mb-8">
```

## Display the Results

Add error handling and a table to display the token balances. Add this code after your form in `app/page.tsx`:

```typescript
{
  error && (
    <div className="p-4 mb-4 bg-red-50 border border-red-200 rounded-md">
      <p className="text-red-600">{error}</p>
    </div>
  );
}

{
  data && data.erc20TokenBalances.length > 0 && (
    <div className="bg-white rounded-lg shadow overflow-hidden">
      <div className="px-6 py-4 bg-gray-50 border-b">
        <h2 className="text-xl font-semibold">
          Token Balances ({data.resultCount} tokens)
        </h2>
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Name
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Symbol
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Balance
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Contract Address
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {data.erc20TokenBalances.map((token, index) => (
              <tr key={index} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {token.contract.name || "Unknown"}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {token.contract.symbol || "-"}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {parseFloat(token.balance).toLocaleString()}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">
                  <a
                    href={`http://shannon-explorer.somnia.network/address/${token.contract.address}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 hover:text-blue-800 font-mono"
                  >
                    {token.contract.address.slice(0, 6)}...
                    {token.contract.address.slice(-4)}
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

{
  data && data.erc20TokenBalances.length === 0 && (
    <div className="bg-gray-50 p-6 rounded-md text-center">
      <p className="text-gray-600">No ERC-20 tokens found for this address</p>
    </div>
  );
}
```

### Test Your dApp

Start the development server:

```bash
npm run dev
```

Open[ http://localhost:3000](http://localhost:3000/) in your browser. Enter a wallet address that has tokens on Somnia Network.

Example test address: `0xC4890Bc98273424a18626772F266C35bf57FA56A`

Look at the browser for the response and the displayed token balances. You can click on any contract address to view it in the Shannon Explorer.

## Complete Code

<details>

<summary>page.tsx</summary>

```typescript
"use client";

import { useState, FormEvent } from "react";

// Type definitions for the API response
interface TokenBalance {
  balance: string;
  contract: {
    address: string;
    decimals: number;
    erc_type: string;
    logoUri: string | null;
    name: string;
    symbol: string;
  };
  raw_balance: string;
}

interface BalanceResponse {
  erc20TokenBalances: TokenBalance[];
  resultCount: number;
}

export default function Home() {
  const [walletAddress, setWalletAddress] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(false);
  const [data, setData] = useState<BalanceResponse | null>(null);
  const [error, setError] = useState<string>("");

  const fetchBalance = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    if (!walletAddress) {
      setError("Please enter a wallet address");
      return;
    }

    setLoading(true);
    setError("");
    setData(null);

    try {
      const response = await fetch(`/api/balance?address=${walletAddress}`, {
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ walletAddress }),
      });

      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.error || "Failed to fetch balance");
      }

      setData(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen bg-white p-8">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold mb-8 text-gray-900">
          Somnia Network Balance Demo
        </h1>

        <form onSubmit={fetchBalance} className="mb-8">
          <div className="flex gap-4">
            <input
              type="text"
              value={walletAddress}
              onChange={(e) => setWalletAddress(e.target.value)}
              placeholder="Enter wallet address (0x...)"
              className="flex-1 px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 text-gray-500"
            />
            <button
              type="submit"
              disabled={loading}
              className="px-6 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600 disabled:bg-gray-400 disabled:cursor-not-allowed"
            >
              {loading ? "Loading..." : "Fetch Balance"}
            </button>
          </div>
        </form>

        {error && (
          <div className="p-4 mb-4 bg-red-50 border border-red-200 rounded-md">
            <p className="text-red-600">{error}</p>
          </div>
        )}

        {data && data.erc20TokenBalances.length > 0 && (
          <div className="bg-white rounded-lg shadow overflow-hidden">
            <div className="px-6 py-4 bg-gray-50 border-b">
              <h2 className="text-xl font-semibold text-gray-900">
                Token Balances ({data.resultCount} tokens)
              </h2>
            </div>
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-900 uppercase tracking-wider">
                      Name
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Symbol
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Balance
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Contract Address
                    </th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {data.erc20TokenBalances.map((token, index) => (
                    <tr key={index} className="hover:bg-gray-50">
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {token.contract.name || "Unknown"}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {token.contract.symbol || "-"}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {parseFloat(token.balance).toLocaleString()}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm">
                        <a
                          href={`http://shannon-explorer.somnia.network/address/${token.contract.address}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:text-blue-800 font-mono"
                        >
                          {token.contract.address.slice(0, 6)}...
                          {token.contract.address.slice(-4)}
                        </a>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {data && data.erc20TokenBalances.length === 0 && (
          <div className="bg-gray-50 p-6 rounded-md text-center">
            <p className="text-gray-600">
              No ERC-20 tokens found for this address
            </p>
          </div>
        )}
      </div>
    </main>
  );
}
```

</details>

<details>

<summary>route.ts</summary>

```typescript
import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const walletAddress = searchParams.get("address");

    if (!walletAddress) {
      return NextResponse.json(
        { error: "Wallet address is required" },
        { status: 400 }
      );
    }

    const apiKey = process.env.PRIVATE_KEY;
    const baseUrl = "https://api.subgraph.somnia.network/public_api/data_api";

    const response = await fetch(
      `${baseUrl}/somnia/v1/address/${walletAddress}/balance/erc20`,
      {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      }
    );

    const data = await response.json();

    if (!response.ok) {
      return NextResponse.json(
        { error: "Failed to fetch data from Ormi API", details: data },
        { status: response.status }
      );
    }

    return NextResponse.json(data);
  } catch (error) {
    console.error("API Error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
```

</details>

## Congratulations&#x20;

You have built your first API enabled dApp on the Somnia Network!&#x20;

Now that you have a working Token Balance dApp, you can extend it by using other Ormi API [endpoints](https://subgraphs.somnia.network/).
