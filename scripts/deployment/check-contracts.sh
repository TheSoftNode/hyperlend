#!/bin/bash

# HyperLend Contract Compilation and Testing Script for Somnia
# Quick verification that everything compiles and works

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔨 HyperLend Smart Contract Compilation Check${NC}"
echo "============================================="

# Check we're in the right directory
if [ ! -f "hardhat.config.ts" ]; then
    echo -e "${RED}❌ Must run from contracts directory${NC}"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    npm install
fi

# Clean previous builds
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
npx hardhat clean

# Compile contracts
echo -e "${YELLOW}🔨 Compiling contracts...${NC}"
npx hardhat compile

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Compilation successful!${NC}"
else
    echo -e "${RED}❌ Compilation failed!${NC}"
    exit 1
fi

# Run tests if they exist
if [ -d "test" ] && [ "$(ls -A test)" ]; then
    echo -e "${YELLOW}🧪 Running tests...${NC}"
    npx hardhat test
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
    else
        echo -e "${RED}❌ Some tests failed!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️ No tests found, skipping test execution${NC}"
fi

# Check if we can run the simple deployment script
echo -e "${YELLOW}🚀 Testing simple deployment script...${NC}"
npx hardhat run scripts/deploy/deploy-simple.ts --network hardhat

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment script works!${NC}"
else
    echo -e "${RED}❌ Deployment script failed!${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 All checks passed! Ready for Somnia deployment!${NC}"
echo -e "${BLUE}💡 Next steps:${NC}"
echo -e "${BLUE}   1. Configure Somnia network in hardhat.config.ts${NC}"
echo -e "${BLUE}   2. Set up environment variables${NC}"
echo -e "${BLUE}   3. Deploy to Somnia testnet${NC}"
echo -e "${BLUE}   4. Test DeFi operations${NC}"
