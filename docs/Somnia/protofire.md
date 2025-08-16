# Verifiable Randomness on Somnia using Protofire Chainlink VRF v2.5

Protofire Chainlink’s Verifiable Random Function (VRF) allows developers to securely request random numbers in a tamper-proof and auditable way. It is ideal for gaming, NFT mints, and lotteries. This tutorial walks you through integrating Protofire's Chainlink VRF v2.5 on Somnia Network, using native STT (Somnia Token) as the payment currency.

## Understanding VRF and Why It Matters

Randomness is essential for many blockchain applications, such as Games, Lotteries, Raffles, and NFT drops, but blockchains are deterministic by nature. This means every node must produce the same output given the same inputs. If you try to use on-chain data like `block.timestamp` or `blockhash` as a random source, miners/validators can manipulate these values to influence the outcome. This is where VRF comes in.

### What is VRF?

A Verifiable Random Function (VRF) is a cryptographic method of generating random numbers along with a proof that the result was not tampered with. When using Protofire Chainlink VRF:

1. You request a random number from the VRF service.
2. Protofire Chainlink’s decentralized oracle network generates a random value off-chain along with a cryptographic proof.
3. The proof is verified on-chain before the value is returned to your contract.

This ensures tamper-proof randomness and publicly verifiable results. Where the outcomes are fair.

### Why is VRF important on blockchain?

Without VRF, randomness in blockchain apps can be gamed. With VRF:

- No single party can manipulate the results
- Users can independently verify the randomness
- Applications gain trust from players, participants, and investors

Requesting VRF Data using Protofire Chainlink services relies on two methods: Subscription and Direct Funding

In the Subscription method, Chainlink VRF requests receive funding from subscription accounts. The [Subscription Manager](https://vrf.chain.link/) lets you create an account and pre-pay for your use of Chainlink VRF requests. You can learn more about the subscription method by referencing the Chainlink [documentation](https://docs.chain.link/vrf/v2-5/overview/subscription).\
\
The Direct Funding method doesn't require a subscription and is optimal for one-off requests for randomness. This method also works best for applications where your end-users must pay the fees for VRF because the cost of the request is determined at request time. [Learn more](https://docs.chain.link/vrf/v2-5/overview/direct-funding).\

In this guide, we will build a Smart Contract called `RandomNumberConsumer` that:

- Inherits the [Protofire Chainlink VRF Wrapper](https://shannon-explorer.somnia.network/address/0x763cC914d5CA79B04dC4787aC14CcAd780a16BD2).
- Requests 3 secure random numbers
- Pays for randomness using native STT (no LINK subscription required)
- Emits events and exposes functions to retrieve the randomness
- Handles overpayments and pending request checks

## Prerequisites

Before getting started:

- You are familiar with Solidity (v0.8+)
- You have the VRF Wrapper address for [Protofire ChainLink VRF Wrapper](https://shannon-explorer.somnia.network/address/0x763cC914d5CA79B04dC4787aC14CcAd780a16BD2)

## TL;DR

1. Owner calls `requestRandomNumber()` and sends enough STT `(msg.value)` to cover the fee.
2. Contract uses **VRF Wrapper** to request 3 random words (in native STT).
3. When VRF is ready, the wrapper calls `fulfillRandomWords`, the contract:
   1. verifies the request,
   2. stores the 3 words,
   3. toggles `fulfilled = true`,
   4. emits RandomNumberFulfilled.
4. User Interfaces and Scripts can read `getLatestRandomWord()` or poll `getRequestStatus()`.

<details>

<summary>EXAMPLE - RandomNumberConsumer.sol</summary>

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts@1.4.0/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts@1.4.0/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts@1.4.0/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import {ConfirmedOwner} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/ConfirmedOwner.sol";

contract RandomNumberConsumer is VRFV2PlusWrapperConsumerBase, ConfirmedOwner {
    uint256 public latestRequestId;
    uint256[] public latestRandomWord;
    bool public fulfilled;

    uint32 public constant CALLBACK_GAS_LIMIT = 2_100_000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 3;

    event RandomNumberRequested(uint256 indexed requestId, address indexed requester, uint256 paid);
    event RandomNumberFulfilled(uint256 indexed requestId, uint256[] randomWord);

    error InsufficientPayment(uint256 required, uint256 sent);
    error RequestAlreadyPending();

    constructor(address wrapper)
        ConfirmedOwner(msg.sender)
        VRFV2PlusWrapperConsumerBase(wrapper)
    {}

    function requestRandomNumber() external payable onlyOwner {
        // Check if there's already a pending request
        if (latestRequestId != 0 && !fulfilled) {
            revert RequestAlreadyPending();
        }

        // Calculate the required payment
        uint256 requestPrice = getRequestPrice();
        if (msg.value < requestPrice) {
            revert InsufficientPayment(requestPrice, msg.value);
        }

        // Prepare the extra arguments for native payment
        VRFV2PlusClient.ExtraArgsV1 memory extraArgs = VRFV2PlusClient.ExtraArgsV1({
            nativePayment: true
        });
        bytes memory args = VRFV2PlusClient._argsToBytes(extraArgs);

        // Request randomness
        (uint256 requestId, uint256 paid) = requestRandomnessPayInNative(
            CALLBACK_GAS_LIMIT,
            REQUEST_CONFIRMATIONS,
            NUM_WORDS,
            args
        );

        latestRequestId = requestId;
        fulfilled = false;

        emit RandomNumberRequested(requestId, msg.sender, paid);

        // Refund excess payment
        if (msg.value > paid) {
            (bool success, ) = msg.sender.call{value: msg.value - paid}("");
            require(success, "Refund failed");
        }
    }

    // This will be called by the VRF Wrapper
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
    require(randomWords.length > 0, "No random word returned");
    require(requestId == latestRequestId, "Unexpected request ID");
    latestRandomWord = randomWords;
    fulfilled = true;

      emit RandomNumberFulfilled(requestId, randomWords);
    }

    function getRequestStatus() external view returns (
        uint256 requestId,
        bool isPending,
        bool isFulfilled
    ) {
        return (
            latestRequestId,
            latestRequestId != 0 && !fulfilled,
            fulfilled
        );
    }

    function getLatestRandomWord() external view returns (uint256[] memory) {
        require(fulfilled, "No fulfilled request yet");
        return latestRandomWord;
    }

    /**
     * @notice Get the current price for a VRF request in native tokens
     * @return The price in wei for requesting random numbers
     */
    function getRequestPrice() public view returns (uint256) {
        return i_vrfV2PlusWrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, NUM_WORDS);
    }

    /**
     * @notice Withdraw any excess native tokens from the contract
     * @dev Only callable by owner, useful for recovering overpayments
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = owner().call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    // Allow contract to receive STT for native payment
    receive() external payable {}
}
```

</details>

## Code Breakdown

```solidity
contract RandomNumberConsumer
  is VRFV2PlusWrapperConsumerBase, ConfirmedOwner
```

`VRFV2PlusWrapperConsumerBase` gives you the glue code for requesting randomness from the VRF Wrapper and receiving the callback `(fulfillRandomWords)`. It also exposes the wrapper instance `i_vrfV2PlusWrapper`.

`ConfirmedOwner` is a lightweight ownership module; it lets you restrict actions to the contract owner via onlyOwner.

## State Variables

```solidity
uint256 public latestRequestId;
uint256[] public latestRandomWord;
bool public fulfilled;
```

`latestRequestId` tracks the most recent VRF request ID. Used to make sure the fulfillment we receive matches the last request.\
\
`latestRandomWord` stores the three random words returned by VRF for the latest request.\
\
`fulfilled` marks whether the latest request has finished (prevents overlapping requests and makes UI/state checks easy).

## VRF Request Parameters (constants)

```solidity
uint32 public constant CALLBACK_GAS_LIMIT = 2_100_000;
uint16 public constant REQUEST_CONFIRMATIONS = 3;
uint32 public constant NUM_WORDS = 3;
```

`CALLBACK_GAS_LIMIT` is the max gas VRF can use when calling your `fulfillRandomWords`. Must be large enough for your logic. This example uses headroom for 3 words.\
\
`REQUEST_CONFIRMATIONS` is how many blocks to wait before fulfillment (trade-off between speed and reorg safety).\
\
`NUM_WORDS` This is how many random numbers you want per request. Here, it’s 3.

## Events

```solidity
event RandomNumberRequested(uint256 indexed requestId, address indexed requester, uint256 paid);
event RandomNumberFulfilled(uint256 indexed requestId, uint256[] randomWord);
```

`RandomNumberRequested` is emitted right after submitting a VRF request. Includes the paid cost in native STT.\
\
`RandomNumberFulfilled` is emitted when VRF returns the result, with the three random words.

Events make it easy to monitor behavior from explorers, indexers, or frontends.

## Custom errors

```solidity
error InsufficientPayment(uint256 required, uint256 sent);
error RequestAlreadyPending();
```

`InsufficientPayment` is thrown if msg.value doesn’t cover the VRF native fee at request time.

`RequestAlreadyPending` is thrown if you try to request again while the previous request hasn’t been fulfilled.

Errors are cheaper than require("string") and clearer to reason about.

## Constructor

```solidity
constructor(address wrapper) ConfirmedOwner(msg.sender) VRFV2PlusWrapperConsumerBase(wrapper) {}
```

Takes the VRF V2+ Wrapper address (the on-chain contract that mediates VRF requests) and initializes ownership to the deployer.

## Function Requesting Randomness

```solidity
function requestRandomNumber() external payable onlyOwner {
  // 1) block overlapping requests
  if (latestRequestId != 0 && !fulfilled) revert RequestAlreadyPending();

  // 2) compute required fee and validate payment
  uint256 requestPrice = getRequestPrice();
  if (msg.value < requestPrice) revert InsufficientPayment(requestPrice, msg.value);

  // 3) signal native payment to the wrapper
  bytes memory args = VRFV2PlusClient._argsToBytes(
    VRFV2PlusClient.ExtraArgsV1({ nativePayment: true })
  );

  // 4) submit request (uses native STT)
  (uint256 requestId, uint256 paid) = requestRandomnessPayInNative(
    CALLBACK_GAS_LIMIT,
    REQUEST_CONFIRMATIONS,
    NUM_WORDS,
    args
  );
  latestRequestId = requestId;
  fulfilled = false;
  emit RandomNumberRequested(requestId, msg.sender, paid);

  // 5) refund any excess back to caller
  if (msg.value > paid) {
    (bool ok, ) = msg.sender.call{ value: msg.value - paid }("");
    require(ok, "Refund failed");
  }
}
```

The `requestRandomNumber()` function implements safeguards and processes to ensure reliable VRF operation. First, it enforces safety by preventing spam or overlapping requests, which ensures a predictable user experience and maintains simpler state management. The function then calculates the exact payment required by calling `getRequestPrice()` to determine how much STT the wrapper currently needs, rejecting any transaction with insufficient payment. To specify the payment method, it encodes `nativePayment: true` in the request parameters, instructing the wrapper to charge in native STT tokens rather than LINK.&#x20;

Once validated, the function submits the request through `requestRandomnessPayInNative()`, which initiates the VRF request to Chainlink while storing the returned requestId and marking the fulfilled status as false to track the pending request.&#x20;

Finally, the function implements automatic refund logic that returns any excess funds to the user if they overpaid, ensuring users never lose funds due to price variations.

## READ OPERATIONS

### VRF callback (fulfillment)

```solidity
function fulfillRandomWords(
  uint256 requestId,
  uint256[] memory randomWords
) internal override {
  require(randomWords.length > 0, "No random word returned");
  require(requestId == latestRequestId, "Unexpected request ID");


  latestRandomWord = randomWords; // stores 3 words
  fulfilled = true;


  emit RandomNumberFulfilled(requestId, randomWords);
}
```

Called by the VRF Wrapper (not by you) and validates that we actually received words, and the `requestId` matches the latest request (guards against stale/foreign callbacks). It then stores the 3 words and flips `fulfilled = true` and emits a completion event. If you need game logic, derive from these random words inside this function or store and consume later.

### getRequestStatus()

```solidity
function getRequestStatus()
  external
  view
  returns (uint256 requestId, bool isPending, bool isFulfilled)
{
  return (latestRequestId, latestRequestId != 0 && !fulfilled, fulfilled);
}
```

For frontends/monitoring: see the last `request ID`, whether it’s still `pending`, and whether it was `fulfilled`.

### getLatestRandomWord()

```solidity
function getLatestRandomWord() external view returns (uint256[] memory) {
  require(fulfilled, "No fulfilled request yet");
  return latestRandomWord;
}
```

Returns the three words from the most recent fulfilled request, which is actually a string on numbers for example: `93869141573160465677701763703933181905260360385351294458479680637737009096153`

### Pricing Helper

```solidity
function getRequestPrice() public view returns (uint256) {
  return i_vrfV2PlusWrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, NUM_WORDS);
}
```

Asks the wrapper how much STT (in wei) you need right now for a request with your chosen `CALLBACK_GAS_LIMIT` and `NUM_WORDS`. Use this in your UI or scripts to fill `msg.value`.

## Conclusion

You've successfully built a secure random number generator on Somnia using Chainlink VRF v2.5. Your `RandomNumberConsumer` Smart Contract provides tamper proof randomness with native STT payment, automatic refunds, and proper request management, everything needed for production use.

### Real-World VRF Use Cases

VRF powers a wide range of blockchain applications where fairness is critical. In gaming, it enables trustworthy dice rolls, loot drops, critical hit calculations, and procedurally generated maps. For NFT collections, VRF ensures unbiased trait assignment during minting, metadata reveals, and rarity distribution. This is crucial when traits can be worth thousands.&#x20;

Lotteries and raffles benefit from transparent winner selection, whether for small community giveaways or million dollar prize pools. DeFi protocols use VRF for random liquidator selection, fair distribution, and variable reward mechanisms, while DAO governance applications include jury selection for disputes, randomized proposal ordering, and representative sampling for surveys.

With VRF integrated, you're ready to build applications where fairness is cryptographically guaranteed, not just promised. Whether for games, NFTs, or DeFi protocols, your users can verify that randomness is truly random and build trust through mathematics, not faith.

\
