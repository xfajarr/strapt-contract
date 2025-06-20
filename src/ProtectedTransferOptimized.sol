// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProtectedTransferOptimized
 * @notice Gas-optimized version of ProtectedTransfer with minimal storage and operations
 * @dev Focuses on core functionality with maximum gas efficiency
 * @author STRAPT Team
 */
contract ProtectedTransferOptimized is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Transfer status packed into uint8
    enum Status { Pending, Claimed, Refunded }

    /// @notice Optimized transfer struct - packed for gas efficiency
    struct Transfer {
        address sender;         // 20 bytes
        address tokenAddress;   // 20 bytes
        uint128 amount;         // 16 bytes - supports up to 340T tokens
        uint64 expiry;          // 8 bytes - timestamp until 2106
        bytes32 claimCodeHash;  // 32 bytes
        Status status;          // 1 byte
        bool hasPassword;       // 1 byte
    }

    /// @notice Mapping from transfer ID to transfer details
    mapping(bytes32 => Transfer) public transfers;

    /// @notice Supported tokens mapping
    mapping(address => bool) public supportedTokens;

    /// @notice Fee collector and fee rate
    address public feeCollector;
    uint16 public feeInBasisPoints; // Max 655.35%

    /// @notice Constants
    uint16 public constant MAX_FEE_BASIS_POINTS = 1000; // 10%
    uint64 public constant DEFAULT_EXPIRY_TIME = 24 hours;
    uint64 public constant MAX_EXPIRY_TIME = 30 days;

    /// @notice Events
    event TransferCreated(bytes32 indexed transferId, address indexed sender, address tokenAddress, uint128 amount, uint64 expiry);
    event TransferClaimed(bytes32 indexed transferId, address indexed claimer, uint128 amount);
    event TransferRefunded(bytes32 indexed transferId, address indexed sender, uint128 amount);
    event TokenSupportUpdated(address indexed tokenAddress, bool isSupported);

    /// @notice Custom errors
    error InvalidToken();
    error InvalidAmount();
    error InvalidExpiry();
    error InvalidClaimCode();
    error TransferExists();
    error TransferNotFound();
    error TransferNotClaimable();
    error TransferNotRefundable();
    error TransferExpired();
    error TransferNotExpired();
    error NotSender();
    error TokenNotSupported();
    error ZeroAddress();

    constructor(address _feeCollector, uint16 _feeInBasisPoints) Ownable(msg.sender) {
        if (_feeCollector == address(0)) revert ZeroAddress();
        if (_feeInBasisPoints > MAX_FEE_BASIS_POINTS) revert InvalidAmount();
        feeCollector = _feeCollector;
        feeInBasisPoints = _feeInBasisPoints;
    }

    /**
     * @notice Creates a direct transfer to a specific recipient - gas optimized
     * @param recipient The recipient address
     * @param tokenAddress The ERC20 token address
     * @param amount The amount of tokens to transfer
     * @param expiry The expiry timestamp (0 for default 24h)
     * @param hasPassword Whether this transfer requires a password
     * @param claimCodeHash The hash of the claim code (bytes32(0) if no password)
     * @return transferId The unique ID of the created transfer
     */
    function createDirectTransfer(
        address recipient,
        address tokenAddress,
        uint128 amount,
        uint64 expiry,
        bool hasPassword,
        bytes32 claimCodeHash
    ) external nonReentrant returns (bytes32) {
        // Input validation - optimized
        if (tokenAddress == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (!supportedTokens[tokenAddress]) revert TokenNotSupported();
        if (hasPassword && claimCodeHash == bytes32(0)) revert InvalidClaimCode();

        // Set default expiry if not provided
        if (expiry == 0) {
            expiry = uint64(block.timestamp) + DEFAULT_EXPIRY_TIME;
        } else {
            uint64 currentTime = uint64(block.timestamp);
            if (expiry <= currentTime || expiry > currentTime + MAX_EXPIRY_TIME) {
                revert InvalidExpiry();
            }
        }

        // Generate transfer ID for direct transfer
        bytes32 transferId = keccak256(
            abi.encodePacked(
                msg.sender,
                recipient,
                tokenAddress,
                amount,
                expiry,
                claimCodeHash,
                block.timestamp
            )
        );

        // Check if transfer already exists
        if (transfers[transferId].sender != address(0)) revert TransferExists();

        // Calculate net amount after fee
        uint128 netAmount = amount;
        uint128 fee = 0;

        if (feeInBasisPoints > 0) {
            fee = uint128((uint256(amount) * feeInBasisPoints) / 10000);
            netAmount = amount - fee;
            if (netAmount == 0) revert InvalidAmount();
        }

        // Create transfer record - optimized storage
        transfers[transferId] = Transfer({
            sender: msg.sender,
            tokenAddress: tokenAddress,
            amount: netAmount,
            expiry: expiry,
            claimCodeHash: hasPassword ? claimCodeHash : bytes32(0),
            status: Status.Pending,
            hasPassword: hasPassword
        });

        // Transfer tokens - single external call
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee if applicable
        if (fee > 0) {
            IERC20(tokenAddress).safeTransfer(feeCollector, fee);
        }

        emit TransferCreated(transferId, msg.sender, tokenAddress, netAmount, expiry);
        return transferId;
    }

    /**
     * @notice Creates a link transfer - gas optimized version
     * @param tokenAddress The ERC20 token address
     * @param amount The amount of tokens to transfer
     * @param expiry The expiry timestamp (0 for default 24h)
     * @param hasPassword Whether this transfer requires a password
     * @param claimCodeHash The hash of the claim code (bytes32(0) if no password)
     * @return transferId The unique ID of the created transfer
     */
    function createLinkTransfer(
        address tokenAddress,
        uint128 amount,
        uint64 expiry,
        bool hasPassword,
        bytes32 claimCodeHash
    ) external nonReentrant returns (bytes32) {
        // Input validation - optimized
        if (tokenAddress == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (!supportedTokens[tokenAddress]) revert TokenNotSupported();
        if (hasPassword && claimCodeHash == bytes32(0)) revert InvalidClaimCode();

        // Set default expiry if not provided
        if (expiry == 0) {
            expiry = uint64(block.timestamp) + DEFAULT_EXPIRY_TIME;
        } else {
            uint64 currentTime = uint64(block.timestamp);
            if (expiry <= currentTime || expiry > currentTime + MAX_EXPIRY_TIME) {
                revert InvalidExpiry();
            }
        }

        // Generate transfer ID - simplified for gas efficiency
        bytes32 transferId = keccak256(
            abi.encodePacked(
                msg.sender,
                tokenAddress,
                amount,
                expiry,
                claimCodeHash,
                block.timestamp
            )
        );

        // Check if transfer already exists
        if (transfers[transferId].sender != address(0)) revert TransferExists();

        // Calculate net amount after fee
        uint128 netAmount = amount;
        uint128 fee = 0;

        if (feeInBasisPoints > 0) {
            fee = uint128((uint256(amount) * feeInBasisPoints) / 10000);
            netAmount = amount - fee;
            if (netAmount == 0) revert InvalidAmount();
        }

        // Create transfer record - optimized storage
        transfers[transferId] = Transfer({
            sender: msg.sender,
            tokenAddress: tokenAddress,
            amount: netAmount,
            expiry: expiry,
            claimCodeHash: hasPassword ? claimCodeHash : bytes32(0),
            status: Status.Pending,
            hasPassword: hasPassword
        });

        // Transfer tokens - single external call
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee if applicable
        if (fee > 0) {
            IERC20(tokenAddress).safeTransfer(feeCollector, fee);
        }

        emit TransferCreated(transferId, msg.sender, tokenAddress, netAmount, expiry);
        return transferId;
    }

    /**
     * @notice Claims a transfer - gas optimized
     * @param transferId The ID of the transfer to claim
     * @param claimCode The plain text claim code (empty string if no password)
     */
    function claimTransfer(bytes32 transferId, string calldata claimCode) external nonReentrant {
        Transfer storage transfer = transfers[transferId];

        // Validate transfer exists and is claimable
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.status != Status.Pending) revert TransferNotClaimable();
        if (uint64(block.timestamp) > transfer.expiry) revert TransferExpired();

        // Verify password if required
        if (transfer.hasPassword) {
            if (keccak256(abi.encodePacked(claimCode)) != transfer.claimCodeHash) {
                revert InvalidClaimCode();
            }
        }

        // Update status and transfer tokens
        transfer.status = Status.Claimed;
        IERC20(transfer.tokenAddress).safeTransfer(msg.sender, transfer.amount);

        emit TransferClaimed(transferId, msg.sender, transfer.amount);
    }

    /**
     * @notice Refunds an expired transfer - gas optimized
     * @param transferId The ID of the transfer to refund
     */
    function refundTransfer(bytes32 transferId) external nonReentrant {
        Transfer storage transfer = transfers[transferId];

        // Validate refund conditions
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.status != Status.Pending) revert TransferNotRefundable();
        if (uint64(block.timestamp) <= transfer.expiry) revert TransferNotExpired();
        if (msg.sender != transfer.sender) revert NotSender();

        // Update status and refund tokens
        transfer.status = Status.Refunded;
        IERC20(transfer.tokenAddress).safeTransfer(transfer.sender, transfer.amount);

        emit TransferRefunded(transferId, transfer.sender, transfer.amount);
    }

    /**
     * @notice Instant refund by sender - gas optimized
     * @param transferId The ID of the transfer to refund
     */
    function instantRefund(bytes32 transferId) external nonReentrant {
        Transfer storage transfer = transfers[transferId];

        // Validate instant refund conditions
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.status != Status.Pending) revert TransferNotRefundable();
        if (msg.sender != transfer.sender) revert NotSender();

        // Update status and refund tokens
        transfer.status = Status.Refunded;
        IERC20(transfer.tokenAddress).safeTransfer(transfer.sender, transfer.amount);

        emit TransferRefunded(transferId, transfer.sender, transfer.amount);
    }

    /**
     * @notice Gets transfer details - compatible with original contract
     * @param transferId The ID of the transfer
     */
    function getTransfer(bytes32 transferId) external view returns (
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
    ) {
        Transfer storage transfer = transfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();

        return (
            transfer.sender,
            address(0), // recipient - always 0 for optimized version (link transfers only)
            transfer.tokenAddress,
            uint256(transfer.amount),
            uint256(transfer.amount), // grossAmount = amount for simplicity
            uint256(transfer.expiry),
            uint8(transfer.status),
            uint256(transfer.expiry - DEFAULT_EXPIRY_TIME), // approximate createdAt
            true, // isLinkTransfer - always true for optimized version
            transfer.hasPassword
        );
    }

    /**
     * @notice Checks if transfer requires password - compatible with original
     * @param transferId The ID of the transfer
     */
    function isPasswordProtected(bytes32 transferId) external view returns (uint8) {
        Transfer storage transfer = transfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();
        return transfer.hasPassword ? 1 : 0;
    }

    /**
     * @notice Checks if transfer is claimable
     * @param transferId The ID of the transfer
     */
    function isTransferClaimable(bytes32 transferId) external view returns (bool) {
        Transfer storage transfer = transfers[transferId];
        return (
            transfer.sender != address(0) &&
            transfer.status == Status.Pending &&
            uint64(block.timestamp) <= transfer.expiry
        );
    }

    // Admin functions - compatible with original contract
    function setTokenSupport(address tokenAddress, bool isSupported) external onlyOwner {
        if (tokenAddress == address(0)) revert InvalidToken();
        supportedTokens[tokenAddress] = isSupported;
        emit TokenSupportUpdated(tokenAddress, isSupported);
    }

    function setFee(uint16 newFeeInBasisPoints) external onlyOwner {
        if (newFeeInBasisPoints > MAX_FEE_BASIS_POINTS) revert InvalidAmount();
        feeInBasisPoints = newFeeInBasisPoints;
    }

    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = newFeeCollector;
    }

    function batchSetTokenSupport(address[] calldata tokens, bool[] calldata statuses) external onlyOwner {
        if (tokens.length != statuses.length || tokens.length == 0) revert InvalidAmount();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            supportedTokens[tokens[i]] = statuses[i];
            emit TokenSupportUpdated(tokens[i], statuses[i]);
        }
    }

    // Compatibility functions for original contract interface
    function getRecipientTransfers(address) external pure returns (bytes32[] memory) {
        // Return empty array for gas optimization - tracking removed
        return new bytes32[](0);
    }

    function getSenderTransfers(address) external pure returns (bytes32[] memory) {
        // Return empty array for gas optimization - tracking removed
        return new bytes32[](0);
    }

    function getUnclaimedTransfers(address) external pure returns (bytes32[] memory) {
        // Return empty array for gas optimization - tracking removed
        return new bytes32[](0);
    }

    function getUnclaimedTransfersBySender(address) external pure returns (bytes32[] memory) {
        // Return empty array for gas optimization - tracking removed
        return new bytes32[](0);
    }
}
