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
        let arbiterInstance;
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

            describe("getUsdcAddress Test", function () {
                it("Should give correct usdc address", async function () {
                    let usdcAddr = await builderBuddy.getUsdcAddress();
                    assert.equal(usdcAddr, usdcToken.address, "Usdc address is not correct");
                });
            });

            describe("getMaxEligibleLevelByScore Test", function () {
                it("Should give correct max level", async function () {
                    let score = 100;
                    let maxLevel = await builderBuddy.getMaxEligibleLevelByScore(score);
                    let level = 1;
                    while (
                        level + 1 < 5 && scores[level] <= score
                    ) {
                        level++;
                    }

                    assert.equal(maxLevel.toString(), level, "Max level is not correct");
                });
            });

            describe("getScore Test", function () {
                it("Should give correct score", async function () {
                    let level = 3;
                    let score = await builderBuddy.getScore(level);
                    assert.equal(score.toString(), scores[level - 1], "Score is not correct");
                });
            });

            describe("getOrderCounter Test", function () {
                it("Should give correct order counter", async function () {
                    let orderCounter = await builderBuddy.getOrderCounter();
                    assert.equal(orderCounter, 0, "Order counter is not correct");
                });
            });
            
            describe("getUserRegistrationContract Test", function () {
                it("Should give correct user registration address", async function () {
                    let userRegAddr = await builderBuddy.getUserRegistrationContract();
                    assert.equal(userRegAddr, userRegistration.address, "User Registration address is not correct");
                });
            });
            
            describe("getArbiterContract Test", function () {
                it("Should give correct arbiter address", async function () {
                    let arbiterAddr = await builderBuddy.getArbiterContract();
                    assert.notEqual(arbiterAddr, 0x0000000000000000000000000000000000000000, "Arbiter address is not correct");
                });
            });
        });
  });