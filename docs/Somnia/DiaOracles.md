# Integrating DIA Oracles on Somnia

## **Overview**

[DIA](https://docs.diadata.org/) Oracles provide **secure, customizable, and decentralized price feeds** that can be integrated into **smart contracts on the Somnia Testnet**. This guide will walk you through how to access **on-chain price data**, understand the oracle’s functionality, and integrate it into your **Solidity Smart Contracts**.

## **Oracle Details**

### **Contracts on Somnia Testnet**

DIA Oracle contract address:

```
0x9206296Ea3aEE3E6bdC07F7AaeF14DfCf33d865D
```

### **Oracle Configuration**

- **Pricing Methodology:** MAIR
- **Deviation Threshold:** 0.5% (Triggers price update if exceeded)
- **Refresh Frequency:** Every 120 seconds
- **Heartbeat:** Forced price update every 24 hours

### **Supported Asset Feeds**

| Asset    | Adapter Address                              |
| -------- | -------------------------------------------- |
| **USDT** | `0x67d2C2a87A17b7267a6DBb1A59575C0E9A1D1c3e` |
| **USDC** | `0x235266D5ca6f19F134421C49834C108b32C2124e` |
| **BTC**  | `0x4803db1ca3A1DA49c3DB991e1c390321c20e1f21` |
| **ARB**  | `0x74952812B6a9e4f826b2969C6D189c4425CBc19B` |
| **SOL**  | `0xD5Ea6C434582F827303423dA21729bEa4F87D519` |

## **How the Oracle Works**

DIA oracles continuously fetch and push asset prices **on-chain** using an **oracleUpdater**, which operates within the `DIAOracleV2` contract. The oracle uses **predefined update intervals** and **deviation thresholds** to determine when price updates are necessary.

<figure><img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nXelAe-nl93fR4uUB8OHaecQRpe5DuDvy7k-1aMyk_8B1DHX2OzmpuZ00anBlexvcuGcg7oilXmYzTBxTDAeGwdytZmbZicu9yKYhz9rgYPh8SCbuEzia98yvw8F77FUVGWdr7vMJg?key=lW9QgbGCuFAGhXIdiB9dWgLT" alt=""><figcaption></figcaption></figure>

Each asset price feed has an adapter contract, allowing access through the AggregatorV3Interface. You can use the methods `getRoundData` and `latestRoundData` to fetch pricing information. Learn more [here](https://nexus.diadata.org/how-to-guides/migrate-to-dia).

## **Using the Solidity Library**

DIA has a dedicated Solidity library to facilitate the integration of DIA oracles in your own contracts. The library consists of two functions, `getPrice` and `getPriceIfNotOlderThan`.

### Access the library <a href="#access-the-library" id="access-the-library"></a>

```
import { DIAOracleLib } from "./libraries/DIAOracleLib.sol";
```

### `getPrice`

```
function getPrice(
        address oracle,
        string memory key
        )
        public
        view
        returns (uint128 latestPrice, uint128 timestampOflatestPrice);
```

**Returns the price of a specified asset along with the update timestamp**.

### **`getPriceIfNotOlderThan`**

```
function getPriceIfNotOlderThan(
        address oracle,
        string memory key,
        uint128 maxTimePassed
        )
        public
        view
        returns (uint128 price, bool inTime)
    {
```

**Checks if the oracle price is older than `maxTimePassed`**

[**Full Example on DIA Docs**](https://nexus.diadata.org/how-to-guides/fetch-price-data/solidity)

## Using DIAOracleV2 Interface

The following contract provides an integration example of retrieving prices and verifying price age.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IDIAOracleV2 {
    function getValue(string memory) external view returns (uint128,
             uint128);
}

contract DIAOracleSample {

    address diaOracle;

    constructor(address _oracle) {
        diaOracle = _oracle;
    }

    function getPrice(string memory key)
    external
    view
    returns (
        uint128 latestPrice,
        uint128 timestampOflatestPrice
    ) {
        (latestPrice, timestampOflatestPrice) =
                 IDIAOracleV2(diaOracle).getValue(key);
    }
}
```

## **Glossary**

| Term                  | Definition                                                            |
| --------------------- | --------------------------------------------------------------------- |
| **Deviation**         | Percentage threshold that triggers a price update when exceeded.      |
| **Refresh Frequency** | Time interval for checking and updating prices if conditions are met. |
| **Trade Window**      | Time interval used to aggregate trades for price calculation.         |
| **Heartbeat**         | Forced price update at a fixed interval.                              |

## **Support**

If you need further assistance integrating DIA Oracles, reach out through DIA’s[ official documentation](https://docs.diadata.org/) and ask your questions in the #dev-support channel on [Discord](https://discord.com/invite/somnia).

Developers can build secure, real-time, and on-chain financial applications with reliable pricing data by integrating DIA Oracles on Somnia.
