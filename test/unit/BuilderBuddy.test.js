const { ethers, network, deployments, getNamedAccounts } = require("hardhat");
const {
  networkConfig,
  localNetworks,
} = require("../../helper-hardhat-config.js");
const { assert, expect } = require("chai");

!localNetworks.includes(network.name)
  ? describe.skip
  : describe("BuilderBuddy Tests", function () {
        let deployer;
        let userRegistration;
        let mocksFunctions;
        let builderBuddy;
        let usdcToken;
        let chainId = network.config.chainId;
        let constructorData = networkConfig[chainId];
        const donName = 'fun-local'
        let client;
        let contractor;
        let attacker;
        
        let clientBB;
        let contractorBB;

        let clientUR;
        let contractorUR;
        
        let clientUsdc;
        let contractorUsdc;

        let collaterals = [2, 3, 4, 5, 6];
        let decimals = constructorData.decimals;
        for (let i in collaterals) {
            collaterals[i] *= Math.pow(10, decimals)
        }

        const scores = [0, 50, 100, 200, 300]
        
        beforeEach(async () => {
            const accounts = await ethers.getSigners();
            deployer = (await getNamedAccounts()).deployer;
            client = accounts[1];
            contractor = accounts[2];
            attacker = accounts[3];
            await deployments.fixture(["main"]);

            const usdcTokenInstance = await deployments.get("MockUsdc");
            usdcToken = await ethers.getContractAt("MockUsdc", usdcTokenInstance.address);

            const userRegistrationInstance = await deployments.get("UserRegistration");
            userRegistration = await ethers.getContractAt("UserRegistration", userRegistrationInstance.address);

            const mockFunctionsRouter = await deployments.get("MockFunctionsRouter");
            mocksFunctions = await ethers.getContractAt("MockFunctionsRouter", mockFunctionsRouter.address);

            const builderBuddyInstance = await deployments.get("BuilderBuddy");
            builderBuddy = await ethers.getContractAt("BuilderBuddy", builderBuddyInstance.address);
            
            clientBB = builderBuddy.connect(client);
            contractorBB = builderBuddy.connect(contractor);

            clientUR = userRegistration.connect(client);
            contractorUR = userRegistration.connect(contractor);

            clientUsdc = usdcToken.connect(client);
            contractorUsdc = usdcToken.connect(contractor);
        });

        describe("Constructor Test", function () {
            it("Should give correct values for constructor", async function () {
                let userRegAddr = await builderBuddy.getUserRegistrationContract();
                let usdcAddr = await builderBuddy.getUsdcAddress();
                let levelRequirements = new Array();
                let scoreForLevel = new Array();

                for (let i = 1; i <= 5; i++) {
                    let levelRequirement = await builderBuddy.getRequiredCollateral(i);
                    levelRequirements.push(levelRequirement.toString());

                    let score = await builderBuddy.getScore(i);
                    scoreForLevel.push(score.toString());
                }

                for (let i = 0; i < 5; i++) {
                    assert.equal(scoreForLevel[i], scores[i]);
                    assert.equal(levelRequirements[i], collaterals[i]);
                }
                
                assert.equal(userRegAddr, userRegistration.address, "User Registration address is not correct");
                assert.equal(usdcAddr, usdcToken.address, "Usdc address is not correct");
                
            });
        });
  });