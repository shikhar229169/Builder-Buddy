const { ethers, network, deployments } = require("hardhat")
const { networkConfig, localNetworks } = require("../../helper-hardhat-config")
const { assert, expect } = require("chai")

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

localNetworks.includes(network.name)
    ? describe.skip
    : describe("BuilderBuddy Staging Tests", () => {
        const chainId = network.config.chainId
        let customer
        let contractor
        let builderBuddy
        let userRegistration

        let builderBuddyCustomer
        let builderBuddyContractor

        let userRegistrationCustomer
        let userRegistrationContractor

        let customerId = getRandomId()
        let contractorId = getRandomId()

        const CUSTOMER = 0
        const CONTRACTOR = 1

        const routerAddr = networkConfig[chainId].router
        const subId = networkConfig[chainId].subId
        let usdc

        let taskManagerAddr

        beforeEach(async() => {
            const contracts = await deployments.fixture(["main"])
            
            const accounts = await ethers.getSigners()
            
            customer = accounts[0]
            contractor = accounts[1]
            
            builderBuddy = await ethers.getContractAt("BuilderBuddy", contracts["BuilderBuddy"].address)
            userRegistration = await ethers.getContractAt("UserRegistration", contracts["UserRegistration"].address)
            usdc = await ethers.getContractAt("IERC20", networkConfig[chainId].usdcToken)
            
            builderBuddyCustomer = builderBuddy.connect(customer)
            builderBuddyContractor = builderBuddy.connect(contractor)
            
            userRegistrationCustomer = userRegistration.connect(customer)
            userRegistrationContractor = userRegistration.connect(contractor)
            
            console.log("Adding consumer to router")
            const router = await ethers.getContractAt("IIFunctionsRouter", routerAddr)
            const response = await router.addConsumer(subId, userRegistration.address)
            await response.wait(1)

            console.log("Added contractor to router")
        })

        describe("BuilderBuddy Staging Tests", () => {
            it("User, contractor registers. User places order, assigns to contractor, gets confirmed and task manager deployed for the order.", async() => {
                // Customer Registers
                await new Promise(async(resolve, reject) => {
                    userRegistrationCustomer.on("Registered", async() => {
                        const customerInfo = await userRegistration.customers(customerId)
                        assert.equal(customerInfo.ethAddress, customer.address)
                        assert.equal(customerInfo.name, "Customer1")
                        resolve()
                    })

                    const reg1 = await userRegistrationCustomer.register(customerId, CUSTOMER, "Customer1")
                    await reg1.wait(1)
                })
                
                // Contractor Registers
                await new Promise(async(resolve, reject) => {
                    userRegistrationCustomer.on("Registered", async() => {
                        const contractorInfo = await userRegistration.contractors(contractorId)
                        assert.equal(contractorInfo.ethAddress, contractor.address)
                        assert.equal(contractorInfo.name, "Contractor1")
                        resolve()
                    })

                    const reg2 = await userRegistrationContractor.register(contractorId, CONTRACTOR, "Contractor1")
                    await reg2.wait(1)
                })

                // Contractor stakes on BuilderBuddy
                // Approves builder buddy to spend the fund
                const level = 1
                const stakeAmount = await builderBuddy.getRequiredCollateral(level)
                const approveResponse = await usdc.connect(contractor).approve(builderBuddy.address, stakeAmount)
                await approveResponse.wait(1)

                // Stakes on builder buddy
                const stakeResponse = await builderBuddyContractor.incrementLevelAndStakeUSDC(contractorId, level)
                await stakeResponse.wait(1)


                // Customer places order
                const title = "Test Order"
                const desc = "This is a test order. We want to construct a house."
                const category = 0               // Construction
                const locality = "Agra"
                const orderLevel = 1
                const budget = 50000000          // 50 USDC
                const expectedStartDate = Date.now() + 1000000
                const orderId = await builderBuddyCustomer.getOrderCounter()
                const orderResponse = await builderBuddyCustomer.createOrder(customerId, title, desc, category, locality, orderLevel, budget, expectedStartDate)
                await orderResponse.wait(1)

                
                // Contractor communicates with customer and customer assign contractor to order
                const assignResponse = await builderBuddyCustomer.assignContractorToOrder(customerId, 0, contractorId)
                await assignResponse.wait(1)

                const orderCounter = await builderBuddyCustomer.getOrderCounter()

                // Contractor confirms it
                const confirmAssignResponse = await builderBuddyContractor.confirmUserOrder(contractorId, 0)
                await confirmAssignResponse.wait(1)

                // Asserts Checks
                const order = await builderBuddy.getOrder(0)
                console.log(order)

                const taskManager = order.taskContract
                taskManagerAddr = taskManager
                assert.notEqual(taskManager, 0)
                assert.equal(orderCounter.toString(), orderId.add(1).toString())
            })

            it("Consructor creates task, customer funds and approves it and marks it completed, finishes work and data structures updated in builder buddy.", async() => {
                const tmCustomer = await ethers.getContractAt("TaskManager", taskManagerAddr, customer)
                const tmContractor = await ethers.getContractAt("TaskManager", taskManagerAddr, contractor)

                // Contractor Adds Task
                const title = "Raw Materials"
                const desc = "Funds required to get raw materials. Please pay for the same."
                const cost = 1000000              // 1 USDC
                const addTaskResponse = await tmContractor.addTask(title, desc, cost)
                await addTaskResponse.wait(1)

                
                // Transfer USDC to Task Manager Contract
                const addUsdcResponse = await usdc.connect(customer).transfer(taskManagerAddr, cost)
                await addUsdcResponse.wait(1)

                // Customer Approves the task
                const approveTaskResponse = await tmCustomer.approveTask()
                await approveTaskResponse.wait(1)

                // Contractor claim the funds
                const claimFundsResponse = await tmContractor.availCost()
                await claimFundsResponse.wait(1)


                // Then contractor performs the task off-chain
                // After task is finished, customer marks it as finished with some rating
                const rating = 10           // range from 1 to 10
                const finishTaskResponse = await tmCustomer.finishTask(rating)
                await finishTaskResponse.wait(1)

                // Once all the tasks are done
                // Customer marks whole work finished and TaskManager contract can't be further modified
                const finishWorkResponse = await tmCustomer.finishWork()
                await finishWorkResponse.wait(1)

                const taskManagerStatus = await tmCustomer.isWorkFinished()
                const contractorInfo = await userRegistration.contractors(contractorId)
                const orderId = 0
                const orderInfo = await builderBuddy.getOrder(orderId)


                assert.equal(taskManagerStatus, true)
                assert.equal(contractorInfo.score, rating * 100)
                assert.equal(contractorInfo.isAssigned, false)
                const FINISHED = 3
                assert.equal(orderInfo.status, FINISHED)
            })
        })
    })