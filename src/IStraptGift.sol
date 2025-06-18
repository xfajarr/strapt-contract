// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Struct to store gift details
struct Gift {
    address creator;
    address tokenAddress;
    uint256 totalAmount;
    uint256 remainingAmount;
    uint256 claimedCount;
    uint256 totalRecipients;
    uint256 amountPerRecipient; // 0 if random
    bool isRandom;
    uint256 expiryTime;
    string message;
    bool isActive;
}

// Custom errors for gas optimization
error InvalidFeePercentage();
error Error__InvalidAddress();
error InvalidAmount();
error InvalidRecipients();
error InvalidExpiryTime();
error GiftNotActive();
error GiftHasExpired();
error AllClaimsTaken();
error AlreadyClaimed();
error NotExpiredYet();
error NotCreator();
error TransferFailed();
error GiftNotFound();

/**
 * @title IStraptGift
 * @notice Interface for the StraptGift contract
 * @author STRAPT Team
 */
interface IStraptGift {
    // Events
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

    event FeeCollected(
        bytes32 indexed giftId,
        address indexed tokenAddress,
        uint256 feeAmount
    );

    event FeePercentageUpdated(uint256 oldPercentage, uint256 newPercentage);
    event FeeCollectorUpdated(address oldCollector, address newCollector);

    /**
     * @notice Set the fee percentage (only owner)
     * @param _feePercentage New fee percentage in basis points (10000 = 100%)
     */
    function setFeePercentage(uint256 _feePercentage) external;

    /**
     * @notice Set the fee collector address (only owner)
     * @param _feeCollector New fee collector address
     */
    function setFeeCollector(address _feeCollector) external;

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
    ) external returns (bytes32);

    /**
     * @notice Claim tokens from a STRAPT Gift
     * @param giftId Unique identifier of the gift
     * @return amount Amount of tokens claimed
     */
    function claimGift(bytes32 giftId) external returns (uint256);

    /**
     * @notice Refund remaining tokens from an expired gift
     * @param giftId Unique identifier of the gift
     * @return amount Amount of tokens refunded
     */
    function refundExpiredGift(bytes32 giftId) external returns (uint256);

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
    );

    /**
     * @notice Check if an address has claimed from a gift
     * @param giftId Unique identifier of the gift
     * @param user Address to check
     * @return claimed Whether the address has claimed
     */
    function hasAddressClaimed(bytes32 giftId, address user) external view returns (bool claimed);

    /**
     * @notice Get amount claimed by an address from a gift
     * @param giftId Unique identifier of the gift
     * @param user Address to check
     * @return amount Amount claimed
     */
    function getClaimedAmount(bytes32 giftId, address user) external view returns (uint256 amount);
}
