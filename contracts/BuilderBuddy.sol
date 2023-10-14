// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {UserRegistration} from "./UserRegistration.sol";

contract BuilderBuddy is UserRegistration {
    // Enums
    enum Status {
        PENDING,
        ASSIGNED,
        REJECTED,
        FINISHED
    }

    // Structs
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
        address taskContract;
    }

    // Errors
    error BuilderBuddy__InvalidCustomer();
    error BuilderBuddy__CallerNotOwnerOfOrder();
    error BuilderBuddy__ContractorNotFound();
    error BuilderBuddy__ContractorAlreadySet();
    error BuilderBuddy__InvalidContractor();

    // State Variables
    uint256 private orderCounter;
    mapping(uint256 orderId => CustomerOrder order) private orders;

    // Events
    event OrderCreated(address indexed customer, uint256 indexed orderId, string title);
    event ContractorAssigned(uint256 indexed orderId, address indexed contractor);
    event OrderConfirmed(uint256 indexed orderId, address indexed contractor);

    // Modifiers
    modifier onlyCustomer(bytes12 userId) {
        if (customers[userId].ethAddress != msg.sender) {
            revert BuilderBuddy__InvalidCustomer();
        }
        _;
    }

    modifier isContractorAssigned(bytes12 contractorUserId) {
        if (contractors[contractorUserId].isAssigned) {
            revert BuilderBuddy__ContractorAlreadySet();
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
        string memory donName
    ) UserRegistration(router, _minimumScore, _scorerId, _source, _subscriptionId, _gasLimit, _secrets, donName) {
        orderCounter = 0;
    }

    // FUNCTIONS

    // should we add category for an order??
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
            taskContract: address(0)
        });

        customers[userId].worksRequested.push(orderId);

        emit OrderCreated(msg.sender, orderId, title);
    }

    // if contractor is already assigned, then contractor can't be assigned to another order
    function assignContractorToOrder(bytes12 userId, uint256 orderId, bytes12 contractorId)
        external
        onlyCustomer(userId)
        isContractorAssigned(contractorId)
    {
        if (orders[orderId].customer != msg.sender) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        address appointedContractorAddress = contractors[contractorId].ethAddress;

        if (appointedContractorAddress == address(0)) {
            revert BuilderBuddy__ContractorNotFound();
        }

        if (appointedContractorAddress == orders[orderId].contractor) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        orders[orderId].contractor = appointedContractorAddress;

        emit ContractorAssigned(orderId, appointedContractorAddress);
    }

    function confirmUserOrder(bytes12 contractorUserId, uint256 orderId) external onlyContractor(contractorUserId) isContractorAssigned(contractorUserId) {
        if (orders[orderId].contractor != msg.sender) {
            revert BuilderBuddy__CallerNotOwnerOfOrder();
        }

        if (orders[orderId].status != Status.PENDING) {
            revert BuilderBuddy__ContractorAlreadySet();
        }

        orders[orderId].status = Status.ASSIGNED;

        contractors[contractorUserId].isAssigned = true;
        contractors[contractorUserId].acceptedContracts.push(orderId);
        
        emit OrderConfirmed(orderId, msg.sender);
    }
}
