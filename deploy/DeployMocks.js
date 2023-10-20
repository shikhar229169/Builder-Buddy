const { ethers, network } = require("hardhat");
const fs = require("fs")
const { localNetworks } = require("../helper-hardhat-config")

module.exports = async( { deployments, getNamedAccounts } ) => {
    if (localNetworks.includes(network.name)) {
        const { deployer } = await getNamedAccounts()
        const { deploy, log } = deployments

        console.log("Deploying Mocks....")

        await deploy("MockUsdc", {
            from: deployer,
            args: [],
            log: true
        })


        await deploy("MockFunctionsRouter", {
            from: deployer,
            args: [],
            log: true
        })

    }
}

module.exports.tags = ["mocks"]