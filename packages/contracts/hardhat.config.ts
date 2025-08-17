import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "dotenv/config";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    networks: {
        hardhat: {
            chainId: 31337,
        },
        "somnia-testnet": {
            url: process.env.SOMNIA_TESTNET_RPC || "https://dream-rpc.somnia.network",
            chainId: 50312,
            accounts: process.env.PRIVATE_KEY && process.env.PRIVATE_KEY !== "your_private_key_here" 
                ? [process.env.PRIVATE_KEY] 
                : ["0x1234567890123456789012345678901234567890123456789012345678901234"], // Dummy key for testing
        },
    },
    mocha: {
        timeout: 60000,
    },
};

export default config;
