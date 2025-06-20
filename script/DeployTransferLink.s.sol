// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BaseDeployment.sol";
import "../src/TransferLink.sol";

/**
 * @title DeployTransferLink
 * @notice Deployment script for TransferLink contract only
 * @author STRAPT Team
 *
 * @dev Usage:
 * forge script script/DeployTransferLink.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployTransferLink is BaseDeployment {
    TransferLink public transferLink;

    function run() external {
        initializeConfig();

        console.log("\n=== Deploying TransferLink Only ===");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TransferLink
        console.log("Deploying TransferLink...");
        transferLink = new TransferLink(
            transferLinkFeeCollector,
            transferLinkFeeBasisPoints
        );
        console.log("TransferLink deployed at:", address(transferLink));

        vm.stopBroadcast();

        // Verify deployment
        require(address(transferLink) != address(0), "TransferLink deployment failed");
        require(transferLink.feeCollector() == transferLinkFeeCollector, "Fee collector mismatch");
        require(transferLink.feeInBasisPoints() == transferLinkFeeBasisPoints, "Fee basis points mismatch");
        require(transferLink.owner() == deployer, "Owner mismatch");

        // Save deployment info
        saveDeploymentInfo(
            "TransferLink",
            address(transferLink),
            string.concat(
                '  "feeCollector": "', vm.toString(transferLinkFeeCollector), '",\n',
                '  "feeBasisPoints": ', vm.toString(transferLinkFeeBasisPoints), ','
            )
        );

        console.log("\n=== TransferLink Deployment Summary ===");
        console.log("Network:", networkName);
        console.log("Contract Address:", address(transferLink));
        console.log("Fee Collector:", transferLinkFeeCollector);
        console.log("Fee Basis Points:", transferLinkFeeBasisPoints);
        console.log("======================================");
    }
}
