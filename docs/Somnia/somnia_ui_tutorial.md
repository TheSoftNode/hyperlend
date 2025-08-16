# Building a UI for Subgraph Queries on Somnia

This guide demonstrates how to create a minimal, functional UI that queries blockchain data from a Somnia subgraph using Next.js, Apollo Client, and GraphQL.

## Prerequisites

- Basic knowledge of React and Next.js
- Node.js installed (v16 or higher)
- A deployed subgraph on Somnia (example uses [SomFlip](https://shannon-explorer.somnia.network/address/0x014F851965F281d6112FC7F6dfe8c331C413Eb9b))

## Project Overview

The UI will provide:
- Display all coin flip results with pagination
- Live feed that auto-refreshes every 5 seconds

## Architecture Flow

```
User Interface (React Components)
↓
Apollo Client (GraphQL Client)
↓
GraphQL Queries
↓
Somnia Subgraph API
↓
Blockchain Data
```

## Setup Instructions

### 1. Create Next.js Project

```bash
npx create-next-app@latest somnia-subgraph-ui --typescript --tailwind --app
cd somnia-subgraph-ui
```

### 2. Install Dependencies

```bash
npm install @apollo/client graphql
```

## Code Implementation

### Apollo Client Configuration

**File: `lib/apollo-client.ts`**

```typescript
import { ApolloClient, InMemoryCache } from '@apollo/client';

const client = new ApolloClient({
  // The URI of your subgraph endpoint
  uri: 'https://proxy.somnia.chain.love/subgraphs/name/somnia-testnet/SomFlip',
  // Apollo's caching layer - stores query results
  cache: new InMemoryCache(),
});

export default client;
```

### Apollo Provider Wrapper

**File: `components/ApolloWrapper.tsx`**

```typescript
'use client'; // Next.js 13+ directive for client-side components

import { ApolloProvider } from '@apollo/client';
import client from '@/lib/apollo-client';

// This component wraps your app with Apollo's context provider
export default function ApolloWrapper({
  children
}: {
  children: React.ReactNode
}) {
  return (
    <ApolloProvider client={client}>
      {children}
    </ApolloProvider>
  );
}
```

### Layout Update

**File: `app/layout.tsx`**

```typescript
import ApolloWrapper from '@/components/ApolloWrapper';

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <ApolloWrapper>
          {children}
        </ApolloWrapper>
      </body>
    </html>
  );
}
```

### GraphQL Queries

**File: `lib/queries.ts`**

```typescript
import { gql } from '@apollo/client';

// Query for paginated flip results
export const GET_FLIP_RESULTS = gql`
  query GetFlipResults($first: Int!, $skip: Int!, $orderBy: String!, $orderDirection: String!) {
    flipResults(
      first: $first
      skip: $skip
      orderBy: $orderBy
      orderDirection: $orderDirection
    ) {
      id
      user
      amount
      guess
      result
      won
      blockNumber
      blockTimestamp
      transactionHash
    }
  }
`;

// Query for recent flips (live feed)
export const GET_RECENT_FLIPS = gql`
  query GetRecentFlips($first: Int!) {
    flipResults(
      first: $first
      orderBy: blockTimestamp
      orderDirection: desc
    ) {
      id
      user
      amount
      guess
      result
      won
      blockNumber
      blockTimestamp
      transactionHash
    }
  }
`;
```

**Key GraphQL Notes:**
- `gql` is the template literal tag that parses GraphQL queries
- Variables start with `$` and have types (`Int!`, `String!`, etc.)
- `!` means the field is required (non-nullable)

### All Flips Component

**File: `components/AllFlips.tsx`**

```typescript
'use client';

import { useState } from 'react';
import { useQuery } from '@apollo/client';
import { GET_FLIP_RESULTS } from '@/lib/queries';

// Utility Functions
// Shortens long blockchain addresses for display
// Example: "0x1234567890abcdef" becomes "0x1234...cdef"
const truncateHash = (hash: string) => {
  return `${hash.slice(0, 6)}...${hash.slice(-4)}`;
};

// Converts wei (smallest unit) to ether (display unit)
// 1 ether = 1,000,000,000,000,000,000 wei (10^18)
const formatEther = (wei: string) => {
  const ether = parseFloat(wei) / 1e18;
  return ether.toFixed(4); // Show 4 decimal places
};

// Converts Unix timestamp to readable date
// Blockchain stores time as seconds since Jan 1, 1970
const formatTime = (timestamp: string) => {
  const milliseconds = parseInt(timestamp) * 1000;
  const date = new Date(milliseconds);
  return date.toLocaleString();
};

export default function AllFlips() {
  // Track which page of results we're viewing
  const [page, setPage] = useState(0);
  const itemsPerPage = 30;

  // Execute the GraphQL Query
  const { loading, error, data } = useQuery(GET_FLIP_RESULTS, {
    variables: {
      first: itemsPerPage, // How many results to fetch
      skip: page * itemsPerPage, // How many to skip
      orderBy: 'blockTimestamp', // Sort by time
      orderDirection: 'desc', // Newest first
    },
  });

  // Handle Query States
  // Show loading spinner while fetching
  if (loading) {
    return <div className="text-center py-8 text-gray-500">Loading...</div>;
  }

  // Show error message if query failed
  if (error) {
    return (
      <div className="text-center py-8 text-red-500">
        Error: {error.message}
      </div>
    );
  }

  // Check if we have results
  if (!data?.flipResults?.length) {
    return <div className="text-center py-8 text-gray-500">No flips found</div>;
  }

  // Render the Table View
  return (
    <div className="max-w-6xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">All Coin Flips</h1>
      
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white border border-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                User
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Amount (ETH)
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Guess
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Result
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Won
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Time
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Tx Hash
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {data.flipResults.map((flip: any) => (
              <tr key={flip.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900">
                  {truncateHash(flip.user)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {formatEther(flip.amount)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {flip.guess ? 'Heads' : 'Tails'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {flip.result ? 'Heads' : 'Tails'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                    flip.won 
                      ? 'bg-green-100 text-green-800' 
                      : 'bg-red-100 text-red-800'
                  }`}>
                    {flip.won ? 'Won' : 'Lost'}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {formatTime(flip.blockTimestamp)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-mono text-blue-600">
                  <a 
                    href={`https://shannon-explorer.somnia.network/tx/${flip.transactionHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:underline"
                  >
                    {truncateHash(flip.transactionHash)}
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Pagination Controls */}
      <div className="flex justify-between items-center mt-6">
        <button
          onClick={() => setPage(Math.max(0, page - 1))}
          disabled={page === 0}
          className="px-4 py-2 bg-blue-500 text-white rounded disabled:bg-gray-300"
        >
          Previous
        </button>
        
        <span className="text-gray-700">
          Page {page + 1}
        </span>
        
        <button
          onClick={() => setPage(page + 1)}
          disabled={data.flipResults.length < itemsPerPage}
          className="px-4 py-2 bg-blue-500 text-white rounded disabled:bg-gray-300"
        >
          Next
        </button>
      </div>
    </div>
  );
}
```

### Live Feed Component

**File: `components/LiveFeed.tsx`**

```typescript
'use client';

import { useQuery } from '@apollo/client';
import { GET_RECENT_FLIPS } from '@/lib/queries';

// Utility Functions (same as AllFlips)
const truncateHash = (hash: string) => {
  return `${hash.slice(0, 6)}...${hash.slice(-4)}`;
};

const formatEther = (wei: string) => {
  return (parseFloat(wei) / 1e18).toFixed(4);
};

const formatTime = (timestamp: string) => {
  const milliseconds = parseInt(timestamp) * 1000;
  const date = new Date(milliseconds);
  return date.toLocaleString();
};

export default function LiveFeed() {
  // Execute query with automatic polling
  const { loading, error, data } = useQuery(GET_RECENT_FLIPS, {
    variables: {
      first: 10 // Get 10 most recent flips
    },
    pollInterval: 5000, // Refresh every 5 seconds (5000ms)
  });

  // Handle Query States (same as AllFlips)
  if (loading) {
    return <div className="text-center py-8 text-gray-500">Loading...</div>;
  }

  if (error) {
    return <div className="text-center py-8 text-red-500">Error: {error.message}</div>;
  }

  if (!data?.flipResults?.length) {
    return <div className="text-center py-8 text-gray-500">No recent flips</div>;
  }

  return (
    <div className="max-w-4xl mx-auto p-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold">Live Feed</h1>
        <div className="flex items-center text-sm text-gray-500">
          <div className="w-2 h-2 bg-green-400 rounded-full mr-2 animate-pulse"></div>
          Updates every 5 seconds
        </div>
      </div>

      <div className="space-y-4">
        {data.flipResults.map((flip: any) => (
          <div 
            key={flip.id} 
            className="bg-white border border-gray-200 rounded-lg p-4 shadow-sm hover:shadow-md transition-shadow"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-4">
                <div className={`w-3 h-3 rounded-full ${flip.won ? 'bg-green-500' : 'bg-red-500'}`}></div>
                <span className="font-mono text-sm">{truncateHash(flip.user)}</span>
                <span className="text-gray-600">flipped {formatEther(flip.amount)} ETH</span>
              </div>
              
              <div className="text-right">
                <div className="text-sm text-gray-500">{formatTime(flip.blockTimestamp)}</div>
                <div className={`text-sm font-semibold ${flip.won ? 'text-green-600' : 'text-red-600'}`}>
                  {flip.won ? '🎉 Won' : '💸 Lost'}
                </div>
              </div>
            </div>
            
            <div className="mt-2 text-sm text-gray-600">
              Guessed: <span className="font-medium">{flip.guess ? 'Heads' : 'Tails'}</span>
              {' • '}
              Result: <span className="font-medium">{flip.result ? 'Heads' : 'Tails'}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
```

**Key Live Feed Features:**
- `pollInterval: 5000` automatically re-executes the query every 5 seconds
- New flips appear without user interaction
- Apollo Client handles the refresh logic
- Set to 0 or remove to disable auto-refresh
- Visual emphasis on win/loss status
- No pagination (shows most recent only)

### Main Page Update

**File: `app/page.tsx`**

```typescript
import AllFlips from '@/components/AllFlips';
import LiveFeed from '@/components/LiveFeed';

export default function Home() {
  return (
    <div className="min-h-screen bg-gray-50">
      <div className="container mx-auto py-8">
        <LiveFeed />
        <div className="my-8 border-t border-gray-200"></div>
        <AllFlips />
      </div>
    </div>
  );
}
```

## Running the Application

```bash
npm run dev
```

Visit `http://localhost:3000` to see your UI in action.

## Key Concepts Explained

### Apollo Client Features
- **Data Fetching**: Handles GraphQL queries and mutations
- **Caching**: Stores query results in memory for fast access
- **State Management**: Manages loading, error, and data states
- **Polling**: Automatic refresh of queries at set intervals

### GraphQL Query Structure
- **Variables**: Dynamic values passed to queries (prefixed with `$`)
- **Types**: Strong typing with `Int!`, `String!`, etc.
- **Required Fields**: `!` suffix indicates non-nullable fields
- **Ordering**: `orderBy` and `orderDirection` for sorting results

### Component Architecture
- **Separation of Concerns**: Utility functions, state management, and rendering are clearly separated
- **Error Handling**: Graceful handling of loading, error, and empty states
- **Responsive Design**: TailwindCSS classes for mobile-friendly layouts

### Blockchain Data Handling
- **Wei to Ether Conversion**: Blockchain amounts stored in smallest units
- **Address Truncation**: Long addresses shortened for display
- **Timestamp Formatting**: Unix timestamps converted to readable dates
- **Transaction Links**: Direct links to blockchain explorer

This tutorial provides a complete foundation for building blockchain data interfaces using modern web technologies and GraphQL.