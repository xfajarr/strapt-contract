#!/bin/bash

# Setup token support for TransferLink contract on Mantle Sepolia
# This script enables MockUSDC and MockUSDT tokens in the deployed TransferLink contract

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setting up Token Support for TransferLink ===${NC}"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create a .env file with your PRIVATE_KEY"
    exit 1
fi

# Load environment variables
source .env

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env file${NC}"
    exit 1
fi

# Contract addresses
TRANSFER_LINK_ADDRESS="0x7E0334471dC5520260c98a171Fea363D5EfEfB48"
MOCK_USDC_ADDRESS="0xf6f8CF56DF9caD9Cd2248A566755b8d0e56a5bEe"
MOCK_USDT_ADDRESS="0x14E8799ae8Da79229990c9d5fBBA993dD663739C"

echo "TransferLink Contract: $TRANSFER_LINK_ADDRESS"
echo "MockUSDC Address: $MOCK_USDC_ADDRESS"
echo "MockUSDT Address: $MOCK_USDT_ADDRESS"
echo ""

# Set RPC URL
RPC_URL=${MANTLE_SEPOLIA_RPC_URL:-"https://rpc.sepolia.mantle.xyz"}
echo "Using RPC URL: $RPC_URL"
echo ""

echo -e "${YELLOW}Checking current token support status...${NC}"

# Check current token support status
echo "Checking MockUSDC support..."
USDC_SUPPORTED=$(cast call $TRANSFER_LINK_ADDRESS "supportedTokens(address)(bool)" $MOCK_USDC_ADDRESS --rpc-url "$RPC_URL")
echo "MockUSDC currently supported: $USDC_SUPPORTED"

echo "Checking MockUSDT support..."
USDT_SUPPORTED=$(cast call $TRANSFER_LINK_ADDRESS "supportedTokens(address)(bool)" $MOCK_USDT_ADDRESS --rpc-url "$RPC_URL")
echo "MockUSDT currently supported: $USDT_SUPPORTED"

echo ""
echo -e "${YELLOW}Setting up token support...${NC}"

# Enable MockUSDC support if not already enabled
if [ "$USDC_SUPPORTED" = "false" ]; then
    echo "Enabling MockUSDC support..."
    cast send $TRANSFER_LINK_ADDRESS "setTokenSupport(address,bool)" $MOCK_USDC_ADDRESS true \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY"

    if [ $? -eq 0 ]; then
        echo "✅ MockUSDC support enabled successfully"
    else
        echo "❌ Failed to enable MockUSDC support"
        exit 1
    fi
else
    echo "✅ MockUSDC already supported"
fi

# Enable MockUSDT support if not already enabled
if [ "$USDT_SUPPORTED" = "false" ]; then
    echo "Enabling MockUSDT support..."
    cast send $TRANSFER_LINK_ADDRESS "setTokenSupport(address,bool)" $MOCK_USDT_ADDRESS true \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY"

    if [ $? -eq 0 ]; then
        echo "✅ MockUSDT support enabled successfully"
    else
        echo "❌ Failed to enable MockUSDT support"
        exit 1
    fi
else
    echo "✅ MockUSDT already supported"
fi

echo ""
echo -e "${YELLOW}Verifying final token support status...${NC}"

# Verify final status
FINAL_USDC_SUPPORTED=$(cast call $TRANSFER_LINK_ADDRESS "supportedTokens(address)(bool)" $MOCK_USDC_ADDRESS --rpc-url "$RPC_URL")
FINAL_USDT_SUPPORTED=$(cast call $TRANSFER_LINK_ADDRESS "supportedTokens(address)(bool)" $MOCK_USDT_ADDRESS --rpc-url "$RPC_URL")

echo "Final MockUSDC support status: $FINAL_USDC_SUPPORTED"
echo "Final MockUSDT support status: $FINAL_USDT_SUPPORTED"

if [ "$FINAL_USDC_SUPPORTED" = "true" ] && [ "$FINAL_USDT_SUPPORTED" = "true" ]; then
    echo ""
    echo -e "${GREEN}=== Token Support Setup Completed Successfully ===${NC}"
    echo ""
    echo "✅ MockUSDC and MockUSDT are now supported by the TransferLink contract!"
    echo ""
    echo "You can now:"
    echo "1. Create transfers using MockUSDC"
    echo "2. Create transfers using MockUSDT"
    echo "3. Test the frontend functionality"
    echo ""
    echo "Next steps:"
    echo "1. Test creating a transfer in the frontend"
    echo "2. Verify the transaction succeeds"
    echo ""
else
    echo ""
    echo -e "${RED}=== Token Support Setup Failed ===${NC}"
    echo ""
    echo "❌ One or more tokens are still not supported."
    echo ""
    echo "Please check the error messages above and try again."
    echo ""
    echo "Common issues:"
    echo "1. Insufficient ETH balance for gas fees"
    echo "2. Wrong private key or network configuration"
    echo "3. Not the contract owner (only owner can set token support)"
    echo ""
    exit 1
fi
