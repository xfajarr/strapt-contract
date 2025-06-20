// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BaseDeployment.sol";
import "../src/TransferLink.sol";
import "../src/StraptGift.sol";

/**
 * @title Deploy
 * @notice Universal deployment script for STRAPT contracts on any supported network
 * @author STRAPT Team
 *
 * @dev Usage:
 * forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
 *
 * Supported Networks:
 * - Ethereum Mainnet (1)
 * - Ethereum Sepolia (11155111)
 * - Polygon (137)
 * - Polygon Mumbai (80001)
 * - Arbitrum (42161)
 * - Arbitrum Sepolia (421614)
 * - Base (8453)
 * - Base Sepolia (84532)
 * - Mantle (5000)
 * - Mantle Sepolia (5003)
 * - Localhost (31337)
 */
contract Deploy is BaseDeployment {
    TransferLink public transferLink;
    StraptGift public straptGift;

    function run() external {
        initializeConfig();

        console.log("\n=== Universal STRAPT Deployment ===");
        console.log("Deploying to:", networkName);

        // Validate network support
        validateNetwork();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TransferLink
        console.log("\nDeploying TransferLink...");
        transferLink = new TransferLink(
            transferLinkFeeCollector,
            transferLinkFeeBasisPoints
        );
        console.log("TransferLink deployed at:", address(transferLink));

        // Deploy StraptGift
        console.log("\nDeploying StraptGift...");
        straptGift = new StraptGift();
        console.log("StraptGift deployed at:", address(straptGift));

        // Configure StraptGift
        console.log("\nConfiguring StraptGift...");
        straptGift.setFeeCollector(straptGiftFeeCollector);
        straptGift.setFeePercentage(straptGiftFeePercentage);
        console.log("StraptGift configured successfully");

        vm.stopBroadcast();

        // Post-deployment verification
        verifyDeployment();

        // Save deployment artifacts
        saveDeploymentArtifacts();

        // Log summary
        logDeploymentSummary(address(transferLink), address(straptGift));

        console.log("\n=== Deployment Completed Successfully ===");
    }

    /**
     * @notice Validate that the current network is supported
     */
    function validateNetwork() internal view {
        bool isSupported =
            chainId == 1 ||      // Ethereum Mainnet
            chainId == 11155111 || // Ethereum Sepolia
            chainId == 137 ||    // Polygon
            chainId == 80001 ||  // Polygon Mumbai
            chainId == 42161 ||  // Arbitrum
            chainId == 421614 || // Arbitrum Sepolia
            chainId == 8453 ||   // Base
            chainId == 84532 ||  // Base Sepolia
            chainId == 5000 ||   // Mantle
            chainId == 5003 ||   // Mantle Sepolia
            chainId == 31337;    // Localhost

        require(isSupported, string.concat("Unsupported network. Chain ID: ", vm.toString(chainId)));

        console.log("Network validation passed");
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
     * @notice Save deployment artifacts
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
}
