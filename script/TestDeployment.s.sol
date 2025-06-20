// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TransferLink.sol";
import "../src/StraptGift.sol";

/**
 * @title TestDeployment
 * @notice Script to test deployed contracts functionality
 * @author STRAPT Team
 *
 * @dev Usage:
 * forge script script/TestDeployment.s.sol --rpc-url $RPC_URL --broadcast
 */
contract TestDeployment is Script {
    // Contract addresses (set these after deployment)
    address constant TRANSFER_LINK_ADDRESS = address(0); // Update after deployment
    address constant STRAPT_GIFT_ADDRESS = address(0);   // Update after deployment

    TransferLink transferLink;
    StraptGift straptGift;

    function run() external {
        // Load contract instances
        if (TRANSFER_LINK_ADDRESS != address(0)) {
            transferLink = TransferLink(TRANSFER_LINK_ADDRESS);
        }
        if (STRAPT_GIFT_ADDRESS != address(0)) {
            straptGift = StraptGift(STRAPT_GIFT_ADDRESS);
        }

        console.log("=== Testing Deployed Contracts ===");

        // Test TransferLink
        if (address(transferLink) != address(0)) {
            testTransferLink();
        } else {
            console.log("TransferLink address not set - skipping tests");
        }

        // Test StraptGift
        if (address(straptGift) != address(0)) {
            testStraptGift();
        } else {
            console.log("StraptGift address not set - skipping tests");
        }

        console.log("=== Testing Completed ===");
    }

    function testTransferLink() internal view {
        console.log("\n--- Testing TransferLink ---");

        try transferLink.owner() returns (address owner) {
            console.log("Owner:", owner);
        } catch {
            console.log("Failed to get owner");
        }

        try transferLink.feeCollector() returns (address feeCollector) {
            console.log("Fee Collector:", feeCollector);
        } catch {
            console.log("Failed to get fee collector");
        }

        try transferLink.feeInBasisPoints() returns (uint16 feeInBasisPoints) {
            console.log("Fee Basis Points:", feeInBasisPoints);
        } catch {
            console.log("Failed to get fee basis points");
        }

        try transferLink.paused() returns (bool paused) {
            console.log("Paused:", paused);
        } catch {
            console.log("Failed to get paused status");
        }

        console.log("TransferLink tests completed");
    }

    function testStraptGift() internal view {
        console.log("\n--- Testing StraptGift ---");

        try straptGift.owner() returns (address owner) {
            console.log("Owner:", owner);
        } catch {
            console.log("Failed to get owner");
        }

        try straptGift.feeCollector() returns (address feeCollector) {
            console.log("Fee Collector:", feeCollector);
        } catch {
            console.log("Failed to get fee collector");
        }

        try straptGift.feePercentage() returns (uint256 feePercentage) {
            console.log("Fee Percentage:", feePercentage);
        } catch {
            console.log("Failed to get fee percentage");
        }

        console.log("StraptGift tests completed");
    }
}
