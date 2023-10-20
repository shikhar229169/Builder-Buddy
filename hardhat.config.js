require("@nomicfoundation/hardhat-toolbox")
require("hardhat-deploy")
require("dotenv").config()

const MUMBAI_RPC_URL = process.env.MUMBAI_RPC_URL
const PRIVATE_KEY = process.env.PRIVATE_KEY
const MUMBAI_API_KEY = process.env.MUMBAI_API_KEY

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true
    }
  },

  defaultNetwork: "hardhat",

  networks: {
    hardhat: {},

    mumbai: {
      url: MUMBAI_RPC_URL,
      chainId: 80001,
      accounts: PRIVATE_KEY !== undefined ? [PRIVATE_KEY] : [],
      blockConfirmations: 3
    }
  },

  namedAccounts: {
    deployer: {
      default: 0
    }
  },

  etherscan: {
    apiKey: MUMBAI_API_KEY
  },

  mocha: {
    timeout: 300000
  }
};