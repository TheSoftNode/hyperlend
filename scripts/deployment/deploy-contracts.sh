#!/bin/bash

# HyperLend Smart Contract Deployment Script for Somnia
# Optimized for Somnia blockchain with native STT integration

set -e

# Configuration
NETWORK=${NETWORK:-"somnia-testnet"}
DEPLOYER_PRIVATE_KEY=${DEPLOYER_PRIVATE_KEY:-""}
CONTRACTS_DIR="packages/contracts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 HyperLend Contract Deployment for Somnia${NC}"
echo "Network: $NETWORK"
echo "Timestamp: $(date)"
echo "======================================"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
        echo -e "${RED}❌ DEPLOYER_PRIVATE_KEY environment variable is required${NC}"
        exit 1
    fi
    
    if [ ! -f "$CONTRACTS_DIR/package.json" ]; then
        echo -e "${RED}❌ Contracts directory not found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    cd $CONTRACTS_DIR
    npm install
    echo -e "${GREEN}✅ Dependencies installed${NC}"
}

# Compile contracts
compile_contracts() {
    echo -e "${YELLOW}🔨 Compiling contracts...${NC}"
    npx hardhat compile
    echo -e "${GREEN}✅ Contracts compiled successfully${NC}"
}

# Deploy contracts to Somnia
deploy_contracts() {
    echo -e "${YELLOW}🚀 Deploying contracts to Somnia...${NC}"
    
    # Deploy core contracts in order
    echo -e "${BLUE}Deploying InterestRateModel...${NC}"
    npx hardhat run scripts/deploy/01-deploy-interest-rate-model.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying PriceOracle...${NC}"
    npx hardhat run scripts/deploy/02-deploy-price-oracle.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying RiskManager...${NC}"
    npx hardhat run scripts/deploy/03-deploy-risk-manager.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying LiquidationEngine...${NC}"
    npx hardhat run scripts/deploy/04-deploy-liquidation-engine.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying HLToken...${NC}"
    npx hardhat run scripts/deploy/05-deploy-hl-token.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying DebtToken...${NC}"
    npx hardhat run scripts/deploy/06-deploy-debt-token.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying RewardToken...${NC}"
    npx hardhat run scripts/deploy/07-deploy-reward-token.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying SomniaWrapper...${NC}"
    npx hardhat run scripts/deploy/08-deploy-somnia-wrapper.ts --network $NETWORK
    
    echo -e "${BLUE}Deploying HyperLendPool (main contract)...${NC}"
    npx hardhat run scripts/deploy/09-deploy-hyperlend-pool.ts --network $NETWORK
    
    echo -e "${GREEN}✅ All contracts deployed successfully${NC}"
}

# Verify contracts on Somnia explorer
verify_contracts() {
    echo -e "${YELLOW}🔍 Verifying contracts on Somnia explorer...${NC}"
    
    if [ -f "deployments/$NETWORK.json" ]; then
        npx hardhat run scripts/verify/verify-all.ts --network $NETWORK
        echo -e "${GREEN}✅ Contract verification completed${NC}"
    else
        echo -e "${YELLOW}⚠️ Deployment file not found, skipping verification${NC}"
    fi
}

# Initialize contracts with Somnia-specific configurations
initialize_contracts() {
    echo -e "${YELLOW}⚙️ Initializing contracts for Somnia...${NC}"
    
    # Set up native STT integration
    npx hardhat run scripts/init/01-setup-native-stt.ts --network $NETWORK
    
    # Configure Somnia-specific parameters
    npx hardhat run scripts/init/02-configure-somnia-params.ts --network $NETWORK
    
    # Set initial interest rates optimized for Somnia's high TPS
    npx hardhat run scripts/init/03-setup-interest-rates.ts --network $NETWORK
    
    echo -e "${GREEN}✅ Contract initialization completed${NC}"
}

# Main deployment flow
main() {
    echo -e "${BLUE}Starting HyperLend deployment on Somnia...${NC}"
    
    check_prerequisites
    install_dependencies
    compile_contracts
    deploy_contracts
    verify_contracts
    initialize_contracts
    
    echo -e "${GREEN}🎉 HyperLend deployment completed successfully!${NC}"
    echo -e "${BLUE}📋 Deployment summary saved to: deployments/$NETWORK.json${NC}"
    echo -e "${BLUE}🌐 Somnia Explorer: https://somnium-explorer.io${NC}"
}

# Run main function
main "$@"
