# HyperLend Deployment Scripts - Somnia Optimized

This directory contains streamlined deployment scripts optimized for the Somnia blockchain and hackathon requirements.

## Scripts Overview

### Contract Deployment Scripts (packages/contracts/scripts/)

1. **deploy-simple.ts** - Quick deployment script for testing

   - Deploys all core contracts in correct order
   - Minimal configuration for rapid testing
   - Usage: `npx hardhat run scripts/deploy/deploy-simple.ts --network localhost`

2. **00_deploy_somnia_optimized.ts** - Full Somnia deployment
   - Complete deployment with Somnia-specific optimizations
   - Includes native STT integration
   - Configured for account abstraction and gasless transactions
   - Usage: `npx hardhat deploy --network somnia-testnet`

### Root Deployment Scripts (scripts/deployment/)

1. **deploy-contracts.sh** - Smart contract deployment

   - Comprehensive contract deployment to Somnia
   - Includes verification and initialization
   - Supports both testnet and devnet

2. **deploy-backend.sh** - Backend service deployment

   - Node.js/Express backend deployment
   - Somnia-optimized environment configuration
   - Database migrations and health checks

3. **deploy-frontend.sh** - Frontend application deployment

   - Next.js frontend deployment
   - Somnia network configuration
   - Contract address integration

4. **deploy-all.sh** - Complete stack deployment

   - Orchestrates full application deployment
   - Contracts → Backend → Frontend → Health checks

5. **check-contracts.sh** - Compilation and testing
   - Verifies contract compilation
   - Runs test suite
   - Quick deployment validation

## Somnia-Specific Features

All deployment scripts are optimized for Somnia's unique features:

- **Native STT Integration**: Zero address convention for native token
- **Account Abstraction**: Enabled by default for gasless transactions
- **High TPS**: Optimized gas settings and confirmation times
- **Sub-second Finality**: Reduced liquidation delays and update intervals

## Usage Examples

### Quick Testing (Local)

```bash
# Check compilation and run tests
./scripts/deployment/check-contracts.sh

# Deploy to local hardhat network
cd packages/contracts
npx hardhat run scripts/deploy/deploy-simple.ts --network localhost
```

### Somnia Testnet Deployment

```bash
# Set environment variables
export DEPLOYER_PRIVATE_KEY="your_private_key"
export NETWORK="somnia-testnet"

# Deploy contracts only
./scripts/deployment/deploy-contracts.sh

# Or deploy full stack
./scripts/deployment/deploy-all.sh
```

### Somnia Devnet Deployment

```bash
export NETWORK="somnia-devnet"
export ENVIRONMENT="development"

./scripts/deployment/deploy-all.sh
```

## Configuration

### Network Settings

- **Somnia Testnet**: Chain ID 50312, optimized for hackathon testing
- **Somnia Devnet**: Chain ID 50311, fast iteration development
- **Gas Settings**: 0.1 gwei gas price, 8M gas limit
- **Confirmations**: 1 block (sub-second finality)

### Protocol Parameters

- **Interest Rates**: 2% base, 8% slope, 250% jump rate
- **Risk Management**: 70% LTV, 80% liquidation threshold, 5% penalty
- **Liquidation**: 30-second delay (optimized for Somnia speed)
- **Price Updates**: 15-second intervals (high TPS capability)

## File Structure

```
scripts/
├── deployment/
│   ├── deploy-all.sh         # Complete deployment
│   ├── deploy-contracts.sh   # Smart contracts
│   ├── deploy-backend.sh     # Backend services
│   ├── deploy-frontend.sh    # Frontend app
│   └── check-contracts.sh    # Compilation check
└── ...

packages/contracts/scripts/
├── deploy/
│   ├── 00_deploy_somnia_optimized.ts  # Full Somnia deployment
│   └── deploy-simple.ts               # Quick testing
└── utils/
    ├── constants.ts          # Somnia-specific constants
    ├── helpers.ts           # Deployment utilities
    ├── save-deployment.ts   # Deployment tracking
    └── verify.ts           # Contract verification
```

## Environment Variables

Required for deployment:

```bash
# Deployment
DEPLOYER_PRIVATE_KEY=        # Deployer wallet private key
NETWORK=somnia-testnet       # Target network
ENVIRONMENT=development      # Environment type

# Optional
DEPLOY_VERIFY=true          # Enable contract verification
DATABASE_URL=               # Backend database connection
```

## Troubleshooting

### Common Issues

1. **Compilation Errors**: Run `npx hardhat clean && npx hardhat compile`
2. **Gas Issues**: Ensure sufficient STT balance for deployment
3. **Network Issues**: Verify RPC URLs and chain IDs
4. **Contract Verification**: Check explorer API URLs

### Support

For hackathon support:

1. Check contract compilation with `check-contracts.sh`
2. Use `deploy-simple.ts` for quick iteration
3. Review deployment logs in `deployments/` directory
4. Test locally before deploying to Somnia

## Next Steps

After successful deployment:

1. Update frontend with contract addresses
2. Test core DeFi operations (supply, borrow, liquidate)
3. Enable account abstraction features
4. Submit hackathon project!
