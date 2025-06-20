// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LinkTransferOptimized
 * @notice Gas-optimized contract for link transfers with optional passwords and unclaimed tracking
 * @dev Focused on link transfers only - direct transfers will be in separate contract
 * @author STRAPT Team
 */
contract LinkTransfer is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Transfer status
    enum Status { Pending, Claimed, Refunded }

    /// @notice Gas-optimized transfer struct
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
    
    /// @notice Mapping to track unclaimed transfers by sender for easy viewing
    mapping(address => bytes32[]) public senderTransfers;
    
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
     * @notice Creates a link transfer with optional password
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

        // Generate transfer ID - optimized for gas efficiency
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

        // Create transfer record
        transfers[transferId] = Transfer({
            sender: msg.sender,
            tokenAddress: tokenAddress,
            amount: netAmount,
            expiry: expiry,
            claimCodeHash: hasPassword ? claimCodeHash : bytes32(0),
            status: Status.Pending,
            hasPassword: hasPassword
        });

        // Add to sender's transfer list for unclaimed tracking
        senderTransfers[msg.sender].push(transferId);

        // Transfer tokens from sender to this contract
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee if applicable
        if (fee > 0) {
            IERC20(tokenAddress).safeTransfer(feeCollector, fee);
        }

        emit TransferCreated(transferId, msg.sender, tokenAddress, netAmount, expiry);
        return transferId;
    }

    /**
     * @notice Claims a link transfer with optional password
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
     * @notice Instantly refunds a transfer back to the sender (regardless of expiry)
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
     * @notice Refunds an expired transfer back to the sender
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
     * @notice Gets all unclaimed transfer IDs for a sender
     * @param sender The sender address
     * @return transferIds Array of unclaimed transfer IDs
     */
    function getUnclaimedTransfersBySender(address sender) external view returns (bytes32[] memory) {
        bytes32[] memory allTransfers = senderTransfers[sender];
        bytes32[] memory tempUnclaimed = new bytes32[](allTransfers.length);
        uint256 unclaimedCount = 0;

        for (uint256 i = 0; i < allTransfers.length; i++) {
            Transfer storage transfer = transfers[allTransfers[i]];
            if (transfer.status == Status.Pending) {
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
     * @notice Gets all transfer IDs sent by a specific sender
     * @param sender The sender address
     * @return transferIds Array of transfer IDs sent by the sender
     */
    function getSenderTransfers(address sender) external view returns (bytes32[] memory) {
        return senderTransfers[sender];
    }

    /**
     * @notice Gets transfer details
     * @param transferId The ID of the transfer
     */
    function getTransfer(bytes32 transferId) external view returns (
        address sender,
        address tokenAddress,
        uint128 amount,
        uint64 expiry,
        uint8 status,
        bool hasPassword
    ) {
        Transfer storage transfer = transfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();

        return (
            transfer.sender,
            transfer.tokenAddress,
            transfer.amount,
            transfer.expiry,
            uint8(transfer.status),
            transfer.hasPassword
        );
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

    /**
     * @notice Checks if transfer requires password
     * @param transferId The ID of the transfer
     */
    function isPasswordProtected(bytes32 transferId) external view returns (uint8) {
        Transfer storage transfer = transfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();
        return transfer.hasPassword ? 1 : 0;
    }

    // Admin functions
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
}
