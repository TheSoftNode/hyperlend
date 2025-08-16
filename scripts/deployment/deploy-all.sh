#!/bin/bash

# HyperLend Full Stack Deployment Script for Somnia
# Deploys contracts, backend, and frontend optimized for Somnia ecosystem

set -e

# Configuration
NETWORK=${NETWORK:-"somnia-testnet"}
ENVIRONMENT=${ENVIRONMENT:-"development"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 HyperLend Full Stack Deployment for Somnia${NC}"
echo "Network: $NETWORK"
echo "Environment: $ENVIRONMENT"
echo "Timestamp: $(date)"
echo "=========================================="

# Deploy smart contracts
deploy_contracts() {
    echo -e "${YELLOW}📝 Deploying smart contracts...${NC}"
    ./scripts/deployment/deploy-contracts.sh
    echo -e "${GREEN}✅ Smart contracts deployed${NC}"
}

# Deploy backend services
deploy_backend() {
    echo -e "${YELLOW}🔧 Deploying backend services...${NC}"
    ./scripts/deployment/deploy-backend.sh
    echo -e "${GREEN}✅ Backend services deployed${NC}"
}

# Deploy frontend application
deploy_frontend() {
    echo -e "${YELLOW}🎨 Deploying frontend application...${NC}"
    ./scripts/deployment/deploy-frontend.sh
    echo -e "${GREEN}✅ Frontend application deployed${NC}"
}

# Run health checks
run_health_checks() {
    echo -e "${YELLOW}🏥 Running health checks...${NC}"
    ./scripts/maintenance/health-check.sh
    echo -e "${GREEN}✅ Health checks completed${NC}"
}

# Main deployment flow
main() {
    echo -e "${BLUE}Starting full stack deployment...${NC}"
    
    # Make scripts executable
    chmod +x scripts/deployment/*.sh
    chmod +x scripts/maintenance/*.sh
    
    deploy_contracts
    deploy_backend
    deploy_frontend
    run_health_checks
    
    echo -e "${GREEN}🎉 Full stack deployment completed successfully!${NC}"
    echo -e "${BLUE}📋 All services are now running on Somnia network${NC}"
    echo -e "${BLUE}🌐 Frontend: Check your deployment logs for URL${NC}"
    echo -e "${BLUE}🔗 Contracts: Check deployments/$NETWORK.json for addresses${NC}"
}

# Run main function
main "$@"
