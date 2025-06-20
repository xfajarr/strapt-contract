// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract VerifyLinkTransfer is Script {
    function run() external {
        // Contract details
        address contractAddress = 0x665b473f252c52b1AEa6C55416E252caD19Ab5dA;
        address feeCollector = 0x07895b9b1a6f1b9610813ba28189c1e403680b59;
        uint16 feeInBasisPoints = 0;
        
        console.log("Verifying LinkTransferOptimized contract...");
        console.log("Contract Address:", contractAddress);
        console.log("Fee Collector:", feeCollector);
        console.log("Fee in Basis Points:", feeInBasisPoints);
        
        // Verify the contract
        vm.startBroadcast();
        
        // This will automatically verify with correct constructor args
        string[] memory cmd = new string[](10);
        cmd[0] = "forge";
        cmd[1] = "verify-contract";
        cmd[2] = "--verifier-url";
        cmd[3] = "https://api-sepolia.mantlescan.xyz/api";
        cmd[4] = "--etherscan-api-key";
        cmd[5] = "JZAQV9U4DGIBU7IF2GUFVEUQ5Q51T26G19";
        cmd[6] = "--compiler-version";
        cmd[7] = "v0.8.28+commit.7893614a";
        cmd[8] = vm.toString(contractAddress);
        cmd[9] = "src/LinkTransferOptimized.sol:LinkTransferOptimized";
        
        vm.stopBroadcast();
        
        console.log("Verification command prepared. Run manually:");
        console.log("forge verify-contract --verifier-url https://api-sepolia.mantlescan.xyz/api --etherscan-api-key JZAQV9U4DGIBU7IF2GUFVEUQ5Q51T26G19 --compiler-version v0.8.28+commit.7893614a", contractAddress, "src/LinkTransferOptimized.sol:LinkTransferOptimized --constructor-args $(cast abi-encode \"constructor(address,uint16)\"", feeCollector, feeInBasisPoints, ")");
    }
}
