// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IStraptGift.sol";
import "./StraptGiftStorage.sol";

/**
 * @title StraptGift
 * @notice Contract for creating and claiming STRAPT Gifts
 * @dev Users can create gifts with fixed or random distribution of tokens
 * @author STRAPT Team
 */
contract StraptGift is ReentrancyGuard, Ownable, IStraptGift, StraptGiftStorage {
    using SafeERC20 for IERC20;

    /**
     * @dev Constructor sets the fee collector to the contract deployer
     */
    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
    }

    /**
     * @notice Set the fee percentage (only owner)
     * @param _feePercentage New fee percentage in basis points (10000 = 100%)
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > MAX_FEE_PERCENTAGE) revert InvalidFeePercentage();

        uint256 oldPercentage = feePercentage;
        feePercentage = _feePercentage;

        emit FeePercentageUpdated(oldPercentage, _feePercentage);
    }

    /**
     * @notice Set the fee collector address (only owner)
     * @param _feeCollector New fee collector address
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        if (_feeCollector == address(0)) revert Gift__InvalidAddress();

        address oldCollector = feeCollector;
        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(oldCollector, _feeCollector);
    }

    /**
     * @notice Create a new STRAPT Gift
     * @param tokenAddress Address of the ERC20 token
     * @param totalAmount Total amount of tokens to distribute
     * @param totalRecipients Number of recipients who can claim
     * @param isRandom Whether distribution is random or fixed
     * @param expiryTime Time when the gift expires (unix timestamp)
     * @param message Optional message for the gift
     * @return giftId Unique identifier for the created gift
     */
    function createGift(
        address tokenAddress,
        uint256 totalAmount,
        uint256 totalRecipients,
        bool isRandom,
        uint256 expiryTime,
        string calldata message
    ) external nonReentrant returns (bytes32) {
        // Input validation
        if (totalAmount == 0) revert Gift__InvalidAmount();
        if (totalRecipients == 0) revert InvalidRecipients();
        if (expiryTime <= block.timestamp) revert Gift__InvalidExpiryTime();
        if (tokenAddress == address(0)) revert Gift__InvalidAddress();

        // Calculate fee
        uint256 feeAmount = (totalAmount * feePercentage) / BASIS_POINTS;
        uint256 netAmount = totalAmount - feeAmount;

        // Transfer tokens from sender to contract
        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        // Transfer fee to fee collector
        if (feeAmount > 0) {
            token.safeTransfer(feeCollector, feeAmount);
            emit FeeCollected(bytes32(0), tokenAddress, feeAmount);
        }

        // Generate unique gift ID
        bytes32 giftId = keccak256(abi.encodePacked(
            msg.sender,
            block.timestamp,
            totalAmount,
            totalRecipients,
            tokenAddress
        ));

        // Calculate amount per recipient if fixed distribution
        uint256 amountPerRecipient = isRandom ? 0 : netAmount / totalRecipients;

        // Create gift
        gifts[giftId] = Gift({
            creator: msg.sender,
            tokenAddress: tokenAddress,
            totalAmount: netAmount,
            remainingAmount: netAmount,
            claimedCount: 0,
            totalRecipients: totalRecipients,
            amountPerRecipient: amountPerRecipient,
            isRandom: isRandom,
            expiryTime: expiryTime,
            message: message,
            isActive: true
        });

        emit GiftCreated(
            giftId,
            msg.sender,
            tokenAddress,
            netAmount,
            totalRecipients,
            isRandom,
            message
        );

        return giftId;
    }

    /**
     * @notice Claim tokens from a STRAPT Gift
     * @param giftId Unique identifier of the gift
     * @return amount Amount of tokens claimed
     */
    function claimGift(bytes32 giftId) external nonReentrant returns (uint256) {
        Gift storage gift = gifts[giftId];

        // Check if gift exists
        if (gift.creator == address(0)) revert GiftNotFound();

        // Validate gift state
        if (!gift.isActive) revert GiftNotActive();
        if (block.timestamp >= gift.expiryTime) revert GiftHasExpired();
        if (gift.claimedCount >= gift.totalRecipients) revert AllClaimsTaken();
        if (hasClaimed[giftId][msg.sender]) revert AlreadyClaimed();

        uint256 amountToSend;

        if (gift.isRandom) {
            amountToSend = _calculateRandomAmount(giftId, gift);
        } else {
            // Fixed distribution
            amountToSend = gift.amountPerRecipient;
        }

        // Update state
        gift.remainingAmount -= amountToSend;
        gift.claimedCount += 1;
        hasClaimed[giftId][msg.sender] = true;
        claimedAmounts[giftId][msg.sender] = amountToSend;

        // If all claimed, mark as inactive
        if (gift.claimedCount == gift.totalRecipients) {
            gift.isActive = false;
        }

        // Transfer tokens to claimer
        IERC20 token = IERC20(gift.tokenAddress);
        token.safeTransfer(msg.sender, amountToSend);

        emit GiftClaimed(giftId, msg.sender, amountToSend);

        return amountToSend;
    }

    /**
     * @notice Refund remaining tokens from an expired gift
     * @param giftId Unique identifier of the gift
     * @return amount Amount of tokens refunded
     */
    function refundExpiredGift(bytes32 giftId) external nonReentrant returns (uint256) {
        Gift storage gift = gifts[giftId];

        // Check if gift exists
        if (gift.creator == address(0)) revert GiftNotFound();

        if (!gift.isActive) revert GiftNotActive();
        if (block.timestamp < gift.expiryTime) revert NotExpiredYet();
        if (gift.creator != msg.sender) revert NotCreator();

        uint256 remainingAmount = gift.remainingAmount;

        // Update state
        gift.remainingAmount = 0;
        gift.isActive = false;

        // Transfer tokens back to creator
        IERC20 token = IERC20(gift.tokenAddress);
        token.safeTransfer(gift.creator, remainingAmount);

        emit GiftExpired(giftId, gift.creator, remainingAmount);

        return remainingAmount;
    }

    /**
     * @notice Get information about a gift
     * @param giftId Unique identifier of the gift
     * @return creator Creator of the gift
     * @return tokenAddress Address of the token
     * @return totalAmount Total amount of tokens in the gift
     * @return remainingAmount Remaining amount of tokens
     * @return claimedCount Number of claims made
     * @return totalRecipients Total number of recipients
     * @return isRandom Whether distribution is random
     * @return expiryTime Time when the gift expires
     * @return message Optional message for the gift
     * @return isActive Whether the gift is active
     */
    function getGiftInfo(bytes32 giftId) external view returns (
        address creator,
        address tokenAddress,
        uint256 totalAmount,
        uint256 remainingAmount,
        uint256 claimedCount,
        uint256 totalRecipients,
        bool isRandom,
        uint256 expiryTime,
        string memory message,
        bool isActive
    ) {
        Gift storage gift = gifts[giftId];

        // Check if gift exists by verifying creator is not zero address
        // This works because we validate creator != address(0) during creation
        if (gift.creator == address(0)) {
            revert GiftNotFound();
        }

        return (
            gift.creator,
            gift.tokenAddress,
            gift.totalAmount,
            gift.remainingAmount,
            gift.claimedCount,
            gift.totalRecipients,
            gift.isRandom,
            gift.expiryTime,
            gift.message,
            gift.isActive
        );
    }

    /**
     * @notice Check if an address has claimed from a gift
     * @param giftId Unique identifier of the gift
     * @param user Address to check
     * @return claimed Whether the address has claimed
     */
    function hasAddressClaimed(bytes32 giftId, address user) external view returns (bool claimed) {
        // Check if gift exists
        if (gifts[giftId].creator == address(0)) {
            revert GiftNotFound();
        }
        return hasClaimed[giftId][user];
    }

    /**
     * @notice Get amount claimed by an address from a gift
     * @param giftId Unique identifier of the gift
     * @param user Address to check
     * @return amount Amount claimed
     */
    function getClaimedAmount(bytes32 giftId, address user) external view returns (uint256 amount) {
        // Check if gift exists
        if (gifts[giftId].creator == address(0)) {
            revert GiftNotFound();
        }
        return claimedAmounts[giftId][user];
    }
}
