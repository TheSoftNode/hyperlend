# Deploy a Smart Contract on Somnia Testnet using Foundry

## Overview
This tutorial demonstrates how to deploy smart contracts on the Somnia Network using Foundry, a blazing fast, portable, and modular toolkit for EVM application development written in Rust. We'll deploy a "Ballot Voting" smart contract as an example.

## What is Foundry?
Foundry is a powerful toolkit for Ethereum application development that includes:
- **Forge**: Build, test, and deploy smart contracts
- **Cast**: Interact with smart contracts and send transactions
- **Anvil**: Local Ethereum node for development
- **Chisel**: Solidity REPL for rapid prototyping

### Key Advantages
- **Speed**: Written in Rust for optimal performance
- **Modularity**: Composable tools that work together
- **Testing**: Built-in fuzzing and property-based testing
- **Gas Optimization**: Advanced gas profiling and optimization
- **Scripting**: Powerful deployment scripting capabilities

## Prerequisites
- Basic Solidity programming knowledge
- MetaMask wallet with Somnia Network configured
- STT (Somnia Test Tokens) for gas fees
- Foundry installed on your local machine ([Installation Guide](https://getfoundry.sh/))

## Step 1: Initialize Foundry Project

Create a new Foundry project:

```bash
forge init BallotVoting
```

This command creates a new directory with the following structure:
```
BallotVoting/
├── src/           # Smart contract source files
├── test/          # Test files
├── script/        # Deployment scripts
├── lib/           # Dependencies
└── foundry.toml   # Configuration file
```

### Project Setup
1. Navigate to the `BallotVoting` directory
2. Open the `src` directory
3. Delete the default `Counter.sol` file

## Step 2: Create the Smart Contract

Create a new file `BallotVoting.sol` in the `src` directory:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract BallotVoting {
    struct Ballot {
        string name;
        string[] options;
        mapping(uint256 => uint256) votes;
        mapping(address => bool) hasVoted;
        bool active;
        uint256 totalVotes;
    }

    uint256 public ballotCount;
    mapping(uint256 => Ballot) public ballots;

    event BallotCreated(uint256 indexed ballotId, string name, string[] options);
    event VoteCast(uint256 indexed ballotId, address indexed voter, uint256 optionIndex);
    event BallotClosed(uint256 indexed ballotId);

    function createBallot(string memory name, string[] memory options) public {
        require(options.length > 1, "Ballot must have at least two options");
        
        ballotCount++;
        Ballot storage ballot = ballots[ballotCount];
        ballot.name = name;
        ballot.options = options;
        ballot.active = true;

        emit BallotCreated(ballotCount, name, options);
    }

    function vote(uint256 ballotId, uint256 optionIndex) public {
        Ballot storage ballot = ballots[ballotId];
        require(ballot.active, "This ballot is closed");
        require(!ballot.hasVoted[msg.sender], "You have already voted");
        require(optionIndex < ballot.options.length, "Invalid option index");

        ballot.votes[optionIndex]++;
        ballot.hasVoted[msg.sender] = true;
        ballot.totalVotes++;

        emit VoteCast(ballotId, msg.sender, optionIndex);
    }

    function closeBallot(uint256 ballotId) public {
        Ballot storage ballot = ballots[ballotId];
        require(ballot.active, "Ballot is already closed");
        
        ballot.active = false;
        emit BallotClosed(ballotId);
    }

    function getBallotDetails(uint256 ballotId)
        public
        view
        returns (
            string memory name,
            string[] memory options,
            bool active,
            uint256 totalVotes
        )
    {
        Ballot storage ballot = ballots[ballotId];
        return (ballot.name, ballot.options, ballot.active, ballot.totalVotes);
    }

    function getBallotResults(uint256 ballotId) public view returns (uint256[] memory results) {
        Ballot storage ballot = ballots[ballotId];
        uint256[] memory voteCounts = new uint256[](ballot.options.length);
        
        for (uint256 i = 0; i < ballot.options.length; i++) {
            voteCounts[i] = ballot.votes[i];
        }
        
        return voteCounts;
    }
}
```

## Contract Architecture Analysis

### Data Structures

#### Ballot Struct
```solidity
struct Ballot {
    string name;                              // Ballot title/question
    string[] options;                         // Array of voting options
    mapping(uint256 => uint256) votes;        // Option index → vote count
    mapping(address => bool) hasVoted;        // Voter address → voted status
    bool active;                              // Ballot status (open/closed)
    uint256 totalVotes;                       // Total number of votes cast
}
```

#### State Variables
- `ballotCount`: Counter for total ballots created
- `ballots`: Mapping of ballot ID to Ballot struct

### Core Functions

#### `createBallot(string memory name, string[] memory options)`
- **Purpose**: Creates a new voting ballot
- **Requirements**: Must have at least 2 options
- **Actions**:
  - Increments ballot counter
  - Stores ballot data
  - Sets ballot as active
  - Emits `BallotCreated` event

#### `vote(uint256 ballotId, uint256 optionIndex)`
- **Purpose**: Allows users to cast votes
- **Requirements**:
  - Ballot must be active
  - User hasn't voted before
  - Valid option index
- **Actions**:
  - Increments vote count for selected option
  - Marks user as voted
  - Increments total vote count
  - Emits `VoteCast` event

#### `closeBallot(uint256 ballotId)`
- **Purpose**: Closes an active ballot
- **Requirements**: Ballot must be active
- **Actions**:
  - Sets ballot status to inactive
  - Emits `BallotClosed` event

#### `getBallotDetails(uint256 ballotId)`
- **Purpose**: Retrieves ballot information
- **Returns**: Name, options, active status, total votes
- **Access**: Public view function

#### `getBallotResults(uint256 ballotId)`
- **Purpose**: Gets vote counts for all options
- **Returns**: Array of vote counts per option
- **Access**: Public view function

### Events
- **`BallotCreated`**: Logged when new ballot is created
- **`VoteCast`**: Logged when vote is cast
- **`BallotClosed`**: Logged when ballot is closed

## Step 3: Compile the Smart Contract

Compile your contract using Forge:

```bash
forge build
```

### Expected Output
```
[⠊] Compiling...
[⠢] Compiling 27 files with Solc 0.8.28
[⠆] Solc 0.8.28 finished in 2.22s
Compiler run successful!
```

### What Happens During Compilation
1. **Solidity Compilation**: Converts source code to bytecode
2. **ABI Generation**: Creates Application Binary Interface
3. **Artifact Creation**: Stores compiled contracts in `out/` directory
4. **Dependency Resolution**: Handles imported libraries

### Compilation Options
You can customize compilation with additional flags:

```bash
# Compile with optimization
forge build --optimize

# Compile specific contract
forge build src/BallotVoting.sol

# Set Solidity version
forge build --use solc:0.8.28
```

## Step 4: Deploy to Somnia Network

### Prerequisites for Deployment
1. **RPC URL**: `https://dream-rpc.somnia.network`
2. **Private Key**: From MetaMask (export securely)
3. **STT Tokens**: For gas fees ([Get from faucet](https://devnet.somnia.network/))

### Deployment Command
```bash
forge create --rpc-url https://dream-rpc.somnia.network --private-key PRIVATE_KEY src/BallotVoting.sol:BallotVoting
```

### Command Breakdown
- `forge create`: Foundry's deployment command
- `--rpc-url`: Somnia RPC endpoint
- `--private-key`: Your wallet's private key
- `src/BallotVoting.sol:BallotVoting`: Contract path and name

### Expected Deployment Output
```
[⠊] Compiling...
No files changed, compilation skipped
Deployer: 0xb6e4fa6ff2873480590c68D9Aa991e5BB14Dbf03
Deployed to: 0x46639fB6Ce28FceC29993Fc0201Cd5B6fb1b7b16
Transaction hash: 0xb3f8fe0443acae4efdb6d642bbadbb66797ae1dcde2c864d5c00a56302fb9a34
```

### Verify Deployment
1. Copy the transaction hash
2. Visit [Somnia Explorer](https://somnia-devnet.socialscan.io/)
3. Paste the transaction hash to view deployment details

## Advanced Foundry Features

### Environment Variables
Create a `.env` file for secure key management:

```bash
# .env file
PRIVATE_KEY=your_private_key_here
SOMNIA_RPC_URL=https://dream-rpc.somnia.network
```

Load environment variables:
```bash
source .env
forge create --rpc-url $SOMNIA_RPC_URL --private-key $PRIVATE_KEY src/BallotVoting.sol:BallotVoting
```

### Deployment Scripts
Create advanced deployment scripts in the `script/` directory:

```solidity
// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/BallotVoting.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BallotVoting voting = new BallotVoting();
        
        console.log("BallotVoting deployed to:", address(voting));

        vm.stopBroadcast();
    }
}
```

Run the script:
```bash
forge script script/Deploy.s.sol --rpc-url https://dream-rpc.somnia.network --broadcast
```

### Testing with Foundry

Create comprehensive tests in the `test/` directory:

```solidity
// test/BallotVoting.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BallotVoting.sol";

contract BallotVotingTest is Test {
    BallotVoting voting;
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        voting = new BallotVoting();
    }

    function testCreateBallot() public {
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        voting.createBallot("Should we implement feature X?", options);
        
        (string memory name, string[] memory retrievedOptions, bool active, uint256 totalVotes) = 
            voting.getBallotDetails(1);
        
        assertEq(name, "Should we implement feature X?");
        assertEq(retrievedOptions.length, 2);
        assertTrue(active);
        assertEq(totalVotes, 0);
    }

    function testVote() public {
        string[] memory options = new string[](2);
        options[0] = "Option A";
        options[1] = "Option B";

        voting.createBallot("Test Ballot", options);
        
        vm.prank(user1);
        voting.vote(1, 0);

        uint256[] memory results = voting.getBallotResults(1);
        assertEq(results[0], 1);
        assertEq(results[1], 0);
    }

    function testCannotVoteTwice() public {
        string[] memory options = new string[](2);
        options[0] = "A";
        options[1] = "B";

        voting.createBallot("Test", options);
        
        vm.startPrank(user1);
        voting.vote(1, 0);
        
        vm.expectRevert("You have already voted");
        voting.vote(1, 1);
        vm.stopPrank();
    }
}
```

Run tests:
```bash
forge test
```

### Gas Profiling
Profile gas usage for optimization:

```bash
forge test --gas-report
```

### Fuzzing
Foundry includes built-in fuzzing capabilities:

```solidity
function testFuzzVoting(uint8 optionIndex, address voter) public {
    vm.assume(voter != address(0));
    vm.assume(optionIndex < 2);
    
    string[] memory options = new string[](2);
    options[0] = "A";
    options[1] = "B";
    
    voting.createBallot("Fuzz Test", options);
    
    vm.prank(voter);
    voting.vote(1, optionIndex);
    
    uint256[] memory results = voting.getBallotResults(1);
    assertEq(results[optionIndex], 1);
}
```

## Configuration File

Create or modify `foundry.toml` for project configuration:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200
via_ir = false

[rpc_endpoints]
somnia = "https://dream-rpc.somnia.network"

[etherscan]
somnia = { key = "API_KEY", url = "https://somnia-devnet.socialscan.io/" }
```

## Interacting with Deployed Contracts

### Using Cast (Foundry's CLI)

Read from contract:
```bash
cast call CONTRACT_ADDRESS "ballotCount()" --rpc-url https://dream-rpc.somnia.network
```

Write to contract:
```bash
cast send CONTRACT_ADDRESS "createBallot(string,string[])" "Test Ballot" "[\"Yes\",\"No\"]" --private-key PRIVATE_KEY --rpc-url https://dream-rpc.somnia.network
```

Get ballot details:
```bash
cast call CONTRACT_ADDRESS "getBallotDetails(uint256)" 1 --rpc-url https://dream-rpc.somnia.network
```

## Security Considerations

### Smart Contract Security
1. **Access Control**: Implement proper permissions
2. **Reentrancy Protection**: Use checks-effects-interactions pattern
3. **Input Validation**: Validate all user inputs
4. **Gas Limits**: Consider gas costs for large operations

### Key Management
1. **Never commit private keys** to version control
2. **Use environment variables** for sensitive data
3. **Consider hardware wallets** for production deployments
4. **Implement multi-sig** for critical operations

## Network Information

| Parameter | Value |
|-----------|--------|
| Network Name | Somnia Testnet |
| RPC URL | https://dream-rpc.somnia.network |
| Chain ID | 50312 |
| Currency | STT |
| Block Explorer | https://somnia-devnet.socialscan.io/ |
| Faucet | https://devnet.somnia.network/ |

## Troubleshooting

### Common Issues

#### Compilation Errors
- **Solution**: Check Solidity version compatibility
- **Command**: `forge --version` to check Foundry version

#### Deployment Failures
- **Insufficient Gas**: Ensure adequate STT balance
- **Network Issues**: Verify RPC URL connectivity
- **Private Key**: Confirm key format (with 0x prefix)

#### Transaction Reverts
- **Debug**: Use `forge test -vvv` for detailed traces
- **Gas Estimation**: Use `--gas-estimate` flag

### Debugging Commands

```bash
# Verbose test output
forge test -vvv

# Debug specific function
forge test --match-test testVote -vvv

# Check contract size
forge build --sizes

# Simulate transaction
cast call CONTRACT_ADDRESS "vote(uint256,uint256)" 1 0 --from YOUR_ADDRESS --rpc-url https://dream-rpc.somnia.network
```

## Best Practices

### Development Workflow
1. **Write tests first** (TDD approach)
2. **Use version control** (Git)
3. **Document functions** with NatSpec
4. **Optimize for gas** efficiency
5. **Test on testnet** before mainnet

### Project Structure
```
BallotVoting/
├── src/
│   ├── BallotVoting.sol
│   └── interfaces/
├── test/
│   ├── BallotVoting.t.sol
│   └── mocks/
├── script/
│   └── Deploy.s.sol
├── lib/
├── .env.example
├── foundry.toml
└── README.md
```

### Code Quality
- Use consistent naming conventions
- Implement comprehensive error messages
- Add event logging for important state changes
- Follow Solidity style guidelines

## Future Enhancements

### Planned Features
- **Contract Verification**: Coming soon to SomniaScan
- **Advanced Analytics**: Enhanced block explorer features
- **Multi-signature Support**: For enterprise deployments

### Potential Contract Improvements
1. **Weighted Voting**: Different vote weights per user
2. **Time-based Ballots**: Automatic opening/closing
3. **Delegation**: Allow vote delegation
4. **Privacy Features**: Anonymous voting mechanisms

## Conclusion

You have successfully learned how to:

1. **Set up** a Foundry project for Somnia development
2. **Create** sophisticated smart contracts with complex data structures
3. **Compile** and **deploy** contracts using Foundry's powerful CLI
4. **Test** contracts with built-in fuzzing and property testing
5. **Interact** with deployed contracts using Cast

Foundry's speed and developer experience, combined with Somnia's high-performance blockchain (1M+ TPS), provides an excellent environment for building scalable decentralized applications. The voting contract demonstrates key concepts like struct management, access control, and event emission that are fundamental to most DeFi and governance applications.

**Next Steps**: Explore Foundry's advanced features like invariant testing, differential testing, and deployment scripting to build production-ready applications on Somnia Network.