// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDIAOracleV2
 * @dev Interface for DIA Oracle V2 integration on Somnia Network
 * @notice Used to fetch secure price data for assets including native STT
 */
interface IDIAOracleV2 {
    /**
     * @notice Get the latest price data for a given asset
     * @param key The asset identifier (e.g., "BTC/USD", "STT/USD")
     * @return price The latest price with 8 decimals
     * @return timestamp The timestamp of the last update
     */
    function getValue(
        string memory key
    ) external view returns (uint128 price, uint128 timestamp);

    /**
     * @notice Get multiple price feeds in a single call
     * @param keys Array of asset identifiers
     * @return prices Array of latest prices
     * @return timestamps Array of update timestamps
     */
    function getValues(
        string[] memory keys
    )
        external
        view
        returns (uint128[] memory prices, uint128[] memory timestamps);

    /**
     * @notice Check if a price feed exists and is active
     * @param key The asset identifier
     * @return exists Whether the price feed exists
     */
    function priceExists(string memory key) external view returns (bool exists);

    /**
     * @notice Get the age of the last price update
     * @param key The asset identifier
     * @return age Age in seconds since last update
     */
    function getPriceAge(string memory key) external view returns (uint256 age);
}
