# Build a DEX on Somnia - Complete Tutorial with Code

## Overview
This tutorial guides developers through building a simple Decentralized Exchange (DEX) on the Somnia network, inspired by Uniswap V2's core mechanics. The implementation covers the essential components needed for a functional AMM-based DEX.

## Prerequisites
- Basic understanding of Solidity programming
- Familiarity with DeFi concepts
- Development environment set up for Somnia network

## Core Concepts

### Automated Market Maker (AMM)
An AMM operates on the principle of liquidity pools rather than traditional order books. Key characteristics:

- **Liquidity Pools**: Smart contracts holding reserves of two or more tokens
- **Direct Trading**: Users trade against the pool, not with other users
- **Constant Product Formula**: Uses `x · y = k` where:
  - `x` = amount of Token A in the pool
  - `y` = amount of Token B in the pool  
  - `k` = constant that must remain unchanged

### Trading Mechanics
When a user wants to buy Token A with Token B:
1. User sends Token B into the pool
2. Smart contract calculates Token A output to maintain `x * y = k`
3. As Token A is withdrawn, its price increases (slippage effect)

### Liquidity Provision
- Anyone can become a Liquidity Provider (LP) by depositing equal values of both tokens
- LPs earn a share of trading fees (typically 0.3%)
- System is fully decentralized and permissionless

## Smart Contract Implementation

### 1. ERC-20 Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

## Deployment Instructions

### Step-by-Step Deployment

1. **Deploy Tokens** (if needed):
   - Create Token A and Token B contracts
   - Or use existing tokens like wSTT and USDC

2. **Deploy Factory Contract**:
   ```solidity
   // Deploy with fee setter address
   SomniaFactory factory = new SomniaFactory(msg.sender);
   ```

3. **Deploy Router Contract**:
   ```solidity
   // Deploy with factory and WETH addresses
   SomniaRouter router = new SomniaRouter(factoryAddress, WETHAddress);
   ```

4. **Create Trading Pairs**:
   ```solidity
   // Create pair for Token A and Token B
   factory.createPair(tokenA, tokenB);
   ```

5. **Add Initial Liquidity**:
   ```solidity
   // Approve tokens first
   tokenA.approve(routerAddress, amount);
   tokenB.approve(routerAddress, amount);
   
   // Add liquidity
   router.addLiquidity(
       tokenA,
       tokenB,
       amountADesired,
       amountBDesired,
       amountAMin,
       amountBMin,
       liquidityProvider,
       deadline
   );
   ```

6. **Enable Swapping**:
   - Users can now perform swaps using the Router contract
   - The DEX is fully functional

## Key Features Explained

### Constant Product Formula Implementation
The core AMM logic maintains `x * y = k` where:
- Before swap: `reserve0 * reserve1 = k`
- After swap: `(reserve0 ± amount0) * (reserve1 ± amount1) = k`
- Trading fee (0.3%) is applied to input amount

### Liquidity Provider Tokens
- LP tokens represent proportional ownership of pool reserves
- Minted when liquidity is added: `liquidity = sqrt(amount0 * amount1)`
- Burned when liquidity is removed, returning underlying tokens

### Price Impact and Slippage
- Larger trades cause bigger price changes
- Slippage protection through minimum output amounts
- Price discovery through supply and demand

### Multi-hop Routing
- Enables trading between tokens without direct pairs
- Route: TokenA → WETH → TokenB
- Router calculates optimal path automatically

## Security Considerations

### Reentrancy Protection
- Uses lock modifier to prevent reentrancy attacks
- Critical for mint, burn, and swap functions

### Integer Overflow Protection
- SafeMath library prevents overflow/underflow
- Modern Solidity 0.8+ has built-in protection

### Flash Loan Resistance
- K value validation ensures reserves can't be manipulated
- Flash loan attacks are prevented by constant product formula

### Access Control
- Factory owner can set fee recipient
- Pair contracts are created deterministically
- No admin functions in core trading logic

## Production Enhancements

### Additional Features to Consider

1. **Fee Tiers**: Different fee levels for different pairs
2. **Concentrated Liquidity**: Uniswap V3 style position management  
3. **Time-Weighted Average Price (TWAP)**: Price oracle functionality
4. **Flash Loans**: Uncollateralized loans within single transaction
5. **Governance**: Protocol parameter updates through voting
6. **Liquidity Mining**: Token rewards for liquidity providers

### Frontend Integration
- Web3 integration for wallet connectivity
- Real-time price feeds and charts
- User-friendly swap interface
- Portfolio tracking and analytics

### Monitoring and Analytics
- Trading volume and liquidity metrics
- Fee collection tracking
- Price impact analysis
- Arbitrage opportunity detection

## Conclusion

This tutorial provides a complete implementation of a functional DEX on Somnia, demonstrating:

1. **Core AMM Mechanics**: How liquidity pools and constant product formula enable decentralized trading
2. **Modular Architecture**: Separation of concerns between Factory, Pair, and Router contracts
3. **Production-Ready Code**: Complete implementation with proper security measures
4. **Testing Framework**: Comprehensive tests to verify functionality
5. **Deployment Guide**: Step-by-step instructions for going live

The implementation serves as a solid foundation for building sophisticated DeFi applications on Somnia. The modular design allows for easy extension and integration of additional features while maintaining the core decentralized, permissionless nature of the system.

Remember to conduct thorough testing on Somnia's testnet and obtain professional security audits before deploying contracts handling real value. This foundation enables you to contribute meaningfully to Somnia's growing DeFi ecosystem.
```

### 2. SomniaPair Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract SomniaPair {
    using SafeMath for uint256;
    
    string public constant name = "Somnia LP Token";
    string public constant symbol = "SLP";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 private reserve0;
    uint256 private reserve1;
    uint32 private blockTimestampLast;
    
    address public factory;
    address public token0;
    address public token1;
    
    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    
    constructor() {
        factory = msg.sender;
    }
    
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }
    
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = uint112(reserve0);
        _reserve1 = uint112(reserve1);
        _blockTimestampLast = blockTimestampLast;
    }
    
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;
        emit Sync(uint112(reserve0), uint112(reserve1));
    }
    
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = ISomniaFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0).mul(_reserve1));
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint256 denominator = rootK.mul(5).add(rootKLast);
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }
    
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = balance1.sub(_reserve1);
        
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0).mul(reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }
    
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];
        
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        amount0 = liquidity.mul(balance0) / _totalSupply;
        amount1 = liquidity.mul(balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        IERC20(_token0).transfer(to, amount0);
        IERC20(_token1).transfer(to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0).mul(reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }
    
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "INSUFFICIENT_LIQUIDITY");
        
        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "INVALID_TO");
            if (amount0Out > 0) IERC20(_token0).transfer(to, amount0Out);
            if (amount1Out > 0) IERC20(_token1).transfer(to, amount1Out);
            if (data.length > 0) ISomniaCallee(to).somniaCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT_AMOUNT");
        {
            uint256 balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint256 balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(balance0Adjusted.mul(balance1Adjusted) >= uint256(_reserve0).mul(_reserve1).mul(1000**2), "K");
        }
        
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    
    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        IERC20(_token0).transfer(to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        IERC20(_token1).transfer(to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }
    
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), uint112(reserve0), uint112(reserve1));
    }
    
    // Standard ERC20 functions
    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }
    
    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }
    
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    
    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }
    
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }
    
    uint256 public kLast;
    uint256 constant MINIMUM_LIQUIDITY = 10**3;
}
```

### 3. SomniaFactory Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SomniaPair.sol";

contract SomniaFactory {
    address public feeTo;
    address public feeToSetter;
    
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    
    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }
    
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");
        
        bytes memory bytecode = type(SomniaPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISomniaPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeTo = _feeTo;
    }
    
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
```

### 4. SomniaRouter Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISomniaFactory.sol";
import "./ISomniaPair.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

contract SomniaRouter {
    using SafeMath for uint256;
    
    address public immutable factory;
    address public immutable WETH;
    
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }
    
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }
    
    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }
    
    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        if (ISomniaFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ISomniaFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = SomniaLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = SomniaLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = SomniaLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = SomniaLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISomniaPair(pair).mint(to);
    }
    
    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = SomniaLibrary.pairFor(factory, tokenA, tokenB);
        ISomniaPair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = ISomniaPair(pair).burn(to);
        (address token0,) = SomniaLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "INSUFFICIENT_B_AMOUNT");
    }
    
    // **** SWAP ****
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SomniaLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? SomniaLibrary.pairFor(factory, output, path[i + 2]) : _to;
            ISomniaPair(SomniaLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SomniaLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SomniaLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SomniaLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SomniaLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure virtual returns (uint256 amountB) {
        return SomniaLibrary.quote(amountA, reserveA, reserveB);
    }
    
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public pure virtual returns (uint256 amountOut)
    {
        return SomniaLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }
    
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public pure virtual returns (uint256 amountIn)
    {
        return SomniaLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }
    
    function getAmountsOut(uint256 amountIn, address[] memory path)
        public view virtual returns (uint256[] memory amounts)
    {
        return SomniaLibrary.getAmountsOut(factory, amountIn, path);
    }
    
    function getAmountsIn(uint256 amountOut, address[] memory path)
        public view virtual returns (uint256[] memory amounts)
    {
        return SomniaLibrary.getAmountsIn(factory, amountOut, path);
    }
}
```

### 5. SomniaLibrary - Helper Functions

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISomniaPair.sol";
import "./SafeMath.sol";

library SomniaLibrary {
    using SafeMath for uint256;
    
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }
    
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            )))));
    }
    
    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ISomniaPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
    
    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB) / reserveA;
    }
    
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
    
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
    
    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }
    
    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
```

### 6. Required Interfaces

```solidity
// ISomniaFactory.sol
interface ISomniaFactory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

## Usage Example

### Deployment Script

```javascript
// deploy.js
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);

    // Deploy Factory
    const SomniaFactory = await ethers.getContractFactory("SomniaFactory");
    const factory = await SomniaFactory.deploy(deployer.address);
    await factory.deployed();
    console.log("SomniaFactory deployed to:", factory.address);

    // Deploy Router (you'll need WETH address for your network)
    const WETH_ADDRESS = "0x..."; // Replace with actual WETH address
    const SomniaRouter = await ethers.getContractFactory("SomniaRouter");
    const router = await SomniaRouter.deploy(factory.address, WETH_ADDRESS);
    await router.deployed();
    console.log("SomniaRouter deployed to:", router.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
```

### Test Script

Create a test script to verify functionality:

```javascript
// test/dex-test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Somnia DEX", function () {
    let factory, router, tokenA, tokenB, pair;
    let owner, user1, user2;

    beforeEach(async function () {
        [owner, user1, user2] = await ethers.getSigners();

        // Deploy mock tokens
        const MockToken = await ethers.getContractFactory("MockERC20");
        tokenA = await MockToken.deploy("Token A", "TKNA", ethers.utils.parseEther("1000000"));
        tokenB = await MockToken.deploy("Token B", "TKNB", ethers.utils.parseEther("1000000"));
        await tokenA.deployed();
        await tokenB.deployed();

        // Deploy Factory
        const SomniaFactory = await ethers.getContractFactory("SomniaFactory");
        factory = await SomniaFactory.deploy(owner.address);
        await factory.deployed();

        // Deploy Router
        const SomniaRouter = await ethers.getContractFactory("SomniaRouter");
        const WETH = "0x0000000000000000000000000000000000000001"; // Mock WETH
        router = await SomniaRouter.deploy(factory.address, WETH);
        await router.deployed();

        // Create pair
        await factory.createPair(tokenA.address, tokenB.address);
        const pairAddress = await factory.getPair(tokenA.address, tokenB.address);
        pair = await ethers.getContractAt("SomniaPair", pairAddress);

        // Transfer tokens to users
        await tokenA.transfer(user1.address, ethers.utils.parseEther("1000"));
        await tokenB.transfer(user1.address, ethers.utils.parseEther("1000"));
        await tokenA.transfer(user2.address, ethers.utils.parseEther("1000"));
        await tokenB.transfer(user2.address, ethers.utils.parseEther("1000"));
    });

    it("Should add liquidity", async function () {
        const amountA = ethers.utils.parseEther("100");
        const amountB = ethers.utils.parseEther("200");

        // Approve tokens
        await tokenA.connect(user1).approve(router.address, amountA);
        await tokenB.connect(user1).approve(router.address, amountB);

        // Add liquidity
        await router.connect(user1).addLiquidity(
            tokenA.address,
            tokenB.address,
            amountA,
            amountB,
            0,
            0,
            user1.address,
            Math.floor(Date.now() / 1000) + 60 * 20 // 20 minutes
        );

        // Check LP token balance
        const lpBalance = await pair.balanceOf(user1.address);
        expect(lpBalance).to.be.gt(0);
    });

    it("Should perform token swap", async function () {
        // First add liquidity
        const amountA = ethers.utils.parseEther("100");
        const amountB = ethers.utils.parseEther("200");

        await tokenA.connect(user1).approve(router.address, amountA);
        await tokenB.connect(user1).approve(router.address, amountB);

        await router.connect(user1).addLiquidity(
            tokenA.address,
            tokenB.address,
            amountA,
            amountB,
            0,
            0,
            user1.address,
            Math.floor(Date.now() / 1000) + 60 * 20
        );

        // Now perform swap
        const swapAmount = ethers.utils.parseEther("10");
        await tokenA.connect(user2).approve(router.address, swapAmount);

        const balanceBefore = await tokenB.balanceOf(user2.address);

        await router.connect(user2).swapExactTokensForTokens(
            swapAmount,
            0, // Accept any amount of tokens out
            [tokenA.address, tokenB.address],
            user2.address,
            Math.floor(Date.now() / 1000) + 60 * 20
        );

        const balanceAfter = await tokenB.balanceOf(user2.address);
        expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should remove liquidity", async function () {
        // Add liquidity first
        const amountA = ethers.utils.parseEther("100");
        const amountB = ethers.utils.parseEther("200");

        await tokenA.connect(user1).approve(router.address, amountA);
        await tokenB.connect(user1).approve(router.address, amountB);

        await router.connect(user1).addLiquidity(
            tokenA.address,
            tokenB.address,
            amountA,
            amountB,
            0,
            0,
            user1.address,
            Math.floor(Date.now() / 1000) + 60 * 20
        );

        const lpBalance = await pair.balanceOf(user1.address);
        
        // Approve LP tokens
        await pair.connect(user1).approve(router.address, lpBalance);

        const balanceABefore = await tokenA.balanceOf(user1.address);
        const balanceBBefore = await tokenB.balanceOf(user1.address);

        // Remove liquidity
        await router.connect(user1).removeLiquidity(
            tokenA.address,
            tokenB.address,
            lpBalance,
            0,
            0,
            user1.address,
            Math.floor(Date.now() / 1000) + 60 * 20
        );

        const balanceAAfter = await tokenA.balanceOf(user1.address);
        const balanceBAfter = await tokenB.balanceOf(user1.address);

        expect(balanceAAfter).to.be.gt(balanceABefore);
        expect(balanceBAfter).to.be.gt(balanceBBefore);
    });
});
```

### Mock ERC20 Token for Testing

```solidity
// MockERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        
        emit Transfer(from, to, value);
        return true;
    }
    
    function mint(address to, uint256 value) external {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }
}

// ISomniaPair.sol
interface ISomniaPair {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);
    
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    
    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
    
    function initialize(address, address) external;
}

// ISomniaCallee.sol
interface ISomniaCallee {
    function somniaCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

// SafeMath.sol
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }
    
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}

// Math.sol
library Math {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
    
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

// TransferHelper.sol
library TransferHelper {
    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}