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
  : describe("TaskManager Tests", function () {
    
    let deployer;
    let client;
    let contractor;
    let attacker;

    let orderId = 0;

    let clientId;
    let contractorId;
    let attackerId;
    
    let chainId = network.config.chainId;
    let constructorData = networkConfig[chainId];

    let usdcToken;
    let userRegistration;
    let mocksFunctions;
    let builderBuddy;
    let taskManager;

    let clientBB;
    let contractorBB;
    let attackerBB;

    let clientUR;
    let contractorUR;

    let clientUsdc;
    let contractorUsdc;

    let clientTM;
    let contractorTM;

    const CUSTOMER = 0
    const CONTRACTOR = 1

    let collaterals = [2, 3, 4, 5, 6];
    let decimals = constructorData.decimals;
    for (let i in collaterals) {
        collaterals[i] *= Math.pow(10, decimals)
    }

    const scores = [0, 50, 100, 200, 300]

    let level = 1;

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
        
        await register(clientUR, mocksFunctions, clientId, CUSTOMER, "Client")

        let title = "I want to build a house";
        let desc = "I want to construct a dream house";
        let category = 0;
        let locality = "Agra";
        let level = 1;
        let budget = 7000000000;
        let expectedStartDate = parseInt(Date.now() / 1000) + 100;
        
        await register(contractorUR, mocksFunctions, contractorId, CONTRACTOR, "Contractor");
        await clientBB.createOrder(clientId, title, desc, category, locality, level, budget, expectedStartDate);

        await contractorUsdc.mint(contractor.address, collaterals[level]);

        const approveResponse = await contractorUsdc.approve(builderBuddy.address, collaterals[level]);
        await approveResponse.wait(1);

        const stakeResponse = await contractorBB.incrementLevelAndStakeUSDC(contractorId, 1);
        await stakeResponse.wait(1);

        const assignContractor = await clientBB.assignContractorToOrder(clientId, 0, contractorId);
        await assignContractor.wait(1);

        await contractorBB.confirmUserOrder(contractorId, orderId)

        const orderData = await clientBB.getOrder(orderId)
        const TaskManagerAddress = await orderData.taskContract
        taskManager = await ethers.getContractAt("TaskManager", TaskManagerAddress);

        clientTM = taskManager.connect(client);
        contractorTM = taskManager.connect(contractor);
    });

    describe("Constructor Tests", function () {
        it("All parameters should be correct", async function () {
            let _clientId = await taskManager.getClientId()
            let _contractorId = await taskManager.getContractorId()
            let _orderId = await taskManager.getOrderId() 
            let _clientAddress = await taskManager.getClientAddress()
            let _contractorAddress = await taskManager.getContractorAddress()
            let _level = await taskManager.getLevel()
            let _usdc = await taskManager.getUsdcToken()
            let _collateralDeposited = await taskManager.getCollateralDeposited()
            let _builderBuddy = await taskManager.getBuilderBuddyAddr()
            let _isContractActive = !(await taskManager.isWorkFinished())
            let _arbiterContract = await taskManager.getArbiterContractAddr()
            
            assert.equal(_clientId, clientId, "Client Id is not correct")
            assert.equal(_contractorId, contractorId, "Contractor Id is not correct")
            assert.equal(_orderId, orderId, "Order Id is not correct")
            assert.equal(_clientAddress, client.address, "Client Address is not correct")
            assert.equal(_contractorAddress, contractor.address, "Contractor Address is not correct")
            assert.equal(_level, level, "Level is not correct")
            assert.equal(_usdc, usdcToken.address, "USDC address is not correct")
            assert.equal(_collateralDeposited.toString(), collaterals[level - 1], "Collateral deposited is not correct")
            assert.equal(_builderBuddy, builderBuddy.address, "BuilderBuddy address is not correct")
            assert.equal(_isContractActive, true, "Contract is not active")
            assert.equal(_arbiterContract, await builderBuddy.getArbiterContract(), "Arbiter contract address is not correct")
        });
    });

    describe("add Task Tests", function () {
        it("Should add task correctly", async function () {
            let taskCounter = 1;
            await expect(contractorTM.addTask("Title", "Description", 1000000)).to.emit(taskManager, "TaskAdded").withArgs(taskCounter, "Title", "Initiated");
            
            const taskData = await clientTM.getTask(taskCounter)

            assert.equal(taskData[0], "Title", "Title is not correct")
            assert.equal(taskData[1], "Description", "Description is not correct")
            assert.equal(taskData[2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[3], 3, "Status is not correct")
        });
    });
    
    describe("approve Task Tests", function () {
        beforeEach(async () => {
            await contractorTM.addTask("Title", "Description", 1000000);
        });
        it("Should approve task correctly and store in data structure", async function () {
            let taskCounter = 1;
            const APPROVED = 1;
            await usdcToken.mint(taskManager.address, 1000000);
            await expect(clientTM.approveTask()).to.emit(taskManager, "TaskApproved").withArgs(taskCounter, "Title", "Approved");
            
            const taskData = await clientTM.getTask(taskCounter)

            assert.equal(taskData[0], "Title", "Title is not correct")
            assert.equal(taskData[1], "Description", "Description is not correct")
            assert.equal(taskData[2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[3], APPROVED, "Status is not correct")
        });
    });

    describe("Avail Cost Tests", function () {
        beforeEach(async () => {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();
        });
        it("Should avail cost correctly", async function () {
            let taskCounter = 1;
            await expect(contractorTM.availCost()).to.emit(taskManager, "AmountTransferred").withArgs(taskCounter, 1000000, "Pending");
            
            const taskData = await clientTM.getTask(taskCounter)

            assert.equal(taskData[0], "Title", "Title is not correct")
            assert.equal(taskData[1], "Description", "Description is not correct")
            assert.equal(taskData[2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[3], 0, "Status is not correct")
        });
    });

    describe("Finish Task Tests", function () {
        beforeEach(async () => {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();
            await contractorTM.availCost();
        });
        it("Should finish task correctly", async function () {
            let rating = 8;
            let taskCounter = 1;
            let FINISHED = 2;
            await expect(clientTM.finishTask(rating)).to.emit(taskManager, "TaskFinished").withArgs(taskCounter, "Title", "Finished");
            const taskVersionCounter = await clientTM.getTaskVersionCounter()
            const taskData = await clientTM.getTask(taskCounter)
            const taskRating = await clientTM.getTaskRating(taskCounter)
            

            assert.equal(taskData[3], FINISHED, "Status is not Finished")
            assert.equal(taskVersionCounter, 0, "Task version counter is not correct")
            assert.equal(taskRating, rating, "Rating is not correct")
        });
    });

    describe("Finish Work Tests", function () {
        beforeEach(async () => {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();
            await contractorTM.availCost();
            await clientTM.finishTask(8);
        });
        it("Should finish work correctly", async function () {
            await expect(clientTM.finishWork()).to.emit(taskManager, "WorkFinished");

            let _isContractActive = !(await taskManager.isWorkFinished());
            let taskCounter = await clientTM.getTaskCounter();
            let overallRating = 0;
            let FINISHED = 3;
            for (let i=1; i < taskCounter + 1; i++){
                overallRating += await clientTM.getTaskRating(i)
            }
            overallRating = (overallRating * 100) / taskCounter;
            let orderId = await taskManager.getOrderId()
            const orderData = await clientBB.getOrder(orderId)
            assert.equal(_isContractActive, false,"Contract is not active")
            assert.equal(overallRating / 1e9, 800,"Overall rating is not correct")
            assert.equal(orderData.status, FINISHED, "Order status is not correct")
        });
    });

    describe("reject Task Tests", function () {
        beforeEach(async () => {
            await contractorTM.addTask("Title", "Description", 1000000);
        });
        it("Should reject task correctly", async function () {
            let rejectCounter = 1;
            let taskCounter = 1;
            let REJECTED = 4;
            await expect(clientTM.rejectTask()).to.emit(taskManager, "TaskRejected").withArgs(taskCounter, "Title", "Rejected");
            
            const taskData = await clientTM.getTask(taskCounter)
            let rejectedTaskCounter = await clientTM.getRejectedTaskCounter()
            const newtaskCounter = await clientTM.getTaskCounter()
            
            assert.equal(taskData[3], REJECTED, "Status is not REJECTED")
            assert.equal(rejectedTaskCounter, rejectCounter, "Rejected task counter is not correct")
            assert.equal(newtaskCounter, taskCounter - 1, "Task counter is not correct")
        });
    });
  });