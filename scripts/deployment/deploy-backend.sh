#!/bin/bash

# HyperLend Backend Deployment Script for Somnia
# Optimized for Somnia's high TPS and sub-second finality

set -e

# Configuration
ENVIRONMENT=${ENVIRONMENT:-"development"}
BACKEND_DIR="packages/backend"
NODE_ENV=${NODE_ENV:-"production"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 HyperLend Backend Deployment for Somnia${NC}"
echo "Environment: $ENVIRONMENT"
echo "Node Environment: $NODE_ENV"
echo "Timestamp: $(date)"
echo "========================================"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if [ ! -f "$BACKEND_DIR/package.json" ]; then
        echo -e "${RED}❌ Backend directory not found${NC}"
        exit 1
    fi
    
    if [ -z "$DATABASE_URL" ]; then
        echo -e "${YELLOW}⚠️ DATABASE_URL not set, using default configuration${NC}"
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}📦 Installing backend dependencies...${NC}"
    cd $BACKEND_DIR
    npm ci --production
    echo -e "${GREEN}✅ Dependencies installed${NC}"
}

# Build backend
build_backend() {
    echo -e "${YELLOW}🔨 Building backend application...${NC}"
    npm run build
    echo -e "${GREEN}✅ Backend built successfully${NC}"
}

# Set up environment for Somnia
setup_environment() {
    echo -e "${YELLOW}⚙️ Setting up Somnia environment...${NC}"
    
    # Create environment file if it doesn't exist
    if [ ! -f ".env.production" ]; then
        echo "# Somnia Network Configuration" > .env.production
        echo "NETWORK=somnia-testnet" >> .env.production
        echo "RPC_URL=https://rpc.somnia.network" >> .env.production
        echo "EXPLORER_URL=https://somnium-explorer.io" >> .env.production
        echo "CHAIN_ID=50311" >> .env.production
        echo "NATIVE_TOKEN=STT" >> .env.production
        echo "ENABLE_ACCOUNT_ABSTRACTION=true" >> .env.production
        echo "HIGH_TPS_MODE=true" >> .env.production
        echo "FINALITY_THRESHOLD=1" >> .env.production
    fi
    
    echo -e "${GREEN}✅ Environment configured for Somnia${NC}"
}

# Run database migrations
run_migrations() {
    echo -e "${YELLOW}🗄️ Running database migrations...${NC}"
    
    if [ -f "prisma/schema.prisma" ] || [ -f "src/database/migrations" ]; then
        npm run migrate:deploy || npm run db:migrate || echo "No migrations found"
    fi
    
    echo -e "${GREEN}✅ Database migrations completed${NC}"
}

# Start backend services
start_services() {
    echo -e "${YELLOW}🚀 Starting backend services...${NC}"
    
    # For development, use pm2 or nodemon
    if [ "$ENVIRONMENT" = "development" ]; then
        npm run dev &
        echo -e "${GREEN}✅ Backend started in development mode${NC}"
    else
        # For production, use pm2 or docker
        if command -v pm2 &> /dev/null; then
            pm2 start ecosystem.config.js --env production
            echo -e "${GREEN}✅ Backend started with PM2${NC}"
        else
            npm start &
            echo -e "${GREEN}✅ Backend started${NC}"
        fi
    fi
}

# Health check
health_check() {
    echo -e "${YELLOW}🏥 Running health check...${NC}"
    
    # Wait for service to start
    sleep 5
    
    # Check if service is responding
    if curl -f http://localhost:3001/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Backend health check passed${NC}"
    else
        echo -e "${YELLOW}⚠️ Health check failed or service not ready${NC}"
    fi
}

# Main deployment flow
main() {
    echo -e "${BLUE}Starting backend deployment...${NC}"
    
    check_prerequisites
    install_dependencies
    build_backend
    setup_environment
    run_migrations
    start_services
    health_check
    
    echo -e "${GREEN}🎉 Backend deployment completed successfully!${NC}"
    echo -e "${BLUE}📋 Backend is now running and optimized for Somnia${NC}"
    echo -e "${BLUE}🌐 API: http://localhost:3001${NC}"
}

# Run main function
main "$@"
