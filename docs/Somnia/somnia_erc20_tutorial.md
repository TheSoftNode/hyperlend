# Create and Deploy your ERC20 Smart Contract to Somnia Network

## Overview
This comprehensive guide teaches developers how to create and deploy ERC20 tokens on the Somnia Network using Remix IDE. The tutorial covers both custom implementation following the EIP-20 standard and using OpenZeppelin libraries.

## Prerequisites
- Basic Solidity programming knowledge (this is NOT an intro to Solidity)
- MetaMask wallet installed and configured
- Somnia Network added to MetaMask
- STT (Somnia Test Tokens) in your wallet from the faucet
- Active connection to Somnia Testnet

## What are ERC20 Tokens?
ERC20 tokens are smart contracts that follow the ERC-20 standard (EIP-20). They provide functionality to:
- Transfer tokens between addresses
- Allow others to transfer tokens on behalf of the token holder
- Maintain token balance and supply information

**Important:** ERC20 tokens are different from native Somnia tokens (STT) used for gas fees.

## Implementation Approach 1: Custom ERC20 Contract

### Step 1: Create the IERC20 Interface

Create a new file called `IERC20.sol` and paste the following code:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);
}
```

**What is an Interface?**
In Solidity, an interface defines a set of function signatures without implementation. It acts as a "blueprint" ensuring contracts adhere to specific standards, enabling seamless interaction within the EVM ecosystem.

### Step 2: Create the ERC20 Implementation

Create a new file called `ERC20.sol` and paste the following code:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IERC20.sol";

contract ERC20 is IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner, address indexed spender, uint256 value
    );

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function transfer(address recipient, uint256 amount)
        external
        returns (bool)
    {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool)
    {
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
```

## Contract Components Explained

### Constructor
- **Purpose:** Initializes token's basic properties
- **Parameters:** 
  - `_name`: Token name (e.g., "MyToken")
  - `_symbol`: Token symbol (e.g., "MTK")
  - `_decimals`: Number of decimal places (typically 18)
- **Example:** `ERC20("MyToken", "MTK", 18)`

### Core Functions

#### `transfer(address recipient, uint256 amount)`
- Moves tokens from sender to recipient
- Checks sender's balance and deducts amount
- Adds amount to recipient's balance
- Emits Transfer event
- Returns `true` on success

#### `approve(address spender, uint256 amount)`
- Allows spender to spend tokens on behalf of owner
- Sets allowance for spender to specified amount
- Commonly used with DEXs and smart contracts
- Emits Approval event
- Returns `true` on success

#### `transferFrom(address sender, address recipient, uint256 amount)`
- Allows approved spender to transfer tokens
- Checks allowance and deducts from both allowance and sender's balance
- Adds amount to recipient's balance
- Used by DEXs and automated systems
- Emits Transfer event
- Returns `true` on success

### Internal Functions

#### `_mint(address to, uint256 amount)`
- Creates new tokens and adds to specified account
- Increases recipient's balance and total supply
- Emits Transfer event with `from` as `address(0)`
- Used for token creation

#### `_burn(address from, uint256 amount)`
- Destroys tokens from account's balance
- Reduces account balance and total supply
- Emits Transfer event with `to` as `address(0)`
- Used for token destruction/burning

### Public Wrappers
- `mint()`: Public wrapper for `_mint()`
- `burn()`: Public wrapper for `_burn()`

### Events
- **Transfer:** Logs all token transfers (including minting/burning)
- **Approval:** Logs allowance approvals

## Deployment Process

### Step 3: Compile the Smart Contract
1. In Remix IDE, click "Solidity Compiler" in left tab
2. Click "Compile ERC20.sol" button
3. This converts Solidity code to machine-readable bytecode
4. Creates the Application Binary Interface (ABI)

### Step 4: Deploy the Smart Contract
1. Click "Deploy and run transactions" in left tab
2. Set Environment to "Injected Provider - MetaMask"
3. Select MetaMask account with STT tokens
4. In DEPLOY field, enter parameters:
   - `_NAME`: Token name (string)
   - `_SYMBOL`: Token symbol (string)
   - `_DECIMALS`: Number of decimals (uint8, typically 18)
5. Click Deploy
6. Approve deployment in MetaMask
7. Check terminal for deployment response and contract address

## Implementation Approach 2: OpenZeppelin Library

For a more streamlined approach, use OpenZeppelin's battle-tested contracts:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts@5.0.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@5.0.0/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts@5.0.0/access/Ownable.sol";

contract MyToken is ERC20, ERC20Burnable, Ownable {
    constructor(address initialOwner)
        ERC20("MyToken", "MTK")
        Ownable()
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
```

### OpenZeppelin Benefits
- **Security:** Battle-tested, audited contracts
- **Features:** Built-in extensions (Burnable, Ownable, etc.)
- **Maintainability:** Standardized, well-documented code
- **Gas Optimization:** Optimized implementations

## Key Differences: Custom vs OpenZeppelin

| Aspect | Custom Implementation | OpenZeppelin |
|--------|----------------------|--------------|
| Security | Requires thorough testing | Battle-tested, audited |
| Features | Manual implementation needed | Rich ecosystem of extensions |
| Code Size | Minimal, custom-tailored | Slightly larger due to imports |
| Learning Value | High - understand internals | Medium - focus on business logic |
| Maintenance | Full responsibility | Community-maintained |

## Testing Your Token

After deployment, you can interact with your token through Remix IDE:
1. **Mint tokens:** Use the `mint` function to create tokens
2. **Transfer tokens:** Send tokens between addresses
3. **Check balances:** View token balances
4. **Approve spending:** Set allowances for other addresses
5. **Burn tokens:** Destroy tokens to reduce supply

## Best Practices

1. **Always test on testnet first**
2. **Use established patterns (OpenZeppelin when possible)**
3. **Implement proper access controls**
4. **Add overflow protection** (Solidity ^0.8.0 has built-in protection)
5. **Emit events for important state changes**
6. **Consider upgradeability patterns if needed**
7. **Audit contracts before mainnet deployment**

## Common Use Cases

- **Governance tokens:** Voting rights in DAOs
- **Utility tokens:** Access to services/features
- **Reward tokens:** Incentive mechanisms
- **Stablecoins:** Price-stable digital assets
- **Gaming tokens:** In-game currencies and assets

## Conclusion

You now have two approaches to deploy ERC20 tokens on Somnia Network:
1. **Custom implementation:** Full control and learning opportunity
2. **OpenZeppelin:** Production-ready, secure, feature-rich

Both approaches leverage Somnia's high-performance capabilities (1M+ TPS) while maintaining full EVM compatibility, making your tokens interoperable with the broader Ethereum ecosystem.