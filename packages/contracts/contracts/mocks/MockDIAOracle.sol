// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockDIAOracle
 * @dev Mock DIA Oracle for testing HyperLend on Somnia Network
 * @notice Implements IDIAOracleV2 interface for testing purposes
 */
contract MockDIAOracle {
    mapping(string => uint128) public prices;
    mapping(string => uint128) public timestamps;

    event PriceSet(string indexed key, uint128 price, uint128 timestamp);

    /**
     * @notice Set price data for a given key
     * @param key Asset identifier (e.g., "STT/USD")
     * @param price Price with 8 decimals precision
     * @param timestamp Price timestamp
     */
    function setValue(
        string memory key,
        uint128 price,
        uint128 timestamp
    ) external {
        prices[key] = price;
        timestamps[key] = timestamp;
        emit PriceSet(key, price, timestamp);
    }

    /**
     * @notice Get price data for a single asset
     * @param key Asset identifier
     * @return price Latest price with 8 decimals
     * @return timestamp Last update timestamp
     */
    function getValue(
        string memory key
    ) external view returns (uint128 price, uint128 timestamp) {
        return (prices[key], timestamps[key]);
    }

    /**
     * @notice Get price data for multiple assets
     * @param keys Array of asset identifiers
     * @return _prices Array of latest prices
     * @return _timestamps Array of update timestamps
     */
    function getValues(
        string[] memory keys
    )
        external
        view
        returns (uint128[] memory _prices, uint128[] memory _timestamps)
    {
        _prices = new uint128[](keys.length);
        _timestamps = new uint128[](keys.length);

        for (uint256 i = 0; i < keys.length; i++) {
            _prices[i] = prices[keys[i]];
            _timestamps[i] = timestamps[keys[i]];
        }
    }

    /**
     * @notice Check if price feed exists
     * @param key Asset identifier
     * @return exists Whether price data exists
     */
    function priceExists(
        string memory key
    ) external view returns (bool exists) {
        return timestamps[key] > 0;
    }

    /**
     * @notice Get age of price data
     * @param key Asset identifier
     * @return age Seconds since last update
     */
    function getPriceAge(
        string memory key
    ) external view returns (uint256 age) {
        if (timestamps[key] == 0) return type(uint256).max;
        return block.timestamp - timestamps[key];
    }

    /**
     * @notice Batch set prices for testing
     * @param keys Array of asset identifiers
     * @param _prices Array of prices
     */
    function setBatchPrices(
        string[] memory keys,
        uint128[] memory _prices
    ) external {
        require(
            keys.length == _prices.length,
            "MockDIAOracle: Array length mismatch"
        );

        uint128 currentTimestamp = uint128(block.timestamp);
        for (uint256 i = 0; i < keys.length; i++) {
            prices[keys[i]] = _prices[i];
            timestamps[keys[i]] = currentTimestamp;
            emit PriceSet(keys[i], _prices[i], currentTimestamp);
        }
    }

    /**
     * @notice Simulate price movement for testing
     * @param key Asset identifier
     * @param percentChange Percentage change (positive or negative, scaled by 100)
     */
    function simulatePriceChange(
        string memory key,
        int256 percentChange
    ) external {
        uint128 currentPrice = prices[key];
        require(currentPrice > 0, "MockDIAOracle: Price not set");

        uint128 newPrice;
        if (percentChange >= 0) {
            newPrice =
                currentPrice +
                uint128(
                    (uint256(currentPrice) * uint256(percentChange)) / 10000
                );
        } else {
            uint256 decrease = (uint256(currentPrice) *
                uint256(-percentChange)) / 10000;
            newPrice = currentPrice > uint128(decrease)
                ? currentPrice - uint128(decrease)
                : currentPrice / 2;
        }

        prices[key] = newPrice;
        timestamps[key] = uint128(block.timestamp);
        emit PriceSet(key, newPrice, uint128(block.timestamp));
    }

    /**
     * @notice Remove price data for testing scenarios
     * @param key Asset identifier
     */
    function removePriceData(string memory key) external {
        delete prices[key];
        delete timestamps[key];
    }
}
