// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { UserRegistration } from "./UserRegistration.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        bytes12 contractorId;
        address taskContract;
    }

    // Errors
    error BuilderBuddy__InvalidCustomer();
    error BuilderBuddy__CallerNotOwnerOfOrder();
    error BuilderBuddy__ContractorNotFound();
    error BuilderBuddy__ContractorAlreadySet();
    error BuilderBuddy__InvalidContractor();
    error BuilderBuddy__InvalidLevelsForCollateral();
    error BuilderBuddy__AlreadyStaked();
    error BuilderBuddy__StakingFailed();
    error BuilderBuddy__AlreadyMaxedLevel();
    error BuilderBuddy__ContractorHasNotStaked();
    error BuilderBuddy__OnlyTaskContractCanCall();
    error BuilderBuddy__AmountIsZero();
    error BuilderBuddy__AmountExceedsDeposited();
    error BuilderBuddy__WithdrawFailed();

    // State Variables
    uint256 private orderCounter;
    uint256 private constant TOTAL_LEVELS = 5;
    mapping (uint256 orderId => CustomerOrder order) private orders;
    mapping (uint8 level => uint256 collateralNeeded) private collateralRequired;
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
        address usdcToken
    ) UserRegistration(router, _minimumScore, _scorerId, _source, _subscriptionId, _gasLimit, _secrets, donName) {
        if (collateralsForLevel.length != 5) {
            revert BuilderBuddy__InvalidLevelsForCollateral();
        }

        for (uint256 i = 0; i < TOTAL_LEVELS; i++) {
            if (collateralsForLevel[i] == 0) {
                revert BuilderBuddy__InvalidLevelsForCollateral();
            }

            if (i != 0 && collateralsForLevel[i] < collateralsForLevel[i - 1]) {
                revert BuilderBuddy__InvalidLevelsForCollateral();
            }

            collateralRequired[uint8(i + 1)] = collateralsForLevel[i];
        }

        orderCounter = 0;
        i_usdc = IERC20(usdcToken);
    }


    // FUNCTIONS

    function stakeUSDC(bytes12 contractorUserId) external onlyContractor(contractorUserId) {
        Contractor memory cont = contractors[contractorUserId];

        if (cont.level == TOTAL_LEVELS) {
            revert BuilderBuddy__AlreadyMaxedLevel();
        }

        contractors[contractorUserId].level++;
        if (cont.totalCollateralDeposited == collateralRequired[cont.level]) {
            revert BuilderBuddy__AlreadyStaked();
        }

        emit ContractorStaked(msg.sender);
        bool success = i_usdc.transferFrom(msg.sender, address(this), collateralRequired[cont.level] - cont.totalCollateralDeposited);

        if (!success) {
            revert BuilderBuddy__StakingFailed();
        }


        contractors[contractorUserId].totalCollateralDeposited = collateralRequired[cont.level];
    }


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
            contractorId: "",
            taskContract: address(0)
        });

        customers[userId].worksRequested.push(orderId);

        emit OrderCreated(msg.sender, orderId, title);
    }

    // if contractor is already assigned, then contractor can't be assigned to another order
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

    function markOrderAsCompleted(uint256 orderId) external {
        // only callable by task manager contract
        if (msg.sender != orders[orderId].taskContract) {
            revert BuilderBuddy__OnlyTaskContractCanCall();
        }

        CustomerOrder memory order = orders[orderId];

        orders[orderId].status = Status.FINISHED;
        contractors[order.contractorId].isAssigned = false;
    }

    function withdrawStakedUSDC(bytes12 contractorUserId, uint256 amount) external onlyContractor(contractorUserId) isContractorValid(contractorUserId) {
        if (amount == 0) {
            revert BuilderBuddy__AmountIsZero();
        }

        if (amount > contractors[contractorUserId].totalCollateralDeposited) {
            revert BuilderBuddy__AmountExceedsDeposited();
        }

        uint256 remainingAmount = contractors[contractorUserId].totalCollateralDeposited - amount;

        uint8 level = 0;
        uint8 currLevel = contractors[contractorUserId].level;

        for (uint8 i = currLevel; i > 0; i--) {
            uint256 reqAmt = collateralRequired[i];
            if (remainingAmount >= reqAmt) {
                level = i;
                break;
            }
        }

        bool success = i_usdc.transfer(msg.sender, amount);
        if (!success) {
            revert BuilderBuddy__WithdrawFailed();
        }

        contractors[contractorUserId].level = level;
    }
}
