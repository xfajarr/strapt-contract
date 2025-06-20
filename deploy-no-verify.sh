#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Deploying Mock Tokens to Mantle Sepolia${NC}"
echo "RPC URL: https://rpc.sepolia.mantle.xyz"

# Compile contracts
echo -e "${GREEN}Compiling contracts...${NC}"
forge build

# Deploy contracts without verification
echo -e "${GREEN}Deploying MockUSDC and MockUSDT (without verification)...${NC}"
forge script script/DeployMockTokens.s.sol \
    --rpc-url "https://rpc.sepolia.mantle.xyz" \
    --private-key "0x2b4bbbc1a5b8c069f4e9376568a8767306a99dce24bd4a3f6a4b048eb9961710" \
    --broadcast \
    --legacy \
    --skip-simulation

# Check if deployment was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo -e "View your transactions on the explorer: https://explorer.sepolia.mantle.xyz"
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi