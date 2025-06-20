#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default network is Mantle Sepolia
NETWORK=${1:-"mantle-sepolia"}

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}Loaded environment variables from .env${NC}"
    
    # Debug: Print environment variables (masked for security)
    echo -e "${YELLOW}Debug: Checking environment variables${NC}"
    if [ -n "$PRIVATE_KEY" ]; then
        echo "PRIVATE_KEY: [Set]"
    else
        echo "PRIVATE_KEY: [Not Set]"
    fi
    
    if [ -n "$MANTLE_RPC_URL" ]; then
        echo "MANTLE_RPC_URL: $MANTLE_RPC_URL"
    else
        echo "MANTLE_RPC_URL: [Not Set]"
    fi
    
    if [ -n "$MANTLESCAN_API_KEY" ]; then
        echo "MANTLESCAN_API_KEY: [Set]"
    else
        echo "MANTLESCAN_API_KEY: [Not Set]"
    fi
else
    echo -e "${YELLOW}Warning: .env file not found${NC}"
fi

# Set RPC URL based on network
case "$NETWORK" in
    "mantle-sepolia")
        RPC_URL=${MANTLE_RPC_URL:-"https://rpc.sepolia.mantle.xyz"}
        EXPLORER="https://explorer.sepolia.mantle.xyz"
        ;;
    "sepolia")
        RPC_URL=${SEPOLIA_RPC_URL:-"https://rpc.sepolia.org"}
        EXPLORER="https://sepolia.etherscan.io"
        ;;
    "lisk-sepolia")
        RPC_URL=${LISK_SEPOLIA_RPC_URL:-"https://sepolia-rpc.lisk.com"}
        EXPLORER="https://sepolia-explorer.lisk.com"
        ;;
    *)
        echo -e "${RED}Error: Unsupported network: $NETWORK${NC}"
        echo "Supported networks: mantle-sepolia, sepolia, lisk-sepolia"
        exit 1
        ;;
esac

echo -e "${GREEN}Deploying Mock Tokens to $NETWORK${NC}"
echo "RPC URL: $RPC_URL"

# Check if private key is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY environment variable is not set${NC}"
    echo "Please set it in your .env file"
    exit 1
fi

# Compile contracts
echo -e "${GREEN}Compiling contracts...${NC}"
forge build

# Deploy contracts
echo -e "${GREEN}Deploying MockUSDC and MockUSDT...${NC}"

# Check if verification is possible
VERIFY_FLAG=""
if [ "$NETWORK" = "mantle-sepolia" ] && [ -n "$MANTLESCAN_API_KEY" ]; then
    echo -e "${GREEN}Will verify contracts on Mantlescan${NC}"
    VERIFY_FLAG="--verify --etherscan-api-key $MANTLESCAN_API_KEY --verifier-url https://api-sepolia.mantlescan.xyz/api"
else
    echo -e "${YELLOW}Skipping contract verification${NC}"
    if [ "$NETWORK" = "mantle-sepolia" ]; then
        echo "MANTLESCAN_API_KEY is not set in environment"
    fi
fi

# Run the deployment command
DEPLOY_CMD="forge script script/DeployMockTokens.s.sol --rpc-url \"$RPC_URL\" --private-key \"$PRIVATE_KEY\" --broadcast $VERIFY_FLAG"
echo -e "${GREEN}Running: $DEPLOY_CMD${NC}"

# Execute the command
eval $DEPLOY_CMD

# Check if deployment was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo -e "View your transactions on the explorer: ${EXPLORER}"
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi

