// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BuilderBuddy } from "./BuilderBuddy.sol";

/// @title Task Manager Smart Contract
/// @notice A contract for managing tasks between clients and contractors.
contract TaskManager {
    /**
     * @dev The client's level, which is set during contract initialization and remains constant.
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
     * @dev The Ethereum address of the client, which can change if needed.
     */
    address private s_clientAddress;

    /**
     * @dev The Ethereum address of the contractor, which can change if needed.
     */
    address private s_contractorAddress;

    /**
     * @dev The amount of collateral deposited by the client, set during contract initialization and remains constant.
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
     * @dev The instance of the BuilderBuddy contract
     */
    BuilderBuddy private builderBuddy;

    /**
     * @dev Represents the status of a task.
     */
    enum Status {
        PENDING,
        APPROVED,
        FINISHED,
        INITIATED
    }

    /**
     * @dev Represents a task with a title, description, cost, and status.
     */
    struct Task {
        string title;
        string description;
        uint256 cost;
        Status status;
    }

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
     * @dev Modifier to ensure the previous task is finished before executing a function.
     * @dev Reverts the transaction if the previous task is not finished or it's the first task.
     */
    modifier lastTaskFinished() {
        if (
            s_taskCounter > 0 &&
            tasks[s_taskCounter - 1].status != Status.FINISHED
        ) revert TaskManager__PreviousTaskNotFinished();
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
     * @param task The task to check for approval.
     */
    modifier isApproved(Task memory task) {
        if (task.status != Status.APPROVED) revert TaskManager__NotApproved();
        _;
    }

    /**
     * @dev Modifier to ensure that the task cost is lower than a percentage of the collateral deposited by the client.
     * @dev Reverts the transaction if the cost is greater than or equal to 80% of the collateral.
     * @param cost The cost of the task to be checked.
     */
    modifier costLowerThanCollateral(uint256 cost) {
        if (cost * 100 >= collateral * 80)
            revert TaskManager__CostGreaterThanCollateral();
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
    ) public onlyContractor lastTaskFinished costLowerThanCollateral(_cost) {
        Task memory task = Task({
            title: _title,
            cost: _cost,
            description: _description,
            status: Status.INITIATED
        });
        s_taskCounter++;
        tasks[s_taskCounter] = task;
        emit TaskAdded(s_taskCounter, task.title, "Initiated");
    }

    /**
     * @dev Approves the current task, changing its status to "Approved".
     * @dev Only callable by the client assigned to the task.
     * @dev Requires that there are existing tasks to approve.
     */
    function approveTask() public onlyClient hasTasks {
        tasks[s_taskCounter].status = Status.APPROVED;

        ///@dev Make sure to check if the collateral deposited by the contrator
        /// is more than the cost the user is approving and is being transfered

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
    function rejectTask() public onlyClient hasTasks {
        s_taskCounter--;

        ///@dev Make sure to check if the collateral deposited by the contrator
        /// is more than the cost the user is approving and is being transfered

        emit TaskRejected(
            s_taskCounter + 1,
            tasks[s_taskCounter + 1].title,
            "Rejected"
        );
    }

    /**
     * @dev Marks the current task as "Pending" and initiates the transfer of the cost to the contractor.
     * @dev Only callable by the contractor assigned to the task.
     * @dev Requires that there are existing tasks and the current task is "Approved".
     */
    function availCost() public onlyContractor hasTasks isApproved {
        uint256 amount;
        tasks[s_taskCounter].status = Status.PENDING;
        emit AmountTransferred(s_taskCounter, amount, "Pending");
    }

    /**
     * @dev Marks the current task as "Finished", indicating its completion.
     * @dev Only callable by the client who initiated the task.
     * @dev Requires that there are existing tasks and the current task is "Approved".
     */
    function finishTask() public onlyClient hasTasks isApproved {
        tasks[s_taskCounter].status = Status.FINISHED;
        emit TaskFinished(
            s_taskCounter,
            tasks[s_taskCounter].title,
            "Finished"
        );
    }

    /**
     * @dev Get the client's level.
     * @return The level of the client.
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
     * @dev Get the collateral deposited by the client.
     * @return The amount of collateral deposited by the client.
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
     * @dev Get information about all tasks.
     * @return An array of Task structures representing all tasks.
     */
    function getAllTasks() public view returns (Task[] memory) {
        Task[] memory allTasks = new Task[](s_taskCounter);

        for (uint256 i = 1; i <= s_taskCounter; i++) {
            allTasks[i - 1] = tasks[i];
        }

        return allTasks;
    }
}
