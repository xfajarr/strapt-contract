#!/bin/bash

# STRAPT Contract Verification Script for Mantle Sepolia
# Usage: ./verify-contracts.sh [contract_address] [contract_name]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER_URL="https://api-sepolia.mantlescan.xyz/api"
COMPILER_VERSION="v0.8.28+commit.7893614a"

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

# Function to show usage
show_usage() {
    echo "STRAPT Contract Verification Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [CONTRACT_ADDRESS] [CONTRACT_NAME]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --list-deployed     List deployed contracts from deployment files"
    echo "  --verify-all        Verify all deployed contracts"
    echo ""
    echo "Examples:"
    echo "  $0 0xBA222A58508F6c4B11fb72073338196A2e82ad89 StraptGift"
    echo "  $0 0x7E0334471dC5520260c98a171Fea363D5EfEfB48 TransferLink"
    echo "  $0 --verify-all"
    echo "  $0 --list-deployed"
    echo ""
    echo "Environment Variables:"
    echo "  MANTLESCAN_API_KEY  Mantlescan API key (required)"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if .env file exists and load it
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        source "$SCRIPT_DIR/.env"
        print_status "Loaded environment variables from .env file"
    fi

    # Check required environment variables
    if [[ -z "$MANTLESCAN_API_KEY" ]]; then
        print_error "MANTLESCAN_API_KEY environment variable is required"
        print_warning "Please set your Mantlescan API key in .env file"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to list deployed contracts
list_deployed_contracts() {
    print_status "Looking for deployed contracts..."

    local deployment_file="$SCRIPT_DIR/deployments/strapt-contracts-mantle-sepolia.json"

    if [[ ! -f "$deployment_file" ]]; then
        print_warning "No deployment file found at: $deployment_file"
        print_warning "Please deploy contracts first or check the deployment file path"
        return 1
    fi

    print_success "Found deployment file: $deployment_file"
    echo ""
    echo -e "${BLUE}Deployed Contracts:${NC}"

    # Extract contract addresses using simple grep
    local transferlink_addr=$(grep -A 3 '"TransferLink"' "$deployment_file" | grep '"address"' | cut -d'"' -f4)
    local straptgift_addr=$(grep -A 3 '"StraptGift"' "$deployment_file" | grep '"address"' | cut -d'"' -f4)

    echo "  TransferLink: $transferlink_addr"
    echo "  StraptGift:   $straptgift_addr"
    echo ""
    echo "To verify individual contracts:"
    echo "  ./verify-contracts.sh $transferlink_addr TransferLink"
    echo "  ./verify-contracts.sh $straptgift_addr StraptGift"
    echo ""
    echo "To verify all contracts:"
    echo "  ./verify-contracts.sh --verify-all"
}

# Function to verify a single contract
verify_contract() {
    local contract_address="$1"
    local contract_name="$2"

    print_status "Verifying $contract_name at address: $contract_address"

    # Determine contract path based on name
    local contract_path
    case "$contract_name" in
        "TransferLink")
            contract_path="src/TransferLink.sol:TransferLink"
            ;;
        "StraptGift")
            contract_path="src/StraptGift.sol:StraptGift"
            ;;
        *)
            print_error "Unknown contract name: $contract_name"
            print_warning "Supported contracts: TransferLink, StraptGift"
            return 1
            ;;
    esac

    # Run verification
    print_status "Running forge verify-contract..."

    if forge verify-contract \
        --verifier-url "$VERIFIER_URL" \
        --etherscan-api-key "$MANTLESCAN_API_KEY" \
        --compiler-version "$COMPILER_VERSION" \
        "$contract_address" \
        "$contract_path" \
        --watch; then

        print_success "$contract_name verification completed successfully!"
        echo "View on Mantlescan: https://sepolia.mantlescan.xyz/address/$contract_address"
        return 0
    else
        print_error "$contract_name verification failed"
        return 1
    fi
}

# Function to verify all deployed contracts
verify_all_contracts() {
    print_status "Verifying all deployed contracts..."

    local deployment_file="$SCRIPT_DIR/deployments/strapt-contracts-mantle-sepolia.json"

    if [[ ! -f "$deployment_file" ]]; then
        print_error "No deployment file found at: $deployment_file"
        return 1
    fi

    # Extract addresses using simple grep
    local transferlink_addr=$(grep -A 3 '"TransferLink"' "$deployment_file" | grep '"address"' | cut -d'"' -f4)
    local straptgift_addr=$(grep -A 3 '"StraptGift"' "$deployment_file" | grep '"address"' | cut -d'"' -f4)

    local success_count=0
    local total_count=2

    # Verify TransferLink
    echo ""
    if verify_contract "$transferlink_addr" "TransferLink"; then
        ((success_count++))
    fi

    # Verify StraptGift
    echo ""
    if verify_contract "$straptgift_addr" "StraptGift"; then
        ((success_count++))
    fi

    echo ""
    print_status "Verification Summary: $success_count/$total_count contracts verified successfully"

    if [[ $success_count -eq $total_count ]]; then
        print_success "All contracts verified successfully!"
        return 0
    else
        print_warning "Some contracts failed verification"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}STRAPT Contract Verification${NC}"
    echo "============================="
    echo ""

    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --list-deployed)
            check_prerequisites
            list_deployed_contracts
            exit $?
            ;;
        --verify-all)
            check_prerequisites
            verify_all_contracts
            exit $?
            ;;
        "")
            print_error "Missing arguments"
            echo ""
            show_usage
            exit 1
            ;;
        *)
            if [[ $# -lt 2 ]]; then
                print_error "Missing contract name"
                echo ""
                show_usage
                exit 1
            fi

            check_prerequisites
            verify_contract "$1" "$2"
            exit $?
            ;;
    esac
}

# Run main function
main "$@"
