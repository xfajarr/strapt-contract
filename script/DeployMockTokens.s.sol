// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockERC20.sol";

/**
 * @title DeployMockTokens
 * @notice Deployment script for MockUSDC and MockUSDT tokens
 * @author STRAPT Team
 */
contract DeployMockTokens is Script {
    // Token configuration
    uint8 constant STABLECOIN_DECIMALS = 6;
    uint256 constant INITIAL_SUPPLY = 10_000_000 * 10**6; // 10 million tokens

    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy MockUSDC
        console.log("Deploying MockUSDC...");
        MockERC20 mockUSDC = new MockERC20(
            "USD Coin",
            "USDC",
            STABLECOIN_DECIMALS,
            INITIAL_SUPPLY  // Adding the missing fourth parameter
        );
        
        // Mint initial supply to the deployer
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        mockUSDC.mint(deployer, INITIAL_SUPPLY);
        
        console.log("MockUSDC deployed at:", address(mockUSDC));
        console.log("Initial supply:", INITIAL_SUPPLY / 10**STABLECOIN_DECIMALS, "USDC");

        // Deploy MockUSDT
        console.log("Deploying MockUSDT...");
        MockERC20 mockUSDT = new MockERC20(
            "Tether USD",
            "USDT",
            STABLECOIN_DECIMALS,
            INITIAL_SUPPLY  // Adding the missing fourth parameter
        );
        
        // Mint initial supply to the deployer
        mockUSDT.mint(deployer, INITIAL_SUPPLY);
        
        console.log("MockUSDT deployed at:", address(mockUSDT));
        console.log("Initial supply:", INITIAL_SUPPLY / 10**STABLECOIN_DECIMALS, "USDT");

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("MockUSDC:", address(mockUSDC));
        console.log("MockUSDT:", address(mockUSDT));
        console.log("Deployment timestamp:", block.timestamp);
    }
}

