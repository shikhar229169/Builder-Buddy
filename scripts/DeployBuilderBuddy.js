const { ethers, network } = require("hardhat");
const fs = require("fs")
const { networkConfig, localNetworks } = require("../helper-hardhat-config")
const { verifyContract } = require("../utils/verifyContract")
const { getEncryptedSecretsUrl } = require("../utils/generateEncryptedSecrets")
require("dotenv").config()


async function main() {
    const chainId = network.config.chainId
    
    
    const minScore = networkConfig[chainId].minScore
    const scorerId = networkConfig[chainId].scorerId
    const source = fs.readFileSync("./Functions-request-source.js").toString()
    const gasLimit = networkConfig[chainId].gasLimit
    const secrets = { GC_API_KEY: process.env.GC_API_KEY }
    const secretsEncrypted = await getEncryptedSecretsUrl(secrets)
    fs.writeFileSync("./encryptedSecretsUrl.txt", secretsEncrypted)
    let collaterals        
    const scores = [0, 50, 100, 200, 300]
    
    let router
    let subId
    let donName
    let usdcToken
    
    
    if (localNetworks.includes(network.name)) {

    }
    else {
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
    
    const args = [router, minScore, scorerId, source, subId, gasLimit, secretsEncrypted, donName, collaterals, scores, usdcToken]
    
    const BuilderBuddyFactory = await ethers.getContractFactory("BuilderBuddy")

    console.log("Deploying Builder Buddy...")

    const contract = await BuilderBuddyFactory.deploy(...args)

    console.log("Waiting for 3 block confirmations")

    await contract.deployTransaction.wait(3)

    console.log("Deployed at Address:", contract.address)

    await verifyContract(contract.address, args)
}

main().catch((err) => {
    console.error(err)
    process.exitCode = 1
  })
