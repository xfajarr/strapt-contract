// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TransferLink} from "../src/TransferLink.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    TransferStatus,
    InvalidTokenAddress,
    Error__InvalidAddress,
    InvalidAmount,
    InvalidExpiryTime,
    InvalidClaimCode,
    TransferAlreadyExists,
    TransferDoesNotExist,
    TransferNotClaimable,
    TransferNotRefundable,
    TransferExpired,
    TransferNotExpired,
    NotIntendedRecipient,
    NotTransferSender,
    TokenNotSupported,
    PasswordProtected,
    NotLinkTransfer,
    ZeroFeeCollector
} from "../src/ITransferLink.sol";

contract TransferLinkTest is Test {
    TransferLink public transferLink;
    MockERC20 public token;

    address public owner;
    address public feeCollector;
    address public alice;
    address public bob;
    address public charlie;

    uint16 public constant FEE_BASIS_POINTS = 100; // 1%
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant TRANSFER_AMOUNT = 1000 * 1e18;

    // Events for testing
    event TransferCreated(
        bytes32 indexed transferId,
        address indexed sender,
        address indexed recipient,
        address tokenAddress,
        uint256 amount,
        uint256 grossAmount,
        uint256 expiry
    );

    event TransferClaimed(
        bytes32 indexed transferId,
        address indexed claimer,
        uint256 amount
    );

    event TransferRefunded(
        bytes32 indexed transferId,
        address indexed sender,
        uint256 amount
    );

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        feeCollector = makeAddr("feeCollector");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18, INITIAL_SUPPLY);

        // Deploy TransferLink contract
        transferLink = new TransferLink(feeCollector, FEE_BASIS_POINTS);

        // Set token as supported
        transferLink.setTokenSupport(address(token), true);

        // Distribute tokens to test accounts
        token.transfer(alice, INITIAL_SUPPLY / 4);
        token.transfer(bob, INITIAL_SUPPLY / 4);
        token.transfer(charlie, INITIAL_SUPPLY / 4);

        // Approve TransferLink contract to spend tokens
        vm.prank(alice);
        token.approve(address(transferLink), type(uint256).max);

        vm.prank(bob);
        token.approve(address(transferLink), type(uint256).max);

        vm.prank(charlie);
        token.approve(address(transferLink), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        assertEq(transferLink.feeCollector(), feeCollector);
        assertEq(transferLink.feeInBasisPoints(), FEE_BASIS_POINTS);
        assertEq(transferLink.owner(), owner);
    }

    function test_Constructor_RevertZeroFeeCollector() public {
        vm.expectRevert(ZeroFeeCollector.selector);
        new TransferLink(address(0), FEE_BASIS_POINTS);
    }

    // ============ Direct Transfer Tests ============

    function test_CreateDirectTransfer_Success() public {
        uint256 expiry = block.timestamp + 1 days;

        // Don't check the transferId in the event since it's generated dynamically
        vm.expectEmit(false, true, true, true);
        emit TransferCreated(
            bytes32(0), // We'll check this separately
            alice,
            bob,
            address(token),
            TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000), // Amount after fee
            TRANSFER_AMOUNT,
            expiry
        );

        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Verify transfer details
        (
            address sender,
            address recipient,
            address tokenAddress,
            uint256 amount,
            uint256 grossAmount,
            uint256 transferExpiry,
            uint8 status,
            uint256 createdAt,
            bool isLinkTransfer,
            bool hasPassword
        ) = transferLink.getTransfer(transferId);

        assertEq(sender, alice);
        assertEq(recipient, bob);
        assertEq(tokenAddress, address(token));
        assertEq(amount, TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000));
        assertEq(grossAmount, TRANSFER_AMOUNT);
        assertEq(transferExpiry, expiry);
        assertEq(status, uint8(TransferStatus.Pending));
        assertEq(createdAt, block.timestamp);
        assertEq(isLinkTransfer, false);
        assertEq(hasPassword, false);

        // Verify token balances
        uint256 expectedFee = TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000;
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY / 4 - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(transferLink)), TRANSFER_AMOUNT - expectedFee);
        assertEq(token.balanceOf(feeCollector), expectedFee);
    }

    function test_CreateDirectTransfer_WithPassword() public {
        string memory password = "secret123";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        // Verify password protection
        assertEq(transferLink.isPasswordProtected(transferId), 1);

        // Verify transfer details
        (,,,,,,,,, bool hasPassword) = transferLink.getTransfer(transferId);
        assertTrue(hasPassword);
    }

    function test_CreateDirectTransfer_DefaultExpiry() public {
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            0, // Use default expiry
            false,
            bytes32(0)
        );

        (,,,,,uint256 expiry,,,,) = transferLink.getTransfer(transferId);
        assertEq(expiry, block.timestamp + transferLink.DEFAULT_EXPIRY_TIME());
    }

    // ============ Direct Transfer Validation Tests ============

    function test_CreateDirectTransfer_RevertInvalidTokenAddress() public {
        vm.prank(alice);
        vm.expectRevert(InvalidTokenAddress.selector);
        transferLink.createDirectTransfer(
            bob,
            address(0),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_RevertInvalidAmount() public {
        vm.prank(alice);
        vm.expectRevert(InvalidAmount.selector);
        transferLink.createDirectTransfer(
            bob,
            address(token),
            0,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_RevertTokenNotSupported() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18, INITIAL_SUPPLY);

        vm.prank(alice);
        vm.expectRevert(TokenNotSupported.selector);
        transferLink.createDirectTransfer(
            bob,
            address(unsupportedToken),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_RevertInvalidRecipient() public {
        vm.prank(alice);
        vm.expectRevert(Error__InvalidAddress.selector);
        transferLink.createDirectTransfer(
            address(0),
            address(token),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_RevertInvalidClaimCode() public {
        vm.prank(alice);
        vm.expectRevert(InvalidClaimCode.selector);
        transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            true, // hasPassword = true
            bytes32(0) // but claimCodeHash is empty
        );
    }

    function test_CreateDirectTransfer_RevertInvalidExpiryTime_Past() public {
        // Set a specific timestamp to ensure we have a valid past time
        vm.warp(1000);

        vm.prank(alice);
        vm.expectRevert(InvalidExpiryTime.selector);
        transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            999, // Past timestamp
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_RevertInvalidExpiryTime_TooFar() public {
        // Set a specific timestamp to ensure we have a valid calculation
        vm.warp(1000);

        vm.prank(alice);
        vm.expectRevert(InvalidExpiryTime.selector);
        transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            1000 + 30 days + 1, // Current time + MAX_EXPIRY_TIME + 1
            false,
            bytes32(0)
        );
    }

    // ============ Link Transfer Tests ============

    function test_CreateLinkTransfer_Success() public {
        uint256 expiry = block.timestamp + 1 days;

        // Don't check the transferId in the event since it's generated dynamically
        vm.expectEmit(false, true, true, true);
        emit TransferCreated(
            bytes32(0), // We'll check this separately
            alice,
            address(0), // No specific recipient for link transfers
            address(token),
            TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000),
            TRANSFER_AMOUNT,
            expiry
        );

        vm.prank(alice);
        bytes32 transferId = transferLink.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Verify transfer details
        (
            address sender,
            address recipient,
            address tokenAddress,
            uint256 amount,
            uint256 grossAmount,
            uint256 transferExpiry,
            uint8 status,
            uint256 createdAt,
            bool isLinkTransfer,
            bool hasPassword
        ) = transferLink.getTransfer(transferId);

        assertEq(sender, alice);
        assertEq(recipient, address(0)); // No specific recipient
        assertEq(tokenAddress, address(token));
        assertEq(amount, TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000));
        assertEq(grossAmount, TRANSFER_AMOUNT);
        assertEq(transferExpiry, expiry);
        assertEq(status, uint8(TransferStatus.Pending));
        assertEq(createdAt, block.timestamp);
        assertEq(isLinkTransfer, true);
        assertEq(hasPassword, false);
    }

    function test_CreateLinkTransfer_WithPassword() public {
        string memory password = "linkPassword";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = transferLink.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        // Verify password protection
        assertEq(transferLink.isPasswordProtected(transferId), 1);

        // Verify transfer details
        (,,,,,,,,, bool hasPassword) = transferLink.getTransfer(transferId);
        assertTrue(hasPassword);
    }

    // ============ Claim Transfer Tests ============

    function test_ClaimDirectTransfer_Success() public {
        // Create a direct transfer
        uint256 expiry = block.timestamp + 1 days;
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        uint256 bobBalanceBefore = token.balanceOf(bob);
        uint256 expectedAmount = TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000);

        vm.expectEmit(true, true, true, true);
        emit TransferClaimed(transferId, bob, expectedAmount);

        // Claim the transfer
        vm.prank(bob);
        transferLink.claimTransfer(transferId, "");

        // Verify balances
        assertEq(token.balanceOf(bob), bobBalanceBefore + expectedAmount);
        assertEq(token.balanceOf(address(transferLink)), 0);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = transferLink.getTransfer(transferId);
        assertEq(status, uint8(TransferStatus.Claimed));
    }

    function test_ClaimDirectTransfer_WithPassword() public {
        string memory password = "secret123";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        // Create a password-protected transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        uint256 bobBalanceBefore = token.balanceOf(bob);
        uint256 expectedAmount = TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000);

        // Claim with correct password
        vm.prank(bob);
        transferLink.claimTransfer(transferId, password);

        // Verify balances
        assertEq(token.balanceOf(bob), bobBalanceBefore + expectedAmount);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = transferLink.getTransfer(transferId);
        assertEq(status, uint8(TransferStatus.Claimed));
    }

    function test_ClaimLinkTransfer_AnyoneCanClaim() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a link transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        uint256 charlieBalanceBefore = token.balanceOf(charlie);
        uint256 expectedAmount = TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000);

        // Charlie (not the intended recipient) can claim link transfer
        vm.prank(charlie);
        transferLink.claimTransfer(transferId, "");

        // Verify balances
        assertEq(token.balanceOf(charlie), charlieBalanceBefore + expectedAmount);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = transferLink.getTransfer(transferId);
        assertEq(status, uint8(TransferStatus.Claimed));
    }

    // ============ Claim Transfer Validation Tests ============

    function test_ClaimTransfer_RevertTransferDoesNotExist() public {
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.prank(bob);
        vm.expectRevert(TransferDoesNotExist.selector);
        transferLink.claimTransfer(nonExistentId, "");
    }

    function test_ClaimTransfer_RevertNotIntendedRecipient() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a direct transfer for bob
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Charlie tries to claim (not the intended recipient)
        vm.prank(charlie);
        vm.expectRevert(NotIntendedRecipient.selector);
        transferLink.claimTransfer(transferId, "");
    }

    function test_ClaimTransfer_RevertInvalidClaimCode() public {
        string memory password = "secret123";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        // Create a password-protected transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        // Try to claim with wrong password
        vm.prank(bob);
        vm.expectRevert(InvalidClaimCode.selector);
        transferLink.claimTransfer(transferId, "wrongpassword");
    }

    function test_ClaimTransfer_RevertTransferExpired() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Try to claim expired transfer
        vm.prank(bob);
        vm.expectRevert(TransferExpired.selector);
        transferLink.claimTransfer(transferId, "");
    }

    function test_ClaimTransfer_RevertAlreadyClaimed() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create and claim a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(bob);
        transferLink.claimTransfer(transferId, "");

        // Try to claim again
        vm.prank(bob);
        vm.expectRevert(TransferNotClaimable.selector);
        transferLink.claimTransfer(transferId, "");
    }

    // ============ Refund Transfer Tests ============

    function test_RefundTransfer_Success() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 expectedAmount = TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000);

        // Fast forward past expiry
        vm.warp(expiry + 1);

        vm.expectEmit(true, true, true, true);
        emit TransferRefunded(transferId, alice, expectedAmount);

        // Refund the transfer
        vm.prank(alice);
        transferLink.refundTransfer(transferId);

        // Verify balances
        assertEq(token.balanceOf(alice), aliceBalanceBefore + expectedAmount);
        assertEq(token.balanceOf(address(transferLink)), 0);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = transferLink.getTransfer(transferId);
        assertEq(status, uint8(TransferStatus.Refunded));
    }

    function test_RefundTransfer_RevertNotExpired() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Try to refund before expiry
        vm.prank(alice);
        vm.expectRevert(TransferNotExpired.selector);
        transferLink.refundTransfer(transferId);
    }

    function test_RefundTransfer_RevertNotTransferSender() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Try to refund as non-sender
        vm.prank(bob);
        vm.expectRevert(NotTransferSender.selector);
        transferLink.refundTransfer(transferId);
    }

    function test_RefundTransfer_RevertAlreadyClaimed() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create and claim a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(bob);
        transferLink.claimTransfer(transferId, "");

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Try to refund claimed transfer
        vm.prank(alice);
        vm.expectRevert(TransferNotRefundable.selector);
        transferLink.refundTransfer(transferId);
    }

    // ============ View Function Tests ============

    function test_IsTransferClaimable() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Should be claimable initially
        assertTrue(transferLink.isTransferClaimable(transferId));

        // Should not be claimable after expiry
        vm.warp(expiry + 1);
        assertFalse(transferLink.isTransferClaimable(transferId));

        // Reset time to before expiry and claim
        vm.warp(expiry - 1 hours);
        vm.prank(bob);
        transferLink.claimTransfer(transferId, "");

        // Should not be claimable after being claimed
        assertFalse(transferLink.isTransferClaimable(transferId));
    }

    function test_GetRecipientTransfers() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create multiple transfers for bob
        vm.prank(alice);
        bytes32 transferId1 = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(charlie);
        bytes32 transferId2 = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );

        // Get bob's transfers
        bytes32[] memory bobTransfers = transferLink.getRecipientTransfers(bob);
        assertEq(bobTransfers.length, 2);
        assertEq(bobTransfers[0], transferId1);
        assertEq(bobTransfers[1], transferId2);

        // Alice should have no transfers as recipient
        bytes32[] memory aliceTransfers = transferLink.getRecipientTransfers(alice);
        assertEq(aliceTransfers.length, 0);
    }

    // ============ Unclaimed Transfer Tests ============

    function test_GetUnclaimedTransfers() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create multiple transfers for bob
        vm.prank(alice);
        bytes32 transferId1 = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(charlie);
        bytes32 transferId2 = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );

        // Both should be unclaimed initially
        bytes32[] memory unclaimedTransfers = transferLink.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 2);
        assertEq(unclaimedTransfers[0], transferId1);
        assertEq(unclaimedTransfers[1], transferId2);

        // Claim one transfer
        vm.prank(bob);
        transferLink.claimTransfer(transferId1, "");

        // Should only have one unclaimed transfer now
        unclaimedTransfers = transferLink.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 1);
        assertEq(unclaimedTransfers[0], transferId2);

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Should have no unclaimed transfers (expired)
        unclaimedTransfers = transferLink.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 0);
    }

    function test_GetUnclaimedTransfersBySender() public {
        uint256 expiry = block.timestamp + 1 days;

        // Alice creates multiple transfers
        vm.startPrank(alice);
        bytes32 transferId1 = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        bytes32 transferId2 = transferLink.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );

        bytes32 transferId3 = transferLink.createDirectTransfer(
            charlie,
            address(token),
            TRANSFER_AMOUNT / 3,
            expiry,
            false,
            bytes32(0)
        );
        vm.stopPrank();

        // All should be unclaimed initially
        bytes32[] memory unclaimedBySender = transferLink.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedBySender.length, 3);
        assertEq(unclaimedBySender[0], transferId1);
        assertEq(unclaimedBySender[1], transferId2);
        assertEq(unclaimedBySender[2], transferId3);

        // Bob claims his transfer
        vm.prank(bob);
        transferLink.claimTransfer(transferId1, "");

        // Should have 2 unclaimed transfers now
        unclaimedBySender = transferLink.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedBySender.length, 2);
        assertEq(unclaimedBySender[0], transferId2);
        assertEq(unclaimedBySender[1], transferId3);

        // Charlie claims his transfer
        vm.prank(charlie);
        transferLink.claimTransfer(transferId3, "");

        // Should have 1 unclaimed transfer now (the link transfer)
        unclaimedBySender = transferLink.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedBySender.length, 1);
        assertEq(unclaimedBySender[0], transferId2);

        // Someone claims the link transfer
        vm.prank(bob);
        transferLink.claimTransfer(transferId2, "");

        // Should have no unclaimed transfers now
        unclaimedBySender = transferLink.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedBySender.length, 0);
    }

    function test_GetUnclaimedTransfers_EmptyForNewAddress() public {
        address newUser = makeAddr("newUser");

        // New address should have no unclaimed transfers
        bytes32[] memory unclaimedTransfers = transferLink.getUnclaimedTransfers(newUser);
        assertEq(unclaimedTransfers.length, 0);

        bytes32[] memory unclaimedBySender = transferLink.getUnclaimedTransfersBySender(newUser);
        assertEq(unclaimedBySender.length, 0);
    }

    function test_GetUnclaimedTransfers_RefundedTransfersNotIncluded() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Should be unclaimed initially
        bytes32[] memory unclaimedTransfers = transferLink.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 1);

        bytes32[] memory unclaimedBySender = transferLink.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedBySender.length, 1);

        // Fast forward past expiry and refund
        vm.warp(expiry + 1);
        vm.prank(alice);
        transferLink.refundTransfer(transferId);

        // Should have no unclaimed transfers after refund
        unclaimedTransfers = transferLink.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 0);

        unclaimedBySender = transferLink.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedBySender.length, 0);
    }

    // ============ Admin Function Tests ============

    function test_SetTokenSupport() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18, INITIAL_SUPPLY);

        // Initially not supported
        assertFalse(transferLink.supportedTokens(address(newToken)));

        // Set as supported
        transferLink.setTokenSupport(address(newToken), true);
        assertTrue(transferLink.supportedTokens(address(newToken)));

        // Set as not supported
        transferLink.setTokenSupport(address(newToken), false);
        assertFalse(transferLink.supportedTokens(address(newToken)));
    }

    function test_SetTokenSupport_RevertNotOwner() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18, INITIAL_SUPPLY);

        vm.prank(alice);
        vm.expectRevert();
        transferLink.setTokenSupport(address(newToken), true);
    }

    function test_SetTokenSupport_RevertInvalidTokenAddress() public {
        vm.expectRevert(InvalidTokenAddress.selector);
        transferLink.setTokenSupport(address(0), true);
    }

    function test_SetFee() public {
        uint16 newFee = 200; // 2%

        transferLink.setFee(newFee);
        assertEq(transferLink.feeInBasisPoints(), newFee);
    }

    function test_SetFee_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        transferLink.setFee(200);
    }

    function test_SetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        transferLink.setFeeCollector(newFeeCollector);
        assertEq(transferLink.feeCollector(), newFeeCollector);
    }

    function test_SetFeeCollector_RevertNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.prank(alice);
        vm.expectRevert();
        transferLink.setFeeCollector(newFeeCollector);
    }

    function test_SetFeeCollector_RevertZeroAddress() public {
        vm.expectRevert(ZeroFeeCollector.selector);
        transferLink.setFeeCollector(address(0));
    }

    // ============ Edge Case Tests ============

    function test_ZeroFeeTransfer() public {
        // Deploy contract with zero fee
        TransferLink zeroFeeContract = new TransferLink(feeCollector, 0);
        zeroFeeContract.setTokenSupport(address(token), true);

        vm.prank(alice);
        token.approve(address(zeroFeeContract), TRANSFER_AMOUNT);

        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = zeroFeeContract.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Verify no fee was taken
        (,,, uint256 amount, uint256 grossAmount,,,,,) = zeroFeeContract.getTransfer(transferId);
        assertEq(amount, grossAmount);
        assertEq(token.balanceOf(feeCollector), 0);
    }

    function test_MaxFeeTransfer() public {
        // Deploy contract with maximum allowed fee (10%)
        TransferLink maxFeeContract = new TransferLink(feeCollector, 1000); // 10%
        maxFeeContract.setTokenSupport(address(token), true);

        vm.prank(alice);
        token.approve(address(maxFeeContract), TRANSFER_AMOUNT);

        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = maxFeeContract.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Verify 10% fee was taken
        uint256 expectedFee = TRANSFER_AMOUNT * 1000 / 10000; // 10%
        (,,, uint256 amount, uint256 grossAmount,,,,,) = maxFeeContract.getTransfer(transferId);
        assertEq(amount, TRANSFER_AMOUNT - expectedFee);
        assertEq(grossAmount, TRANSFER_AMOUNT);
        assertEq(token.balanceOf(feeCollector), expectedFee);
    }

    function test_ExcessiveFeeRejected() public {
        // Test that fees above 10% are rejected
        vm.expectRevert(InvalidAmount.selector);
        new TransferLink(feeCollector, 1001); // 10.01% should fail
    }

    function test_MultipleTransfersFromSameUser() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create multiple transfers from alice
        vm.startPrank(alice);
        bytes32 transferId1 = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        bytes32 transferId2 = transferLink.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );
        vm.stopPrank();

        // Verify both transfers exist and are different
        assertTrue(transferId1 != transferId2);
        assertTrue(transferLink.isTransferClaimable(transferId1));
        assertTrue(transferLink.isTransferClaimable(transferId2));
    }

    // ============ Fuzz Tests ============

    function testFuzz_CreateDirectTransfer(
        uint256 amount,
        uint256 timeOffset
    ) public {
        // Bound inputs to reasonable ranges
        amount = bound(amount, transferLink.MIN_TRANSFER_AMOUNT(), INITIAL_SUPPLY / 4);
        timeOffset = bound(timeOffset, 1 hours, transferLink.MAX_EXPIRY_TIME());

        uint256 expiry = block.timestamp + timeOffset;

        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            amount,
            expiry,
            false,
            bytes32(0)
        );

        // Verify transfer was created successfully
        (address sender,,,,,,,,,) = transferLink.getTransfer(transferId);
        assertEq(sender, alice);
        assertTrue(transferLink.isTransferClaimable(transferId));
    }

    function testFuzz_ClaimAndRefund(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 1 hours, transferLink.MAX_EXPIRY_TIME());
        uint256 expiry = block.timestamp + timeOffset;

        // Create transfer
        vm.prank(alice);
        bytes32 transferId = transferLink.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Should be able to refund
        vm.prank(alice);
        transferLink.refundTransfer(transferId);

        // Verify refund
        (,,,,,, uint8 status,,,) = transferLink.getTransfer(transferId);
        assertEq(status, uint8(TransferStatus.Refunded));
    }
}