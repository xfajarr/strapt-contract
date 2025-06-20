// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IStraptGift.sol";

/**
 * @title StraptGiftStorage
 * @notice Storage contract for StraptGift containing all state variables and constants
 * @author STRAPT Team
 */
abstract contract StraptGiftStorage {
    // Constants
    uint256 internal constant BASIS_POINTS = 100;
    uint256 internal constant MAX_FEE_PERCENTAGE = 50;
    uint256 internal constant MIN_AMOUNT = 1;

    // Fee configuration
    uint256 public feePercentage = 10; // 0.1% (in basis points, 10000 = 100%)
    address public feeCollector;

    // Mappings
    mapping(bytes32 => Gift) public gifts;
    mapping(bytes32 => mapping(address => bool)) public hasClaimed;
    mapping(bytes32 => mapping(address => uint256)) public claimedAmounts;

    /**
     * @notice Calculate random amount for a claim
     * @dev Internal function to calculate random amount for a claim
     * @param giftId Unique identifier of the gift
     * @param gift Gift storage reference
     * @return amountToSend Amount to send to the claimer
     */
    function _calculateRandomAmount(bytes32 giftId, Gift storage gift) internal view returns (uint256) {
        uint256 amountToSend;

        if (gift.claimedCount == gift.totalRecipients - 1) {
            // Last person gets the remainder
            amountToSend = gift.remainingAmount;
        } else {
            // Use a fair random algorithm
            uint256 remainingRecipients = gift.totalRecipients - gift.claimedCount;
            uint256 averageAmount = gift.remainingAmount / remainingRecipients;
            uint256 maxPossible = _min(averageAmount * 2, gift.remainingAmount);

            // Generate random number using keccak256
            uint256 randomFactor = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                msg.sender,
                giftId,
                gift.claimedCount
            ))) % 100;

            // Calculate random amount between 1% and 200% of average
            amountToSend = (averageAmount * (randomFactor + 100)) / 100;

            // Ensure amount is within bounds
            amountToSend = _min(amountToSend, maxPossible);
            amountToSend = _max(amountToSend, MIN_AMOUNT); // Ensure at least 1 token unit
        }

        return amountToSend;
    }

    /**
     * @notice Internal function to get minimum of two values
     * @param a First value
     * @param b Second value
     * @return Minimum value
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Internal function to get maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
