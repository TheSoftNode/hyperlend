# Build a Live Crypto Price dApp Using Protofire Oracle

## Available Price Feed Contracts on Somnia Testnet

<table data-header-hidden><thead><tr><th></th><th width="456.400390625"></th></tr></thead><tbody><tr><td>Token Pair</td><td>Contract Address</td></tr><tr><td>USDC/USD</td><td>0xa2515C9480e62B510065917136B08F3f7ad743B4</td></tr><tr><td>ETH/USD</td><td>0xd9132c1d762D432672493F640a63B758891B449e</td></tr><tr><td>BTC/USD</td><td>0x8CeE6c58b8CbD8afdEaF14e6fCA0876765e161fE</td></tr></tbody></table>

Use any of these when deploying the PriceConsumer Smart Contract for your dApp.

## What Are Oracles and Why Do They Matter

This service is powered by Protofire, an infrastructure provider that integrates decentralized oracle networks for Somnia. Learn more at[ protofire.io](https://protofire.io/services/solution/oracle-integration).

Oracles are critical infrastructure in the blockchain ecosystem that enable Smart Contracts to interact with real-world data. Blockchains are deterministic by design and cannot fetch off-chain information directly. This creates a need for oracles, which are trusted data feeds that can push external data, like market prices, sports scores, or weather conditions, into Smart Contracts.

Chainlink is the most widely adopted decentralized oracle network. It allows developers to access reliable data feeds that are resistant to manipulation and downtime. In this tutorial, we focus on Protofire Chainlink Price Feeds, which provide real-time market prices for assets like ETH, BTC, and USDC on Somnia

Smart Contracts that rely on accurate pricing (e.g., lending, trading, insurance) benefit immensely from using decentralized oracles like Protofire. Oracles unlock use cases that were previously impossible due to blockchain isolation.

In this guide, we will build a live crypto price tracker that displays BTC/USD, ETH/USD, and USDC/USD using Protofire Chainlink Price Feeds deployed on the Somnia Testnet.

## Prerequisites

1. This guide is not an introduction to JavaScript Programming; you are expected to understand JavaScript.
2. Basic knowledge of React & Next.js.

### Solidity Contract (Chainlink Oracle Consumer)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
contract PriceConsumer {
    AggregatorV3Interface internal priceFeed;
    constructor(address _priceFeed) {
    priceFeed = AggregatorV3Interface(_priceFeed);
    }

     /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int256) {
        (
        /* uint80 roundID */,
            int256 price,
            /* uint startedAt */,
            /* uint timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        return price;
}

 /**
     * Returns price decimals
     */
    function getDecimals() public view returns (uint8) {
        return priceFeed.decimals();
    }
}
```

### Code Breakdown

```solidity
import `@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol
```

Pulls in the AggregatorV3Interface from the Chainlink library. This interface allows interaction with Chainlink oracle contracts for Price Feeds.

```solidity
constructor(address _priceFeed) { }
```

The contract's constructor runs once when the contract is deployed. It takes the address of the Protofire Chainlink Price Feed contract and stores it.

```solidity
priceFeed = AggregatorV3Interface(_priceFeed);
```

Instantiates the interface with the provided address, enabling function calls to the external oracle.

```solidity
function getLatestPrice() public view returns (int256) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint startedAt */,
            /* uint timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        return price;
}
```

`getLatestPrice()` is a public function which is callable from outside the contract. It does not modify blockchain state and returns the latest price from the Chainlink feed. It calls the Chainlink function **`latestRoundData()`** which returns a 5-value tuple:

```solidity
(uint80 roundId, int256 price, uint startedAt, uint timeStamp, uint80 answeredInRound)
```

This function extracts only the price and ignores the rest using commas. It returns the latest price as an int256.

```solidity
function getDecimals() public view returns (uint8) {
        return priceFeed.decimals();
    }
```

`getDecimals()` is a helper function to return the number of decimals used by the price feed. Ensures consumers of the contract know how to scale the price properly.

## How Price Oracle latestRoundData() works

It's helpful to understand how the Price Feed data is structured.

The function `latestRoundData()` from the Chainlink Aggregator interface returns the following tuple:

```solidity
(uint80 roundId, int256 answer, uint startedAt, uint timeStamp, uint80 answeredInRound)
```

- `roundId`: The current round number for the feed
- `price`: The actual price value (e.g. ETH/USD = 1900.42 × 10^8)
- `startedAt`: Timestamp when this round started
- `timeStamp`: When the answer was last updated
- `answeredInRound`: The round in which the answer was submitted\

Most price consumer contracts use only `price`, but for more robust designs, `timeStamp` can be checked to ensure the price is recent.

Additionally, Protofire Chainlink Price Feeds often return prices with 8 decimals. This means the raw price value needs to be normalized by dividing it by 10 \*\* decimals. This is essential because Solidity doesn't support floating-point math. Prices are represented using fixed-point math.

For example, if ETH/USD is $1,940.82 and the feed uses 8 decimals, the returned price would be 194082000000. You must divide by 10 \*\* 8 to display $1940.82 in your UI.

Always use the `getDecimals()` method provided by the Aggregator interface to dynamically adjust for different feeds that may use 6, 8, or 18 decimals depending on the asset.

## Deploy with Hardhat

Update ignition/modules/deploy.js:

```typescript
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PriceConsumerModule = buildModule("PriceConsumerModule", (m) => {
  // Replace this with the correct feed address for your chosen pair
  const feedAddress = m.getParameter(
    "feedAddress",
    "0xd9132c1d762D432672493F640a63B758891B449e" // Example: ETH/USD on Somnia
  );

  const priceConsumer = m.contract("PriceConsumer", [feedAddress]);

  return { priceConsumer };
});

export default PriceConsumerModule;
```

Deploy using:

```bash
npx hardhat ignition deploy ./ignition/modules/Lock.js --network somnia
```

## Building the UI

Now that we’ve deployed the contract and confirmed it fetches live price data from Somnia’s Protofire Oracles, let’s bring it to life with a clean and responsive UI. We’ll use React and Viem.js to build a real-time dashboard that displays crypto prices with auto-refresh and token selection.&#x20;

Start by creating a new Next.js app.

```bash
npx create-next-app@latest somnia-protofire-example
cd somnia-protofire-example
```

Then, install required dependencies.

```bash
npm install viem
```

Add imports to the `index.js` file

```typescript
import { useEffect, useState } from "react";
import { createPublicClient, http, parseAbi, formatUnits } from "viem";
import { somniaTestnet } from "viem/chains";
```

- useEffect, useState: React hooks for lifecycle and state management.
- createPublicClient: Creates a read-only client to interact with the blockchain.
- http: Defines the transport layer for the client (uses Somnia RPC).
- parseAbi: Parses the contract's ABI.
- formatUnits: Converts big numbers (like token prices) to a human readable format.s.

#### Create a Viem Client for Somnia

```typescript
const client = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});
```

Creates a blockchain client configured for Somnia Testnet using its RPC URL and allows reading smart contract data without needing a wallet or signer.

#### Declare a variable for the deployed Smart Contracts for your Price Feed Addresses

```typescript
const FEEDS = {
  ETH: "0x604CF5063eC760A78d1C089AA55dFf29B90937f9",
  BTC: "0x3dF17dbaa3BA861D03772b501ADB343B4326C676",
  USDC: "0xA4a08Eb26f85A53d40E3f908B406b2a69B1A2441",
};
```

This will map token pairs to their corresponding Chainlink oracle contract addresses deployed on Somnia.\

Parse the ABI

```typescript
const abi = parseAbi([
  "function getLatestPrice() view returns (int256)",
  "function getDecimals() view returns (uint8)",
]);
```

#### Set up the State

```typescript
export default function PriceWidget() {
  const [price, setPrice] = useState('');
  const [selectedToken, setSelectedToken] = useState<'ETH' | 'BTC' | 'USDC'>('ETH');
```

The `price` state will store the formatted token price and `selectedToken` will track which token is selected from the dropdown (default: ETH).

#### Fetch the Latest Price

```typescript
const fetchPrice = async () => {
  const contractAddress = FEEDS[selectedToken];
  const [rawPrice, decimals] = await Promise.all([
    client.readContract({
      address: contractAddress,
      abi,
      functionName: "getLatestPrice",
    }),
    client.readContract({
      address: contractAddress,
      abi,
      functionName: "getDecimals",
    }),
  ]);

  const normalized = formatUnits(rawPrice, decimals);
  setPrice(parseFloat(normalized).toFixed(2));
};
```

Reads the price and its decimal precision from the Chainlink oracle contract. The function declaration uses `Promise.all()` to optimize performance by fetching both at once and formats the price to 2 decimal places for display.

#### Fetch Price on Load & Every 10 Seconds

```typescript
useEffect(() => {
  fetchPrice();
  const interval = setInterval(fetchPrice, 10000);
  return () => clearInterval(interval);
}, [selectedToken]);
```

The `useEffect` hook runs `fetchPrice()`, once on component mount and every time `selectedToken` changes. The hook also refreshes price data every 10 seconds

Live Price Display in the `return` statement.

```typescript
return (
        <p>${price}</p>
```

## Complete Code

<details>

<summary>index.js</summary>

```typescript
import { useEffect, useState } from "react";
import { createPublicClient, http, parseAbi, formatUnits } from "viem";
import { somniaTestnet } from "viem/chains";

const client = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});

const FEEDS = {
  ETH: "0x604CF5063eC760A78d1C089AA55dFf29B90937f9",
  BTC: "0x3dF17dbaa3BA861D03772b501ADB343B4326C676",
  USDC: "0xA4a08Eb26f85A53d40E3f908B406b2a69B1A2441",
};

const abi = parseAbi([
  "function getLatestPrice() view returns (int256)",
  "function getDecimals() view returns (uint8)",
]);

export default function PriceWidget() {
  const [price, setPrice] = useState("");
  const [selectedToken, setSelectedToken] = useState<"ETH" | "BTC" | "USDC">(
    "ETH"
  );

  const fetchPrice = async () => {
    const contractAddress = FEEDS[selectedToken];
    const [rawPrice, decimals] = await Promise.all([
      client.readContract({
        address: contractAddress,
        abi,
        functionName: "getLatestPrice",
      }),
      client.readContract({
        address: contractAddress,
        abi,
        functionName: "getDecimals",
      }),
    ]);

    const normalized = formatUnits(rawPrice, decimals);
    setPrice(parseFloat(normalized).toFixed(2));
  };

  useEffect(() => {
    fetchPrice();
    const interval = setInterval(fetchPrice, 10000);
    return () => clearInterval(interval);
  }, [selectedToken]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center p-6 border border-gray-200 rounded-lg shadow-lg bg-white max-w-sm w-full">
        <h3 className="text-2xl font-bold mb-4 text-gray-800">
          {selectedToken}/USD on Somnia
        </h3>
        <select
          value={selectedToken}
          onChange={(e) =>
            setSelectedToken(e.target.value as "ETH" | "BTC" | "USDC")
          }
          className="mb-6 px-4 py-2 border border-gray-300 rounded-md w-full text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="ETH">ETH/USD</option>
          <option value="BTC">BTC/USD</option>
          <option value="USDC">USDC/USD</option>
        </select>
        <p className="text-4xl font-semibold text-blue-600">${price}</p>
      </div>
    </div>
  );
}
```

</details>

## Conclusion

The Protofire Oracle integration on Somnia provides developers with reliable, on-chain price feeds for key assets like ETH, BTC, and USDC. By using verified oracles and standardized data formats, it enables accurate, real-time pricing essential for building GaemFi, DeFi, trading, and financial applications.

\
