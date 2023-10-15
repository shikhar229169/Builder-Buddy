// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { UserRegistration } from "./UserRegistration.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Builder Buddy Smart Contract
/// @notice This contract manages users registration and orders
contract BuilderBuddy is UserRegistration {
    // Enums
    enum Status {
        PENDING,
        ASSIGNED,
        REJECTED,
        FINISHED
    }

    // Structs
    // @audit Add level for that Task (Order)
    struct CustomerOrder {
        address customer;
        string title;
        string description;
        string locality;
        uint256 budget;
        uint256 expectedStartDate;
        Status status;
        uint256 timestamp;
        address contractor;
        bytes12 contractorId;
        address taskContract;
    }

    ///* @dev For a particular level contractor needs to have at least 'score' score
    struct LevelRequirements {
        uint256 collateralRequired;
        uint256 minScore;
    }

    // Errors
    error BuilderBuddy__InvalidCustomer();
    error BuilderBuddy__CallerNotOwnerOfOrder();
    error BuilderBuddy__ContractorNotFound();
    error BuilderBuddy__ContractorAlreadySet();
    error BuilderBuddy__InvalidContractor();
    error BuilderBuddy__InvalidLevelsConfig();
    error BuilderBuddy__AlreadyStaked();
    error BuilderBuddy__StakingFailed();
    error BuilderBuddy__AlreadyMaxedLevel();
    error BuilderBuddy__ContractorHasNotStaked();
    error BuilderBuddy__OnlyTaskContractCanCall();
    error BuilderBuddy__AmountIsZero();
    error BuilderBuddy__AmountExceedsDeposited();
    error BuilderBuddy__WithdrawFailed();
    error BuilderBuddy__YouCantDowngrade();
    error BuilderBuddy__YouCantUpgrade();
    error BuilderBuddy__ScoreIsLess();

    // State Variables
    uint256 private orderCounter;
    uint256 private constant TOTAL_LEVELS = 5;
    mapping (uint256 orderId => CustomerOrder order) private orders;
    mapping (uint8 level => LevelRequirements) private levelRequirements;
    IERC20 private immutable i_usdc;

    // Events
    event OrderCreated(address indexed customer, uint256 indexed orderId, string title);
    event ContractorAssigned(uint256 indexed orderId, address indexed contractor);
    event OrderConfirmed(uint256 indexed orderId, address indexed contractor);
    event ContractorStaked(address indexed contractor);

    // Modifiers
    modifier onlyCustomer(bytes12 userId) {
        if (customers[userId].ethAddress != msg.sender) {
            revert BuilderBuddy__InvalidCustomer();
        }
        _;
    }

    modifier isContractorValid(bytes12 contractorUserId) {
        if (contractors[contractorUserId].isAssigned) {
            revert BuilderBuddy__ContractorAlreadySet();
        }
        if (contractors[contractorUserId].level == 0) {
            revert BuilderBuddy__ContractorHasNotStaked();
        }
        _;
    }

    modifier onlyContractor(bytes12 userId) {
        if (contractors[userId].ethAddress != msg.sender) {
            revert BuilderBuddy__InvalidContractor();
        }
        _;
    }

    // Constructor
    constructor(
        address router,
        uint256 _minimumScore,
        string memory _scorerId,
        string memory _source,
        uint64 _subscriptionId,
        uint32 _gasLimit,
        bytes memory _secrets,
        string memory donName,
        uint256[] memory collateralsForLevel,
        uint256[] memory scoreForLevel,
        address usdcToken
    ) UserRegistration(router, _minimumScore, _scorerId, _source, _subscriptionId, _gasLimit, _secrets, donName) {
        if (collateralsForLevel.length != 5) {
            revert BuilderBuddy__InvalidLevelsConfig();
        }

        if (scoreForLevel[0] != 0) {
            revert BuilderBuddy__InvalidLevelsConfig();
        }

        for (uint8 i = 0; i < TOTAL_LEVELS; i++) {
            if (collateralsForLevel[i] == 0) {
                revert BuilderBuddy__InvalidLevelsConfig();
            }

            if (i != 0 && (collateralsForLevel[i] <= collateralsForLevel[i - 1] || scoreForLevel[i] <= scoreForLevel[i - 1])) {
                revert BuilderBuddy__InvalidLevelsConfig();
            }

            levelRequirements[i + 1].collateralRequired = collateralsForLevel[i];
            levelRequirements[i + 1].minScore = scoreForLevel[i];
        }

        orderCounter = 0;
        i_usdc = IERC20(usdcToken);
    }


    // FUNCTIONS

    /**
     * @dev Allows contractor to stake usdc to increment their level
     * @param contractorUserId The contractor's user id
     * @param _level Level the contractor want to upgrade to
     */
    function incrementLevelAndStakeUSDC(bytes12 contractorUserId, uint8 _level) external onlyContractor(contractorUserId) {
        Contractor memory cont = contractors[contractorUserId];

        if (_level <= cont.level) {
            revert BuilderBuddy__YouCantDowngrade();
        }

        if (_level > TOTAL_LEVELS) {
            revert BuilderBuddy__AlreadyMaxedLevel();
        }

        LevelRequirements memory req = levelRequirements[_level];

        if (cont.score < req.minScore) {
            revert BuilderBuddy__ScoreIsLess();
        }

        emit ContractorStaked(msg.sender);
        bool success = i_usdc.transferFrom(msg.sender, address(this), req.collateralRequired - cont.totalCollateralDeposited);

        if (!success) {
            revert BuilderBuddy__StakingFailed();
        }


        contractors[contractorUserId].totalCollateralDeposited = req.collateralRequired;
        contractors[contractorUserId].level = _level;
    }

    /**
     * @dev Allows contractor to unstake their USDC deposited
     * @notice Assigns the respective level to the contractor based on the remaining amount
     * @param contractorUserId The user id of the contractor
     * @param _level The level to downgrade to
     */
    function withdrawStakedUSDC(bytes12 contractorUserId, uint8 _level) external onlyContractor(contractorUserId) isContractorValid(contractorUserId) {
        Contractor memory cont = contractors[contractorUserId];
        uint8 currLevel = cont.level;

        if (_level >= currLevel) {
            revert BuilderBuddy__YouCantUpgrade();
        }

        uint256 remainingStakedAmount = levelRequirements[_level].collateralRequired;
        uint256 amount = cont.totalCollateralDeposited - remainingStakedAmount;

        bool success = i_usdc.transfer(msg.sender, amount);
        if (!success) {
            revert BuilderBuddy__WithdrawFailed();
        }

        contractors[contractorUserId].level = _level;
        contractors[contractorUserId].totalCollateralDeposited = remainingStakedAmount;
    }

    // should we add category for an order??
    /**
     * @dev Allows customer to create an order
     * @param userId The customer's user id
     * @param title The title of the order
     * @param desc The description of the order
     * @param locality The locality of the order
     * @param budget The budget of the customer for the work
     * @param expectedStartDate The expected start date of the work
     */
    function createOrder(
        bytes12 userId,
        string memory title,
        string memory desc,
        string memory locality,
        uint256 budget,
        uint256 expectedStartDate
    ) external onlyCustomer(userId) {
        uint256 orderId = orderCounter;
        orderCounter++;

        orders[orderId] = CustomerOrder({
            customer: msg.sender,
            title: title,
            description: desc,
            locality: locality,
            budget: budget,
            expectedStartDate: expectedStartDate,
            status: Status.PENDING,
            timestamp: block.timestamp,
            contractor: address(0),
            contractorId: "",
            taskContract: address(0)
        });

        customers[userId].worksRequested.push(orderId);

        emit OrderCreated(msg.sender, orderId, title);
    }

    /**
     * @dev Allows customer to assign a contractor to their order
     * @param userId The customer's user id
     * @param orderId The customer's order id
     * @param contractorId The contractor's user id
     * @notice if contractor is already assigned, then contractor can't be assigned to another order
     */
    // PENDING - ADD A CHECK IF IN CASE ORDER LEVEL IS GREATER THAN CONTRACTOR LVL THEN REVERT
    function assignContractorToOrder(bytes12 userId, uint256 orderId, bytes12 contractorId)
        external
        onlyCustomer(userId)
        isContractorValid(contractorId)
    {
        if (orders[orderId].customer != msg.sender) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        if (orders[orderId].status != Status.PENDING) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        address appointedContractorAddress = contractors[contractorId].ethAddress;

        if (appointedContractorAddress == address(0)) {
            revert BuilderBuddy__ContractorNotFound();
        }

        if (appointedContractorAddress == orders[orderId].contractor) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        orders[orderId].contractor = appointedContractorAddress;
        orders[orderId].contractorId = contractorId;

        emit ContractorAssigned(orderId, appointedContractorAddress);
    }

    /**
     * @dev Allows contractor to confirm the order, when customer assigns them to the order
     * @dev Also deploys a dedicated task manager contract which handles all the payments and work logs
     * @notice 2 way txn process to confirm the order by both customer and contractor0
     * @param contractorUserId The contractor's user id
     * @param orderId The customer's order id
     */
    function confirmUserOrder(bytes12 contractorUserId, uint256 orderId) external onlyContractor(contractorUserId) isContractorValid(contractorUserId) {
        if (orders[orderId].contractor != msg.sender) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        if (orders[orderId].status != Status.PENDING) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        orders[orderId].status = Status.ASSIGNED;

        contractors[contractorUserId].isAssigned = true;
        contractors[contractorUserId].acceptedContracts.push(orderId);

        // deploy the task contract
        // update the task contract address
        
        emit OrderConfirmed(orderId, msg.sender);
    }

    /**
     * @dev Mark the order as confirmed upon confirmation by customer
     * @notice This is called by Task Manager Contract by a function which is called by customer
     * @param orderId The customer's order id
     */
    function markOrderAsCompleted(uint256 orderId) external {
        // only callable by task manager contract
        if (msg.sender != orders[orderId].taskContract) {
            revert BuilderBuddy__OnlyTaskContractCanCall();
        }

        CustomerOrder memory order = orders[orderId];

        orders[orderId].status = Status.FINISHED;
        contractors[order.contractorId].isAssigned = false;
    }

    /**
     * @dev Returns the order details corresponding to order id
     * @param orderId The order id of the customer's order
     */
    function getOrder(uint256 orderId) external view returns (CustomerOrder memory) {
        return orders[orderId];
    }

    /**
     * @dev Returns all the orders placed by a customer
     * @return An array of Order struct, containing details about every order
     * @param customerUserId The user id of customer
     */
    function getAllCustomerOrders(bytes12 customerUserId) external view returns (CustomerOrder[] memory) {
        uint256[] memory customerOrderIds = customers[customerUserId].worksRequested;
        uint256 orderLength = customerOrderIds.length;
        CustomerOrder[] memory customerOrders = new CustomerOrder[](orderLength);

        for (uint256 i = 0; i < orderLength; i++) {
            customerOrders[i] = orders[customerOrderIds[i]];
        }

        return customerOrders;
    }

    /**
     * @notice Returns all the orders placed by customers
     */
    function getAllOrders() external view returns (CustomerOrder[] memory) {
        CustomerOrder[] memory currOrder = new CustomerOrder[](orderCounter);

        for (uint256 i = 0; i < orderCounter; i++) {
            currOrder[i] = orders[i];
        }

        return currOrder;
    }

    /**
     * @dev Returns the total collateral deposited by contractor
     * @param contractorId The user id of contractor
     */
    function getCollateralDeposited(bytes12 contractorId) external view returns (uint256) {
        if (contractors[contractorId].ethAddress == address(0)) {
            revert BuilderBuddy__ContractorNotFound();
        }

        return contractors[contractorId].totalCollateralDeposited;
    }

    /**
     * @dev Returns the usdc address used for staking and payments
     */
    function getUsdcAddress() external view returns (address) {
        return address(i_usdc);
    }

    /**
     * @dev Returns the collateral required to be deposited for a level
     * @notice Level 1 is the lowest level and level 5 is the highest level
     * @param level The level of the contractor
     */
    function getRequiredCollateral(uint8 level) external view returns (uint256) {
        if (level == 0 || level > TOTAL_LEVELS) {
            revert();
        }

        return levelRequirements[level].collateralRequired;
    }

    /**
     * @dev Returns the max eligible level a contractor can have
     * @param score The score of contractor
     */
    function getMaxEligibleLevelByScore(uint256 score) external view returns (uint256) {
        uint8 level = 1;
        
        while (level + 1 < TOTAL_LEVELS && score >= levelRequirements[level + 1].minScore) {
            level++;
        }

        return level;
    }

    /**
     * @dev Returns the minimum score required to be eligible for a level
     * @param level The level of the contractor
     */
    function getScore(uint8 level) external view returns (uint256) {
        if (level == 0 || level > TOTAL_LEVELS) {
            revert();
        }

        return levelRequirements[level].minScore;
    }

    /**
     * @dev Returns total number of orders placed
     */
    function getOrderCounter() external view returns (uint256) {
        return orderCounter;
    }
}