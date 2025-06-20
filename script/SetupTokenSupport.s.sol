// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TransferLink.sol";

/**
 * @title SetupTokenSupport
 * @notice Script to enable token support for deployed TransferLink contract
 * @author STRAPT Team
 *
 * @dev Usage:
 * forge script script/SetupTokenSupport.s.sol --rpc-url $RPC_URL --broadcast --sig "run()"
 */
contract SetupTokenSupport is Script {
    // Mantle Sepolia addresses
    address constant TRANSFER_LINK_ADDRESS = 0x7E0334471dC5520260c98a171Fea363D5EfEfB48;
    address constant MOCK_USDC_ADDRESS = 0xf6f8CF56DF9caD9Cd2248A566755b8d0e56a5bEe;
    address constant MOCK_USDT_ADDRESS = 0x14E8799ae8Da79229990c9d5fBBA993dD663739C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Setting up token support for TransferLink...");
        console.log("Deployer:", deployer);
        console.log("TransferLink:", TRANSFER_LINK_ADDRESS);
        console.log("MockUSDC:", MOCK_USDC_ADDRESS);
        console.log("MockUSDT:", MOCK_USDT_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        TransferLink transferLink = TransferLink(TRANSFER_LINK_ADDRESS);

        // Check current token support status
        console.log("\nCurrent token support status:");
        console.log("MockUSDC supported:", transferLink.supportedTokens(MOCK_USDC_ADDRESS));
        console.log("MockUSDT supported:", transferLink.supportedTokens(MOCK_USDT_ADDRESS));

        // Enable MockUSDC support if not already enabled
        if (!transferLink.supportedTokens(MOCK_USDC_ADDRESS)) {
            console.log("Enabling MockUSDC support...");
            transferLink.setTokenSupport(MOCK_USDC_ADDRESS, true);
        } else {
            console.log("MockUSDC already supported");
        }

        // Enable MockUSDT support if not already enabled
        if (!transferLink.supportedTokens(MOCK_USDT_ADDRESS)) {
            console.log("Enabling MockUSDT support...");
            transferLink.setTokenSupport(MOCK_USDT_ADDRESS, true);
        } else {
            console.log("MockUSDT already supported");
        }

        vm.stopBroadcast();

        console.log("Token support setup completed successfully!");

        // Verify the final setup
        console.log("\nFinal token support status:");
        console.log("MockUSDC supported:", transferLink.supportedTokens(MOCK_USDC_ADDRESS));
        console.log("MockUSDT supported:", transferLink.supportedTokens(MOCK_USDT_ADDRESS));
    }
}
