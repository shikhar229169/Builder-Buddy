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

        it("reverts if not called by contractor", async function () {
            await expect(clientTM.addTask("Title", "Description", 1000000)).to.be.revertedWithCustomError(taskManager, "TaskManager__NotContractor")
        });

        it("reverts if previous task is not finished", async function () {
            await contractorTM.addTask("Title", "Description", 1000000)
            await expect(contractorTM.addTask("Title", "Description", 1000000)).to.be.revertedWithCustomError(taskManager, "TaskManager__PreviousTaskNotFinished")
        });

        it("reverts if budget is greater than 80 % collateral deposited", async function () {
            await expect(contractorTM.addTask("Title", "Description", 1700000)).to.be.revertedWithCustomError(taskManager, "TaskManager__CostGreaterThanCollateral")
        });
    });
    
    describe("approve Task Tests", function () {
        it("Should approve task correctly and store in data structure", async function () {
            let taskCounter = 1;
            const APPROVED = 1;
            await contractorTM.addTask("Title", "Description", 1000000);

            await usdcToken.mint(taskManager.address, 1000000);
            await expect(clientTM.approveTask()).to.emit(taskManager, "TaskApproved").withArgs(taskCounter, "Title", "Approved");
            
            const taskData = await clientTM.getTask(taskCounter)

            assert.equal(taskData[0], "Title", "Title is not correct")
            assert.equal(taskData[1], "Description", "Description is not correct")
            assert.equal(taskData[2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[3], APPROVED, "Status is not correct")
        });

        it("reverts if not called by client", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);

            await expect(contractorTM.approveTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotClient")
        });

        it("reverts if task is not added", async function () {
            await usdcToken.mint(taskManager.address, 1000000);
            await expect(clientTM.approveTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__NoTasksYet")
        });

        it("reverts if budget is not transferred", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await expect(clientTM.approveTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__InsufficientFundsForTask")
        });

        it("reverts if task status is not Initiated", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();

            await expect(clientTM.approveTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotInitiated")
        });
    });

    describe("Avail Cost Tests", function () {
        it("Should avail cost correctly", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();

            let taskCounter = 1;
            await expect(contractorTM.availCost()).to.emit(taskManager, "AmountTransferred").withArgs(taskCounter, 1000000, "Pending");
            
            const taskData = await clientTM.getTask(taskCounter)

            assert.equal(taskData[0], "Title", "Title is not correct")
            assert.equal(taskData[1], "Description", "Description is not correct")
            assert.equal(taskData[2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[3], 0, "Status is not correct")
        });

        it("reverts if not called by contractor", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();
            
            await expect(clientTM.availCost()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotContractor")
        });

        it("reverts if task is not added", async function () {
            await expect(contractorTM.availCost()).to.be.revertedWithCustomError(taskManager, "TaskManager__NoTasksYet")
        });

        it("reverts if task status is not Approved", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);

            await expect(contractorTM.availCost()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotApproved")
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

        it("reverts if not called by client", async function () {
            await expect(contractorTM.finishTask(8)).to.be.revertedWithCustomError(taskManager, "TaskManager__NotClient")
        });

        it("revets if task is not Pending", async function () {
            let rating = 8;
            await clientTM.finishTask(rating)

            await expect(clientTM.finishTask(rating)).to.be.revertedWithCustomError(taskManager, "TaskManager__NotPending")
        });

        it("reverts if rating is not between 0 and 10", async function () {
            let rating = 11;
            await expect(clientTM.finishTask(rating)).to.be.revertedWithCustomError(taskManager, "TaskManager__RatingNotInRange")
        });
    });

    describe("revert if task is not add and try to finish Tests", function () {
        it("Should revert if task is not add and try to finish", async function () {
            await expect(clientTM.finishTask(8)).to.be.revertedWithCustomError(taskManager, "TaskManager__NoTasksYet")
        });
    });

    describe("Finish Work Tests", function () {
        beforeEach(async () => {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();
            await contractorTM.availCost();
        });
        it("Should finish work correctly", async function () {
            await clientTM.finishTask(8);

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

        it("reverts if not called by client", async function () {
            await clientTM.finishTask(8);

            await expect(contractorTM.finishWork()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotClient")
        });

        it("reverts if task is not Finished", async function () {
            await expect(clientTM.finishWork()).to.be.revertedWithCustomError(taskManager, "TaskManager__PreviousTaskNotFinished")
        });

        it("reverts if task is not active", async function () {
            await clientTM.finishTask(8);
            await clientTM.finishWork();

            await expect(clientTM.finishWork()).to.be.revertedWithCustomError(taskManager, "TaskManager__ContractNotActive")
        });
    });

    describe("reject Task Tests", function () {
        it("Should reject task correctly", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);

            let rejectCounter = 1;
            let taskCounter = 1;
            let REJECTED = 4;
            await expect(clientTM.rejectTask()).to.emit(taskManager, "TaskRejected").withArgs(taskCounter, "Title", "Rejected");
            
            const taskData = await clientTM.getTask(taskCounter)
            let rejectedTaskCounter = await clientTM.getRejectedTaskCounter()
            const newtaskCounter = await clientTM.getTaskCounter()
            const allRejectedTasks = await clientTM.getAllRejectedTasks()
            
            assert.equal(allRejectedTasks[0][0], taskData[0], "Title is not correct")
            assert.equal(allRejectedTasks[0][1], taskData[1], "Description is not correct")
            assert.equal(allRejectedTasks[0][2].toString(), taskData[2].toString(), "Budget is not correct")
            assert.equal(allRejectedTasks[0][3], taskData[3], "Status is not correct")
            assert.equal(taskData[3], REJECTED, "Status is not REJECTED")
            assert.equal(rejectedTaskCounter, rejectCounter, "Rejected task counter is not correct")
            assert.equal(newtaskCounter, taskCounter - 1, "Task counter is not correct")
        });

        it("reverts if not called by client", async function () {
            await expect(contractorTM.rejectTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotClient")
        });

        it("reverts if task is not added", async function () {
            await expect(clientTM.rejectTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__NoTasksYet")
        });

        it("reverts if task status is not Initiated", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();

            await expect(clientTM.rejectTask()).to.be.revertedWithCustomError(taskManager, "TaskManager__NotInitiated")
        });
    });

    describe("get Order Id Tests", function () {
        it("Should return correct order id", async function () {
            let _orderId = await taskManager.getOrderId()

            assert.equal(_orderId.toString(),orderId, "Order Id is not correct")
        });
    });

    describe("get Level Tests", function () {
        it("Should return correct level of contractor", async function () {
            let contractorLevel = await taskManager.getLevel()

            assert.equal(contractorLevel, level, "contractor level is not correct")
        });
    });

    describe("get Client Id Tests", function () {
        it("Should return correct client id", async function () {
            let _clientId = await taskManager.getClientId()

            assert.equal(_clientId, clientId, "Client Id is not correct")
        });
    });

    describe("get Contractor Id Tests", function () {
        it("Should return correct contractor id", async function () {
            let _contractorId = await taskManager.getContractorId()

            assert.equal(_contractorId, contractorId, "Contractor Id is not correct")
        });
    });

    describe("get Client Address Tests", function () {
        it("Should return correct client address", async function () {
            let _clientAddress = await taskManager.getClientAddress()

            assert.equal(_clientAddress, client.address, "Client Address is not correct")
        });
    });

    describe("get Contractor Address Tests", function () {
        it("Should return correct contractor address", async function () {
            let _contractorAddress = await taskManager.getContractorAddress()

            assert.equal(_contractorAddress, contractor.address, "Contractor Address is not correct")
        });
    });

    describe("get Collateral Deposited Tests", function () {
        it("Should return correct collateral deposited", async function () {
            let _collateralDeposited = await taskManager.getCollateralDeposited()

            assert.equal(_collateralDeposited.toString(), collaterals[level - 1], "Collateral deposited is not correct")
        });
    });

    describe("get USDC Token Tests", function () {
        it("Should return correct USDC token address", async function () {
            let _usdc = await taskManager.getUsdcToken()

            assert.equal(_usdc, usdcToken.address, "USDC address is not correct")
        });
    });

    describe("get Task Counter Tests", function () {
        it("Should return correct task counter", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            let _taskCounter = await taskManager.getTaskCounter()

            assert.equal(_taskCounter, 1, "Task counter is not correct")
        });
    });

    describe("get Rejected Task Counter Tests", function () {
        it("Should return correct rejected task counter", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await clientTM.rejectTask()
            let _rejectedTaskCounter = await taskManager.getRejectedTaskCounter()

            assert.equal(_rejectedTaskCounter, 1, "Rejected task counter is not correct")
        });
    });

    describe("get Task Version Counter Tests", function () {
        it("Should return correct task version counter", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            let _taskVersionCounter = await taskManager.getTaskVersionCounter()

            assert.equal(_taskVersionCounter, 1, "Task version counter is not correct")
        });
    });

    describe("get Task Tests", function () {
        it("Should return correct task data", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            let taskCounter = 1;
            let taskData = await clientTM.getTask(taskCounter)

            assert.equal(taskData[0], "Title", "Title is not correct")
            assert.equal(taskData[1], "Description", "Description is not correct")
            assert.equal(taskData[2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[3], 3, "Status is not correct")
        });
    });

    describe("get All Tasks Tests", function () {
        it("Should return correct task data", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            let taskData = await clientTM.getAllTasks()
            let INITIATED = 3;

            assert.equal(taskData[0][0], "Title", "Title is not correct")
            assert.equal(taskData[0][1], "Description", "Description is not correct")
            assert.equal(taskData[0][2].toString(), 1000000, "Budget is not correct")
            assert.equal(taskData[0][3], INITIATED, "Status is not correct")
        });
    });

    describe("get All Rejected Tasks Tests", function () {
        it("Should return correct task data", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await clientTM.rejectTask()

            let REJECTED = 4;
            let rejectedTaskData = await clientTM.getAllRejectedTasks()

            assert.equal(rejectedTaskData[0][0], "Title", "Title is not correct")
            assert.equal(rejectedTaskData[0][1], "Description", "Description is not correct")
            assert.equal(rejectedTaskData[0][2].toString(), 1000000, "Budget is not correct")
            assert.equal(rejectedTaskData[0][3], REJECTED, "Status is not correct")
        });
    });

    describe("isWorkFinished Tests", function () {
        it("Should return correct work status", async function () {
            let _isWorkFinished = await taskManager.isWorkFinished()
            assert.equal(_isWorkFinished, false, "Work status is not correct")
        });
    });

    describe("get Builder Buddy Address Tests", function () {
        it("Should return correct Builder Buddy address", async function () {
            let _builderBuddy = await taskManager.getBuilderBuddyAddr()

            assert.equal(_builderBuddy, builderBuddy.address, "BuilderBuddy address is not correct")
        });
    });

    describe("get Arbiter Contract Address Tests", function () {
        it("Should return correct Arbiter Contract address", async function () {
            const arbiterContract = await builderBuddy.getArbiterContract()
            let _arbiterContract = await taskManager.getArbiterContractAddr()

            assert.equal(_arbiterContract, arbiterContract, "Arbiter contract address is not correct")
        });
    });

    describe("get Task Rating Tests", function () {
        it("Should return correct task rating", async function () {
            await contractorTM.addTask("Title", "Description", 1000000);
            await usdcToken.mint(taskManager.address, 1000000);
            await clientTM.approveTask();
            await contractorTM.availCost();
            await clientTM.finishTask(8);

            let _taskRating = await clientTM.getTaskRating(1)
            assert.equal(_taskRating, 8, "Task rating is not correct")
        });
    });
  });