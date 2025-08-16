# WebSocket Event Listening on Somnia - Complete Tutorial

## Overview
This guide teaches developers how to create WebSocket connections to listen for smart contract events on the Somnia network in real-time. We'll use a simple Greeting contract as an example to demonstrate the core concepts.

## Resources
- **Somnia Network RPC**: `https://dream-rpc.somnia.network`
- **Somnia WebSocket**: `wss://dream-rpc.somnia.network/ws`
- **Example Contract**: `0xADA7b2953E7d670092644d37b6a39BAE3237beD7`

## Prerequisites
- Node.js installed (v14 or higher)
- Basic understanding of JavaScript
- A deployed smart contract on Somnia network

## What are WebSockets?

WebSockets are a communication protocol that provides bidirectional communication channels over a single TCP connection. Unlike traditional HTTP requests, WebSockets maintain a persistent connection between the client and server.

### How WebSockets Work
WebSockets begin with a connection establishment phase where the client initiates a WebSocket handshake through an HTTP upgrade request. Once established, the connection stays open as a persistent channel between client and server. This enables bidirectional communication where both client and server can send messages at any time without waiting for requests.

### WebSocket Connection Lifecycle
```
Client                     Server
  |                          |
  |----Connection Request--->|
  |<---Connection Accept-----|
  |                          |
  |<===Open Connection=====> |
  |                          |
  |----Send Message--------->|
  |<---Receive Message-------|
  |<---Push Notification-----|
  |----Send Message--------->|
  |                          |
  |<===Open Connection=====> |
  |                          |
  |----Close Connection----->|
```

## WebSocket vs HTTP Polling

### HTTP Polling Approach (Inefficient)

```javascript
// Inefficient: Constantly asking "Any updates?"
setInterval(async () => {
  const response = await fetch('https://api.example.com/events');
  const data = await response.json();
  if (data.hasNewEvents) {
    console.log('New event:', data.events);
  }
}, 5000); // Check every 5 seconds
```

**Problems with Polling:**
- Wastes bandwidth by constantly checking for updates
- Introduces delays of up to the polling interval
- Increases server computational load
- Higher costs for RPC providers

### WebSocket Approach (Efficient)

```javascript
// Efficient: Server pushes updates immediately
const ws = new WebSocket('wss://api.example.com/events');
ws.on('message', (data) => {
  console.log('New event:', data); // Instant notification
});
```

**Benefits of WebSockets:**
- Real-time updates in milliseconds
- Eliminates wasted requests
- Reduces server load and bandwidth
- Lower infrastructure costs
- Superior user experience

## Blockchain Events and WebSockets

Smart contracts emit events when important state changes occur. These events are included in transaction receipts and stored in blockchain logs.

### Event Flow Process:
1. User calls Smart Contract function through Transaction
2. Contract updates Internal State and emits Events
3. Transactions and Events are included in new Block
4. Block is finalized by Validators
5. Nodes broadcast block to network
6. WebSocket connections notify clients instantly

## Example Use Cases

### DeFi Applications
- Monitor price updates on DEX swaps
- Track liquidity changes
- Alert on large trades

### NFT Marketplaces
- Live bidding updates in auctions
- New listing notifications
- Transfer tracking

### Gaming DApps
- Real-time game state updates
- Player action notifications
- Leaderboard changes

### DAOs and Governance
- Live voting updates
- Proposal status changes
- Execution notifications

### Supply Chain
- Product status updates
- Location tracking
- Quality checkpoints

## Indexed Parameters in Events

When you mark an event parameter as `indexed` in Solidity, it becomes part of the event's topics rather than the data section.

### Non-Indexed String (accessible directly):
```solidity
event MessageSent(string message); // Can read 'message' directly from logs
```

### Indexed String (hashed for filtering):
```solidity
event MessageSent(string indexed message); // 'message' is hashed, cannot read directly
```

### Why Use Indexed Parameters?

**Benefits:**
- Enable efficient filtering by allowing nodes to quickly find specific events
- Gas optimization for filtering operations
- Faster indexing and searching by nodes

**Trade-offs:**
For strings and bytes, indexing means:
- ✅ Can filter events by this parameter efficiently
- ❌ Cannot retrieve the actual value from the event log
- 🔄 Must query contract state to get the current value

## Complete WebSocket Implementation

### 1. Basic Setup

```javascript
const { ethers } = require('ethers');

// Somnia WebSocket connection
const wsUrl = 'wss://dream-rpc.somnia.network/ws';
const provider = new ethers.WebSocketProvider(wsUrl);

// Contract details
const contractAddress = '0xADA7b2953E7d670092644d37b6a39BAE3237beD7';
const abi = [
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "string",
        "name": "oldGreeting",
        "type": "string"
      },
      {
        "indexed": true,
        "internalType": "string", 
        "name": "newGreeting",
        "type": "string"
      }
    ],
    "name": "GreetingSet",
    "type": "event"
  },
  {
    "inputs": [],
    "name": "getGreeting",
    "outputs": [
      {
        "internalType": "string",
        "name": "",
        "type": "string"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];
```

### 2. Main WebSocket Listener Function

```javascript
async function listen() {
  try {
    console.log('Connecting to Somnia WebSocket...');
    
    // Wait for connection to be ready
    await provider._waitUntilReady();
    console.log('Connected to Somnia WebSocket!');
    
    // Create contract instance
    const contract = new ethers.Contract(contractAddress, abi, provider);
    
    // Define event filter
    const filter = {
      address: contractAddress,
      topics: [ethers.id("GreetingSet(string,string)")]
    };
    
    console.log('Listening for GreetingSet events...');
    
    // Set up event listener
    provider.on(filter, async (log) => {
      try {
        console.log('\n🎉 Event detected!');
        console.log('Block Number:', log.blockNumber);
        console.log('Transaction Hash:', log.transactionHash);
        
        // Since the greeting parameters are indexed (hashed),
        // we need to query the contract to get the current greeting
        const greeting = await contract.getGreeting();
        console.log(`New greeting: "${greeting}"`);
        
        // Parse the log to get additional information
        const parsedLog = contract.interface.parseLog(log);
        console.log('Event Name:', parsedLog.name);
        console.log('Raw Log Data:', log);
        
      } catch (error) {
        console.error('Error processing event:', error);
      }
    });
    
    // Keep connection alive with periodic heartbeat
    const heartbeat = setInterval(async () => {
      try {
        const blockNumber = await provider.getBlockNumber();
        console.log(`Heartbeat - Current block: ${blockNumber}`);
      } catch (error) {
        console.error('Heartbeat failed:', error);
        clearInterval(heartbeat);
      }
    }, 30000); // Every 30 seconds
    
    // Handle connection errors
    provider.on('error', (error) => {
      console.error('Provider error:', error);
      clearInterval(heartbeat);
    });
    
    // Handle disconnection
    provider.on('close', (code, reason) => {
      console.log('Connection closed:', code, reason);
      clearInterval(heartbeat);
    });
    
  } catch (error) {
    console.error('Connection error:', error);
    throw error;
  }
}
```

### 3. Connection with Retry Logic

```javascript
async function connectWithRetry() {
  let retries = 0;
  const maxRetries = 5;
  
  while (retries < maxRetries) {
    try {
      console.log(`Connection attempt ${retries + 1}/${maxRetries}`);
      await listen();
      break;
    } catch (error) {
      console.error(`Connection failed:`, error.message);
      retries++;
      
      if (retries < maxRetries) {
        console.log(`Retrying in 5 seconds...`);
        await new Promise(resolve => setTimeout(resolve, 5000));
      } else {
        console.error('Max retries reached. Giving up.');
        process.exit(1);
      }
    }
  }
}
```

### 4. Historical Event Fetching

```javascript
async function getHistoricalEvents() {
  try {
    console.log('Fetching historical events...');
    
    // Create HTTP provider for historical queries
    const httpProvider = new ethers.JsonRpcProvider('https://dream-rpc.somnia.network');
    const contract = new ethers.Contract(contractAddress, abi, httpProvider);
    
    // Get current block number
    const currentBlock = await httpProvider.getBlockNumber();
    
    // Get events from last 100 blocks
    const fromBlock = Math.max(0, currentBlock - 100);
    const events = await contract.queryFilter('GreetingSet', fromBlock, currentBlock);
    
    console.log(`Found ${events.length} historical events:`);
    
    events.forEach((event, index) => {
      console.log(`${index + 1}. Block: ${event.blockNumber}, Tx: ${event.transactionHash}`);
    });
    
    return events;
  } catch (error) {
    console.error('Error fetching historical events:', error);
    return [];
  }
}
```

### 5. Multiple Event Listeners

```javascript
async function listenMultipleEvents() {
  await provider._waitUntilReady();
  const contract = new ethers.Contract(contractAddress, abi, provider);
  
  // Listen for GreetingSet events
  const greetingFilter = {
    address: contractAddress,
    topics: [ethers.id("GreetingSet(string,string)")]
  };
  
  provider.on(greetingFilter, async (log) => {
    console.log('GreetingSet event detected');
    const greeting = await contract.getGreeting();
    console.log(`New greeting: "${greeting}"`);
  });
  
  // Listen for another event (example)
  const anotherFilter = {
    address: contractAddress,
    topics: [ethers.id("AnotherEvent(address,uint256)")]
  };
  
  provider.on(anotherFilter, (log) => {
    console.log('AnotherEvent detected');
    // Handle the other event
    const parsedLog = contract.interface.parseLog(log);
    console.log('Event data:', parsedLog.args);
  });
}
```

### 6. Complete Example with Error Handling

```javascript
const { ethers } = require('ethers');

class SomniaEventListener {
  constructor(contractAddress, abi) {
    this.contractAddress = contractAddress;
    this.abi = abi;
    this.wsUrl = 'wss://dream-rpc.somnia.network/ws';
    this.provider = null;
    this.contract = null;
    this.heartbeatInterval = null;
    this.isConnected = false;
  }
  
  async connect() {
    try {
      console.log('Initializing WebSocket connection...');
      
      this.provider = new ethers.WebSocketProvider(this.wsUrl);
      await this.provider._waitUntilReady();
      
      this.contract = new ethers.Contract(this.contractAddress, this.abi, this.provider);
      this.isConnected = true;
      
      console.log('✅ Connected to Somnia WebSocket!');
      
      // Set up error handlers
      this.provider.on('error', this.handleError.bind(this));
      this.provider.on('close', this.handleClose.bind(this));
      
      // Start heartbeat
      this.startHeartbeat();
      
      return true;
    } catch (error) {
      console.error('❌ Connection failed:', error);
      this.isConnected = false;
      throw error;
    }
  }
  
  async listenForEvents(eventName, callback) {
    if (!this.isConnected) {
      throw new Error('Not connected. Call connect() first.');
    }
    
    try {
      // Create filter for the event
      const eventSignature = this.contract.interface.getEvent(eventName);
      const filter = {
        address: this.contractAddress,
        topics: [ethers.id(eventSignature.format('sighash'))]
      };
      
      console.log(`👂 Listening for ${eventName} events...`);
      
      this.provider.on(filter, async (log) => {
        try {
          const parsedLog = this.contract.interface.parseLog(log);
          const eventData = {
            name: parsedLog.name,
            args: parsedLog.args,
            blockNumber: log.blockNumber,
            transactionHash: log.transactionHash,
            address: log.address
          };
          
          await callback(eventData, this.contract);
        } catch (error) {
          console.error(`Error processing ${eventName} event:`, error);
        }
      });
      
    } catch (error) {
      console.error(`Error setting up listener for ${eventName}:`, error);
      throw error;
    }
  }
  
  startHeartbeat() {
    this.heartbeatInterval = setInterval(async () => {
      try {
        if (this.isConnected) {
          const blockNumber = await this.provider.getBlockNumber();
          console.log(`💓 Heartbeat - Block: ${blockNumber}`);
        }
      } catch (error) {
        console.error('💔 Heartbeat failed:', error);
        this.handleError(error);
      }
    }, 30000);
  }
  
  handleError(error) {
    console.error('🚨 Provider error:', error);
    this.isConnected = false;
    this.cleanup();
  }
  
  handleClose(code, reason) {
    console.log(`🔌 Connection closed: ${code} ${reason}`);
    this.isConnected = false;
    this.cleanup();
  }
  
  cleanup() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
    
    if (this.provider) {
      this.provider.removeAllListeners();
    }
  }
  
  async disconnect() {
    console.log('🔌 Disconnecting...');
    this.isConnected = false;
    this.cleanup();
    
    if (this.provider) {
      await this.provider.destroy();
    }
  }
}
```

### 7. Usage Example

```javascript
// Usage
async function main() {
  const contractAddress = '0xADA7b2953E7d670092644d37b6a39BAE3237beD7';
  const abi = [
    {
      "anonymous": false,
      "inputs": [
        {
          "indexed": true,
          "internalType": "string",
          "name": "oldGreeting",
          "type": "string"
        },
        {
          "indexed": true,
          "internalType": "string", 
          "name": "newGreeting",
          "type": "string"
        }
      ],
      "name": "GreetingSet",
      "type": "event"
    },
    {
      "inputs": [],
      "name": "getGreeting",
      "outputs": [
        {
          "internalType": "string",
          "name": "",
          "type": "string"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    }
  ];
  
  const listener = new SomniaEventListener(contractAddress, abi);
  
  try {
    // Connect to WebSocket
    await listener.connect();
    
    // Get historical events first
    await getHistoricalEvents();
    
    // Listen for new events
    await listener.listenForEvents('GreetingSet', async (eventData, contract) => {
      console.log('\n🎉 New GreetingSet event!');
      console.log('Block:', eventData.blockNumber);
      console.log('Transaction:', eventData.transactionHash);
      
      // Since greeting is indexed, query current state
      const currentGreeting = await contract.getGreeting();
      console.log(`Current greeting: "${currentGreeting}"`);
    });
    
    // Handle graceful shutdown
    process.on('SIGINT', async () => {
      console.log('\n👋 Shutting down gracefully...');
      await listener.disconnect();
      process.exit(0);
    });
    
    console.log('✅ Event listener is running. Press Ctrl+C to stop.');
    
  } catch (error) {
    console.error('Failed to start event listener:', error);
    process.exit(1);
  }
}

// Start the application
main().catch(console.error);
```

### 8. Package.json Setup

```json
{
  "name": "somnia-websocket-listener",
  "version": "1.0.0",
  "description": "WebSocket event listener for Somnia network",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js"
  },
  "dependencies": {
    "ethers": "^6.7.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  },
  "keywords": [
    "blockchain",
    "websocket",
    "somnia",
    "ethereum",
    "events"
  ]
}
```

## Testing Your WebSocket Connection

### 1. Deploy Smart Contract
Deploy your smart contract to Somnia network and note the contract address.

### 2. Run the Listener
In one terminal, run the listener:
```bash
node websocket-listener.js
```

### 3. Trigger Events
From another script or dApp, trigger events on your contract.

### 4. Observe Real-time Updates
Watch your listener terminal for instant event notifications.

## Common Patterns and Best Practices

### Event Filter Patterns

```javascript
// Single event filter
const singleFilter = {
  address: contractAddress,
  topics: [ethers.id("Transfer(address,address,uint256)")]
};

// Multiple events from same contract
const multipleFilters = [
  ethers.id("Transfer(address,address,uint256)"),
  ethers.id("Approval(address,address,uint256)")
];

// Filter with indexed parameters
const filteredTransfers = {
  address: contractAddress,
  topics: [
    ethers.id("Transfer(address,address,uint256)"),
    null, // from (any address)
    ethers.zeroPadValue(myAddress, 32) // to (specific address)
  ]
};
```

### Connection Management

```javascript
// Reconnection with exponential backoff
async function connectWithExponentialBackoff() {
  let attempt = 0;
  const maxAttempts = 10;
  
  while (attempt < maxAttempts) {
    try {
      await listener.connect();
      console.log('Connected successfully');
      return;
    } catch (error) {
      attempt++;
      const delay = Math.min(1000 * Math.pow(2, attempt), 30000);
      console.log(`Attempt ${attempt} failed, retrying in ${delay}ms`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  
  throw new Error('Failed to connect after maximum attempts');
}
```

### Performance Optimization

```javascript
// Batch process events to avoid overwhelming the system
class EventBatcher {
  constructor(batchSize = 10, flushInterval = 1000) {
    this.batchSize = batchSize;
    this.flushInterval = flushInterval;
    this.events = [];
    this.timer = null;
  }
  
  addEvent(event) {
    this.events.push(event);
    
    if (this.events.length >= this.batchSize) {
      this.flush();
    } else if (!this.timer) {
      this.timer = setTimeout(() => this.flush(), this.flushInterval);
    }
  }
  
  flush() {
    if (this.events.length > 0) {
      this.processEvents([...this.events]);
      this.events = [];
    }
    
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }
  
  processEvents(events) {
    console.log(`Processing batch of ${events.length} events`);
    // Process events in batch
  }
}
```

## Troubleshooting

### Common Issues and Solutions

1. **Connection Timeouts**
   ```javascript
   // Increase timeout and add retry logic
   const provider = new ethers.WebSocketProvider(wsUrl, null, {
     timeout: 60000 // 60 second timeout
   });
   ```

2. **Memory Leaks**
   ```javascript
   // Always remove listeners when done
   provider.removeAllListeners();
   ```

3. **Rate Limiting**
   ```javascript
   // Implement request queuing
   const queue = [];
   const processQueue = async () => {
     if (queue.length > 0) {
       const request = queue.shift();
       await request();
       setTimeout(processQueue, 100); // 100ms between requests
     }
   };
   ```

## Conclusion

WebSocket connections provide real-time event monitoring for smart contracts on Somnia. This comprehensive guide demonstrated:

1. **Real-time Event Listening**: Connect to Somnia's WebSocket endpoint for instant notifications
2. **Proper Connection Management**: Handle errors, reconnection, and graceful shutdowns  
3. **Event Processing**: Parse and handle different types of blockchain events
4. **Production Patterns**: Implement retry logic, batching, and performance optimization
5. **Best Practices**: Error handling, connection lifecycle management, and resource cleanup

With this foundation, you can build responsive dApps that react instantly to blockchain events without the overhead of constant polling. The WebSocket approach provides superior performance, lower costs, and better user experience compared to traditional HTTP polling methods.

### Key Takeaways:
- WebSockets eliminate polling delays and provide real-time updates
- Indexed parameters require special handling for string/bytes types
- Connection management and error handling are crucial for production apps
- Proper cleanup prevents memory leaks and resource exhaustion
- Heartbeat mechanisms keep connections alive and detect failures

This implementation serves as a robust foundation for building event-driven blockchain applications on the Somnia network.