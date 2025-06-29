// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ITransferLink.sol";

/**
 * @title TransferLinkStorage
 * @notice Storage contract for TransferLink containing all state variables and constants
 * @author STRAPT Team
 */
abstract contract TransferLinkStorage {
    /// @notice Mapping from transfer ID to transfer details
    mapping(bytes32 => Transfer) public transfers;

    /// @notice Mapping of supported tokens
    mapping(address => bool) public supportedTokens;

    /**
     * @notice Mapping to track transfer IDs for each recipient
     * @dev This is used to allow users to see all transfers intended for them
     */
    mapping(address => bytes32[]) internal recipientTransfers;

    /**
     * @notice Mapping to track transfer IDs for each sender
     * @dev This is used to allow senders to see all transfers they've created
     */
    mapping(address => bytes32[]) internal senderTransfers;

    /// @notice Fee collector address
    address public feeCollector;

    /// @notice Fee in basis points (1/100 of a percent, e.g. 20 = 0.2%)
    uint16 public feeInBasisPoints;

    /// @notice Minimum expiry time (24 hours)
    uint256 public constant MIN_EXPIRY_TIME = 24 hours;

    /// @notice Maximum expiry time (30 days)
    uint256 public constant MAX_EXPIRY_TIME = 30 days;

    /// @notice Default expiry time (24 hours)
    uint256 public constant DEFAULT_EXPIRY_TIME = 24 hours;

    /// @notice Minimum transfer amount to prevent dust attacks
    uint256 public constant MIN_TRANSFER_AMOUNT = 1000; // 1000 wei minimum

    /**
     * @notice Associates a transfer with a recipient for tracking purposes
     * @dev This is called internally when creating a direct transfer
     * @param transferId The ID of the transfer
     * @param recipient The recipient address
     */
    /**
     * @notice Event emitted when a transfer is associated with a recipient
     */
    event TransferAssociatedWithRecipient(
        bytes32 indexed transferId,
        address indexed recipient
    );

    function _associateTransferWithRecipient(bytes32 transferId, address recipient) internal {
        if (recipient != address(0)) {
            recipientTransfers[recipient].push(transferId);
            emit TransferAssociatedWithRecipient(transferId, recipient);
        }
    }

    /**
     * @notice Associates a transfer with a sender for tracking purposes
     * @dev This is called internally when creating any transfer
     * @param transferId The ID of the transfer
     * @param sender The sender address
     */
    function _associateTransferWithSender(bytes32 transferId, address sender) internal {
        senderTransfers[sender].push(transferId);
    }

    /**
     * @notice Gets all transfer IDs associated with a recipient
     * @param recipient The recipient address
     * @return transferIds Array of transfer IDs intended for the recipient
     */
    function getRecipientTransfers(address recipient) external view returns (bytes32[] memory) {
        return recipientTransfers[recipient];
    }

    /**
     * @notice Gets all unclaimed transfer IDs for a specific recipient
     * @param recipient The recipient address
     * @return transferIds Array of unclaimed transfer IDs for the recipient
     */
    function getUnclaimedTransfers(address recipient) external view returns (bytes32[] memory) {
        bytes32[] memory allTransfers = recipientTransfers[recipient];
        bytes32[] memory tempUnclaimed = new bytes32[](allTransfers.length);
        uint256 unclaimedCount = 0;

        for (uint256 i = 0; i < allTransfers.length; i++) {
            Transfer storage transfer = transfers[allTransfers[i]];
            if (transfer.status == TransferStatus.Pending && block.timestamp <= transfer.expiry) {
                tempUnclaimed[unclaimedCount] = allTransfers[i];
                unclaimedCount++;
            }
        }

        // Create array with exact size
        bytes32[] memory unclaimedTransfers = new bytes32[](unclaimedCount);
        for (uint256 i = 0; i < unclaimedCount; i++) {
            unclaimedTransfers[i] = tempUnclaimed[i];
        }

        return unclaimedTransfers;
    }

    /**
     * @notice Gets all unclaimed transfer IDs sent by a specific sender
     * @param sender The sender address
     * @return transferIds Array of unclaimed transfer IDs sent by the sender
     */
    function getUnclaimedTransfersBySender(address sender) external view returns (bytes32[] memory) {
        bytes32[] memory allTransfers = senderTransfers[sender];
        bytes32[] memory tempUnclaimed = new bytes32[](allTransfers.length);
        uint256 unclaimedCount = 0;

        for (uint256 i = 0; i < allTransfers.length; i++) {
            Transfer storage transfer = transfers[allTransfers[i]];
            if (transfer.status == TransferStatus.Pending) {
                tempUnclaimed[unclaimedCount] = allTransfers[i];
                unclaimedCount++;
            }
        }

        // Create array with exact size
        bytes32[] memory unclaimedTransfers = new bytes32[](unclaimedCount);
        for (uint256 i = 0; i < unclaimedCount; i++) {
            unclaimedTransfers[i] = tempUnclaimed[i];
        }

        return unclaimedTransfers;
    }

    /**
     * @notice Generates a transfer ID for direct transfers
     * @dev Internal function used by createDirectTransfer
     */
    function _generateTransferId(
        address sender,
        address recipient,
        address tokenAddress,
        uint256 amount,
        uint256 expiry,
        bytes32 claimCodeHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                sender,
                recipient,
                tokenAddress,
                amount,
                expiry,
                claimCodeHash,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );
    }
}
