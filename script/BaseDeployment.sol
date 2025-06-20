// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title BaseDeployment
 * @notice Base contract for deployment scripts with common utilities
 * @author STRAPT Team
 */
abstract contract BaseDeployment is Script {
    // Environment variables
    uint256 internal deployerPrivateKey;
    address internal deployer;

    // Network information
    uint256 internal chainId;
    string internal networkName;

    // Deployment configuration
    address internal transferLinkFeeCollector;
    uint16 internal transferLinkFeeBasisPoints;
    address internal straptGiftFeeCollector;
    uint256 internal straptGiftFeePercentage;

    // Deployment tracking
    mapping(string => address) internal deployedContracts;

    /**
     * @notice Initialize deployment configuration from environment variables
     */
    function initializeConfig() internal {
        // Get deployer private key
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Get network information
        chainId = block.chainid;
        networkName = getNetworkName(chainId);

        // Get fee configuration
        transferLinkFeeCollector = vm.envOr("TRANSFER_LINK_FEE_COLLECTOR", deployer);
        transferLinkFeeBasisPoints = uint16(vm.envOr("TRANSFER_LINK_FEE_BASIS_POINTS", uint256(50)));
        straptGiftFeeCollector = vm.envOr("STRAPT_GIFT_FEE_COLLECTOR", deployer);
        straptGiftFeePercentage = vm.envOr("STRAPT_GIFT_FEE_PERCENTAGE", uint256(10));

        // Validate configuration
        validateConfig();

        console.log("=== Deployment Configuration ===");
        console.log("Network:", networkName);
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("TransferLink Fee Collector:", transferLinkFeeCollector);
        console.log("TransferLink Fee Basis Points:", transferLinkFeeBasisPoints);
        console.log("StraptGift Fee Collector:", straptGiftFeeCollector);
        console.log("StraptGift Fee Percentage:", straptGiftFeePercentage);
        console.log("================================");
    }

    /**
     * @notice Validate deployment configuration
     */
    function validateConfig() internal view {
        require(deployer != address(0), "Invalid deployer address");
        require(transferLinkFeeCollector != address(0), "Invalid TransferLink fee collector");
        require(straptGiftFeeCollector != address(0), "Invalid StraptGift fee collector");
        require(transferLinkFeeBasisPoints <= 1000, "TransferLink fee too high (max 10%)");
        require(straptGiftFeePercentage <= 50, "StraptGift fee too high (max 0.5%)");
    }

    /**
     * @notice Get network name from chain ID
     */
    function getNetworkName(uint256 _chainId) internal pure returns (string memory) {
        if (_chainId == 1) return "mainnet";
        if (_chainId == 11155111) return "sepolia";
        if (_chainId == 137) return "polygon";
        if (_chainId == 80001) return "mumbai";
        if (_chainId == 42161) return "arbitrum";
        if (_chainId == 421614) return "arbitrum-sepolia";
        if (_chainId == 8453) return "base";
        if (_chainId == 84532) return "base-sepolia";
        if (_chainId == 5003) return "mantle-sepolia";
        if (_chainId == 5000) return "mantle";
        if (_chainId == 31337) return "localhost";
        return "unknown";
    }

    /**
     * @notice Save deployment information to file
     */
    function saveDeploymentInfo(
        string memory contractName,
        address contractAddress,
        string memory additionalInfo
    ) internal {
        string memory deploymentDir = "./deployments/";
        string memory filename = string.concat(contractName, "-", networkName, ".json");
        string memory filepath = string.concat(deploymentDir, filename);

        // Create deployment info JSON
        string memory json = string.concat(
            '{\n',
            '  "contractName": "', contractName, '",\n',
            '  "contractAddress": "', vm.toString(contractAddress), '",\n',
            '  "network": "', networkName, '",\n',
            '  "chainId": ', vm.toString(chainId), ',\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "deploymentTime": ', vm.toString(block.timestamp), ',\n',
            '  "blockNumber": ', vm.toString(block.number), ',\n',
            additionalInfo,
            '\n}'
        );

        // Try to write to file, handle permission errors gracefully
        try vm.writeFile(filepath, json) {
            console.log("Deployment info saved to:", filepath);
        } catch {
            console.log("Note: Could not save deployment file (permission issue in simulation)");
            console.log("Deployment info would be saved to:", filepath);
            console.log("JSON content:");
            console.log(json);
        }
    }

    /**
     * @notice Save combined deployment information for multiple contracts
     */
    function saveCombinedDeploymentInfo(
        address transferLinkAddress,
        address straptGiftAddress
    ) internal {
        string memory deploymentDir = "./deployments/";
        string memory filename = string.concat("strapt-contracts-", networkName, ".json");
        string memory filepath = string.concat(deploymentDir, filename);

        // Create combined deployment info JSON
        string memory json = string.concat(
            '{\n',
            '  "network": "', networkName, '",\n',
            '  "chainId": ', vm.toString(chainId), ',\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "deploymentTime": ', vm.toString(block.timestamp), ',\n',
            '  "blockNumber": ', vm.toString(block.number), ',\n',
            '  "contracts": {\n',
            '    "TransferLink": {\n',
            '      "address": "', vm.toString(transferLinkAddress), '",\n',
            '      "feeCollector": "', vm.toString(transferLinkFeeCollector), '",\n',
            '      "feeBasisPoints": ', vm.toString(transferLinkFeeBasisPoints), '\n',
            '    },\n',
            '    "StraptGift": {\n',
            '      "address": "', vm.toString(straptGiftAddress), '",\n',
            '      "feeCollector": "', vm.toString(straptGiftFeeCollector), '",\n',
            '      "feePercentage": ', vm.toString(straptGiftFeePercentage), '\n',
            '    }\n',
            '  }\n',
            '}'
        );

        // Try to write to file, handle permission errors gracefully
        try vm.writeFile(filepath, json) {
            console.log("Combined deployment info saved to:", filepath);
        } catch {
            console.log("Note: Could not save combined deployment file (permission issue in simulation)");
            console.log("Combined deployment info would be saved to:", filepath);
            console.log("JSON content:");
            console.log(json);
        }
    }

    /**
     * @notice Log deployment summary
     */
    function logDeploymentSummary(
        address transferLinkAddress,
        address straptGiftAddress
    ) internal view {
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", networkName);
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("TransferLink Contract:", transferLinkAddress);
        console.log("  - Fee Collector:", transferLinkFeeCollector);
        console.log("  - Fee Basis Points:", transferLinkFeeBasisPoints);
        console.log("");
        console.log("StraptGift Contract:", straptGiftAddress);
        console.log("  - Fee Collector:", straptGiftFeeCollector);
        console.log("  - Fee Percentage:", straptGiftFeePercentage);
        console.log("==========================");
    }
}
