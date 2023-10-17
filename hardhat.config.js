require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config()

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL || "url"
const MUMBAI_RPC_URL = process.env.MUMBAI_RPC_URL
const PRIVATE_KEY = process.env.PRIVATE_KEY
const MUMBAI_API_KEY = process.env.MUMBAI_API_KEY

const SOLC_SETTINGS = {
  optimizer: {
    enabled: true,
    runs: 200,
  },
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {

  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 37,
      },
      "viaIR": true,
    }
  },
  
  // contractSizer: {
  //   alphaSort: true,
  //   disambiguatePaths: false,
  //   runOnCompile: true,
  //   strict: true,
  // },

//   solidity: {
//     compilers: [
//     {
//       version: "0.8.19",
//       settings: SOLC_SETTINGS
//     }
//   ]
// },

  defaultNetwork: "mumbai",

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
