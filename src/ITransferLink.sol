// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Enum to track the status of a transfer (represented as uint8 for better frontend compatibility)
enum TransferStatus {
    Pending,    // 0: Transfer is created but not claimed
    Claimed,    // 1: Transfer has been claimed by recipient
    Refunded,   // 2: Transfer has been refunded to sender
    Expired     // 3: Transfer has expired (not used yet, for future auto-expiry)
}

/// @notice Struct to store transfer details
struct Transfer {
    address sender;         // Creator of the transfer
    address recipient;      // Optional: can be zero address for link/QR transfers
    address tokenAddress;   // ERC20 token address
    uint256 amount;         // Net amount of tokens to transfer (after fee)
    uint256 grossAmount;    // Original amount before fee deduction
    uint256 expiry;         // Timestamp after which transfer can be refunded
    bytes32 claimCodeHash;  // Hash of the claim code (can be empty for transfers without password)
    TransferStatus status;  // Current status of the transfer
    uint256 createdAt;      // Timestamp when transfer was created
    bool isLinkTransfer;    // Whether this is a link transfer (true) or direct transfer (false)
    bool hasPassword;       // Explicitly track if transfer has password protection
}

// Custom errors for gas optimization
error InvalidTokenAddress();
error Error__InvalidAddress();
error InvalidAmount();
error InvalidExpiryTime();
error InvalidClaimCode();
error TransferAlreadyExists();
error TransferDoesNotExist();
error TransferNotClaimable();
error TransferNotRefundable();
error TransferExpired();
error TransferNotExpired();
error NotIntendedRecipient();
error NotTransferSender();
error TokenNotSupported();
error PasswordProtected();
error NotLinkTransfer();
error ZeroFeeCollector();

/**
 * @title ITransferLink
 * @notice Interface for the TransferLink contract
 * @author STRAPT Team
 */
interface ITransferLink {
    // Events
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

    event TokenSupportUpdated(
        address indexed tokenAddress,
        bool isSupported
    );

    event FeeUpdated(
        uint16 feeInBasisPoints
    );

    event FeeCollectorUpdated(
        address indexed feeCollector
    );

    /**
     * @notice Creates a direct transfer to a specific recipient
     * @param recipient The recipient address
     * @param tokenAddress The ERC20 token address to transfer
     * @param amount The amount of tokens to transfer
     * @param expiry The timestamp after which the transfer can be refunded
     * @param hasPassword Whether this transfer requires a password to claim
     * @param claimCodeHash The hash of the claim code (keccak256) - can be bytes32(0) if hasPassword is false
     * @return transferId The unique ID of the created transfer
     */
    function createDirectTransfer(
        address recipient,
        address tokenAddress,
        uint256 amount,
        uint256 expiry,
        bool hasPassword,
        bytes32 claimCodeHash
    ) external returns (bytes32);

    /**
     * @notice Creates a link/QR transfer that can be claimed with just the transfer ID
     * @param tokenAddress The ERC20 token address to transfer
     * @param amount The amount of tokens to transfer
     * @param expiry The timestamp after which the transfer can be refunded
     * @param hasPassword Whether this transfer requires a password to claim
     * @param claimCodeHash The hash of the claim code (keccak256) - can be bytes32(0) if hasPassword is false
     * @return transferId The unique ID of the created transfer (to be shared as link/QR)
     */
    function createLinkTransfer(
        address tokenAddress,
        uint256 amount,
        uint256 expiry,
        bool hasPassword,
        bytes32 claimCodeHash
    ) external returns (bytes32);

    /**
     * @notice Claims a transfer (works for both direct and link transfers)
     * @param transferId The ID of the transfer to claim
     * @param claimCode The plain text claim code (only needed for password-protected transfers)
     */
    function claimTransfer(bytes32 transferId, string calldata claimCode) external;

    /**
     * @notice Refunds an expired transfer back to the sender
     * @param transferId The ID of the transfer to refund
     */
    function refundTransfer(bytes32 transferId) external;

    /**
     * @notice Gets the details of a transfer
     * @param transferId The ID of the transfer
     * @return sender The address that created the transfer
     * @return recipient The intended recipient (if specified)
     * @return tokenAddress The ERC20 token address
     * @return amount The net amount of tokens (after fee)
     * @return grossAmount The original amount before fee deduction
     * @return expiry The expiry timestamp
     * @return status The current status of the transfer (as uint8 for better frontend compatibility)
     * @return createdAt The timestamp when the transfer was created
     * @return isLinkTransfer Whether this is a link transfer
     * @return hasPassword Whether this transfer requires a password
     */
    function getTransfer(bytes32 transferId)
        external
        view
        returns (
            address sender,
            address recipient,
            address tokenAddress,
            uint256 amount,
            uint256 grossAmount,
            uint256 expiry,
            uint8 status,
            uint256 createdAt,
            bool isLinkTransfer,
            bool hasPassword
        );

    /**
     * @notice Checks if a transfer exists and is claimable
     * @param transferId The ID of the transfer to check
     * @return isClaimable True if the transfer is claimable
     */
    function isTransferClaimable(bytes32 transferId) external view returns (bool);

    /**
     * @notice Checks if a transfer requires a password to claim
     * @param transferId The ID of the transfer to check
     * @return isPasswordProtected True if the transfer requires a password
     */
    function isPasswordProtected(bytes32 transferId) external view returns (uint8);

    /**
     * @notice Set token support status
     * @param tokenAddress The token address to update
     * @param isSupported Whether the token is supported
     */
    function setTokenSupport(address tokenAddress, bool isSupported) external;

    /**
     * @notice Set the fee in basis points
     * @param newFeeInBasisPoints The new fee in basis points (1/100 of a percent, e.g. 20 = 0.2%)
     */
    function setFee(uint16 newFeeInBasisPoints) external;

    /**
     * @notice Set the fee collector address
     * @param newFeeCollector The new fee collector address
     */
    function setFeeCollector(address newFeeCollector) external;
}
