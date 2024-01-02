// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { UserRegistration } from "./UserRegistration.sol";
import { TaskManager } from "./TaskManager.sol";
import { ArbiterContract } from "./ArbiterContract.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Builder Buddy Smart Contract
/// @notice This contract manages users registration and orders
contract BuilderBuddy {
    // Enums
    enum Status {
        PENDING,
        ASSIGNED,
        REJECTED,
        FINISHED
    }

    enum Category {
        Construction,
        Rennovation,
        Maintenance,
        Electrical,
        Plumbing,
        Carpentry
    }

    struct CustomerOrder {
        address customer;
        bytes12 customerId;
        string title;
        string description;
        Category category;
        string locality;
        uint256 budget;
        uint256 expectedStartDate;
        Status status;
        uint256 timestamp;
        address contractor;
        bytes12 contractorId;
        address taskContract;
        uint8 level;
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
    error BuilderBuddy__InvalidLevel();
    error BuilderBuddy__ContractorIneligible();
    error BuilderBuddy__OrderCantHavePastDate();
    error BuilderBuddy__OrderNotFound();
    error BuilderBuddy__TokenTransferFailed();
    error BuilderBuddy__OrderCantBeCancelled();
    error BuilderBuddy__CantWithdrawContractorAssigned();

    // State Variables
    uint256 private orderCounter;
    uint256 private constant TOTAL_LEVELS = 5;
    mapping(uint256 orderId => CustomerOrder order) private orders;
    mapping(bytes12 customerId => uint256[] orderId) private customerOrders;
    mapping(bytes12 contractorId => uint256[] orderId) private contractorAcceptedOrders;
    mapping(uint8 level => LevelRequirements) private levelRequirements;
    IERC20 private immutable i_usdc;
    address private immutable i_arbiterContract;
    UserRegistration private immutable i_userReg;

    // Events
    event OrderCreated(
        address indexed customer,
        uint256 indexed orderId,
        string title
    );
    event OrderCancelled(uint256 indexed orderId);
    event ContractorAssigned(
        uint256 indexed orderId,
        address indexed contractor
    );
    event OrderConfirmed(uint256 indexed orderId, address indexed contractor);
    event ContractorStaked(address indexed contractor);
    event ContractorUnstaked(address indexed contractor);
    event RefundedWithCollateral(uint256 indexed orderId, address indexed user, bytes12 indexed contractor);

    // Modifiers
    modifier orderExists(uint256 orderId) {
        if (orders[orderId].customer == address(0)) {
            revert BuilderBuddy__OrderNotFound();
        }
        _;
    }

    modifier onlyCustomer(bytes12 userId) {
        if (i_userReg.getCustomerAddr(userId) != msg.sender) {
            revert BuilderBuddy__InvalidCustomer();
        }
        _;
    }

    modifier isContractorValid(bytes12 contractorUserId) {
        UserRegistration.Contractor memory contr = i_userReg.getContractorInfo(contractorUserId);

        if (contr.ethAddress == address(0)) {
            revert BuilderBuddy__ContractorNotFound();
        }

        if (contr.isAssigned) {
            revert BuilderBuddy__ContractorAlreadySet();
        }
        if (contr.level == 0) {
            revert BuilderBuddy__ContractorHasNotStaked();
        }

        if (levelRequirements[contr.level].collateralRequired != contr.totalCollateralDeposited) {
            revert BuilderBuddy__ContractorHasNotStaked();
        }
        _;
    }

    modifier onlyContractor(bytes12 userId) {
        if (i_userReg.getContractorAddr(userId) != msg.sender) {
            revert BuilderBuddy__InvalidContractor();
        }
        _;
    }

    // Constructor
    constructor(
        address userRegAddr,
        uint256[] memory collateralsForLevel,
        uint256[] memory scoreForLevel,
        address usdcToken
    ) {
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

            if (
                i != 0 &&
                (collateralsForLevel[i] <= collateralsForLevel[i - 1] ||
                    scoreForLevel[i] <= scoreForLevel[i - 1])
            ) {
                revert BuilderBuddy__InvalidLevelsConfig();
            }

            levelRequirements[i + 1].collateralRequired = collateralsForLevel[i];
            levelRequirements[i + 1].minScore = scoreForLevel[i];
        }


        orderCounter = 0;
        i_usdc = IERC20(usdcToken);
        i_userReg = UserRegistration(userRegAddr);
        i_arbiterContract = address(new ArbiterContract(msg.sender, address(this)));
    }

    // FUNCTIONS

    /**
     * @dev Allows contractor to stake usdc to increment their level
     * @param contractorUserId The contractor's user id
     * @param _level Level the contractor want to upgrade to
     */
    function incrementLevelAndStakeUSDC(
        bytes12 contractorUserId,
        uint8 _level
    ) external onlyContractor(contractorUserId) {
        UserRegistration.Contractor memory cont = i_userReg.getContractorInfo(contractorUserId);
        LevelRequirements memory req = levelRequirements[_level];

        if (_level < cont.level) {
            revert BuilderBuddy__YouCantDowngrade();
        }

        if (req.collateralRequired == cont.totalCollateralDeposited) {
            revert BuilderBuddy__AlreadyStaked();
        }

        if (_level > TOTAL_LEVELS) {
            revert BuilderBuddy__AlreadyMaxedLevel();
        }


        if (cont.score < req.minScore) {
            revert BuilderBuddy__ScoreIsLess();
        }

        emit ContractorStaked(msg.sender);
        bool success = i_usdc.transferFrom(
            msg.sender,
            address(this),
            req.collateralRequired - cont.totalCollateralDeposited
        );

        if (!success) {
            revert BuilderBuddy__StakingFailed();
        }

        i_userReg.setLevelAndCollateral(contractorUserId, _level, req.collateralRequired);
    }

    /**
     * @dev Allows contractor to unstake their USDC deposited
     * @notice Assigns the respective level to the contractor based on the remaining amount
     * @param contractorUserId The user id of the contractor
     * @param _level The level to downgrade to
     */
    function withdrawStakedUSDC(
        bytes12 contractorUserId,
        uint8 _level
    )
        external
        onlyContractor(contractorUserId)
    {
        UserRegistration.Contractor memory cont = i_userReg.getContractorInfo(contractorUserId);
        uint8 currLevel = cont.level;

        if (cont.isAssigned) {
            revert BuilderBuddy__CantWithdrawContractorAssigned();
        }

        if (_level >= currLevel) {
            revert BuilderBuddy__YouCantUpgrade();
        }

        uint256 remainingStakedAmount = levelRequirements[_level].collateralRequired;
        uint256 amount = cont.totalCollateralDeposited - remainingStakedAmount;

        emit ContractorUnstaked(msg.sender);
        bool success = i_usdc.transfer(msg.sender, amount);
        if (!success) {
            revert BuilderBuddy__WithdrawFailed();
        }

        i_userReg.setLevelAndCollateral(contractorUserId, _level, remainingStakedAmount);
    }

    /**
     * @dev Allows customer to create an order
     * @param userId The customer's user id
     * @param title The title of the order
     * @param desc The description of the order
     * @param locality The locality of the order
     * @param budget The budget of the customer for the work
     * @param expectedStartDate The expected start date of the work in unix timestamp (seconds)
     */
    function createOrder(
        bytes12 userId,
        string memory title,
        string memory desc,
        Category category,
        string memory locality,
        uint8 _level,
        uint256 budget,
        uint256 expectedStartDate
    ) external onlyCustomer(userId) returns (uint256) {
        if (_level <= 0 || _level > TOTAL_LEVELS) {
            revert BuilderBuddy__InvalidLevel();
        }

        if (expectedStartDate < block.timestamp) {
            revert BuilderBuddy__OrderCantHavePastDate();
        }

        uint256 orderId = orderCounter;
        orderCounter++;

        orders[orderId] = CustomerOrder({
            customer: msg.sender,
            customerId: userId,
            title: title,
            description: desc,
            category: category,
            locality: locality,
            budget: budget,
            expectedStartDate: expectedStartDate,
            status: Status.PENDING,
            timestamp: block.timestamp,
            contractor: address(0),
            contractorId: "",
            taskContract: address(0),
            level: _level
        });

        customerOrders[userId].push(orderId);

        emit OrderCreated(msg.sender, orderId, title);

        return orderId;
    }

    /**
     * @notice Allows customer to cancel an order
     * @notice Only allowed if it is not assigned to a contractor
     * @param userId The userId of customer
     * @param orderId The order Id to cancel
     */
    function cancelOrder(bytes12 userId, uint256 orderId) external onlyCustomer(userId) orderExists(orderId) {
        CustomerOrder memory currOrder = orders[orderId];

        if (msg.sender != currOrder.customer) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        if (currOrder.taskContract != address(0)) {
            revert BuilderBuddy__OrderCantBeCancelled();
        }

        orders[orderId].status = Status.REJECTED;
        orders[orderId].contractor = address(0);
        orders[orderId].contractorId = bytes12(0);

        emit OrderCancelled(orderId);
    }

    /**
     * @dev Allows customer to assign a contractor to their order
     * @param userId The customer's user id
     * @param orderId The customer's order id
     * @param contractorId The contractor's user id
     * @notice if contractor is already assigned, then contractor can't be assigned to another order
     */
    function assignContractorToOrder(
        bytes12 userId,
        uint256 orderId,
        bytes12 contractorId
    ) external onlyCustomer(userId) orderExists(orderId) isContractorValid(contractorId) {
        if (orders[orderId].customer != msg.sender) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        UserRegistration.Contractor memory contr = i_userReg.getContractorInfo(contractorId);

        if (orders[orderId].level > contr.level) {
            revert BuilderBuddy__ContractorIneligible();
        }
        if (orders[orderId].status != Status.PENDING) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        address appointedContractorAddress = contr.ethAddress;

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
    function confirmUserOrder(
        bytes12 contractorUserId,
        uint256 orderId
    )
        external
        onlyContractor(contractorUserId)
        orderExists(orderId)
        isContractorValid(contractorUserId)
    {
        CustomerOrder memory currOrder = orders[orderId];
        if (currOrder.contractor != msg.sender) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        if (currOrder.status != Status.PENDING) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        orders[orderId].status = Status.ASSIGNED;

        contractorAcceptedOrders[contractorUserId].push(orderId);

        // deploy the task contract
        TaskManager taskManager = new TaskManager(orderId, currOrder.customerId, currOrder.contractorId, currOrder.customer, currOrder.contractor, currOrder.level, i_userReg.getCollateralDeposited(contractorUserId), i_usdc, address(this));

        // update the task contract address
        orders[orderId].taskContract = address(taskManager);

        i_userReg.setContractorAssignStatus(contractorUserId, true);
        emit OrderConfirmed(orderId, msg.sender);
    }

    /**
     * @dev Mark the order as confirmed upon confirmation by customer
     * @notice This is called by Task Manager Contract by a function which is called by customer
     * @param orderId The customer's order id
     */
    function markOrderAsCompleted(uint256 orderId, uint256 score) external {
        if (msg.sender != orders[orderId].taskContract) {
            revert BuilderBuddy__OnlyTaskContractCanCall();
        }

        CustomerOrder memory order = orders[orderId];
        orders[orderId].status = Status.FINISHED;
        
        i_userReg.setContractorAssignStatus(order.contractorId, false);
        i_userReg.incrementContractorScore(order.contractorId, score);
    }

    function transferCollateralToCustomer(uint256 orderId, address arbiter, uint256 amount) external {
        if (msg.sender != orders[orderId].taskContract) {
            revert BuilderBuddy__OnlyTaskContractCanCall();
        }

        bytes12 contrId = orders[orderId].contractorId;
        address currCustomer = orders[orderId].customer;

        uint256 arbiterReward = (5 * amount) / 100;
        i_userReg.decrementCollateral(contrId, amount + arbiterReward);

        emit RefundedWithCollateral(orderId, currCustomer, contrId);
        bool success = i_usdc.transfer(currCustomer, amount);
        if (!success) {
            revert BuilderBuddy__TokenTransferFailed();
        }

        if (arbiterReward > 0) {
            bool success2 = i_usdc.transfer(arbiter, arbiterReward);

            if (!success2) {
                revert BuilderBuddy__TokenTransferFailed();
            }
        }
    }

    /**
     * @dev Returns the order details corresponding to order id
     * @param orderId The order id of the customer's order
     */
    function getOrder(
        uint256 orderId
    ) external orderExists(orderId) view returns (CustomerOrder memory) {
        return orders[orderId];
    }

    function getTaskContract(uint256 orderId) external orderExists(orderId) view returns (address) {
        return orders[orderId].taskContract;
    }

    /**
     * @dev Returns all the orders placed by a customer
     * @return An array of Order struct, containing details about every order
     * @param customerUserId The user id of customer
     */
    function getAllCustomerOrders(
        bytes12 customerUserId
    ) external view returns (CustomerOrder[] memory) {
        uint256[] memory customerOrderIds = customerOrders[customerUserId];
        uint256 orderLength = customerOrderIds.length;
        CustomerOrder[] memory currCustomerOrders = new CustomerOrder[](orderLength);

        for (uint256 i = 0; i < orderLength; i++) {
            currCustomerOrders[i] = orders[customerOrderIds[i]];
        }

        return currCustomerOrders;
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
    function getRequiredCollateral(
        uint8 level
    ) external view returns (uint256) {
        if (level == 0 || level > TOTAL_LEVELS) {
            revert();
        }

        return levelRequirements[level].collateralRequired;
    }

    /**
     * @dev Returns the max eligible level a contractor can have
     * @param score The score of contractor
     */
    function getMaxEligibleLevelByScore(
        uint256 score
    ) external view returns (uint256) {
        uint8 level = 1;

        while (
            level + 1 < TOTAL_LEVELS &&
            score >= levelRequirements[level + 1].minScore
        ) {
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

    function getUserRegistrationContract() external view returns (address) {
        return address(i_userReg);
    }

    function getArbiterContract() external view returns (address) {
        return i_arbiterContract;
    }
}
