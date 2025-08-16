# Using Native Somnia Token (STT) - Complete Tutorial

STT is the native token of the Somnia Network, similar to ETH on Ethereum. Unlike ERC20 tokens, STT is built into the protocol itself and **does not have a contract address**.

## Key Characteristics of STT

- **Native Protocol Token**: Built directly into the blockchain protocol
- **No Contract Address**: Unlike ERC20 tokens, STT doesn't exist as a smart contract
- **Similar to ETH**: Functions exactly like Ethereum's native token
- **Gas Currency**: Used for transaction fees and smart contract interactions

## Tutorial Overview

This guide covers four main use cases for STT:

1. **Payments** - Simple exact payment requirements
2. **Escrow** - Secure buyer-seller transactions
3. **Donations & Tipping** - Accept tips from any wallet
4. **Sponsored Gas** - Gasless transactions via Account Abstraction

---

## 1. STT for Payments in Smart Contracts

### Basic Payment Contract

A simple contract that requires exact STT payments:

```solidity
pragma solidity ^0.8.0;

contract PaymentContract {
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    // Function that requires exact STT payment
    function payToAccess() external payable {
        require(msg.value == 0.01 ether, "Must send exactly 0.01 STT");
        // Add your access logic here
    }
    
    // Withdraw collected STT
    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Get contract's STT balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```

### Key Points for Payments

- **Use `msg.value`**: Access the native token sent in a transaction
- **No ERC20 functions needed**: STT works with standard Solidity payment patterns
- **Exact payments**: Use `require()` statements to enforce specific amounts
- **Withdrawal**: Use `.transfer()` or `.call()` to move STT out of contracts

### Deployment and Testing

**Deploy using Hardhat:**
```javascript
// hardhat.config.js deployment script
async function main() {
    const PaymentContract = await ethers.getContractFactory("PaymentContract");
    const contract = await PaymentContract.deploy();
    await contract.deployed();
    console.log("Payment contract deployed to:", contract.address);
}
```

**Test with sendTransaction:**
```javascript
// Testing the payment function
await walletClient.sendTransaction({
    to: contractAddress,
    value: parseEther('0.01'), // Send exactly 0.01 STT
    data: encodeFunctionData({
        abi: contractABI,
        functionName: 'payToAccess'
    })
});
```

---

## 2. STT Escrow Contract

A secure escrow system where a buyer deposits STT and can later release or refund:

```solidity
pragma solidity ^0.8.0;

contract STTEscrow {
    address public buyer;
    address payable public seller;
    uint256 public amount;
    bool public isCompleted;
    bool public isRefunded;
    
    event FundsReleased(address indexed seller, uint256 amount);
    event FundsRefunded(address indexed buyer, uint256 amount);
    
    modifier onlyBuyer() {
        require(msg.sender == buyer, "Only buyer can call this function");
        _;
    }
    
    modifier onlyAfterDeadline() {
        // Add deadline logic if needed
        _;
    }
    
    // Constructor accepts STT deposit
    constructor(address payable _seller) payable {
        require(msg.value > 0, "Must deposit STT");
        buyer = msg.sender;
        seller = _seller;
        amount = msg.value;
        isCompleted = false;
        isRefunded = false;
    }
    
    // Release funds to the seller
    function release() external onlyBuyer {
        require(!isCompleted && !isRefunded, "Transaction already completed or refunded");
        
        isCompleted = true;
        seller.transfer(amount);
        
        emit FundsReleased(seller, amount);
    }
    
    // Refund to the buyer (in case of dispute or agreement)
    function refund() external onlyBuyer {
        require(!isCompleted && !isRefunded, "Transaction already completed or refunded");
        
        isRefunded = true;
        payable(buyer).transfer(amount);
        
        emit FundsRefunded(buyer, amount);
    }
    
    // Get escrow status
    function getStatus() external view returns (string memory) {
        if (isCompleted) return "Completed - Funds released to seller";
        if (isRefunded) return "Refunded - Funds returned to buyer";
        return "Pending - Funds in escrow";
    }
    
    // Get escrow details
    function getDetails() external view returns (
        address _buyer,
        address _seller,
        uint256 _amount,
        bool _completed,
        bool _refunded
    ) {
        return (buyer, seller, amount, isCompleted, isRefunded);
    }
}
```

### Deployment with STT Value

**Deploy with Hardhat Ignition:**
```javascript
// Deploy escrow with STT deposit
async function deployEscrow() {
    const [buyer] = await ethers.getSigners();
    const sellerAddress = "0x..."; // Seller's address
    
    const STTEscrow = await ethers.getContractFactory("STTEscrow");
    const escrow = await STTEscrow.deploy(sellerAddress, {
        value: ethers.utils.parseEther("1.0") // Deposit 1.0 STT
    });
    
    await escrow.deployed();
    console.log("Escrow deployed with 1.0 STT at:", escrow.address);
}
```

**Usage Example:**
```javascript
// Release funds to seller
await escrow.release();

// Or refund to buyer
await escrow.refund();

// Check status
const status = await escrow.getStatus();
console.log(status);
```

---

## 3. STT Tip Jar Contract

A contract that accepts tips from any wallet:

```solidity
pragma solidity ^0.8.0;

contract STTTipJar {
    address public owner;
    uint256 public totalTips;
    
    mapping(address => uint256) public tipperAmounts;
    address[] public tippers;
    
    event Tipped(address indexed tipper, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can withdraw");
        _;
    }
    
    // Receive function - accepts direct STT transfers
    receive() external payable {
        require(msg.value > 0, "Tip amount must be greater than 0");
        
        // Track new tippers
        if (tipperAmounts[msg.sender] == 0) {
            tippers.push(msg.sender);
        }
        
        tipperAmounts[msg.sender] += msg.value;
        totalTips += msg.value;
        
        emit Tipped(msg.sender, msg.value);
    }
    
    // Alternative tip function with message
    function tipWithMessage(string memory message) external payable {
        require(msg.value > 0, "Tip amount must be greater than 0");
        
        if (tipperAmounts[msg.sender] == 0) {
            tippers.push(msg.sender);
        }
        
        tipperAmounts[msg.sender] += msg.value;
        totalTips += msg.value;
        
        emit Tipped(msg.sender, msg.value);
        // Could emit additional event with message if needed
    }
    
    // Withdraw all tips
    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No tips to withdraw");
        
        payable(owner).transfer(amount);
        emit Withdrawn(owner, amount);
    }
    
    // Withdraw specific amount
    function withdrawAmount(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        require(amount > 0, "Amount must be greater than 0");
        
        payable(owner).transfer(amount);
        emit Withdrawn(owner, amount);
    }
    
    // Get contract balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // Get total number of unique tippers
    function getTipperCount() external view returns (uint256) {
        return tippers.length;
    }
    
    // Get tipper by index
    function getTipper(uint256 index) external view returns (address, uint256) {
        require(index < tippers.length, "Index out of bounds");
        address tipper = tippers[index];
        return (tipper, tipperAmounts[tipper]);
    }
}
```

### Frontend Integration

**Send tips using Web3 libraries:**

```javascript
// Using Viem
import { parseEther } from 'viem';

async function sendTip() {
    await walletClient.sendTransaction({
        to: '0xTipJarAddress', // Your tip jar contract address
        value: parseEther('0.05'), // Send 0.05 STT
    });
}

// Using Ethers.js
async function sendTipEthers() {
    const tx = await signer.sendTransaction({
        to: tipJarAddress,
        value: ethers.utils.parseEther('0.05')
    });
    await tx.wait();
}

// Send tip with message
async function sendTipWithMessage(message) {
    const contract = new ethers.Contract(tipJarAddress, tipJarABI, signer);
    const tx = await contract.tipWithMessage(message, {
        value: ethers.utils.parseEther('0.05')
    });
    await tx.wait();
}
```

**React Component Example:**
```jsx
import { useState } from 'react';
import { parseEther } from 'viem';

function TipJar({ tipJarAddress, walletClient }) {
    const [tipAmount, setTipAmount] = useState('');
    const [message, setMessage] = useState('');
    const [loading, setLoading] = useState(false);
    
    const sendTip = async () => {
        if (!tipAmount) return;
        
        setLoading(true);
        try {
            await walletClient.sendTransaction({
                to: tipJarAddress,
                value: parseEther(tipAmount),
            });
            
            setTipAmount('');
            setMessage('');
            alert('Tip sent successfully!');
        } catch (error) {
            console.error('Error sending tip:', error);
            alert('Error sending tip');
        } finally {
            setLoading(false);
        }
    };
    
    return (
        <div className="tip-jar">
            <h3>Send a Tip</h3>
            <input
                type="number"
                step="0.001"
                placeholder="Tip amount (STT)"
                value={tipAmount}
                onChange={(e) => setTipAmount(e.target.value)}
            />
            <input
                type="text"
                placeholder="Optional message"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
            />
            <button onClick={sendTip} disabled={loading || !tipAmount}>
                {loading ? 'Sending...' : 'Send Tip'}
            </button>
        </div>
    );
}
```

---

## 4. Sponsored STT Transactions with Account Abstraction

Using Account Abstraction, dApps can cover gas fees for users:

### Smart Contract Example

```solidity
pragma solidity ^0.8.0;

contract SponsoredMinting {
    address public owner;
    uint256 public tokenCounter;
    mapping(address => uint256) public userTokens;
    
    event TokenMinted(address indexed user, uint256 tokenId);
    
    constructor() {
        owner = msg.sender;
    }
    
    // This function can be called without the user paying gas
    function mint(address to) external {
        // The paymaster/relayer pays the gas fees
        tokenCounter++;
        userTokens[to] = tokenCounter;
        
        emit TokenMinted(to, tokenCounter);
    }
    
    // Sponsored transaction for multiple operations
    function batchMint(address[] calldata recipients) external {
        for (uint256 i = 0; i < recipients.length; i++) {
            tokenCounter++;
            userTokens[recipients[i]] = tokenCounter;
            emit TokenMinted(recipients[i], tokenCounter);
        }
    }
}
```

### Frontend Implementation with Account Abstraction

**Using Privy or Thirdweb:**

```javascript
// Example with sponsored transactions
async function sponsoredMint() {
    // Smart account + relayer covers the gas
    await sendTransaction({
        to: contractAddress,
        data: mintFunctionEncoded,
        value: 0n, // User sends no STT for gas
    });
}

// The Smart Contract function executes normally
// The paymaster or relayer pays STT for gas fees
```

**Detailed Implementation:**

```javascript
import { createSmartAccountClient } from 'permissionless';
import { privateKeyToAccount } from 'viem/accounts';

// Setup smart account with paymaster
async function setupSponsoredTransactions() {
    const smartAccount = createSmartAccountClient({
        signer: privateKeyToAccount('0x...'), // User's key
        bundlerUrl: 'https://bundler.somnia.network',
        paymasterUrl: 'https://paymaster.somnia.network',
    });
    
    // Execute sponsored transaction
    const txHash = await smartAccount.sendTransaction({
        to: contractAddress,
        data: encodeFunctionData({
            abi: contractABI,
            functionName: 'mint',
            args: [userAddress]
        }),
        // No value needed - paymaster covers gas
    });
    
    console.log('Sponsored transaction hash:', txHash);
}
```

**React Hook for Sponsored Transactions:**

```jsx
import { useState } from 'react';

function useSponsoredTransactions(smartAccount, contractAddress, abi) {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    
    const executeSponsored = async (functionName, args = []) => {
        setLoading(true);
        setError(null);
        
        try {
            const txHash = await smartAccount.sendTransaction({
                to: contractAddress,
                data: encodeFunctionData({
                    abi,
                    functionName,
                    args
                })
            });
            
            return txHash;
        } catch (err) {
            setError(err.message);
            throw err;
        } finally {
            setLoading(false);
        }
    };
    
    return { executeSponsored, loading, error };
}

// Usage in component
function MintingApp() {
    const { executeSponsored, loading } = useSponsoredTransactions(
        smartAccount, 
        contractAddress, 
        contractABI
    );
    
    const handleMint = async () => {
        try {
            const txHash = await executeSponsored('mint', [userAddress]);
            console.log('Minted with sponsored gas:', txHash);
        } catch (error) {
            console.error('Minting failed:', error);
        }
    };
    
    return (
        <button onClick={handleMint} disabled={loading}>
            {loading ? 'Minting...' : 'Mint (Gas Sponsored)'}
        </button>
    );
}
```

---

## Key Concepts Summary

### STT Characteristics
- **Native Token**: STT is built into the protocol, not a contract
- **No Contract Address**: Cannot be imported like ERC20 tokens
- **Standard Solidity Patterns**: Use `msg.value`, `.transfer()`, and `payable`
- **Gas Currency**: Used for transaction fees

### Development Patterns

#### ✅ Correct STT Usage
```solidity
// ✅ Access STT sent to contract
uint256 sttAmount = msg.value;

// ✅ Send STT from contract
payable(recipient).transfer(amount);

// ✅ Check contract's STT balance
uint256 balance = address(this).balance;

// ✅ Require specific STT amount
require(msg.value == requiredAmount, "Incorrect STT amount");
```

#### ❌ Incorrect STT Usage
```solidity
// ❌ Don't treat STT like ERC20
// STT.transfer(recipient, amount); // This won't work!

// ❌ Don't look for STT contract address
// address sttContract = 0x...; // STT has no contract!

// ❌ Don't use ERC20 functions
// STT.balanceOf(address); // This doesn't exist for STT!
```

### Integration Benefits

1. **Simplicity**: No ERC20 complexity - just use native Solidity patterns
2. **Efficiency**: Lower gas costs compared to ERC20 operations
3. **Security**: Built-in protocol security, no smart contract vulnerabilities
4. **Account Abstraction**: Enable gasless dApps with STT as sponsor currency
5. **Compatibility**: Works with any Solidity application expecting native tokens

### Best Practices

1. **Always validate `msg.value`** for exact payments
2. **Use proper access controls** for withdrawal functions
3. **Emit events** for transparency and frontend integration
4. **Handle edge cases** like zero amounts and insufficient balances
5. **Consider Account Abstraction** for better user experience
6. **Test thoroughly** with actual STT transactions on testnet

This comprehensive guide provides all the tools needed to integrate STT into your Somnia Network applications, from simple payments to complex sponsored transaction systems.