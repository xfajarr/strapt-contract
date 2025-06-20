// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ProtectedTransfer} from "../src/ProtectedTransfer.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract ProtectedTransferTest is Test {
    ProtectedTransfer public protectedTransfer;
    MockERC20 public token;
    MockERC20 public token2;

    address public owner;
    address public feeCollector;
    address public alice;
    address public bob;
    address public charlie;

    uint16 public constant FEE_BASIS_POINTS = 10; // 0.1%
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

    event TransferAssociatedWithRecipient(
        bytes32 indexed transferId,
        address indexed recipient
    );

    event TransferAssociatedWithSender(
        bytes32 indexed transferId,
        address indexed sender
    );

    event TokenSupportUpdated(
        address indexed tokenAddress,
        bool isSupported
    );

    event FeeUpdated(uint16 feeInBasisPoints);
    event FeeCollectorUpdated(address indexed feeCollector);

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        feeCollector = makeAddr("feeCollector");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy mock tokens
        token = new MockERC20("Test Token", "TEST", 18, INITIAL_SUPPLY);
        token2 = new MockERC20("Test Token 2", "TEST2", 6, INITIAL_SUPPLY);

        // Deploy ProtectedTransfer contract
        protectedTransfer = new ProtectedTransfer(feeCollector, FEE_BASIS_POINTS);

        // Set tokens as supported
        protectedTransfer.setTokenSupport(address(token), true);
        protectedTransfer.setTokenSupport(address(token2), true);

        // Distribute tokens to test accounts
        token.transfer(alice, INITIAL_SUPPLY / 4);
        token.transfer(bob, INITIAL_SUPPLY / 4);
        token.transfer(charlie, INITIAL_SUPPLY / 4);

        token2.transfer(alice, INITIAL_SUPPLY / 4);
        token2.transfer(bob, INITIAL_SUPPLY / 4);
        token2.transfer(charlie, INITIAL_SUPPLY / 4);

        // Approve ProtectedTransfer contract to spend tokens
        vm.prank(alice);
        token.approve(address(protectedTransfer), type(uint256).max);
        vm.prank(alice);
        token2.approve(address(protectedTransfer), type(uint256).max);

        vm.prank(bob);
        token.approve(address(protectedTransfer), type(uint256).max);
        vm.prank(bob);
        token2.approve(address(protectedTransfer), type(uint256).max);

        vm.prank(charlie);
        token.approve(address(protectedTransfer), type(uint256).max);
        vm.prank(charlie);
        token2.approve(address(protectedTransfer), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        assertEq(protectedTransfer.feeCollector(), feeCollector);
        assertEq(protectedTransfer.feeInBasisPoints(), FEE_BASIS_POINTS);
        assertEq(protectedTransfer.owner(), owner);
        assertEq(protectedTransfer.MAX_FEE_BASIS_POINTS(), 1000);
        assertEq(protectedTransfer.DEFAULT_EXPIRY_TIME(), 24 hours);
        assertEq(protectedTransfer.MAX_EXPIRY_TIME(), 30 days);
        assertEq(protectedTransfer.MIN_EXPIRY_TIME(), 24 hours);
    }

    function test_Constructor_RevertZeroFeeCollector() public {
        vm.expectRevert(ProtectedTransfer.ZeroFeeCollector.selector);
        new ProtectedTransfer(address(0), FEE_BASIS_POINTS);
    }

    function test_Constructor_RevertExcessiveFee() public {
        vm.expectRevert(ProtectedTransfer.InvalidAmount.selector);
        new ProtectedTransfer(feeCollector, 1001); // > MAX_FEE_BASIS_POINTS
    }

    // ============ Direct Transfer Tests ============

    function test_CreateDirectTransfer_Success() public {
        uint256 expiry = block.timestamp + 1 days;

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
        bytes32 transferId = protectedTransfer.createDirectTransfer(
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
        ) = protectedTransfer.getTransfer(transferId);

        assertEq(sender, alice);
        assertEq(recipient, bob);
        assertEq(tokenAddress, address(token));
        assertEq(amount, TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000));
        assertEq(grossAmount, TRANSFER_AMOUNT);
        assertEq(transferExpiry, expiry);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Pending));
        assertEq(createdAt, block.timestamp);
        assertEq(isLinkTransfer, false);
        assertEq(hasPassword, false);

        // Verify token balances
        uint256 expectedFee = TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000;
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY / 4 - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(protectedTransfer)), TRANSFER_AMOUNT - expectedFee);
        assertEq(token.balanceOf(feeCollector), expectedFee);

        // Verify tracking
        bytes32[] memory recipientTransfers = protectedTransfer.getRecipientTransfers(bob);
        assertEq(recipientTransfers.length, 1);
        assertEq(recipientTransfers[0], transferId);

        bytes32[] memory senderTransfers = protectedTransfer.getSenderTransfers(alice);
        assertEq(senderTransfers.length, 1);
        assertEq(senderTransfers[0], transferId);
    }

    function test_CreateDirectTransfer_WithPassword() public {
        string memory password = "secret123";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        // Verify password protection
        assertEq(protectedTransfer.isPasswordProtected(transferId), 1);

        // Verify transfer details
        (,,,,,,,,, bool hasPassword) = protectedTransfer.getTransfer(transferId);
        assertTrue(hasPassword);
    }

    function test_CreateDirectTransfer_DefaultExpiry() public {
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            0, // Use default expiry
            false,
            bytes32(0)
        );

        (,,,,,uint256 expiry,,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(expiry, block.timestamp + protectedTransfer.DEFAULT_EXPIRY_TIME());
    }

    function test_CreateDirectTransfer_ZeroAmountAfterFee() public {
        // Create a scenario where fee would result in zero transfer amount
        // Deploy a contract with maximum fee (1000 basis points = 10%)
        ProtectedTransfer highFeeContract = new ProtectedTransfer(feeCollector, 1000);
        highFeeContract.setTokenSupport(address(token), true);

        vm.prank(alice);
        token.approve(address(highFeeContract), type(uint256).max);

        // Use an amount where 10% fee equals the entire amount
        // For amount = 10, fee = 10 * 1000 / 10000 = 1, transferAmount = 10 - 1 = 9 (not zero)
        // For amount = 1, fee = 1 * 1000 / 10000 = 0 (due to integer division), transferAmount = 1 (not zero)
        // We need to use an amount where the fee calculation results in the entire amount being taken as fee
        // Since max fee is 10%, this is actually impossible with integer division
        // Let's test with amount = 1 and expect it to succeed, then change the test logic

        uint256 smallAmount = 1; // 1 wei

        // This should actually succeed because fee = 1 * 1000 / 10000 = 0 (integer division)
        // So let's test that it doesn't revert
        vm.prank(alice);
        bytes32 transferId = highFeeContract.createDirectTransfer(
            bob,
            address(token),
            smallAmount,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );

        // Verify the transfer was created successfully
        (,,,uint256 amount,,,,,,) = highFeeContract.getTransfer(transferId);
        assertEq(amount, smallAmount); // Should be 1 wei since fee was 0 due to integer division
    }

    // ============ Direct Transfer Validation Tests ============

    function test_CreateDirectTransfer_RevertInvalidTokenAddress() public {
        vm.prank(alice);
        vm.expectRevert(ProtectedTransfer.InvalidTokenAddress.selector);
        protectedTransfer.createDirectTransfer(
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
        vm.expectRevert(ProtectedTransfer.InvalidAmount.selector);
        protectedTransfer.createDirectTransfer(
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
        vm.expectRevert(ProtectedTransfer.TokenNotSupported.selector);
        protectedTransfer.createDirectTransfer(
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
        vm.expectRevert(ProtectedTransfer.Error__InvalidAddress.selector);
        protectedTransfer.createDirectTransfer(
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
        vm.expectRevert(ProtectedTransfer.InvalidClaimCode.selector);
        protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            true, // hasPassword = true
            bytes32(0) // but claimCodeHash is empty
        );
    }

    function test_CreateDirectTransfer_RevertInvalidExpiryTime_Past() public {
        vm.warp(1000);

        vm.prank(alice);
        vm.expectRevert(ProtectedTransfer.InvalidExpiryTime.selector);
        protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            999, // Past timestamp
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_RevertInvalidExpiryTime_TooFar() public {
        vm.warp(1000);

        vm.prank(alice);
        vm.expectRevert(ProtectedTransfer.InvalidExpiryTime.selector);
        protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            1000 + 30 days + 1, // Current time + MAX_EXPIRY_TIME + 1
            false,
            bytes32(0)
        );
    }

    function test_CreateDirectTransfer_WhenPaused() public {
        protectedTransfer.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );
    }

    // ============ Link Transfer Tests ============

    function test_CreateLinkTransfer_Success() public {
        uint256 expiry = block.timestamp + 1 days;

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
        bytes32 transferId = protectedTransfer.createLinkTransfer(
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
        ) = protectedTransfer.getTransfer(transferId);

        assertEq(sender, alice);
        assertEq(recipient, address(0)); // No specific recipient
        assertEq(tokenAddress, address(token));
        assertEq(amount, TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000));
        assertEq(grossAmount, TRANSFER_AMOUNT);
        assertEq(transferExpiry, expiry);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Pending));
        assertEq(createdAt, block.timestamp);
        assertEq(isLinkTransfer, true);
        assertEq(hasPassword, false);

        // Verify sender tracking
        bytes32[] memory senderTransfers = protectedTransfer.getSenderTransfers(alice);
        assertEq(senderTransfers.length, 1);
        assertEq(senderTransfers[0], transferId);
    }

    function test_CreateLinkTransfer_WithPassword() public {
        string memory password = "linkPassword";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        // Verify password protection
        assertEq(protectedTransfer.isPasswordProtected(transferId), 1);

        // Verify transfer details
        (,,,,,,,,, bool hasPassword) = protectedTransfer.getTransfer(transferId);
        assertTrue(hasPassword);
    }

    function test_CreateLinkTransfer_WhenPaused() public {
        protectedTransfer.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        protectedTransfer.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT,
            block.timestamp + 1 days,
            false,
            bytes32(0)
        );
    }

    // ============ Claim Transfer Tests ============

    function test_ClaimDirectTransfer_Success() public {
        // Create a direct transfer
        uint256 expiry = block.timestamp + 1 days;
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
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
        protectedTransfer.claimTransfer(transferId, "");

        // Verify balances
        assertEq(token.balanceOf(bob), bobBalanceBefore + expectedAmount);
        assertEq(token.balanceOf(address(protectedTransfer)), 0);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Claimed));
    }

    function test_ClaimDirectTransfer_WithPassword() public {
        string memory password = "secret123";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        // Create a password-protected transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
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
        protectedTransfer.claimTransfer(transferId, password);

        // Verify balances
        assertEq(token.balanceOf(bob), bobBalanceBefore + expectedAmount);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Claimed));
    }

    function test_ClaimLinkTransfer_AnyoneCanClaim() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a link transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createLinkTransfer(
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
        protectedTransfer.claimTransfer(transferId, "");

        // Verify balances
        assertEq(token.balanceOf(charlie), charlieBalanceBefore + expectedAmount);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Claimed));
    }

    function test_ClaimTransfer_WhenPaused() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        protectedTransfer.pause();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        protectedTransfer.claimTransfer(transferId, "");
    }

    // ============ Claim Transfer Validation Tests ============

    function test_ClaimTransfer_RevertTransferDoesNotExist() public {
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.prank(bob);
        vm.expectRevert(ProtectedTransfer.TransferDoesNotExist.selector);
        protectedTransfer.claimTransfer(nonExistentId, "");
    }

    function test_ClaimTransfer_RevertNotIntendedRecipient() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a direct transfer for bob
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Charlie tries to claim (not the intended recipient)
        vm.prank(charlie);
        vm.expectRevert(ProtectedTransfer.NotIntendedRecipient.selector);
        protectedTransfer.claimTransfer(transferId, "");
    }

    function test_ClaimTransfer_RevertInvalidClaimCode() public {
        string memory password = "secret123";
        bytes32 claimCodeHash = keccak256(abi.encodePacked(password));
        uint256 expiry = block.timestamp + 1 days;

        // Create a password-protected transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            true,
            claimCodeHash
        );

        // Try to claim with wrong password
        vm.prank(bob);
        vm.expectRevert(ProtectedTransfer.InvalidClaimCode.selector);
        protectedTransfer.claimTransfer(transferId, "wrongpassword");
    }

    function test_ClaimTransfer_RevertTransferExpired() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
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
        vm.expectRevert(ProtectedTransfer.TransferExpired.selector);
        protectedTransfer.claimTransfer(transferId, "");
    }

    function test_ClaimTransfer_RevertAlreadyClaimed() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create and claim a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(bob);
        protectedTransfer.claimTransfer(transferId, "");

        // Try to claim again
        vm.prank(bob);
        vm.expectRevert(ProtectedTransfer.TransferNotClaimable.selector);
        protectedTransfer.claimTransfer(transferId, "");
    }

    // ============ Refund Transfer Tests ============

    function test_RefundTransfer_Success() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
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
        protectedTransfer.refundTransfer(transferId);

        // Verify balances
        assertEq(token.balanceOf(alice), aliceBalanceBefore + expectedAmount);
        assertEq(token.balanceOf(address(protectedTransfer)), 0);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Refunded));
    }

    function test_RefundTransfer_WhenPaused() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.warp(expiry + 1);
        protectedTransfer.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        protectedTransfer.refundTransfer(transferId);
    }

    function test_RefundTransfer_RevertNotExpired() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Try to refund before expiry
        vm.prank(alice);
        vm.expectRevert(ProtectedTransfer.TransferNotExpired.selector);
        protectedTransfer.refundTransfer(transferId);
    }

    function test_RefundTransfer_RevertNotTransferSender() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
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
        vm.expectRevert(ProtectedTransfer.NotTransferSender.selector);
        protectedTransfer.refundTransfer(transferId);
    }

    // ============ Instant Refund Tests ============

    function test_InstantRefund_Success() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 expectedAmount = TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000);

        vm.expectEmit(true, true, true, true);
        emit TransferRefunded(transferId, alice, expectedAmount);

        // Instantly refund the transfer (before expiry)
        vm.prank(alice);
        protectedTransfer.instantRefund(transferId);

        // Verify balances
        assertEq(token.balanceOf(alice), aliceBalanceBefore + expectedAmount);
        assertEq(token.balanceOf(address(protectedTransfer)), 0);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Refunded));
    }

    function test_InstantRefund_BeforeExpiry() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Should be able to instantly refund even before expiry
        vm.prank(alice);
        protectedTransfer.instantRefund(transferId);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Refunded));
    }

    function test_InstantRefund_LinkTransfer() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a link transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 expectedAmount = TRANSFER_AMOUNT - (TRANSFER_AMOUNT * FEE_BASIS_POINTS / 10000);

        // Should be able to instantly refund link transfers too
        vm.prank(alice);
        protectedTransfer.instantRefund(transferId);

        // Verify balances
        assertEq(token.balanceOf(alice), aliceBalanceBefore + expectedAmount);

        // Verify transfer status
        (,,,,,, uint8 status,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(status, uint8(ProtectedTransfer.TransferStatus.Refunded));
    }

    function test_InstantRefund_WhenPaused() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        protectedTransfer.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        protectedTransfer.instantRefund(transferId);
    }

    function test_InstantRefund_RevertNotTransferSender() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Try to instantly refund as non-sender
        vm.prank(bob);
        vm.expectRevert(ProtectedTransfer.NotTransferSender.selector);
        protectedTransfer.instantRefund(transferId);
    }

    function test_InstantRefund_RevertAlreadyClaimed() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create and claim a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(bob);
        protectedTransfer.claimTransfer(transferId, "");

        // Try to instantly refund claimed transfer
        vm.prank(alice);
        vm.expectRevert(ProtectedTransfer.TransferNotRefundable.selector);
        protectedTransfer.instantRefund(transferId);
    }

    function test_InstantRefund_RevertTransferDoesNotExist() public {
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.prank(alice);
        vm.expectRevert(ProtectedTransfer.TransferDoesNotExist.selector);
        protectedTransfer.instantRefund(nonExistentId);
    }

    // ============ View Function Tests ============

    function test_IsTransferClaimable() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create a transfer
        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Should be claimable initially
        assertTrue(protectedTransfer.isTransferClaimable(transferId));

        // Should not be claimable after expiry
        vm.warp(expiry + 1);
        assertFalse(protectedTransfer.isTransferClaimable(transferId));

        // Create a new transfer to test claiming
        uint256 currentTime = block.timestamp + 2 days;
        vm.warp(currentTime);
        uint256 newExpiry = currentTime + 1 days;

        vm.prank(alice);
        bytes32 transferId2 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            newExpiry,
            false,
            bytes32(0)
        );

        // Should be claimable initially
        assertTrue(protectedTransfer.isTransferClaimable(transferId2));

        // Claim the transfer
        vm.prank(bob);
        protectedTransfer.claimTransfer(transferId2, "");

        // Should not be claimable after being claimed
        assertFalse(protectedTransfer.isTransferClaimable(transferId2));
    }

    function test_GetRecipientTransfers() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create multiple transfers for bob
        vm.prank(alice);
        bytes32 transferId1 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(charlie);
        bytes32 transferId2 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );

        // Get bob's transfers
        bytes32[] memory bobTransfers = protectedTransfer.getRecipientTransfers(bob);
        assertEq(bobTransfers.length, 2);
        assertEq(bobTransfers[0], transferId1);
        assertEq(bobTransfers[1], transferId2);

        // Alice should have no transfers as recipient
        bytes32[] memory aliceTransfers = protectedTransfer.getRecipientTransfers(alice);
        assertEq(aliceTransfers.length, 0);
    }

    function test_GetSenderTransfers() public {
        uint256 expiry = block.timestamp + 1 days;

        // Alice creates multiple transfers
        vm.startPrank(alice);
        bytes32 transferId1 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        bytes32 transferId2 = protectedTransfer.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );
        vm.stopPrank();

        // Get alice's transfers
        bytes32[] memory aliceTransfers = protectedTransfer.getSenderTransfers(alice);
        assertEq(aliceTransfers.length, 2);
        assertEq(aliceTransfers[0], transferId1);
        assertEq(aliceTransfers[1], transferId2);

        // Bob should have no transfers as sender
        bytes32[] memory bobTransfers = protectedTransfer.getSenderTransfers(bob);
        assertEq(bobTransfers.length, 0);
    }

    // ============ Enhanced Query Function Tests ============

    function test_GetUnclaimedTransfers() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create multiple transfers for bob
        vm.prank(alice);
        bytes32 transferId1 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(charlie);
        bytes32 transferId2 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );

        // Both should be unclaimed initially
        bytes32[] memory unclaimedTransfers = protectedTransfer.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 2);
        assertEq(unclaimedTransfers[0], transferId1);
        assertEq(unclaimedTransfers[1], transferId2);

        // Claim one transfer
        vm.prank(bob);
        protectedTransfer.claimTransfer(transferId1, "");

        // Should only have one unclaimed transfer now
        unclaimedTransfers = protectedTransfer.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 1);
        assertEq(unclaimedTransfers[0], transferId2);

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Should have no unclaimed transfers (expired)
        unclaimedTransfers = protectedTransfer.getUnclaimedTransfers(bob);
        assertEq(unclaimedTransfers.length, 0);
    }

    function test_GetUnclaimedTransfersBySender() public {
        uint256 expiry = block.timestamp + 1 days;

        // Alice creates multiple transfers
        vm.startPrank(alice);
        bytes32 transferId1 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        bytes32 transferId2 = protectedTransfer.createLinkTransfer(
            address(token),
            TRANSFER_AMOUNT / 2,
            expiry,
            false,
            bytes32(0)
        );

        bytes32 transferId3 = protectedTransfer.createDirectTransfer(
            charlie,
            address(token),
            TRANSFER_AMOUNT / 3,
            expiry,
            false,
            bytes32(0)
        );
        vm.stopPrank();

        // All should be unclaimed initially
        bytes32[] memory unclaimedTransfers = protectedTransfer.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedTransfers.length, 3);
        assertEq(unclaimedTransfers[0], transferId1);
        assertEq(unclaimedTransfers[1], transferId2);
        assertEq(unclaimedTransfers[2], transferId3);

        // Claim one transfer
        vm.prank(bob);
        protectedTransfer.claimTransfer(transferId1, "");

        // Should have two unclaimed transfers now
        unclaimedTransfers = protectedTransfer.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedTransfers.length, 2);
        assertEq(unclaimedTransfers[0], transferId2);
        assertEq(unclaimedTransfers[1], transferId3);

        // Refund one transfer
        vm.prank(alice);
        protectedTransfer.instantRefund(transferId2);

        // Should have one unclaimed transfer now
        unclaimedTransfers = protectedTransfer.getUnclaimedTransfersBySender(alice);
        assertEq(unclaimedTransfers.length, 1);
        assertEq(unclaimedTransfers[0], transferId3);
    }

    // ============ Administrative Function Tests ============

    function test_SetTokenSupport() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18, INITIAL_SUPPLY);

        // Initially not supported
        assertFalse(protectedTransfer.supportedTokens(address(newToken)));

        vm.expectEmit(true, true, true, true);
        emit TokenSupportUpdated(address(newToken), true);

        // Set as supported
        protectedTransfer.setTokenSupport(address(newToken), true);
        assertTrue(protectedTransfer.supportedTokens(address(newToken)));

        // Set as not supported
        protectedTransfer.setTokenSupport(address(newToken), false);
        assertFalse(protectedTransfer.supportedTokens(address(newToken)));
    }

    function test_SetTokenSupport_RevertInvalidTokenAddress() public {
        vm.expectRevert(ProtectedTransfer.InvalidTokenAddress.selector);
        protectedTransfer.setTokenSupport(address(0), true);
    }

    function test_SetTokenSupport_RevertNotOwner() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18, INITIAL_SUPPLY);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        protectedTransfer.setTokenSupport(address(newToken), true);
    }

    function test_BatchSetTokenSupport() public {
        MockERC20 token3 = new MockERC20("Token 3", "TK3", 18, INITIAL_SUPPLY);
        MockERC20 token4 = new MockERC20("Token 4", "TK4", 18, INITIAL_SUPPLY);

        address[] memory tokens = new address[](2);
        tokens[0] = address(token3);
        tokens[1] = address(token4);

        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;

        vm.expectEmit(true, true, true, true);
        emit TokenSupportUpdated(address(token3), true);
        vm.expectEmit(true, true, true, true);
        emit TokenSupportUpdated(address(token4), true);

        protectedTransfer.batchSetTokenSupport(tokens, statuses);

        assertTrue(protectedTransfer.supportedTokens(address(token3)));
        assertTrue(protectedTransfer.supportedTokens(address(token4)));
    }

    function test_BatchSetTokenSupport_RevertArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        bool[] memory statuses = new bool[](1); // Different length

        vm.expectRevert(ProtectedTransfer.InvalidAmount.selector);
        protectedTransfer.batchSetTokenSupport(tokens, statuses);
    }

    function test_BatchSetTokenSupport_RevertEmptyArray() public {
        address[] memory tokens = new address[](0);
        bool[] memory statuses = new bool[](0);

        vm.expectRevert(ProtectedTransfer.InvalidAmount.selector);
        protectedTransfer.batchSetTokenSupport(tokens, statuses);
    }

    function test_SetFee() public {
        uint16 newFee = 50; // 0.5%

        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(newFee);

        protectedTransfer.setFee(newFee);
        assertEq(protectedTransfer.feeInBasisPoints(), newFee);
    }

    function test_SetFee_RevertExcessiveFee() public {
        vm.expectRevert(ProtectedTransfer.InvalidAmount.selector);
        protectedTransfer.setFee(1001); // > MAX_FEE_BASIS_POINTS
    }

    function test_SetFee_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        protectedTransfer.setFee(50);
    }

    function test_SetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.expectEmit(true, true, true, true);
        emit FeeCollectorUpdated(newFeeCollector);

        protectedTransfer.setFeeCollector(newFeeCollector);
        assertEq(protectedTransfer.feeCollector(), newFeeCollector);
    }

    function test_SetFeeCollector_RevertZeroAddress() public {
        vm.expectRevert(ProtectedTransfer.ZeroFeeCollector.selector);
        protectedTransfer.setFeeCollector(address(0));
    }

    function test_SetFeeCollector_RevertNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        protectedTransfer.setFeeCollector(newFeeCollector);
    }

    // ============ Pausability Tests ============

    function test_Pause() public {
        assertFalse(protectedTransfer.paused());

        protectedTransfer.pause();
        assertTrue(protectedTransfer.paused());
    }

    function test_Unpause() public {
        protectedTransfer.pause();
        assertTrue(protectedTransfer.paused());

        protectedTransfer.unpause();
        assertFalse(protectedTransfer.paused());
    }

    function test_Pause_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        protectedTransfer.pause();
    }

    function test_Unpause_RevertNotOwner() public {
        protectedTransfer.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        protectedTransfer.unpause();
    }

    // ============ Edge Case Tests ============

    function test_MultipleTokenSupport() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create transfers with different tokens
        vm.prank(alice);
        bytes32 transferId1 = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        vm.prank(alice);
        bytes32 transferId2 = protectedTransfer.createDirectTransfer(
            bob,
            address(token2),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Both transfers should exist
        assertTrue(protectedTransfer.isTransferClaimable(transferId1));
        assertTrue(protectedTransfer.isTransferClaimable(transferId2));

        // Verify different token addresses
        (,, address tokenAddr1,,,,,,,) = protectedTransfer.getTransfer(transferId1);
        (,, address tokenAddr2,,,,,,,) = protectedTransfer.getTransfer(transferId2);

        assertEq(tokenAddr1, address(token));
        assertEq(tokenAddr2, address(token2));
    }

    function test_ZeroFeeScenario() public {
        // Deploy contract with zero fee
        ProtectedTransfer zeroFeeContract = new ProtectedTransfer(feeCollector, 0);
        zeroFeeContract.setTokenSupport(address(token), true);

        // Approve the new contract
        vm.prank(alice);
        token.approve(address(zeroFeeContract), type(uint256).max);

        uint256 expiry = block.timestamp + 1 days;
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 feeCollectorBalanceBefore = token.balanceOf(feeCollector);

        vm.prank(alice);
        bytes32 transferId = zeroFeeContract.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        // Verify no fee was collected
        assertEq(token.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(feeCollector), feeCollectorBalanceBefore); // No change
        assertEq(token.balanceOf(address(zeroFeeContract)), TRANSFER_AMOUNT);

        // Verify transfer amount equals gross amount
        (,,, uint256 amount, uint256 grossAmount,,,,,) = zeroFeeContract.getTransfer(transferId);
        assertEq(amount, grossAmount);
        assertEq(amount, TRANSFER_AMOUNT);
    }

    // ============ Fuzz Tests ============

    function testFuzz_CreateTransferWithValidAmount(uint256 amount) public {
        // Bound amount to reasonable range (avoid zero and very large amounts)
        amount = bound(amount, 1000, INITIAL_SUPPLY / 10);
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            amount,
            expiry,
            false,
            bytes32(0)
        );

        (,,, uint256 transferAmount, uint256 grossAmount,,,,,) = protectedTransfer.getTransfer(transferId);

        assertEq(grossAmount, amount);

        if (FEE_BASIS_POINTS > 0) {
            uint256 expectedFee = (amount * FEE_BASIS_POINTS) / 10000;
            assertEq(transferAmount, amount - expectedFee);
        } else {
            assertEq(transferAmount, amount);
        }
    }

    function testFuzz_CreateTransferWithValidExpiry(uint256 timeOffset) public {
        // Bound time offset to valid range
        timeOffset = bound(timeOffset, 1 hours, 29 days);
        uint256 expiry = block.timestamp + timeOffset;

        vm.prank(alice);
        bytes32 transferId = protectedTransfer.createDirectTransfer(
            bob,
            address(token),
            TRANSFER_AMOUNT,
            expiry,
            false,
            bytes32(0)
        );

        (,,,,,uint256 transferExpiry,,,,) = protectedTransfer.getTransfer(transferId);
        assertEq(transferExpiry, expiry);
    }
}
