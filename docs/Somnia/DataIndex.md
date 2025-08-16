# Indexing Data on Somnia using Graph Services

The blockchain is an ever-growing database of transactions and Smart Contract events. Developers use subgraphs, an indexing solution provided by the Graph protocol, to retrieve and analyze this data efficiently.

A graph in this context represents the structure of blockchain data, including token transfers, contract events, and user interactions. A subgraph is a customized indexing service that listens to blockchain transactions and structures them in a way that can be easily queried using GraphQL.

## Prerequisites

- This guide is not an introduction to Solidity Programming; you are expected to understand Basic Solidity Programming.
- GraphQL is installed and set up on your local machine.&#x20;

```bash
npm install -g @graphprotocol/graph-cli
```

## Deploy a Simple ERC20 Token on Somnia

We will deploy a basic ERC20 token on the Somnia network using Hardhat. Ensure you have Hardhat, OpenZeppelin, and dotenv installed:

```bash
npm install --save-dev hardhat @nomicfoundation/hardhat-ignition-ethers @openzeppelin/contracts dotenv ethers
```

## Create an ERC20 Token Contract

Create a new Solidity file: `contracts/MyToken.sol` and update it

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("MyToken", "MTK") {
        _mint(msg.sender, initialSupply * 10**decimals());
    }
function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
```

## Create a Deployment Script

Create a new file in `ignition/modules/MyTokenModule.ts`

```typescript
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MyTokenModule", (m) => {
  const initialSupply = m.getParameter("initialSupply", 1000000n * 10n ** 18n);

  const myToken = m.contract("MyToken", [initialSupply]);
  return { myToken };
});
```

## Deploy the Smart Contract

Open the hardhat.config.js file and update the network information by adding Somnia Network to the list of networks. Copy your Wallet Address Private Key from MetaMask, and add it to the accounts section. Ensure there are enough STT Token in the Wallet Address to pay for Gas. You can get some from the Somnia Faucet.\

```javascript
module.exports = {
  // ...
  networks: {
    somniaTestnet: {
      url: "https://dream-rpc.somnia.network",
      accounts: ["0xPRIVATE_KEY"], // put dev menomonic or PK here,
    },
  },
  // ...
};
```

Open a new terminal and deploy the smart contract to the Somnia Network. Run the command:

```bash
npx hardhat ignition deploy ./ignition/modules/MyTokenModule.ts --network somniaTestnet

```

This will deploy the ERC20 contract to the Somnia network and return the deployed contract address.

## Simulate On-Chain Activity

Once deployed, we will create a script to generate multiple transactions on the blockchain.

Create a new file `scripts/interact.js`

<details>

<summary><code>interact.js</code></summary>

```javascript
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // Connect to Somnia RPC
  const provider = new ethers.JsonRpcProvider(process.env.SOMNIA_RPC_URL);

  // Load wallets from .env
  const deployer = new ethers.Wallet(process.env.PRIVATE_KEY_1, provider);
  const user1 = new ethers.Wallet(process.env.PRIVATE_KEY_2, provider);
  const user2 = new ethers.Wallet(process.env.PRIVATE_KEY_3, provider);
  const user3 = new ethers.Wallet(process.env.PRIVATE_KEY_4, provider);
  const user4 = new ethers.Wallet(process.env.PRIVATE_KEY_5, provider);

  const contractAddress = "0xBF9516ADc5263d277E2505d4e141F7159B103d33"; // Replace with your deployed contract address
  const abi = [
    "function transfer(address to, uint256 amount) external returns (bool)",
    "function mint(address to, uint256 amount) external",
    "function burn(uint256 amount) external",
  ];

  // Attach to the deployed ERC20 contract
  const token = new ethers.Contract(contractAddress, abi, provider);

  console.log("🏁 Starting Token Transactions Simulation on Somnia...");

  // Simulate Transfers
  const transfers = [
    { from: deployer, to: user1.address, amount: "1000" },
    { from: deployer, to: user2.address, amount: "1000" },
    { from: user1, to: user2.address, amount: "50" },
    { from: user2, to: user3.address, amount: "30" },
    { from: user3, to: user4.address, amount: "10" },
    { from: user4, to: deployer.address, amount: "5" },
    { from: deployer, to: user2.address, amount: "100" },
    { from: user1, to: user3.address, amount: "70" },
    { from: user2, to: user4.address, amount: "40" },
  ];

  for (const tx of transfers) {
    const { from, to, amount } = tx;
    const txResponse = await token
      .connect(from)
      .transfer(to, ethers.parseUnits(amount, 18));
    await txResponse.wait();
    console.log(`✅ ${from.address} sent ${amount} MTK to ${to}`);
  }

  // Simulate Minting
  const mintAmount1 = ethers.parseUnits("500", 18);
  const mintTx1 = await token
    .connect(deployer)
    .mint(user1.address, mintAmount1);
  await mintTx1.wait();
  console.log(`✅ Minted ${ethers.formatUnits(mintAmount1, 18)} MTK to User1!`);

  const mintAmount2 = ethers.parseUnits("300", 18);
  const mintTx2 = await token
    .connect(deployer)
    .mint(user2.address, mintAmount2);
  await mintTx2.wait();
  console.log(`✅ Minted ${ethers.formatUnits(mintAmount2, 18)} MTK to User2!`);

  // Simulate Burning
  const burnAmount1 = ethers.parseUnits("50", 18);
  const burnTx1 = await token.connect(user1).burn(burnAmount1);
  await burnTx1.wait();
  console.log(`🔥 User1 burned ${ethers.formatUnits(burnAmount1, 18)} MTK!`);

  const burnAmount2 = ethers.parseUnits("100", 18);
  const burnTx2 = await token.connect(user2).burn(burnAmount2);
  await burnTx2.wait();
  console.log(`🔥 User2 burned ${ethers.formatUnits(burnAmount2, 18)} MTK!`);

  console.log("🏁 Simulation Complete on Somnia!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

</details>

&#x20;Create an `.env` file to hold sensitive informations such as the private keys

```properties
SOMNIA_RPC_URL=https://dream-rpc.somnia.network
PRIVATE_KEY_1=0x...
PRIVATE_KEY_2=0x...
PRIVATE_KEY_3=0x...
PRIVATE_KEY_4=0x...
PRIVATE_KEY_5=0x...
```

#### Run the Script

```bash
node scripts/interact.js
```

This will generate several on-chain transactions for our subgraph to index.

## Deploy a Subgraph on Somnia

Go to [https://somnia.chain.love/](https://somnia.chain.love/) and connect your Wallet.

<figure><img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nXcOA43Zg4tecvciwgPQxb-dlcBwhPkTGY0POkIQ8JaUdKcaheg-AwetWTR1yFdYSGw_A2c_fm-xuQba6mVDitI_rD7wuazgEsjBjUjxT8-0ELLl9CW0JFlzNuPLHlZYXKy7VP16_A?key=ZDOrGANolV8eE-n5bJ-_qrWy" alt=""><figcaption></figcaption></figure>

First, you need to create a private key for deploying subgraphs. To do so, please go to [Somnia Protofire Service](https://somnia.chain.love) and create an Account.

You are now able to create subgraphs. Click the create button and enter the required details.

<figure><img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nXdbWSqj7ddwv0yFj8FlHdDGGlJmeqmRakTRUNX2LUCUHlqPjcK2eSBdRwnwwZ5pq8T-3op10MJwdknOn-KfCDbsJ4nuI7Uu39obkcb8gYfVTlRhrt1s4IJ3U7VNgEnMW0mMN7hK6w?key=ZDOrGANolV8eE-n5bJ-_qrWy" alt=""><figcaption></figcaption></figure>

<figure><img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nXex3AIr44-pbEiLznhnQE0xhOYHgtOmwRyu8HwXjFWsTQLM9JtyFD10YPZdDxY0qFNVC2JUqt_29q8VtSmV0emS8VVOZrF4VfYUUxmqQM3yF-_c29E9vQaRfvVoV7Guu6AkI8mgUw?key=ZDOrGANolV8eE-n5bJ-_qrWy" alt=""><figcaption></figcaption></figure>

After initialising the subgraph on [https://somnia.chain.love/](https://somnia.chain.love/) the next step is to create and deploy the subgraph via the terminal.

## Initialize the Subgraph

```bash
graph init --contract-name MyToken --from-contract 0xYourTokenAddress --network somnia-testnet mytoken
```

<figure><img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nXeFtlgKbMC4sCBfwGl1xI76iHiOxsc7jKZtg9BUeMGiTsormp5HRYnreVlo4cpuZe23eESQT9pgbCdf9dQ4lKw_-fjsBwPLd-DZd-o_Gc3BA9VxjE95i05yuXDacPmNBbwsEvvvbA?key=ZDOrGANolV8eE-n5bJ-_qrWy" alt=""><figcaption></figcaption></figure>

Then, update networks.json to use Somnia’s RPC

```bash
{
  "somnia-testnet": {
    "network": "Somnia Testnet",
    "rpc": "https://dream-rpc.somnia.network",
    "startBlock": 12345678
  }
}
```

## Define the Subgraph Schema

📁 Edit schema.graphql

```bash
type Transfer @entity(immutable: true) {
  id: Bytes!
  from: Bytes!
  to: Bytes!
  value: BigInt!
  blockNumber: BigInt!
  blockTimestamp: BigInt!
  transactionHash: Bytes!
}
```

## Build the Subgraph

```bash
graph codegen
graph build
```

## Deploy the Subgraph

```bash
graph deploy --node https://proxy.somnia.chain.love/graph/somnia-testnet --version-label 0.0.1 somnia-testnet/test-mytoken
--access-token=your_token_from_somnia_chain_love
```

<figure><img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nXfc-Mu-wBk_mvxbW4Rz6ODZK_RtWPtTxDjKcldwtudapplfGjxVMZTGS_xzX73VOp_XcRCiicQsA-q7yXG0x8Tz6vyCeTU1Lw08Kmi8rbZlWapYgskmfWXgHo3t2Rgypy3x3cfd0A?key=ZDOrGANolV8eE-n5bJ-_qrWy" alt=""><figcaption></figcaption></figure>

## Query the Subgraph

Once your subgraph is deployed and indexing blockchain data on Somnia, you can retrieve information using GraphQL queries. These queries allow you to efficiently access structured data such as token transfers, approvals, and contract interactions without having to scan the blockchain manually.

Developers can query indexed blockchain data in real time using the Graph Explorer or a GraphQL client. This enables DApps, analytics dashboards, and automated systems to interact more efficiently with blockchain events.

This section demonstrates how to write and execute GraphQL queries to fetch blockchain data indexed by the subgraph. Go to [https://somnia.chain.love/graph/17](https://somnia.chain.love/graph/17)&#x20;

### Fetch Latest Transfers

```json
{
  transfers(first: 10, orderBy: blockTimestamp, orderDirection: desc) {
    id
    from
    to
    value
    blockTimestamp
    transactionHash
  }
}
```

### Get Transfers by Address

```json
{
  transfers(where: { from: "0xUserWalletAddress" }) {
    id
    from
    to
    value
  }
}
```

### Get Transfers in a Time Range

```
{
  transfers(where: { blockTimestamp_gte: "1700000000", blockTimestamp_lte: "1710000000" }) {
    id
    from
    to
    value
  }
}
```

## Conclusion

This tutorial provides a complete pipeline for indexing blockchain data on Somnia using The Graph! 🔥

\
