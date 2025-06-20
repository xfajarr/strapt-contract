// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ProtectedTransferOptimized.sol";

contract DeployOptimized is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying ProtectedTransferOptimized...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with 0.1% fee (10 basis points) and deployer as fee collector
        ProtectedTransferOptimized protectedTransfer = new ProtectedTransferOptimized(
            deployer, // Fee collector
            10        // 0.1% fee (10 basis points)
        );

        console.log("ProtectedTransferOptimized deployed at:", address(protectedTransfer));

        // Enable USDT and USDC support
        address USDT = 0x14E8799ae8Da79229990c9d5fBBA993dD663739C;
        address USDC = 0xf6f8CF56DF9caD9Cd2248A566755b8d0e56a5bEe;

        console.log("Enabling token support...");
        
        address[] memory tokens = new address[](2);
        bool[] memory statuses = new bool[](2);
        
        tokens[0] = USDT;
        tokens[1] = USDC;
        statuses[0] = true;
        statuses[1] = true;
        
        protectedTransfer.batchSetTokenSupport(tokens, statuses);
        
        console.log("USDT support enabled:", USDT);
        console.log("USDC support enabled:", USDC);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Contract:", address(protectedTransfer));
        console.log("Fee Collector:", deployer);
        console.log("Fee Rate: 0.1% (10 basis points)");
        console.log("USDT Supported:", USDT);
        console.log("USDC Supported:", USDC);
        console.log("==========================");
    }
}
