require("dotenv").config()

const networkConfig = {
    80001: {
        name: "mumbai",
        router: "0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C",
        donId: "fun-polygon-mumbai-1",
        scorerId: process.env.GC_SCORER_ID,
        minScore: "1",
        subId: "429",            // you can replace this with your own chainlink functions subId
        gasLimit: "300000",
        usdcToken: "0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747",
        decimals: 6
    },
    31337: {
        name: "hardhat",
        scorerId: process.env.GC_SCORER_ID,
        minScore: "1",
        gasLimit: "300000",
        decimals: 6
    }
}

const localNetworks = ["hardhat", "localhost"]

module.exports = { networkConfig, localNetworks }