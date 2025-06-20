// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    /**
     * @notice Constructor to create a mock ERC20 token with optional initial supply
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param decimals_ The number of decimals for the token
     * @param initialSupply Optional initial supply to mint to deployer (use 0 for no initial supply)
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimals_;
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to a specific address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from a specific address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @notice Batch mint tokens to multiple addresses
     * @param recipients Array of addresses to mint tokens to
     * @param amounts Array of amounts to mint to each address
     */
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "MockERC20: arrays length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @notice Get formatted balance with decimals
     * @param account The address to check balance for
     * @return The balance formatted as a string with decimal places
     */
    function balanceOfFormatted(address account) external view returns (string memory) {
        uint256 balance = balanceOf(account);
        return _formatTokenAmount(balance);
    }

    /**
     * @notice Get formatted total supply with decimals
     * @return The total supply formatted as a string with decimal places
     */
    function totalSupplyFormatted() external view returns (string memory) {
        return _formatTokenAmount(totalSupply());
    }

    /**
     * @dev Internal function to format token amounts with decimals
     * @param amount The amount to format
     * @return The formatted amount as a string
     */
    function _formatTokenAmount(uint256 amount) internal view returns (string memory) {
        if (amount == 0) return "0";

        uint256 decimalPlaces = _decimals;
        if (decimalPlaces == 0) {
            return _toString(amount);
        }

        uint256 divisor = 10 ** decimalPlaces;
        uint256 wholePart = amount / divisor;
        uint256 fractionalPart = amount % divisor;

        if (fractionalPart == 0) {
            return _toString(wholePart);
        }

        // Convert fractional part to string and pad with zeros
        string memory fractionalStr = _toString(fractionalPart);
        bytes memory fractionalBytes = bytes(fractionalStr);

        // Pad with leading zeros if necessary
        uint256 zerosNeeded = decimalPlaces - fractionalBytes.length;
        bytes memory paddedFractional = new bytes(decimalPlaces);

        for (uint256 i = 0; i < zerosNeeded; i++) {
            paddedFractional[i] = "0";
        }
        for (uint256 i = 0; i < fractionalBytes.length; i++) {
            paddedFractional[zerosNeeded + i] = fractionalBytes[i];
        }

        // Remove trailing zeros
        uint256 endIndex = paddedFractional.length;
        while (endIndex > 0 && paddedFractional[endIndex - 1] == "0") {
            endIndex--;
        }

        bytes memory trimmedFractional = new bytes(endIndex);
        for (uint256 i = 0; i < endIndex; i++) {
            trimmedFractional[i] = paddedFractional[i];
        }

        return string(abi.encodePacked(_toString(wholePart), ".", trimmedFractional));
    }

    /**
     * @dev Internal function to convert uint256 to string
     * @param value The value to convert
     * @return The string representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}