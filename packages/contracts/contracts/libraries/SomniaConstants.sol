// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SomniaConstants
 * @dev Constants for Somnia Network deployments based on official DIA Oracle documentation
 * @notice Updated from official Somnia DIA docs: https://docs.diadata.org/chains/somnia
 */
library SomniaConstants {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // OFFICIAL DIA ORACLE ADDRESSES (from official Somnia docs)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Official DIA Oracle V2 on Somnia Mainnet
    address public constant DIA_ORACLE_MAINNET =
        0xbA0E0750A56e995506CA458b2BdD752754CF39C4;

    /// @notice Official DIA Oracle V2 on Somnia Testnet
    address public constant DIA_ORACLE_TESTNET =
        0x9206296ea3aee3e6bdc07f7aaef14dfcf33d865d;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // OFFICIAL TOKEN ADDRESSES (from official Somnia docs)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Official USDC on Somnia Mainnet
    address public constant USDC_MAINNET =
        0x28bec7e30e6faee657a03e19bf1128aad7632a00;

    /// @notice Official USDT on Somnia Mainnet
    address public constant USDT_MAINNET =
        0x67B302E35Aef5EEE8c32D934F5856869EF428330;

    /// @notice Official WETH on Somnia Mainnet
    address public constant WETH_MAINNET =
        0x936Ab8C674bcb567CD5dEB85D8A216494704E9D8;

    /// @notice Official WSOMI (Wrapped Somnia) on Mainnet
    address public constant WSOMI_MAINNET =
        0x046EDe9564A72571df6F5e44d0405360c0f4dCab;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UTILITY CONTRACTS (from official Somnia docs)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice MultiCallV3 contract on Somnia
    address public constant MULTICALL_V3 =
        0x5e44F178E8cF9B2F5409B6f18ce936aB817C5a11;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // LAYERZERO INTEGRATION (from official Somnia docs)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice LayerZero EndpointV2 on Somnia
    address public constant LAYERZERO_ENDPOINT_V2 =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;

    /// @notice LayerZero Chain ID (EID) for Somnia
    uint32 public constant LAYERZERO_CHAIN_ID = 30380;

    /// @notice LayerZero SendUln302
    address public constant LAYERZERO_SEND_ULN302 =
        0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;

    /// @notice LayerZero ReceiveUln302
    address public constant LAYERZERO_RECEIVE_ULN302 =
        0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;

    /// @notice LayerZero Executor
    address public constant LAYERZERO_EXECUTOR =
        0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;

    /// @notice LayerZero DeadDVN
    address public constant LAYERZERO_DEAD_DVN =
        0x6788f52439ACA6BFF597d3eeC2DC9a44B8FEE842;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // MAINNET ASSET ADAPTER ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice USDT Adapter on Mainnet
    address public constant USDT_ADAPTER_MAINNET =
        0x936C4F07fD4d01485849ee0EE2Cdcea2373ba267;

    /// @notice USDC Adapter on Mainnet
    address public constant USDC_ADAPTER_MAINNET =
        0x5D4266f4DD721c1cD8367FEb23E4940d17C83C93;

    /// @notice BTC Adapter on Mainnet
    address public constant BTC_ADAPTER_MAINNET =
        0xb12e1d47b0022fA577c455E7df2Ca9943D0152bE;

    /// @notice ARB Adapter on Mainnet
    address public constant ARB_ADAPTER_MAINNET =
        0x6a96a0232402c2BC027a12C73f763b604c9F77a6;

    /// @notice SOL Adapter on Mainnet
    address public constant SOL_ADAPTER_MAINNET =
        0xa4a3a8B729939E2a79dCd9079cee7d84b0d96234;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // TESTNET ASSET ADAPTER ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice USDT Adapter on Testnet
    address public constant USDT_ADAPTER_TESTNET =
        0x67d2c2a87a17b7267a6dbb1a59575c0e9a1d1c3e;

    /// @notice USDC Adapter on Testnet
    address public constant USDC_ADAPTER_TESTNET =
        0x235266D5ca6f19F134421C49834C108b32C2124e;

    /// @notice BTC Adapter on Testnet
    address public constant BTC_ADAPTER_TESTNET =
        0x4803db1ca3A1DA49c3DB991e1c390321c20e1f21;

    /// @notice ARB Adapter on Testnet
    address public constant ARB_ADAPTER_TESTNET =
        0x74952812B6a9e4f826b2969C6D189c4425CBc19B;

    /// @notice SOL Adapter on Testnet
    address public constant SOL_ADAPTER_TESTNET =
        0xD5Ea6C434582F827303423dA21729bEa4F87D519;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // DIA ORACLE CONFIGURATION (from official docs)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice DIA Oracle decimals (8 decimal places)
    uint8 public constant DIA_ORACLE_DECIMALS = 8;

    /// @notice Deviation threshold that triggers price updates (0.5%)
    uint256 public constant DEVIATION_THRESHOLD = 50; // 0.5% in basis points

    /// @notice Refresh frequency in seconds (120 seconds = 2 minutes)
    uint256 public constant REFRESH_FREQUENCY = 120;

    /// @notice Heartbeat interval (24 hours forced update)
    uint256 public constant HEARTBEAT_INTERVAL = 86400;

    /// @notice Pricing methodology identifier
    string public constant PRICING_METHODOLOGY = "MAIR";

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ASSET PRICE KEYS (for DIA Oracle getValue calls)
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice STT/USD price key (native Somnia token)
    string public constant STT_USD_KEY = "STT/USD";

    /// @notice USDT/USD price key
    string public constant USDT_USD_KEY = "USDT/USD";

    /// @notice USDC/USD price key
    string public constant USDC_USD_KEY = "USDC/USD";

    /// @notice BTC/USD price key
    string public constant BTC_USD_KEY = "BTC/USD";

    /// @notice ARB/USD price key (Arbitrum)
    string public constant ARB_USD_KEY = "ARB/USD";

    /// @notice SOL/USD price key (Solana)
    string public constant SOL_USD_KEY = "SOL/USD";

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NETWORK IDENTIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Somnia Mainnet Chain ID
    uint256 public constant MAINNET_CHAIN_ID = 50311;

    /// @notice Somnia Testnet Chain ID
    uint256 public constant TESTNET_CHAIN_ID = 50312;

    /// @notice Native STT address (0x0 for native tokens)
    address public constant NATIVE_STT = address(0);

    // ═══════════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get DIA Oracle address for current network
     * @param chainId The chain ID to get oracle for
     * @return oracle DIA Oracle address
     */
    function getDIAOracle(
        uint256 chainId
    ) internal pure returns (address oracle) {
        if (chainId == MAINNET_CHAIN_ID) {
            return DIA_ORACLE_MAINNET;
        } else if (chainId == TESTNET_CHAIN_ID) {
            return DIA_ORACLE_TESTNET;
        } else {
            revert("Unsupported chain ID");
        }
    }

    /**
     * @notice Get asset adapter address for current network
     * @param asset Asset identifier (USDT, USDC, BTC, ARB, SOL)
     * @param chainId The chain ID
     * @return adapter Asset adapter address
     */
    function getAssetAdapter(
        string memory asset,
        uint256 chainId
    ) internal pure returns (address adapter) {
        bytes32 assetHash = keccak256(abi.encodePacked(asset));

        if (chainId == MAINNET_CHAIN_ID) {
            if (assetHash == keccak256("USDT")) return USDT_ADAPTER_MAINNET;
            if (assetHash == keccak256("USDC")) return USDC_ADAPTER_MAINNET;
            if (assetHash == keccak256("BTC")) return BTC_ADAPTER_MAINNET;
            if (assetHash == keccak256("ARB")) return ARB_ADAPTER_MAINNET;
            if (assetHash == keccak256("SOL")) return SOL_ADAPTER_MAINNET;
        } else if (chainId == TESTNET_CHAIN_ID) {
            if (assetHash == keccak256("USDT")) return USDT_ADAPTER_TESTNET;
            if (assetHash == keccak256("USDC")) return USDC_ADAPTER_TESTNET;
            if (assetHash == keccak256("BTC")) return BTC_ADAPTER_TESTNET;
            if (assetHash == keccak256("ARB")) return ARB_ADAPTER_TESTNET;
            if (assetHash == keccak256("SOL")) return SOL_ADAPTER_TESTNET;
        }

        revert("Asset not supported");
    }

    /**
     * @notice Check if chain ID is supported
     * @param chainId Chain ID to check
     * @return supported Whether chain is supported
     */
    function isChainSupported(
        uint256 chainId
    ) internal pure returns (bool supported) {
        return chainId == MAINNET_CHAIN_ID || chainId == TESTNET_CHAIN_ID;
    }
}
