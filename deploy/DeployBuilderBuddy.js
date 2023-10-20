const { ethers, network } = require("hardhat");
const fs = require("fs")
const { networkConfig, localNetworks } = require("../helper-hardhat-config")
const { verifyContract } = require("../utils/verifyContract")
const { getEncryptedSecretsUrl } = require("../utils/generateEncryptedSecrets")
require("dotenv").config()


module.exports = async({ getNamedAccounts, deployments }) => {
    const chainId = network.config.chainId
    const { deployer } = await getNamedAccounts()
    const { deploy, log } = deployments
    
    const minScore = networkConfig[chainId].minScore
    const scorerId = networkConfig[chainId].scorerId
    const source = fs.readFileSync("./Functions-request-source.js").toString()
    const gasLimit = networkConfig[chainId].gasLimit
    let secretsEncrypted
    let collaterals        
    let conf
    const scores = [0, 50, 100, 200, 300]
    
    let router
    let subId
    let donName
    let usdcToken

    
    if (localNetworks.includes(network.name)) {
        conf = 1
        const mocksDeployed = await deployments.fixture(["mocks"])
        router = mocksDeployed["MockFunctionsRouter"].address
        usdcToken = mocksDeployed["MockUsdc"].address
        subId = 1
        donName = 'fun-local'
        secretsEncrypted = "0x12"
        
        const decimals = networkConfig[chainId].decimals
        collaterals = [2, 3, 4, 5, 6]
        for (let i in collaterals) {
            collaterals[i] *= Math.pow(10, decimals)
        }
    }
    else {
        conf = 3
        
        const secrets = { GC_API_KEY: process.env.GC_API_KEY }
        secretsEncrypted = await getEncryptedSecretsUrl(secrets)
        fs.writeFileSync("./encryptedSecretsUrl.txt", secretsEncrypted)
        
        router = networkConfig[chainId].router
        subId = networkConfig[chainId].subId
        donName = networkConfig[chainId].donId
        usdcToken = networkConfig[chainId].usdcToken
        const decimals = networkConfig[chainId].decimals
        collaterals = [2, 3, 4, 5, 6]
        for (let i in collaterals) {
            collaterals[i] *= Math.pow(10, decimals)
        }
    }
    
    
    // for User Registration Contract
    console.log("Deploying User Registration...")
    const args1 = [router, minScore, scorerId, source, subId, gasLimit, secretsEncrypted, donName]
    const userRegistrationContract = await deploy("UserRegistration",  {
        from: deployer,
        args: args1,
        log: true,
        waitConfirmations: conf
    })
    
    console.log("Deployed at: ", userRegistrationContract.address)
    
    
    // for BuilderBuddy Contract
    const args2 = [userRegistrationContract.address, collaterals, scores, usdcToken]
    
    console.log("Deploying Builder Buddy...")
    const builderBuddyContract = await deploy("BuilderBuddy", {
        from: deployer,
        args: args2,
        log: true,
        waitConfirmations: conf
    })
    
    console.log("Deployed at address: ", builderBuddyContract.address)
    
    console.log("Setting Builder Buddy contract address in user registration...")
    const userRegistration = await ethers.getContractAt("UserRegistration", userRegistrationContract.address)
    const response = await userRegistration.setBuilderBuddy(builderBuddyContract.address)
    await response.wait(1)
    console.log("Setted up")
    
    const builderBuddy = await ethers.getContractAt("BuilderBuddy", builderBuddyContract.address)
    const arbiterContractAddress = await builderBuddy.getArbiterContract()
    
    if (!localNetworks.includes(network.name) && process.env.MUMBAI_API_KEY) {
        await verifyContract(builderBuddyContract.address, args2)
        await verifyContract(userRegistrationContract.address, args1)
        await verifyContract(arbiterContractAddress, [deployer, builderBuddyContract.address])
    }
}

module.exports.tags = ["main"]