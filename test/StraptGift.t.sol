// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StraptGift} from "../src/StraptGift.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    InvalidFeePercentage,
    Error__InvalidAddress,
    InvalidAmount,
    InvalidRecipients,
    InvalidExpiryTime,
    GiftNotActive,
    GiftHasExpired,
    AllClaimsTaken,
    AlreadyClaimed,
    NotExpiredYet,
    NotCreator,
    TransferFailed,
    GiftNotFound
} from "../src/IStraptGift.sol";

contract StraptGiftTest is Test {
    StraptGift public straptGift;
    MockERC20 public token;

    address public owner;
    address public feeCollector;
    address public creator;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant GIFT_AMOUNT = 1000 * 1e18;
    uint256 public constant FEE_PERCENTAGE = 10; // 0.1%

    // Events for testing
    event GiftCreated(
        bytes32 indexed giftId,
        address indexed creator,
        address indexed tokenAddress,
        uint256 totalAmount,
        uint256 totalRecipients,
        bool isRandom,
        string message
    );

    event GiftClaimed(
        bytes32 indexed giftId,
        address indexed recipient,
        uint256 amount
    );

    event GiftExpired(
        bytes32 indexed giftId,
        address indexed creator,
        uint256 remainingAmount
    );

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        feeCollector = makeAddr("feeCollector");
        creator = makeAddr("creator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18, INITIAL_SUPPLY);

        // Deploy StraptGift contract
        straptGift = new StraptGift();

        // Set fee collector
        straptGift.setFeeCollector(feeCollector);

        // Distribute tokens to test accounts
        token.transfer(creator, INITIAL_SUPPLY / 4);
        token.transfer(user1, INITIAL_SUPPLY / 4);
        token.transfer(user2, INITIAL_SUPPLY / 4);

        // Approve StraptGift contract to spend tokens
        vm.prank(creator);
        token.approve(address(straptGift), type(uint256).max);

        vm.prank(user1);
        token.approve(address(straptGift), type(uint256).max);

        vm.prank(user2);
        token.approve(address(straptGift), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(straptGift.feeCollector(), feeCollector); // We set it in setUp
        assertEq(straptGift.feePercentage(), FEE_PERCENTAGE);
        assertEq(straptGift.owner(), owner);
    }

    // ============ Admin Function Tests ============

    function test_SetFeePercentage() public {
        uint256 newFee = 20; // 0.2%

        straptGift.setFeePercentage(newFee);
        assertEq(straptGift.feePercentage(), newFee);
    }

    function test_SetFeePercentage_RevertExcessiveFee() public {
        vm.expectRevert(InvalidFeePercentage.selector);
        straptGift.setFeePercentage(51); // Above 50% (MAX_FEE_PERCENTAGE)
    }

    function test_SetFeePercentage_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        straptGift.setFeePercentage(20);
    }

    function test_SetFeeCollector() public {
        address newCollector = makeAddr("newCollector");

        straptGift.setFeeCollector(newCollector);
        assertEq(straptGift.feeCollector(), newCollector);
    }

    function test_SetFeeCollector_RevertZeroAddress() public {
        vm.expectRevert(Error__InvalidAddress.selector);
        straptGift.setFeeCollector(address(0));
    }

    function test_SetFeeCollector_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        straptGift.setFeeCollector(makeAddr("newCollector"));
    }

    // ============ Gift Creation Tests ============

    function test_CreateFixedGift_Success() public {
        uint256 totalRecipients = 5;
        uint256 expiry = block.timestamp + 1 days;
        string memory message = "Happy Birthday!";

        uint256 expectedNetAmount = GIFT_AMOUNT - (GIFT_AMOUNT * FEE_PERCENTAGE / 100);

        // Don't check the giftId in the event since it's generated dynamically
        vm.expectEmit(false, true, true, true);
        emit GiftCreated(
            bytes32(0), // We'll check this separately
            creator,
            address(token),
            expectedNetAmount,
            totalRecipients,
            false, // isRandom
            message
        );

        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            totalRecipients,
            false, // fixed distribution
            expiry,
            message
        );

        // Verify gift details
        {
            (
                address giftCreator,
                address tokenAddress,
                uint256 totalAmount,
                uint256 remainingAmount,
                uint256 claimedCount,
                uint256 totalRecipientsStored,
                bool isRandom,
                uint256 expiryTime,
                string memory giftMessage,
                bool isActive
            ) = straptGift.getGiftInfo(giftId);

            assertEq(giftCreator, creator);
            assertEq(tokenAddress, address(token));
            assertEq(totalAmount, expectedNetAmount);
            assertEq(remainingAmount, expectedNetAmount);
            assertEq(claimedCount, 0);
            assertEq(totalRecipientsStored, totalRecipients);
            assertEq(isRandom, false);
            assertEq(expiryTime, expiry);
            assertEq(giftMessage, message);
            assertEq(isActive, true);
        }

        // Verify fee was collected
        uint256 expectedFee = GIFT_AMOUNT * FEE_PERCENTAGE / 100;
        assertEq(token.balanceOf(feeCollector), expectedFee);
        assertEq(token.balanceOf(address(straptGift)), expectedNetAmount);
    }

    function test_CreateRandomGift_Success() public {
        uint256 totalRecipients = 3;
        uint256 expiry = block.timestamp + 1 days;
        string memory message = "Random Gift!";

        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            totalRecipients,
            true, // random distribution
            expiry,
            message
        );

        // Verify gift details
        {
            (,,,,, uint256 totalRecipientsStored, bool isRandom,,,) = straptGift.getGiftInfo(giftId);

            assertEq(totalRecipientsStored, totalRecipients);
            assertEq(isRandom, true);
        }
    }

    // ============ Gift Creation Validation Tests ============

    function test_CreateGift_RevertInvalidAmount() public {
        vm.prank(creator);
        vm.expectRevert(InvalidAmount.selector);
        straptGift.createGift(
            address(token),
            0, // Invalid amount
            5,
            false,
            block.timestamp + 1 days,
            "Test"
        );
    }

    function test_CreateGift_RevertInvalidRecipients() public {
        vm.prank(creator);
        vm.expectRevert(InvalidRecipients.selector);
        straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            0, // Invalid recipients
            false,
            block.timestamp + 1 days,
            "Test"
        );
    }

    function test_CreateGift_RevertInvalidExpiryTime() public {
        vm.prank(creator);
        vm.expectRevert(InvalidExpiryTime.selector);
        straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            5,
            false,
            block.timestamp - 1, // Past expiry
            "Test"
        );
    }

    function test_CreateGift_RevertInvalidTokenAddress() public {
        vm.prank(creator);
        vm.expectRevert(Error__InvalidAddress.selector);
        straptGift.createGift(
            address(0), // Invalid token address
            GIFT_AMOUNT,
            5,
            false,
            block.timestamp + 1 days,
            "Test"
        );
    }

    // ============ Gift Claiming Tests ============

    function test_ClaimFixedGift_Success() public {
        uint256 totalRecipients = 3;
        uint256 expiry = block.timestamp + 1 days;

        // Create gift
        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            totalRecipients,
            false, // fixed distribution
            expiry,
            "Test Gift"
        );

        uint256 expectedNetAmount = GIFT_AMOUNT - (GIFT_AMOUNT * FEE_PERCENTAGE / 100);
        uint256 expectedAmountPerRecipient = expectedNetAmount / totalRecipients;

        uint256 user1BalanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit GiftClaimed(giftId, user1, expectedAmountPerRecipient);

        // Claim gift
        vm.prank(user1);
        uint256 claimedAmount = straptGift.claimGift(giftId);

        // Verify claim
        assertEq(claimedAmount, expectedAmountPerRecipient);
        assertEq(token.balanceOf(user1), user1BalanceBefore + expectedAmountPerRecipient);

        // Verify gift state
        (,,,uint256 remainingAmount, uint256 claimedCount,,,,,) = straptGift.getGiftInfo(giftId);
        assertEq(remainingAmount, expectedNetAmount - expectedAmountPerRecipient);
        assertEq(claimedCount, 1);

        // Verify claim tracking
        assertTrue(straptGift.hasAddressClaimed(giftId, user1));
        assertEq(straptGift.getClaimedAmount(giftId, user1), expectedAmountPerRecipient);
    }

    function test_ClaimRandomGift_Success() public {
        uint256 totalRecipients = 2;
        uint256 expiry = block.timestamp + 1 days;

        // Create random gift
        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            totalRecipients,
            true, // random distribution
            expiry,
            "Random Gift"
        );

        uint256 user1BalanceBefore = token.balanceOf(user1);

        // Claim gift
        vm.prank(user1);
        uint256 claimedAmount = straptGift.claimGift(giftId);

        // Verify claim (amount should be > 0 and <= total amount)
        assertGt(claimedAmount, 0);
        assertEq(token.balanceOf(user1), user1BalanceBefore + claimedAmount);

        // Verify claim tracking
        assertTrue(straptGift.hasAddressClaimed(giftId, user1));
        assertEq(straptGift.getClaimedAmount(giftId, user1), claimedAmount);
    }

    // ============ Gift Claiming Validation Tests ============

    function test_ClaimGift_RevertGiftNotFound() public {
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.prank(user1);
        vm.expectRevert(GiftNotFound.selector);
        straptGift.claimGift(nonExistentId);
    }

    function test_ClaimGift_RevertGiftExpired() public {
        uint256 expiry = block.timestamp + 1 hours;

        // Create gift
        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            5,
            false,
            expiry,
            "Test Gift"
        );

        // Fast forward past expiry
        vm.warp(expiry + 1);

        // Try to claim expired gift
        vm.prank(user1);
        vm.expectRevert(GiftHasExpired.selector);
        straptGift.claimGift(giftId);
    }

    function test_ClaimGift_RevertAlreadyClaimed() public {
        uint256 expiry = block.timestamp + 1 days;

        // Create gift
        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            5,
            false,
            expiry,
            "Test Gift"
        );

        // First claim
        vm.prank(user1);
        straptGift.claimGift(giftId);

        // Try to claim again
        vm.prank(user1);
        vm.expectRevert(AlreadyClaimed.selector);
        straptGift.claimGift(giftId);
    }

    // ============ Refund Tests ============

    function test_RefundExpiredGift_Success() public {
        uint256 expiry = block.timestamp + 1 hours;

        // Create gift
        vm.prank(creator);
        bytes32 giftId = straptGift.createGift(
            address(token),
            GIFT_AMOUNT,
            5,
            false,
            expiry,
            "Test Gift"
        );

        uint256 expectedNetAmount = GIFT_AMOUNT - (GIFT_AMOUNT * FEE_PERCENTAGE / 100);
        uint256 creatorBalanceBefore = token.balanceOf(creator);

        // Fast forward past expiry
        vm.warp(expiry + 1);

        vm.expectEmit(true, true, true, true);
        emit GiftExpired(giftId, creator, expectedNetAmount);

        // Refund expired gift
        vm.prank(creator);
        uint256 refundedAmount = straptGift.refundExpiredGift(giftId);

        // Verify refund
        assertEq(refundedAmount, expectedNetAmount);
        assertEq(token.balanceOf(creator), creatorBalanceBefore + expectedNetAmount);

        // Verify gift state
        (,,,uint256 remainingAmount,,,,,, bool isActive) = straptGift.getGiftInfo(giftId);
        assertEq(remainingAmount, 0);
        assertFalse(isActive);
    }
}