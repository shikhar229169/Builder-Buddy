## Sample Contracts Deployed on Polygon Mumbai
- UserRegistration - 0x7706dB18C4d446e3F11B0A64371C30511b055427
- BuilderBuddy - 0xA2810D43556A8cB6692DE836627e7F78BF498Ebe
- ArbiterContract - 0xcF7aD392148C93Ee79E435FEc919532BE1C88d4b


## Builder Buddy Project
Our project aims to link workers and users. As it is very difficult nowadays to find the best worker, with our protocol it will be hassle-free for a user to find the best worker for their work request and also for contractor to find work. It allows users to find the best worker that best fit for their work they want to achieve, and allows workers to get orders from users and they can select the work that they are willing to do.
We have 3 roles on our protocol: Customer, Contractor/Worker and Arbiter.
1. Customer/Client -> Those who want to get their work done (construction, renovation, maintenance, plumbing, carpentry, electricity, etc.) they can place an order with their work request info and will be communicated by contractor/worker.
2. Contractor/Worker -> Those who are willing to provide services to customer and will contact them.
3. Arbiter -> Those who will resolve the conflicts between customer and contractor and can take necessary actions defined in smart contract.

Workflow
First customer places an order on our protocol with brief description of the work they want to get done, then contractors belonging to that category will see the orders and can communicate with the customer. Customer will have the ability to assign the required contractor to their work and after that contractor has to confirm it, and then they can go on with their order.

<br>
The main problem was to verify the identity of the user. So, in order for a user to register in our protocol, they have to authenticate various accounts on gitcoin and collect score, once they score is above a minimum, they will be eligible to register. So, in order for this to work on-chain, we are using Chainlink Functions to send api request to gitcoin in order to get details about their authentication and if it satisfies, they are registered.
So, while they Register they will also select a role- customer, worker/contractor.
For the role of arbiter, they can't actually register directly, our protocol admins will choose them and registers them. Arbiters are handled on a separate contract (ArbiterContract)
Some data will be stored on-chain but their private information like address will be off-chain.
Once after successful registration they can use the services, where user will request for services and worker will provide users with the required service.

Users can place their request for services (like construction, maintenance, renovation, electricity, plumbing etc) and it will be sent to all workers belonging to those categories.  Also, every worker will have a level ranging from 1 to 5, which will correspond to the level of work a user requested. So, a worker of level X can select work less than or equal to their level X.
Before confirming a worker will be able to communicate with the user off-chain via call or chat and after confirming they can approve with each other to move on with the process.
On the basis of the level the contractor is on they will have to stake some funds in the Builder Buddy contract which will be used to compensate the user in case the worker leaves without any work done. Also, if a worker didn't stake, they can't accept orders. (if the order is of level x, then the worker's level should be >= x, and in order to have a level x or above they need to deposit some fixed collateral).

Once user assigns a worker/contractor to their order and that same assigned worker/contractor confirms a user's work order request, this will lead to the deployment of a dedicated Task Manager contract. This contract will be used to track all the tasks that are being done related to the work. The whole work will be divided into tasks and contractor will be adding those tasks containing title, description and cost of task. . And user will then approves and funds for those tasks. User will be required to fund USDC token in the Task Manager Contract and then call the approve task function and then contractor can claim those funds and start working towards the task. After the task is completed off-chain by the contractor, user will then confirm it and mark the task as completed along with a rating on a scale of 1-10 which will be used to calculate a score for the contractor. Adding the task process will go on until all work is done. When the whole work is finished, user will then mark the whole work as finished from the task manager contract which will update the contractor's score.

Now, contractor can level up on the basis of their score, and if the upgrade their level they have to stake the corresponding USDC amount on builder buddy.

Now, if the work doesn't go on smoothly, we have the role of arbiters, which can be assigned by user to their corresponding order and arbiter can take various actions. For ex., if the worker leaves after claiming the funds, the arbiter can call the function which will take the contractor/worker's collateral to compensate the user.



# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Nodejs](https://nodejs.org/en/)
- [Yarn](https://yarnpkg.com/getting-started/install)

## Quickstart

```
git clone https://github.com/workers-contractors-users-link/SmartContracts.git
cd SmartContracts
yarn install
```

# Usage

Deploy on hardhat:

```
yarn hardhat deploy
```

Deploy on mumbai:
```
yarn hardhat deploy --network mumbai
```

## Testing

```
yarn hardhat test
```

# Deployment to a testnet or mainnet

1. Setup environment variabltes

You will need to add the following environment variables:
- GC_API_KEY - Go to [gitcoin scorer website](https://scorer.gitcoin.co/) to get the API Key
- GC_SCORER_ID - Go to [gitcoin scorer website](https://scorer.gitcoin.co/) to get the scorer id from scorer section
- PRIVATE_KEY - The private key of your account
- SECOND_PRIVATE_KEY - The second private key (required to test for another entity on testnet)
- MUMBAI_RPC_URL - This is url of the polygon mumbai testnet node. You can get it from [Alchemy](https://www.alchemy.com/)
- GITHUB_API_TOKEN - The github api token to create/delete gists
- MUMBAI_API_KEY - The polygonscan mumbai api key to verify smart contracts on explorer

2. Get testnet ETH

Go to [Mumbai Faucet](https://mumbaifaucet.com/) to get test matic on polygon mumbai

3. Setup a Chainlink Functions Sub Id

Go to [Chainlink Functions](https://functions.chain.link/mumbai) and create a sub id and replace the subId in helper-hardhat-config file for chainId 80001 (Mumbai Network) to your own sub id
Fund your subscription with test link from [Chainlink Faucets](https://faucets.chain.link/mumbai)

3. Deploy

To deploy the contracts on polygon mumbai network, run:
```
yarn hardhat deploy --network mumbai
```


## User Registration
This contract is the first place where user will have to register. User selects a role either as a contractor or customer.
But before that user have to go to [Gitcoin Passport](https://passport.gitcoin.co/) and add stamps there by authenticating with various accounts. Then they can call the register function to get themselves registerd in the selected role

## Methods
### 1. Register
User can call this funtion to get registered in the protocol. It places a request on the chainlink functions to query the details of user on gitcoin and if it is satisfied then user is registered. The response from chainlink functions router is sent in a second txn in which the user is registered.
```solidity
function register(bytes12 userId, uint8 role, string memory name) external;
```
- userId -> A unique userId
- role -> Role of user (0 for customer and 1 for contractor/worker)

### 2. Contractor Info
Returns the contractor info registered corresponding to userId
```solidity
function getContractorInfo(bytes12 userId) external view returns (Contractor memory);
```

### 3. Customer Info
Returns the customer info registered corresponding to userId
```solidity
function getCustomerInfo(bytes12 userId) external view returns (Customer memory);
```

## Builder Buddy
This is the main contract which allows customers to place their work order request and find contractors to get their work done. Customer places an order, then contractor communicates with them and customer will assign desired contractor to their work order. Then contractor confirms the customer's order which lead to deployment of Task Manager contract that will handle all the payments and tasks.
Also, contractor will be staking on the Builder Buddy contract then only they can be assigned to customer's work order requests.
Note: Customer can place an order if they are registered on the UserRegistration Contract.

### 1. Create Order
This allows customer to place a work order request on BuilderBuddy contract.
```solidity
function createOrder(
    bytes12 userId,
    string memory title,
    string memory desc,
    uint8 category,
    string memory locality,
    uint8 _level,
    uint256 budget,
    uint256 expectedStartDate
) external;
```
- userId - The user id of customer (Note: They are required to call the create order function with the same account they used to register with the userId)
- title - Title of order
- desc - Description of order
- category - Category of order (0 for construction, 1 for maintenance, 2 for renovation, 3 for electricity, 4 for plumbing, 5 for carpentry)
- locality - Locality of order
- _level - Level of order (1 to 5)
- budget - Budget of order
- expectedStartDate - Expected start date of order in unix timestamp in seconds (should be greater than current time) 


### 2. Assign Contractor To Order
This allows customer to assign a contractor to their order. The contractor should be registerd and should have staked. Also the level of contractor should be >= level of order.
```solidity
function assignContractorToOrder(bytes12 userId, uint256 orderId, bytes12 contractorId) external;
```
- userId - The user id of customer (Note: They are required to call the create order function with the same account they used to register with the userId)
- orderId - The order id of the order to which they want to assign the contractor
- contractorId - The user id of the contractor they want to assign to their order

### 3. Confirm User Order
This allows contractor to confirm the user's order. This will lead to deployment of Task Manager contract.
```solidity
function confirmUserOrder(bytes12 contractorUserId, uint256 orderId) external;
```
- contractorUserId - The user id of contractor (Note: They are required to call the create order function with the same account they used to register with the userId)
- orderId - The order id of the order to which they want to confirm

### 4. Cancel Order
This allows customer to cancel their order. Cancellation is only allowed if the order is not confirmed by the contractor.
```solidity
function cancelOrder(bytes12 userId, uint256 orderId) external;
```
- userId - The user id of customer
- orderId - The order id of the order to which they want to cancel

### 5. Increment Level and Stak USDC
This allows contractor to increment their level and stake USDC on Builder Buddy contract. The contractor should first approve the Builder Buddy contract to spend their USDC tokens by interacting with USDC contract.
They should be registered. Also if they want to go to level x, then they must have a score specified in the level requirements.
```solidity
function incrementLevelAndStakeUSDC(bytes12 contractorUserId, uint8 _level) external;
```
- contractorUserId - The user id of contractor
- _level - The level to which they want to increment

### 6. Withdraw Stake USDC
This allows contractor to withdraw their staked USDC tokens from Builder Buddy contract. The contractor should not be assigned to any order otherwise they can't withdraw.
```solidity
function withdrawStakedUSDC(bytes12 contractorUserId, uint8 _level) external;
```
- contractorUserId - The user id of contractor
- _level - The level to which they want to decrease to

### Getter Functions
```solidity
function getAllCustomerOrders(bytes12 customerUserId) external view returns (CustomerOrder[] memory);
function getAllOrders() external view returns (CustomerOrder[] memory);
function getArbiterContract() external view returns (address);
function getMaxEligibleLevelByScore(uint256 score) external view returns (uint256);
function getOrder(uint256 orderId) external view returns (CustomerOrder memory);
function getOrderCounter() external view returns (uint256);
function getRequiredCollateral(uint8 level) external view returns (uint256);
function getScore(uint8 level) external view returns (uint256);
function getTaskContract(uint256 orderId) external view returns (address);
function getUsdcAddress() external view returns (address);
function getUserRegistrationContract() external view returns (address);
```


## Task Manager Contract
This contract is deployed when a contract confirms an order. This is used to handle all the tasks and payments.
A work is divided into chunks of tasks and contractor will be adding those tasks and their cost. Then customer will approve those tasks and funds will be transferred to the Task Manager contract. Then contractor can claim those funds and start working on the task. After the task is completed off-chain by the contractor, customer will then confirm it and mark the task as completed along with a rating on a scale of 1-10 which will be used to calculate a score for the contractor. Adding the task process will go on until all work is done. When the whole work is finished, customer will then mark the whole work as finished from the task manager contract which will update the contractor's score. 
Contractor can't add new task if the previous task is not completed.
Also, if there is a dispute then arbiter can be assigned and can take necessary actions.

### 1. Add Task
This allows contractor to add a task to the task manager contract. The contractor should be assigned to the order corresponding to the task manager contract.
```solidity
function addTask(string memory title, string memory desc, uint256 cost) external;
```
- title - Title of task
- desc - Description of task
- cost - Cost of task

### 2. Approve Task
This allows customer to approve a task. The customer first need to transfer USDC tokens equivalent to the cost of the task to the task manager contract and then call this function to approve the task.
```solidity
function approveTask() external;
```

### 3. Avail Cost
This allows contractor to claim the cost of the task. The contractor will claim funds in advanced and then start working on the task off-chain.
```solidity
function availCost() external;
```

### 4. Finish Task
This allows customer to mark the task as finished. The customer will mark the task as finished after the contractor has completed the task off-chain.
```solidity
function finishTask(uint256 rating) external;
```
- rating - The rating of task on a scale of 1-10. This will be used to calculate score of contractor.

### 5. Finish Work
This allows customer to mark the work as finished. The customer will mark the work as finished after all the tasks are completed.
```solidity
function finishWork() external;
```

### 6. Reject Task
This allows customer to reject the task, if it is not according to their needs.
```solidity
function rejectTask() external;
```

### 7. Involve Arbiter
This allows customer to involve arbiter in case of dispute. The customer will involve arbiter if the contractor leaves without completing the work.
```solidity
function involveArbiter(address arbiter) external;
```
- arbiter - The address of arbiter

### 8. Resolve Dispute
This allows arbiter to resolve the dispute. The arbiter will resolve the dispute by taking necessary actions.
```solidity
function resolveDispute(string memory remarks, uint256 amtToRefund) external
```
- remarks - The remarks of arbiter
- amtToRefund - The amount to refund to customer

### Getter Functions
```solidity
function getAllRejectedTasks() external view returns (Task[] memory);
function getAllTasks() external view returns (Task[] memory);
function getArbiterContractAddr() external view returns (address);
function getBuilderBuddyAddr() external view returns (address);
function getClientAddress() external view returns (address);
function getClientId() external view returns (bytes12);
function getCollateralDeposited() external view returns (uint256);
function getContractorAddress() external view returns (address);
function getContractorId() external view returns (bytes12);
function getLevel() external view returns (uint8);
function getOrderId() external view returns (uint256);
function getRejectedTaskCounter() external view returns (uint256);
function getTask(uint256 taskId) external view returns (string memory, string memory, uint256, uint8);
function getTaskCounter() external view returns (uint256);
function getTaskRating(uint256 taskId) external view returns (uint256);
function getTaskVersionCounter() external view returns (uint256);
function getUsdcToken() external view returns (address);
```

## Arbiter Contract
This contract contains info of all the arbiters and the conflicts they deal with. Only the owner is allowed to resiter arbiters.

### 1. Add Arbiter
This allows owner to add an arbiter to the contract.
```solidity
function addArbiter(bytes12 userId, address arbiter) external;
```
- userId - The user id of arbiter
- arbiter - The address of arbiter

### 2. Assign Arbiter To Resolve Confict
This function is called by Task Manager contract when customer calls involveArbiter function on TaskManager Contract and it assigns arbiter to a order which involves conflicts.
```solidity
function assignArbiterToResolveConflict(address arbiter, uint256 orderId) external returns (uint256)
```
- arbiter - The address of arbiter
- orderId - The order id of the order which involves conflict

### 3. Mark Conflict As Resolved
When the arbiter finds a way to resolve the confict, they call the resolveDispute function on Task Manager contract and TaskManager contract call this function on ArbiterContract which marks the conflict as resolved.
```solidity
function markConflictAsResolved(address arbiter, string memory remarks, uint256 conflictIdx) external;
```
- arbiter - The address of arbiter
- remarks - The remarks of arbiter
- conflictIdx - The index of conflict

### Getter Functions
```solidity
function getAllArbiterConflicts(bytes12 arbiterId) external view returns (ConflictDetails[] memory);
function getArbiterAddress(bytes12 userId) external view returns (address);
function getArbiterUserId(address arbiter) external view returns (bytes12);
function getBuilderBuddy() external view returns (address);
function getConflictDetails(bytes12 arbiterId, uint256 conflictIdx)
    external
    view
    returns (ConflictDetails memory);
function getOwner() external view returns (address);
```
