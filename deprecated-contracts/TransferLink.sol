// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./ITransferLink.sol";
import "./TransferLinkStorage.sol";

/**
 * @title TransferLink
 * @author STRAPT Team
 */
contract TransferLink is ReentrancyGuard, Ownable, Pausable, ITransferLink, TransferLinkStorage {
    using SafeERC20 for IERC20;

    /// @notice Maximum fee in basis points (10% = 1000 basis points)
    uint16 public constant MAX_FEE_BASIS_POINTS = 1000;

    /**
     * @notice Constructor to initialize the contract
     * @param _feeCollector Address to collect fees (typically the deployer)
     * @param _feeInBasisPoints Fee in basis points (1/100 of a percent, e.g. 20 = 0.2%)
     */
    constructor(address _feeCollector, uint16 _feeInBasisPoints) Ownable(msg.sender) {
        if (_feeCollector == address(0)) revert ZeroFeeCollector();
        if (_feeInBasisPoints > MAX_FEE_BASIS_POINTS) revert InvalidAmount();
        feeCollector = _feeCollector;
        feeInBasisPoints = _feeInBasisPoints;
    }

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
    ) external nonReentrant whenNotPaused returns (bytes32) {
        // Input validation
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        if (amount == 0) revert InvalidAmount();
        if (!supportedTokens[tokenAddress]) revert TokenNotSupported();
        if (recipient == address(0)) revert Error__InvalidAddress();

        // If hasPassword is true, claimCodeHash must be non-zero
        if (hasPassword && claimCodeHash == bytes32(0)) revert InvalidClaimCode();

        // Validate expiry time
        if (expiry == 0) {
            expiry = block.timestamp + DEFAULT_EXPIRY_TIME;
        } else if (expiry <= block.timestamp || // Must be in the future
                  expiry > block.timestamp + MAX_EXPIRY_TIME) { // Must not be too far in the future
            revert InvalidExpiryTime();
        }

        // Generate a unique transfer ID
        bytes32 transferId = _generateTransferId(
            msg.sender,
            recipient,
            tokenAddress,
            amount,
            expiry,
            claimCodeHash
        );

        // Ensure transfer ID doesn't already exist
        if (transfers[transferId].createdAt != 0) revert TransferAlreadyExists();

        // Calculate fee if applicable
        uint256 fee = 0;
        uint256 transferAmount = amount;

        if (feeInBasisPoints > 0) {
            fee = (amount * feeInBasisPoints) / 10000;
            transferAmount = amount - fee;
            // Ensure transfer amount is not zero after fee deduction
            if (transferAmount == 0) revert InvalidAmount();
        }

        // Create the transfer record
        transfers[transferId] = Transfer({
            sender: msg.sender,
            recipient: recipient,
            tokenAddress: tokenAddress,
            amount: transferAmount,
            grossAmount: amount,
            expiry: expiry,
            claimCodeHash: hasPassword ? claimCodeHash : bytes32(0),
            status: TransferStatus.Pending,
            createdAt: block.timestamp,
            isLinkTransfer: false,
            hasPassword: hasPassword
        });

        // Transfer tokens from sender to this contract
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee to fee collector if applicable
        if (fee > 0) {
            IERC20(tokenAddress).safeTransfer(feeCollector, fee);
        }

        // Associate the transfer with the recipient and sender for tracking
        _associateTransferWithRecipient(transferId, recipient);
        _associateTransferWithSender(transferId, msg.sender);

        emit TransferCreated(
            transferId,
            msg.sender,
            recipient,
            tokenAddress,
            transferAmount,
            amount,
            expiry
        );

        return transferId;
    }

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
    ) external nonReentrant whenNotPaused returns (bytes32) {
        // Input validation
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        if (amount == 0) revert InvalidAmount();
        if (!supportedTokens[tokenAddress]) revert TokenNotSupported();

        // If hasPassword is true, claimCodeHash must be non-zero
        if (hasPassword && claimCodeHash == bytes32(0)) revert InvalidClaimCode();

        // Validate expiry time
        if (expiry == 0) {
            expiry = block.timestamp + DEFAULT_EXPIRY_TIME;
        } else if (expiry <= block.timestamp || // Must be in the future
                  expiry > block.timestamp + MAX_EXPIRY_TIME) { // Must not be too far in the future
            revert InvalidExpiryTime();
        }

        // Generate a unique transfer ID with additional randomness
        bytes32 transferId = keccak256(
            abi.encodePacked(
                msg.sender,
                tokenAddress,
                amount,
                expiry,
                hasPassword ? claimCodeHash : bytes32(0),
                block.timestamp,
                blockhash(block.number - 1), // Add block hash for more randomness
                address(this)                // Add contract address for uniqueness
            )
        );

        // Ensure transfer ID doesn't already exist
        if (transfers[transferId].createdAt != 0) revert TransferAlreadyExists();

        // Calculate fee if applicable
        uint256 fee = 0;
        uint256 transferAmount = amount;

        if (feeInBasisPoints > 0) {
            fee = (amount * feeInBasisPoints) / 10000;
            transferAmount = amount - fee;
            // Ensure transfer amount is not zero after fee deduction
            if (transferAmount == 0) revert InvalidAmount();
        }

        // Create the transfer record
        transfers[transferId] = Transfer({
            sender: msg.sender,
            recipient: address(0),          // No specific recipient for link transfers
            tokenAddress: tokenAddress,
            amount: transferAmount,
            grossAmount: amount,
            expiry: expiry,
            claimCodeHash: hasPassword ? claimCodeHash : bytes32(0),
            status: TransferStatus.Pending,
            createdAt: block.timestamp,
            isLinkTransfer: true,
            hasPassword: hasPassword
        });

        // Transfer tokens from sender to this contract
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee to fee collector if applicable
        if (fee > 0) {
            IERC20(tokenAddress).safeTransfer(feeCollector, fee);
        }

        // Associate the transfer with the sender for tracking
        _associateTransferWithSender(transferId, msg.sender);

        emit TransferCreated(
            transferId,
            msg.sender,
            address(0),
            tokenAddress,
            transferAmount,
            amount,
            expiry
        );

        return transferId;
    }

    /**
     * @notice Claims a transfer (works for both direct and link transfers)
     * @param transferId The ID of the transfer to claim
     * @param claimCode The plain text claim code (only needed for password-protected transfers)
     */
    function claimTransfer(bytes32 transferId, string calldata claimCode)
        external
        nonReentrant
        whenNotPaused
    {
        Transfer storage transfer = transfers[transferId];

        // Validate transfer
        if (transfer.createdAt == 0) revert TransferDoesNotExist();
        if (transfer.status != TransferStatus.Pending) revert TransferNotClaimable();
        if (block.timestamp > transfer.expiry) revert TransferExpired();

        // For transfers with a password, verify the code
        if (transfer.hasPassword) {
            bytes32 providedCodeHash = keccak256(abi.encodePacked(claimCode));
            if (providedCodeHash != transfer.claimCodeHash) revert InvalidClaimCode();
        }

        // If recipient is specified, only they can claim
        if (transfer.recipient != address(0) && msg.sender != transfer.recipient) {
            revert NotIntendedRecipient();
        }

        // Update transfer status first to prevent reentrancy
        transfer.status = TransferStatus.Claimed;

        // Transfer tokens to claimer
        IERC20(transfer.tokenAddress).safeTransfer(msg.sender, transfer.amount);

        emit TransferClaimed(transferId, msg.sender, transfer.amount);
    }

    /**
     * @notice Refunds an expired transfer back to the sender
     * @param transferId The ID of the transfer to refund
     */
    function refundTransfer(bytes32 transferId) external nonReentrant whenNotPaused {
        Transfer storage transfer = transfers[transferId];

        // Validate transfer
        if (transfer.createdAt == 0) revert TransferDoesNotExist();
        if (transfer.status != TransferStatus.Pending) revert TransferNotRefundable();
        if (block.timestamp <= transfer.expiry) revert TransferNotExpired();
        if (msg.sender != transfer.sender) revert NotTransferSender();

        // Update transfer status first to prevent reentrancy
        transfer.status = TransferStatus.Refunded;

        // Transfer tokens back to sender
        IERC20(transfer.tokenAddress).safeTransfer(transfer.sender, transfer.amount);

        emit TransferRefunded(transferId, transfer.sender, transfer.amount);
    }

    /**
     * @notice Instantly refunds a transfer back to the sender (regardless of expiry)
     * @param transferId The ID of the transfer to refund instantly
     */
    function instantRefund(bytes32 transferId) external nonReentrant whenNotPaused {
        Transfer storage transfer = transfers[transferId];

        // Validate transfer
        if (transfer.createdAt == 0) revert TransferDoesNotExist();
        if (transfer.status != TransferStatus.Pending) revert TransferNotRefundable();
        if (msg.sender != transfer.sender) revert NotTransferSender();

        // Update transfer status first to prevent reentrancy
        transfer.status = TransferStatus.Refunded;

        // Transfer tokens back to sender
        IERC20(transfer.tokenAddress).safeTransfer(transfer.sender, transfer.amount);

        emit TransferRefunded(transferId, transfer.sender, transfer.amount);
    }

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
        )
    {
        Transfer storage transfer = transfers[transferId];
        if (transfer.createdAt == 0) revert TransferDoesNotExist();

        return (
            transfer.sender,
            transfer.recipient,
            transfer.tokenAddress,
            transfer.amount,
            transfer.grossAmount,
            transfer.expiry,
            uint8(transfer.status),  // Convert enum to uint8 for better frontend compatibility
            transfer.createdAt,
            transfer.isLinkTransfer,
            transfer.hasPassword
        );
    }

    /**
     * @notice Checks if a transfer exists and is claimable
     * @param transferId The ID of the transfer to check
     * @return isClaimable True if the transfer is claimable
     */
    function isTransferClaimable(bytes32 transferId) external view returns (bool) {
        Transfer storage transfer = transfers[transferId];
        return (
            transfer.createdAt > 0 &&
            transfer.status == TransferStatus.Pending &&
            block.timestamp <= transfer.expiry
        );
    }

    /**
     * @notice Checks if a transfer requires a password to claim
     * @param transferId The ID of the transfer to check
     * @return isPasswordProtected True if the transfer requires a password
     */
    function isPasswordProtected(bytes32 transferId) external view returns (uint8) {
        Transfer storage transfer = transfers[transferId];
        if (transfer.createdAt == 0) revert TransferDoesNotExist();

        // Return 1 for true, 0 for false (better frontend compatibility)
        return transfer.hasPassword ? 1 : 0;
    }

    /**
     * @notice Set token support status
     * @param tokenAddress The token address to update
     * @param isSupported Whether the token is supported
     */
    function setTokenSupport(address tokenAddress, bool isSupported) external onlyOwner {
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        supportedTokens[tokenAddress] = isSupported;
        emit TokenSupportUpdated(tokenAddress, isSupported);
    }

    /**
     * @notice Set the fee in basis points
     * @param newFeeInBasisPoints The new fee in basis points (1/100 of a percent, e.g. 20 = 0.2%)
     */
    function setFee(uint16 newFeeInBasisPoints) external onlyOwner {
        if (newFeeInBasisPoints > MAX_FEE_BASIS_POINTS) revert InvalidAmount();
        feeInBasisPoints = newFeeInBasisPoints;
        emit FeeUpdated(newFeeInBasisPoints);
    }

    /**
     * @notice Set the fee collector address
     * @param newFeeCollector The new fee collector address
     */
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) revert ZeroFeeCollector();
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    /**
     * @notice Pause the contract in case of emergency
     * @dev Only owner can pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only owner can unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Batch set token support for multiple tokens
     * @param tokenAddresses Array of token addresses
     * @param supportStatuses Array of support statuses corresponding to token addresses
     */
    function batchSetTokenSupport(
        address[] calldata tokenAddresses,
        bool[] calldata supportStatuses
    ) external onlyOwner {
        if (tokenAddresses.length != supportStatuses.length) revert InvalidAmount();
        if (tokenAddresses.length == 0) revert InvalidAmount();

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] == address(0)) revert InvalidTokenAddress();
            supportedTokens[tokenAddresses[i]] = supportStatuses[i];
            emit TokenSupportUpdated(tokenAddresses[i], supportStatuses[i]);
        }
    }
}
