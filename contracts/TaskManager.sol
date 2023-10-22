// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BuilderBuddy } from "./BuilderBuddy.sol";
import { ArbiterContract } from "./ArbiterContract.sol";

/// @title Task Manager Smart Contract
/// @notice A contract for managing tasks between clients and contractors.
contract TaskManager {
    /**
     * @dev Represents the status of a task.
     */
    enum Status {
        PENDING,
        APPROVED,
        FINISHED,
        INITIATED,
        REJECTED
    }

    /**
     * @dev Represents a task with a title, description, cost, and status.
     */
    struct Task {
        string title;
        string description;
        uint256 cost;
        Status status;
        uint256 number;
        uint256 version;
    }

    /**
     * @dev The order's level, which is set during contract initialization and remains constant.
     */
    uint8 private immutable i_level;

    /**
     * @dev The unique identifier of the client, set during contract initialization.
     */
    bytes12 private immutable i_clientId;

    /**
     * @dev The unique identifier of the contractor, set during contract initialization.
     */
    bytes12 private immutable i_contractorId;

    /**
     * @dev The Ethereum address of the client
     */
    address private s_clientAddress;

    /**
     * @dev The Ethereum address of the contractor
     */
    address private s_contractorAddress;

    uint256 private immutable i_orderId;


    /**
     * @dev The amount of collateral deposited by the contractor, set during contract initialization and remains constant.
     */
    uint256 private immutable i_collateralDeposited;

    /**
     * @dev The address of the USDC token contract, set during contract initialization and remains constant.
     */
    IERC20 private immutable i_usdc;

    /**
     * @dev The task counter, which tracks the number of tasks created in the contract.
     */
    uint256 private s_taskCounter = 0;

    /**
     * @dev The task version counter, which tracks the version of tasks created in the contract.
     */
    uint256 private s_taskVersionCounter = 0;

    uint256 private s_rejectedTaskCounter = 0;

    bool private s_isContractActive;

    /**
     * @dev A mapping that associates a task ID (uint256) with its corresponding task information.
     */
    mapping(uint256 => Task) private tasks;

    /**
     * @dev A mapping that associates rejected task ID (uint156) with its corresponding rejected task information.
     */
    mapping(uint256 => Task task) private rejectedTask;

    /**
     * @dev The rating given by client for each task.
     */
    mapping(uint256 => uint256) private taskRating;

    /**
     * @dev The instance of the BuilderBuddy contract
     */
    BuilderBuddy private builderBuddy;

    ArbiterContract private arbiterContract;

    address private arbiterAssigned;
    uint256 private conflictIdx;

    // Errors

    /**
     * @dev Custom error: Indicates that a task is not in the "Approved" status.
     */
    error TaskManager__NotApproved();

    /**
     * @dev Custom error: Indicates that the sender is not the contractor.
     */
    error TaskManager__NotContractor();

    /**
     * @dev Custom error: Indicates that the sender is not the client.
     */
    error TaskManager__NotClient();

    /**
     * @dev Custom error: Indicates that the previous task is not finished.
     */
    error TaskManager__PreviousTaskNotFinished();

    /**
     * @dev Custom error: Indicates that there are no tasks in the contract.
     */
    error TaskManager__NoTasksYet();

    /**
     * @dev Custom error: Indicates that the task cost is greater than or equal to 80% of the collateral.
     */
    error TaskManager__CostGreaterThanCollateral();

    /**
     * @dev Error indicating that a task has already been approved.
     */
    error TaskManager__NotInitiated();

    /**
     * @dev Error indicating that there are insufficient funds to execute a task.
     */
    error TaskManager__InsufficientFundsForTask();

    /**
     * @dev Error indicating that funds transfer for a task has failed.
     */
    error TaskManager__FundsTransferFailed();

    /**
     * @dev Error indicating that the task is not in a pending state.
     */
    error TaskManager__NotPending();
    error TaskManager__ContractNotActive();
    error TaskManager__RatingNotInRange();
    error TaskManager__NeitherContractorNorClient();
    error TaskManager__OnlyArbiterCanResolveDisputes();
    error TaskManager__RefundCantBeMoreThanCost();
    error TaskManager__LastTaskAlreadyFinished();
    error TaskManager__ArbiterCantBeClientOrContr();
    error TaskManager__LastTaskNotApproved();

    /**
     * @dev Modifier to ensure the previous task is finished before executing a function.
     * @dev Reverts the transaction if the previous task is not finished or it's the first task.
     */
    modifier lastTaskFinished() {
        if (s_taskCounter > 0 && tasks[s_taskCounter].status != Status.FINISHED)
            revert TaskManager__PreviousTaskNotFinished();
        _;
    }

    /**
     * @dev Modifier to ensure there are existing tasks in the contract.
     * @dev Reverts the transaction if there are no tasks.
     */
    modifier hasTasks() {
        if (s_taskCounter <= 0) revert TaskManager__NoTasksYet();
        _;
    }

    /**
     * @dev Modifier to restrict a function's access to the client.
     * @dev Reverts the transaction if the sender is not the client.
     */
    modifier onlyClient() {
        if (msg.sender != s_clientAddress) revert TaskManager__NotClient();
        _;
    }

    /**
     * @dev Modifier to restrict a function's access to the contractor.
     * @dev Reverts the transaction if the sender is not the contractor.
     */
    modifier onlyContractor() {
        if (msg.sender != s_contractorAddress)
            revert TaskManager__NotContractor();
        _;
    }

    /**
     * @dev Modifier to ensure that a task is in the "Approved" status.
     * @dev Reverts the transaction if the task is not in the "Approved" status.
     */
    modifier isApproved() {
        if (tasks[s_taskCounter].status != Status.APPROVED)
            revert TaskManager__NotApproved();
        _;
    }

    /**
     * @dev Modifier to check if a task is in the "PENDING" status.
     * @notice Reverts with `TaskManager__NotPending` error if the task is not in the "PENDING" status.
     */
    modifier isPending() {
        if (tasks[s_taskCounter].status != Status.PENDING)
            revert TaskManager__NotPending();
        _;
    }

    /**
     * @dev Modifier to check if a task is in the "INITIATED" status.
     * @notice Reverts with `TaskManager__NotPending` error if the task is not in the "PENDING" status.
     */
    modifier isInitiated() {
        if (tasks[s_taskCounter].status != Status.INITIATED)
            revert TaskManager__NotInitiated();
        _;
    }
    modifier isActive() {
        if (!s_isContractActive) revert TaskManager__ContractNotActive();
        _;
    }

    /**
     * @dev Emitted when a new task is added.
     * @param taskId The unique identifier of the task.
     * @param title The title of the task.
     * @param status The status of the task when it is added.
     */
    event TaskAdded(uint256 indexed taskId, string title, string status);

    /**
     * @dev Emitted when a task is approved.
     * @param taskId The unique identifier of the task.
     * @param title The title of the task.
     * @param status The status of the task when it is approved.
     */
    event TaskApproved(uint256 indexed taskId, string title, string status);

    /**
     * @dev Emitted when a task is rejected.
     * @param taskId The unique identifier of the task.
     * @param title The title of the task.
     * @param status The status of the task when it is rejected.
     */
    event TaskRejected(uint256 indexed taskId, string title, string status);

    /**
     * @dev Emitted when an amount is transferred for a task.
     * @param taskId The unique identifier of the task.
     * @param amount The amount transferred.
     * @param status The status of the task when the amount is transferred.
     */
    event AmountTransferred(
        uint256 indexed taskId,
        uint256 amount,
        string status
    );

    /**
     * @dev Emitted when a task is marked as finished.
     * @param taskId The unique identifier of the task.
     * @param title The title of the task.
     * @param status The status of the task when it is marked as finished.
     */
    event TaskFinished(uint256 indexed taskId, string title, string status);

    /**
     * Emitted when the whole work is finished.
     * @param orderId The orderId of work.
     * @param timestamp The timestamp at which the work is finished.
     */
    event WorkFinished(uint256 indexed orderId, uint256 indexed timestamp);

    event ArbiterAdded(address arbiter);

    /**
     * @dev Constructor to initialize the contract with initial parameters.
     * @param _clientId The unique identifier of the client.
     * @param _contractorId The unique identifier of the contractor.
     * @param _clientAddress The Ethereum address of the client.
     * @param _contractorAddress The Ethereum address of the contractor.
     * @param _level The contractor's level.
     * @param _collateralDeposited The amount of collateral deposited by the contractor.
     * @param _usdc The address of the USDC token contract.
     */
    constructor(
        uint256 _orderId,
        bytes12 _clientId,
        bytes12 _contractorId,
        address _clientAddress,
        address _contractorAddress,
        uint8 _level,
        uint256 _collateralDeposited,
        IERC20 _usdc,
        address builderBuddyAddr
    ) {
        i_clientId = _clientId;
        i_contractorId = _contractorId;
        s_clientAddress = _clientAddress;
        s_contractorAddress = _contractorAddress;
        i_level = _level;
        i_usdc = _usdc;
        i_collateralDeposited = _collateralDeposited;
        builderBuddy = BuilderBuddy(builderBuddyAddr);
        s_isContractActive = true;
        i_orderId = _orderId;
        arbiterContract = ArbiterContract(builderBuddy.getArbiterContract());
        arbiterAssigned = address(0);               // no arbiter assigned initially
    }

    /**
     * @dev Adds a new task with the provided title, description, and cost.
     * @dev Only callable by the contractor.
     * @dev Requires that the previous task is finished, or it's the first task.
     * @dev Requires that the task cost is lower than a percentage of the collateral deposited by the client.
     * @param _title The title of the new task.
     * @param _description The description of the new task.
     * @param _cost The cost associated with the new task.
     */
    function addTask(
        string memory _title,
        string memory _description,
        uint256 _cost
    ) external onlyContractor lastTaskFinished isActive {
        if (_cost * 100 >= i_collateralDeposited * 80)
            revert TaskManager__CostGreaterThanCollateral();

        s_taskCounter++;
        s_taskVersionCounter++;

        Task memory task = Task({
            title: _title,
            cost: _cost,
            description: _description,
            status: Status.INITIATED,
            number: s_taskCounter,
            version: s_taskVersionCounter
        });

        tasks[s_taskCounter] = task;
        emit TaskAdded(s_taskCounter, task.title, "Initiated");
    }

    /**
     * @dev Approves the current task, changing its status to "Approved".
     * @dev Only callable by the client assigned to the task.
     * @dev Requires that there are existing tasks to approve.
     */
    function approveTask() external onlyClient hasTasks isInitiated isActive {
        if (i_usdc.balanceOf(address(this)) < tasks[s_taskCounter].cost) {
            revert TaskManager__InsufficientFundsForTask();
        }

        tasks[s_taskCounter].status = Status.APPROVED;

        emit TaskApproved(
            s_taskCounter,
            tasks[s_taskCounter].title,
            "Approved"
        );
    }

    /**
     * @dev Rejects the current task, changing its status to "Rejected".
     * @dev Only callable by the client who initiated the task.
     * @dev Requires that there are existing tasks to reject.
     */
    function rejectTask() external onlyClient hasTasks isInitiated isActive {
        Task storage task = tasks[s_taskCounter];

        task.status = Status.REJECTED;

        s_rejectedTaskCounter++;
        rejectedTask[s_rejectedTaskCounter] = task;

        s_taskCounter--;

        emit TaskRejected(task.number, task.title, "Rejected");
    }

    /**
     * @dev Marks the current task as "Pending" and initiates the transfer of the cost to the contractor.
     * @dev Only callable by the contractor assigned to the task.
     * @dev Requires that there are existing tasks and the current task is "Approved".
     */
    function availCost() external onlyContractor hasTasks isApproved isActive {
        uint256 amount = tasks[s_taskCounter].cost;
        tasks[s_taskCounter].status = Status.PENDING;

        emit AmountTransferred(s_taskCounter, amount, "Pending");

        bool success = i_usdc.transfer(msg.sender, amount);

        if (!success) {
            revert TaskManager__FundsTransferFailed();
        }
    }

    /**
     * @dev Marks the current task as "Finished", indicating its completion.
     * @dev Only callable by the client who initiated the task.
     * @dev Requires that there are existing tasks and the current task is "Approved".
     */
    function finishTask(
        uint256 rating
    ) external onlyClient hasTasks isPending isActive {
        if (rating < 1 || rating > 10) {
            revert TaskManager__RatingNotInRange();
        } 
        
        _finishTask(rating);
    }


    function finishWork() external onlyClient lastTaskFinished isActive {
        _finishWork();
    }

    function involveArbiter(address arbiter) external isActive hasTasks {
        if (msg.sender != s_clientAddress) {
            revert TaskManager__NeitherContractorNorClient();
        }

        Task memory lastTask = tasks[s_taskCounter];

        if (lastTask.status == Status.INITIATED) {
            revert TaskManager__LastTaskNotApproved();
        }

        if (arbiter == s_clientAddress || arbiter == s_contractorAddress) {
            revert TaskManager__ArbiterCantBeClientOrContr();
        }

        conflictIdx = arbiterContract.assignArbiterToResolveConflict(arbiter, i_orderId);

        arbiterAssigned = arbiter;

        emit ArbiterAdded(arbiter);
    }

    function resolveDispute(string memory remarks, uint256 amtToRefund) external isActive {
        if (msg.sender != arbiterAssigned) {
            revert TaskManager__OnlyArbiterCanResolveDisputes();
        }

        // now there are 2 scenarios, either the contractor was malicious, or the client didn't called finishTask or finishWork
        Task memory lastTask = tasks[s_taskCounter];

        if (lastTask.status == Status.INITIATED) {
            revert TaskManager__LastTaskNotApproved();
        }

        if (lastTask.status == Status.PENDING) {
            if (amtToRefund > lastTask.cost) {
                revert TaskManager__RefundCantBeMoreThanCost();
            }
            builderBuddy.transferCollateralToCustomer(i_orderId, msg.sender, amtToRefund);
        }
        else if (lastTask.status == Status.APPROVED) {
            uint256 cost = lastTask.cost;
            uint256 arbiterReward = (2 * cost) / 100; 
            bool success = i_usdc.transfer(s_clientAddress, cost - arbiterReward);
            bool success2 = i_usdc.transfer(msg.sender, arbiterReward);

            if (!success || !success2) {
                revert TaskManager__FundsTransferFailed();
            }
        }

        _finishTask(0);
        _finishWork();

        arbiterContract.markConflictAsResolved(msg.sender, remarks, conflictIdx);

        arbiterAssigned = address(0);
    }


    function _finishTask(uint256 rating) private {
        s_taskVersionCounter = 0;
        tasks[s_taskCounter].status = Status.FINISHED;

        taskRating[s_taskCounter] = rating;

        emit TaskFinished(
            s_taskCounter,
            tasks[s_taskCounter].title,
            "Finished"
        );
    }

    function _finishWork() private {
        uint256 overallRating = 0;
        for (uint256 i = 1; i <= s_taskCounter; i++) {
            overallRating += taskRating[i];
        }

        overallRating = (overallRating * 100) / s_taskCounter;

        builderBuddy.markOrderAsCompleted(i_orderId, overallRating);

        s_isContractActive = false;

        emit WorkFinished(i_orderId, block.timestamp);
    }

    function getOrderId() external view returns (uint256) {
        return i_orderId;
    }

    /**
     * @dev Get the order's level.
     * @return The level of the order.
     */
    function getLevel() public view returns (uint8) {
        return i_level;
    }

    /**
     * @dev Get the client's ID.
     * @return The unique identifier of the client.
     */
    function getClientId() public view returns (bytes12) {
        return i_clientId;
    }

    /**
     * @dev Get the contractor's ID.
     * @return The unique identifier of the contractor.
     */
    function getContractorId() public view returns (bytes12) {
        return i_contractorId;
    }

    /**
     * @dev Get the client's address.
     * @return The Ethereum address of the client.
     */
    function getClientAddress() public view returns (address) {
        return s_clientAddress;
    }

    /**
     * @dev Get the contractor's address.
     * @return The Ethereum address of the contractor.
     */
    function getContractorAddress() public view returns (address) {
        return s_contractorAddress;
    }

    /**
     * @dev Get the collateral deposited by the contractor.
     * @return The amount of collateral deposited by the contractor.
     */
    function getCollateralDeposited() public view returns (uint256) {
        return i_collateralDeposited;
    }

    /**
     * @dev Get the address of the USDC token contract.
     * @return The address of the USDC token contract.
     */
    function getUsdcToken() public view returns (IERC20) {
        return i_usdc;
    }

    /**
     * @dev Get the current task counter.
     * @return The total number of tasks that have been created.
     */
    function getTaskCounter() public view returns (uint256) {
        return s_taskCounter;
    }

    /**
     * @dev Get the rejected task counter.
     * @return The total number of tasks that have been rejected by client.
     */
    function getRejectedTaskCounter() public view returns (uint256) {
        return s_rejectedTaskCounter;
    }

    /**
     * @dev Get the task version counter.
     * @return The total versions of task rejected for the current task
     */
    function getTaskVersionCounter() public view returns (uint256) {
        return s_taskVersionCounter;
    }

    /**
     * @dev Get information about a specific task.
     * @param taskId The unique identifier of the task.
     * @return A tuple containing the title, description, cost, and status of the task.
     */
    function getTask(
        uint256 taskId
    ) public view returns (string memory, string memory, uint256, Status) {
        Task storage task = tasks[taskId];
        return (task.title, task.description, task.cost, task.status);
    }

    /**
     * @dev Get information about all non-rejected tasks.
     * @return An array of Task structures representing all non-rejected tasks.
     */
    function getAllTasks() public view returns (Task[] memory) {
        Task[] memory allTasks = new Task[](s_taskCounter);

        for (uint256 i = 1; i <= s_taskCounter; i++) {
            allTasks[i - 1] = tasks[i];
        }

        return allTasks;
    }

    /**
     * @dev Get details of all rejected tasks.
     * @return An array of Task structures representing all rejected tasks
     */
    function getAllRejectedTasks() public view returns (Task[] memory) {
        Task[] memory allTasks = new Task[](s_rejectedTaskCounter);

        for (uint256 i = 1; i <= s_rejectedTaskCounter; i++) {
            allTasks[i - 1] = rejectedTask[i];
        }
        return allTasks;
    }

    /**
     * @return True/False representing whether work has finished or not
     */
    function isWorkFinished() external view returns (bool) {
        return (!s_isContractActive);
    }

    function getBuilderBuddyAddr() external view returns (address) {
        return address(builderBuddy);
    }

    function getArbiterContractAddr() external view returns (address) {
        return address(arbiterContract);
    }

    function getTaskRating(uint256 taskId) external view returns (uint256) {
        return taskRating[taskId];
    }
}
