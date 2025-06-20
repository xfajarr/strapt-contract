// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BaseDeployment.sol";
import "../src/StraptGift.sol";

/**
 * @title DeployStraptGift
 * @notice Deployment script for StraptGift contract only
 * @author STRAPT Team
 * 
 * @dev Usage:
 * forge script script/DeployStraptGift.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployStraptGift is BaseDeployment {
    StraptGift public straptGift;
    
    function run() external {
        initializeConfig();
        
        console.log("\n=== Deploying StraptGift Only ===");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy StraptGift
        console.log("Deploying StraptGift...");
        straptGift = new StraptGift();
        console.log("StraptGift deployed at:", address(straptGift));
        
        // Configure StraptGift
        console.log("Configuring StraptGift...");
        straptGift.setFeeCollector(straptGiftFeeCollector);
        straptGift.setFeePercentage(straptGiftFeePercentage);
        console.log("StraptGift configured successfully");
        
        vm.stopBroadcast();
        
        // Verify deployment
        require(address(straptGift) != address(0), "StraptGift deployment failed");
        require(straptGift.feeCollector() == straptGiftFeeCollector, "Fee collector mismatch");
        require(straptGift.feePercentage() == straptGiftFeePercentage, "Fee percentage mismatch");
        require(straptGift.owner() == deployer, "Owner mismatch");
        
        // Save deployment info
        saveDeploymentInfo(
            "StraptGift",
            address(straptGift),
            string.concat(
                '  "feeCollector": "', vm.toString(straptGiftFeeCollector), '",\n',
                '  "feePercentage": ', vm.toString(straptGiftFeePercentage), ','
            )
        );
        
        console.log("\n=== StraptGift Deployment Summary ===");
        console.log("Network:", networkName);
        console.log("Contract Address:", address(straptGift));
        console.log("Fee Collector:", straptGiftFeeCollector);
        console.log("Fee Percentage:", straptGiftFeePercentage);
        console.log("====================================");
    }
}
