// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BaseDeployment.sol";
import "../src/TransferLink.sol";
import "../src/StraptGift.sol";

/**
 * @title DeployMantleSepolia
 * @notice Deployment script for STRAPT contracts on Mantle Sepolia testnet
 * @author STRAPT Team
 *
 * @dev Usage:
 * forge script script/DeployMantleSepolia.s.sol --rpc-url $MANTLE_RPC_URL --broadcast --verify
 */
contract DeployMantleSepolia is BaseDeployment {
    // Deployed contract instances
    TransferLink public transferLink;
    StraptGift public straptGift;

    /**
     * @notice Main deployment function
     */
    function run() external {
        // Initialize configuration
        initializeConfig();

        // Verify we're on Mantle Sepolia
        require(chainId == 5003, "This script is only for Mantle Sepolia (Chain ID: 5003)");

        console.log("\n=== Starting Mantle Sepolia Deployment ===");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy TransferLink contract
        console.log("\nDeploying TransferLink...");
        transferLink = new TransferLink(
            transferLinkFeeCollector,
            transferLinkFeeBasisPoints
        );
        console.log("TransferLink deployed at:", address(transferLink));

        // Deploy StraptGift contract
        console.log("\nDeploying StraptGift...");
        straptGift = new StraptGift();
        console.log("StraptGift deployed at:", address(straptGift));

        // Configure StraptGift
        console.log("\nConfiguring StraptGift...");
        straptGift.setFeeCollector(straptGiftFeeCollector);
        straptGift.setFeePercentage(straptGiftFeePercentage);
        console.log("StraptGift configured successfully");

        // Stop broadcasting
        vm.stopBroadcast();

        // Post-deployment verification
        verifyDeployment();

        // Save deployment information
        saveDeploymentArtifacts();

        // Log summary
        logDeploymentSummary(address(transferLink), address(straptGift));

        console.log("\n=== Deployment Completed Successfully ===");
    }

    /**
     * @notice Verify deployment was successful
     */
    function verifyDeployment() internal view {
        console.log("\n=== Verifying Deployment ===");

        // Verify TransferLink
        require(address(transferLink) != address(0), "TransferLink deployment failed");
        require(transferLink.feeCollector() == transferLinkFeeCollector, "TransferLink fee collector mismatch");
        require(transferLink.feeInBasisPoints() == transferLinkFeeBasisPoints, "TransferLink fee basis points mismatch");
        require(transferLink.owner() == deployer, "TransferLink owner mismatch");
        console.log("TransferLink verification passed");

        // Verify StraptGift
        require(address(straptGift) != address(0), "StraptGift deployment failed");
        require(straptGift.feeCollector() == straptGiftFeeCollector, "StraptGift fee collector mismatch");
        require(straptGift.feePercentage() == straptGiftFeePercentage, "StraptGift fee percentage mismatch");
        require(straptGift.owner() == deployer, "StraptGift owner mismatch");
        console.log("StraptGift verification passed");

        console.log("All contracts verified successfully");
    }

    /**
     * @notice Save deployment artifacts and information
     */
    function saveDeploymentArtifacts() internal {
        console.log("\n=== Saving Deployment Artifacts ===");

        // Save individual contract deployment info
        saveDeploymentInfo(
            "TransferLink",
            address(transferLink),
            string.concat(
                '  "feeCollector": "', vm.toString(transferLinkFeeCollector), '",\n',
                '  "feeBasisPoints": ', vm.toString(transferLinkFeeBasisPoints), ','
            )
        );

        saveDeploymentInfo(
            "StraptGift",
            address(straptGift),
            string.concat(
                '  "feeCollector": "', vm.toString(straptGiftFeeCollector), '",\n',
                '  "feePercentage": ', vm.toString(straptGiftFeePercentage), ','
            )
        );

        // Save combined deployment info
        saveCombinedDeploymentInfo(address(transferLink), address(straptGift));

        console.log("Deployment artifacts saved");
    }

    /**
     * @notice Get deployment addresses (for testing/verification)
     */
    function getDeployedAddresses() external view returns (address, address) {
        return (address(transferLink), address(straptGift));
    }

    /**
     * @notice Estimate deployment gas costs
     */
    function estimateGasCosts() external view returns (uint256, uint256, uint256) {
        // These are rough estimates based on contract size
        uint256 transferLinkGas = 2_500_000; // ~2.5M gas
        uint256 straptGiftGas = 2_200_000;   // ~2.2M gas
        uint256 configurationGas = 100_000;  // ~100K gas for configuration

        return (transferLinkGas, straptGiftGas, configurationGas);
    }
}
