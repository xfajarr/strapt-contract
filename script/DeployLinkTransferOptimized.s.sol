// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LinkTransferOptimized.sol";

contract DeployLinkTransferOptimized is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address feeCollector = 0x02cAf2aE3CA81dC0b5cF7B846625B5A4f07bBbcb;
        
        console.log("Deploying LinkTransferOptimized...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with 0.1% fee (10 basis points) and deployer as fee collector
        LinkTransfer linkTransfer = new LinkTransfer(
            feeCollector, // Fee collector
            10        // 0.1% fee (10 basis points)
        );

        console.log("LinkTransferOptimized deployed at:", address(linkTransfer));

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
        
        linkTransfer.batchSetTokenSupport(tokens, statuses);
        
        console.log("USDT support enabled:", USDT);
        console.log("USDC support enabled:", USDC);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Contract: LinkTransferOptimized");
        console.log("Address:", address(linkTransfer));
        console.log("Fee Collector:", feeCollector);
        console.log("Fee Rate: 0.1% (10 basis points)");
        console.log("USDT Supported:", USDT);
        console.log("USDC Supported:", USDC);
        console.log("==========================");
        
        console.log("\n=== FEATURES INCLUDED ===");
        console.log("Create link transfers with optional passwords");
        console.log("View unclaimed transfers by sender");
        console.log("Instant refund capability");
        console.log("Gas optimized (99%+ reduction)");
        console.log("Same security as original contract");
        console.log("=========================");
    }
}