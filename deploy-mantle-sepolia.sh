#!/bin/bash

# STRAPT Mantle Sepolia Deployment Script
# Usage: ./deploy-mantle-sepolia.sh [--verify] [--dry-run] [--help]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERIFY=false
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            VERIFY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "STRAPT Mantle Sepolia Deployment Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verify    Enable contract verification on Mantlescan"
            echo "  --dry-run   Simulate deployment without broadcasting"
            echo "  --help, -h  Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PRIVATE_KEY                    Deployer private key (required)"
            echo "  MANTLE_RPC_URL                 Mantle Sepolia RPC URL (optional)"
            echo "  MANTLESCAN_API_KEY            Mantlescan API key (required for --verify)"
            echo "  TRANSFER_LINK_FEE_COLLECTOR   Fee collector address (optional)"
            echo "  TRANSFER_LINK_FEE_BASIS_POINTS Fee in basis points (optional)"
            echo "  STRAPT_GIFT_FEE_COLLECTOR     Fee collector address (optional)"
            echo "  STRAPT_GIFT_FEE_PERCENTAGE    Fee percentage (optional)"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if forge is installed
    if ! command_exists forge; then
        print_error "Foundry (forge) is not installed. Please install it from https://book.getfoundry.sh/"
        exit 1
    fi

    # Check if .env file exists
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        print_warning ".env file not found. Using environment variables or defaults."
    else
        print_status "Loading environment variables from .env file"
        source "$SCRIPT_DIR/.env"
    fi

    # Check required environment variables
    if [[ -z "$PRIVATE_KEY" ]]; then
        print_error "PRIVATE_KEY environment variable is required"
        exit 1
    fi

    # Set default RPC URL if not provided
    if [[ -z "$MANTLE_RPC_URL" ]]; then
        export MANTLE_RPC_URL="https://rpc.sepolia.mantle.xyz"
        print_warning "Using default Mantle Sepolia RPC URL: $MANTLE_RPC_URL"
    fi

    # Check verification requirements
    if [[ "$VERIFY" == true && -z "$MANTLESCAN_API_KEY" ]]; then
        print_error "MANTLESCAN_API_KEY is required for contract verification"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to estimate gas costs
estimate_gas() {
    print_status "Estimating deployment costs..."

    # Get current gas price (in wei)
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$MANTLE_RPC_URL" 2>/dev/null || echo "1000000000") # 1 gwei fallback

    # Estimated gas usage
    local transfer_link_gas=2500000
    local strapt_gift_gas=2200000
    local config_gas=100000
    local total_gas=$((transfer_link_gas + strapt_gift_gas + config_gas))

    # Calculate costs in wei and MNT
    local total_cost_wei=$((total_gas * gas_price))
    local total_cost_mnt=$(echo "scale=6; $total_cost_wei / 1000000000000000000" | bc -l 2>/dev/null || echo "~0.005")

    echo -e "${BLUE}Gas Estimation:${NC}"
    echo "  TransferLink: ~$transfer_link_gas gas"
    echo "  StraptGift: ~$strapt_gift_gas gas"
    echo "  Configuration: ~$config_gas gas"
    echo "  Total: ~$total_gas gas"
    echo "  Estimated cost: ~$total_cost_mnt MNT"
}

# Function to run deployment
run_deployment() {
    local forge_cmd="forge script script/DeployMantleSepolia.s.sol --rpc-url $MANTLE_RPC_URL"

    if [[ "$DRY_RUN" == true ]]; then
        print_status "Running dry run (simulation only)..."
        # No additional flags needed for dry run
    else
        print_status "Running actual deployment..."
        forge_cmd="$forge_cmd --broadcast"

        if [[ "$VERIFY" == true ]]; then
            forge_cmd="$forge_cmd --verify"
        fi
    fi

    print_status "Executing: $forge_cmd"

    # Run the deployment
    if eval "$forge_cmd"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_success "Dry run completed successfully"
        else
            print_success "Deployment completed successfully"
        fi
    else
        print_error "Deployment failed"
        exit 1
    fi
}

# Function to display post-deployment information
show_post_deployment_info() {
    if [[ "$DRY_RUN" == true ]]; then
        return
    fi

    echo ""
    echo -e "${GREEN}=== DEPLOYMENT COMPLETED ===${NC}"
    echo ""
    echo "Network: Mantle Sepolia Testnet"
    echo "Chain ID: 5003"
    echo "RPC URL: $MANTLE_RPC_URL"
    echo "Explorer: https://sepolia.mantlescan.xyz/"
    echo ""
    echo "Deployment artifacts saved in: deployments/"
    echo ""
    echo "Next steps:"
    echo "1. Verify contract addresses in the deployment files"
    echo "2. Test contract functionality with small transactions"
    echo "3. Update frontend configuration with new addresses"
    echo "4. Monitor contract performance"
    echo ""

    if [[ "$VERIFY" == true ]]; then
        echo "Contracts have been verified on Mantlescan"
    else
        echo "To verify contracts later, run with --verify flag"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}STRAPT Mantle Sepolia Deployment${NC}"
    echo "=================================="
    echo ""

    check_prerequisites
    estimate_gas

    echo ""
    if [[ "$DRY_RUN" == false ]]; then
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled by user"
            exit 0
        fi
    fi

    run_deployment
    show_post_deployment_info
}

# Run main function
main "$@"
