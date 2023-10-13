const { ethers, run } = require("hardhat");
const fs = require("fs")
const { SecretsManager, createGist } = require("@chainlink/functions-toolkit");
require("dotenv").config()

async function getEncryptedGistsForSecrets(routerAddress, donId, secrets) {
    // First encrypt secrets and create a gist
    // const provider = new ethers.JsonRpcProvider(process.env.MUMBAI_RPC_URL)
    // const wallet = new ethers.Wallet(process.env.PRIVATE_KEY);
    // const signer_ = wallet.connect(provider); 

    const accounts = await ethers.getSigners()
    const signer = accounts[0]

  const secretsManager = new SecretsManager({
    signer: signer,
    functionsRouterAddress: routerAddress,
    donId: donId,
  });

  await secretsManager.initialize();

  // Encrypt secrets
  const encryptedSecretsObj = await secretsManager.encryptSecrets(secrets);

  console.log(`Creating gist...`);
  const githubApiToken = process.env.GITHUB_API_TOKEN;
  if (!githubApiToken)
    throw new Error(
      "githubApiToken not provided - check your environment variables"
    );

  // Create a new GitHub Gist to store the encrypted secrets
  const gistURL = await createGist(
    githubApiToken,
    JSON.stringify(encryptedSecretsObj)
  );
  console.log(`\n✅Gist created ${gistURL} . Encrypt the URLs..`);
  const encryptedSecretsUrls = await secretsManager.encryptSecretsUrls([
    gistURL,
  ]);

  return encryptedSecretsUrls
}

async function main() {
    const UserRegistationFactory = await ethers.getContractFactory("UserRegistration")
    const router = "0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C"
    const minScore = 1
    const scorerId = "5919"
    const source = fs.readFileSync("./Functions-request-source.js").toString()
    
    console.log(1);
    
    const subId = 362
    const gasLimit = 300000
    const secrets = { GC_API_KEY: process.env.GC_API_KEY }
    const secretsEncrypted = "0xf71824e4f22b805f9632fd7e6c9c6a4e0202d51ef4079bba5d15f9da4ec6722142a24803cbcb7bf36bf1fa8ac6a348008ca8d7fb37ff3164bdbbd0abe0471cf47cd938210d85675de7b377f4b2b04f3abc1a03bcbdfb9a5876dbf17702cd2c9b096582ce6a859a5f7405d9b767826962e66f9cf3a27544d403017baf029b4f2dea2bad82a92ee90e7bdc86f6958f752d43fc18aa66e1bc9977d2bf4eb63854cbec"
    const donName = "fun-polygon-mumbai-1"

    // const encryptedGistUrl = await getEncryptedGistsForSecrets(router, donName, secrets)
    // console.log(encryptedGistUrl);
    
    const contract = await UserRegistationFactory.deploy(router, minScore, scorerId, source, subId, gasLimit, secretsEncrypted, donName)
    console.log(contract);

    await contract.deploymentTransaction().wait(3)

    console.log(contract.target);

    await run("verify:verify", {
        address: contract.target,
        constructorArguments: [router, minScore, scorerId, source, subId, gasLimit, secretsEncrypted, donName]
    })
}

main().catch((err) => {
    console.error(err)
    process.exitCode = 1
  })
  