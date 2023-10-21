const { ethers, network, deployments, getNamedAccounts } = require("hardhat");
const {
  networkConfig,
  localNetworks,
} = require("../../helper-hardhat-config.js");
const { assert, expect } = require("chai");

function getRandomId() {
    userId = "0x"

    for (let i = 0; i < 24; i++) {
        let randomValue = Math.floor((Math.random() * 100) % 15);
        if (randomValue <= 9) {
            userId += String.fromCharCode(48 + randomValue);
        }
        else {
            userId += String.fromCharCode(97 + randomValue - 9); 
        }
    }

    return userId
}

async function register(userRegistration, functionsMock, userId, role, name) {
    const response = await userRegistration.register(userId, role, name)
    const receipt = await response.wait(1)

    const reqId = receipt.logs[1].topics[1]

    const fulfillResponse = await functionsMock.fulfillRequest(reqId)
    const fulfillReceipt = await fulfillResponse.wait(1)
}

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
        let clientId
        let contractorId
        let attackerId

        let attacker;
        
        let clientBB;
        let contractorBB;
        let attackerBB;

        let clientUR;
        let contractorUR;
        
        let clientUsdc;
        let contractorUsdc;

        const CUSTOMER = 0
        const CONTRACTOR = 1

        const USDC_START_BALANCE = 1e9
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

            clientId = getRandomId()
            contractorId = getRandomId()
            attackerId = getRandomId()

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
            attackerBB = builderBuddy.connect(attacker);

            clientUR = userRegistration.connect(client);
            contractorUR = userRegistration.connect(contractor);

            clientUsdc = usdcToken.connect(client);
            contractorUsdc = usdcToken.connect(contractor);

            const usdcTransfer1 = await usdcToken.mint(client.address, USDC_START_BALANCE)
            await usdcTransfer1.wait(1)

            const usdcTransfer2 = await usdcToken.mint(contractor.address, USDC_START_BALANCE)
            await usdcTransfer2.wait(1)
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

            describe("Create Order Test", () => {
                let title = "I want to build a house"
                let desc = "I want to construct a dream house"
                let category = 0                // construction
                let locality = "Agra"
                let level = 1
                let budget = 6969696969
                let expectedStartDate = parseInt(Date.now() / 1000) + 100

                beforeEach(async() => {
                    await register(clientUR, mocksFunctions, clientId, CUSTOMER, "billa69")
                    await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "bhai me contractor hu")
                })

                it("Order Created and stored in ds", async() => {
                    await expect(clientBB.createOrder(clientId, title, desc, category, locality, level, budget, expectedStartDate))
                        .to.emit(builderBuddy, "OrderCreated")

                    const counter = await clientBB.getOrderCounter()
                    const data = await clientBB.getOrder(counter - 1)

                    assert.equal(data.customer, client.address)
                    assert.equal(data.customerId, clientId)
                    assert.equal(data.title, title)
                    assert.equal(data.description, desc)
                    assert.equal(data.category, category)
                    assert.equal(data.locality, locality)
                    assert.equal(data.level, level)
                    assert.equal(data.budget, budget)
                    assert.equal(data.expectedStartDate, expectedStartDate)
                    assert.equal(data.status, 0)
                    assert.equal(data.contractor, 0x00)
                    assert.equal(data.contractorId, 0x00)
                    assert.equal(data.taskContract, 0)
                })

                it("checking getAllCustomerOrders Test", async() => {
                    await clientBB.createOrder(clientId, title, desc, category, locality, level, budget, expectedStartDate);
                    let currCustomerOrders = await clientBB.getAllCustomerOrders(clientId);
                    assert.equal(currCustomerOrders.length, 1);
                });

                it("reverts if Customer is not register", async() => {
                    let newCustomerId = getRandomId();
                    attackerBB = builderBuddy.connect(attacker);
                    

                    await expect(attackerBB.createOrder(newCustomerId, title, desc, category, locality, level, budget, expectedStartDate))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__InvalidCustomer");
                
                });

                it("revets if clientId is not of Caller", async() => {
                    attackerBB = builderBuddy.connect(attacker);
                    await expect(attackerBB.createOrder(clientId, title, desc, category, locality, level, budget, expectedStartDate))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__InvalidCustomer");
                });

                it("reverts if level is not valid", async() => {
                    let newLevel = 6;
                    await expect(clientBB.createOrder(clientId, title, desc, category, locality, newLevel, budget, expectedStartDate))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__InvalidLevel");
                });

                it("reverts if Time is not valid", async() => {
                    let newExpectedStartDate = parseInt(Date.now() / 1000) - 100;
                    await expect(clientBB.createOrder(clientId, title, desc, category, locality, level, budget, newExpectedStartDate))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__OrderCantHavePastDate");
                });
            })

            describe("Confirm User Order Testing", () => {
                let title = "I want to build a house"
                let desc = "I want to construct a dream house"
                let category = 0                // construction
                let locality = "Agra"
                let level = 1
                let budget = 6969696969
                let expectedStartDate = parseInt(Date.now() / 1000) + 100

                beforeEach(async() => {
                    // Register Customer
                    await register(clientUR, mocksFunctions, clientId, CUSTOMER, "billa69")

                    // Register Contractor
                    await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "bhai me contractor hu")

                    // Contractor Stake USDC on Builder Buddy

                    const approveResponse = await contractorUsdc.approve(builderBuddy.address, collaterals[level - 1])
                    await approveResponse.wait(1)

                    const stakeResponse = await contractorBB.incrementLevelAndStakeUSDC(contractorId, level)
                    await stakeResponse.wait(1)
                })

                it("Customer places order, add contractor, contractor confirms order and task manager deployed", async() => {
                    const contractorData = await contractorUR.contractors(contractorId)
                    assert.equal(contractorData.level, level)
                    assert.equal(contractorData.totalCollateralDeposited, collaterals[level - 1])
                    

                    // Customer Places Order
                    const orderId = await clientBB.getOrderCounter()
                    const orderResponse = await clientBB.createOrder(clientId, title, desc, category, locality, level, budget, expectedStartDate)
                    await orderResponse.wait(1)


                    // Assigns Contractor
                    const assignContractorResponse = await clientBB.assignContractorToOrder(clientId, orderId, contractorId)
                    await assignContractorResponse.wait(1)

                    // Contractor Confirms Order
                    await expect(contractorBB.confirmUserOrder(contractorId, orderId)).to.emit(builderBuddy, "OrderConfirmed")


                    const orderData = await clientBB.getOrder(orderId)
                    const taskContract = await orderData.taskContract

                    // Asserts
                    assert.equal(orderData.status, 1)
                    assert.equal(orderData.contractor, contractor.address)
                    assert.equal(orderData.contractorId, contractorId)
                    assert.notEqual(taskContract, 0)

                    console.log("Task Contract:", taskContract);

                    const tm = await ethers.getContractAt("TaskManager", taskContract)

                    const _orderId = await tm.getOrderId()
                    const _clientId = await tm.getClientId()
                    const _contractorId = await tm.getContractorId()
                    const _client = await tm.getClientAddress()
                    const _contractor = await tm.getContractorAddress()
                    const _level = await tm.getLevel()
                    const _usdcAddress = await tm.getUsdcToken()
                    const _collDep = await tm.getCollateralDeposited()
                    const _workFinished = await tm.isWorkFinished()
                    const _builderBuddyAddr = await tm.getBuilderBuddyAddr()
                    const taskCounter = await tm.getTaskCounter()

                    assert.equal(_orderId.toString(), orderId)
                    assert.equal(_clientId, clientId)
                    assert.equal(_contractorId, contractorId)
                    assert.equal(_client, client.address)
                    assert.equal(_contractor, contractor.address)
                    assert.equal(_level, level)
                    assert.equal(_usdcAddress, usdcToken.address)
                    assert.equal(_collDep.toString(), contractorData.totalCollateralDeposited)
                    assert.equal(_workFinished, false)
                    assert.equal(_builderBuddyAddr, builderBuddy.address)
                    assert.equal(taskCounter, 0)
                })
            })

            describe("Assign Contractor To Order Test", () => {
                beforeEach(async() => {
                    // Register Customer
                    await register(clientUR, mocksFunctions, clientId, CUSTOMER, "billa69");

                    
                    let title = "I want to build a house"
                    let desc = "I want to construct a dream house"
                    let category = 0                // construction
                    let locality = "Agra"
                    let level = 1
                    let budget = 6969696969
                    let expectedStartDate = parseInt(Date.now() / 1000) + 100
                    await clientBB.createOrder(clientId, title, desc, category, locality, level, budget, expectedStartDate);
                    
                    let newLevel = 2;
                    await clientBB.createOrder(clientId, title, desc, category, locality, newLevel, budget, expectedStartDate);
                })

                it("reverts if contractor is not registered", async() => {
                    let newContractorId = getRandomId();
                    await expect(clientBB.assignContractorToOrder(clientId, 0, newContractorId))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__ContractorNotFound");
                });

                it("reverts if client is not caller", async() => {
                    await expect(attackerBB.assignContractorToOrder(clientId, 0, contractorId))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__InvalidCustomer");
                });
                
                it("reverts if contractor has not stacked", async() => {
                    await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "bhai me contractor hu");

                    await expect(clientBB.assignContractorToOrder(clientId, 0, contractorId))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__ContractorHasNotStaked");
                });

                it("reverts if contractor is assigned to an order", async() => {
                    await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "bhai me contractor hu");
                    
                    let level = 1;
                    const approveResponse = await contractorUsdc.approve(builderBuddy.address, collaterals[level])
                    await approveResponse.wait(1)

                    const stakeResponse = await contractorBB.incrementLevelAndStakeUSDC(contractorId, 1);
                    await stakeResponse.wait(1)

                    const assignContractor = await clientBB.assignContractorToOrder(clientId, 0, contractorId);
                    await assignContractor.wait(1)

                    await contractorBB.confirmUserOrder(contractorId, 0);

                    await expect(clientBB.assignContractorToOrder(clientId, 0, contractorId))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__ContractorAlreadySet");
                });

                it("reverts if order level is greater than contractor level", async() => {
                    await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "bhai me contractor hu");
                    
                    let level = 1;
                    const approveResponse = await contractorUsdc.approve(builderBuddy.address, collaterals[level])
                    await approveResponse.wait(1)

                    const stakeResponse = await contractorBB.incrementLevelAndStakeUSDC(contractorId, 1);
                    await stakeResponse.wait(1)

                    await expect(clientBB.assignContractorToOrder(clientId, 1, contractorId))
                        .to.be.revertedWithCustomError(builderBuddy, "BuilderBuddy__ContractorIneligible");
                });

                it("contractor is assigned to order and store in data structure", async() => {
                    await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "bhai me contractor hu");

                    let level = 1;
                    const approveResponse = await contractorUsdc.approve(builderBuddy.address, collaterals[level])
                    await approveResponse.wait(1)

                    const stakeResponse = await contractorBB.incrementLevelAndStakeUSDC(contractorId, 1);
                    await stakeResponse.wait(1)

                    await expect(clientBB.assignContractorToOrder(clientId, 0, contractorId)).to.emit(builderBuddy, "ContractorAssigned").withArgs(0, contractor.address);
                    
                    let orderData = await clientBB.getOrder(0); 
                    assert.equal(orderData.contractor, contractor.address);
                    assert.equal(orderData.contractorId, contractorId);
                });
            });

            // describe("confirm User Order Test", () => {
                
            // })

            describe("getRequiredCollateral Test", function () {
                it("Should give correct collateral", async function () {
                    for(let level = 1; level <= 5; level++){
                        let collateral = await builderBuddy.getRequiredCollateral(level);
                        assert.equal(collateral.toString(), collaterals[level - 1], "Collateral is not correct");
                    }
                });
            });
        });
  });