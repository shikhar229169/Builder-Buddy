// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IBuilderBuddy {
    function getTaskContract(uint256 orderId) external view returns (address);
}

/**
 * @title Arbiter Contract
 * @notice This contract contains all the arbiters which the users can appoint if there is a conflict
 */
contract ArbiterContract {
    error ArbiterContract__NotOwner();
    error ArbiterContract__ArbiterAlreadyAdded();
    error ArbiterContract__NotTaskManager();
    error ArbiterContract__ArbiterNotExist();
    error ArbiterContract__AssignedToOtherWork();
    error ArbiterContract__NotAllocatedToArbiter();

    enum Status {
        PENDING,
        RESOLVED
    }

    struct ConflictDetails {
        uint256 orderId;
        address taskManager;
        Status status;
        string remarks;
    }

    mapping(bytes12 userId => address arbiter) private arbiters;
    IBuilderBuddy private builderBuddy;
    address private immutable i_owner;
    mapping(bytes12 arbiterUserId => ConflictDetails[]) private conflictDetails;
    mapping(address => bytes12 arbiterUserId) private arbiterAddrToId;

    // Events
    event ArbiterAdded(address indexed arbiter);

    modifier onlyOwner() {
        if (msg.sender != i_owner) {
            revert ArbiterContract__NotOwner();
        }
        _;
    }

    constructor(address _owner, address _builderBuddyAddr) {
        i_owner = _owner;
        builderBuddy = IBuilderBuddy(_builderBuddyAddr);
    }

    function addArbiter(bytes12 userId, address arbiter) external onlyOwner {
        if (arbiters[userId] != address(0)) {
            revert ArbiterContract__ArbiterAlreadyAdded();
        }

        if (arbiterAddrToId[arbiter] != bytes12(0)) {
            revert ArbiterContract__ArbiterAlreadyAdded();
        }

        arbiters[userId] = arbiter;
        arbiterAddrToId[arbiter] = userId;

        emit ArbiterAdded(arbiter);
    }

    function assignArbiterToResolveConflict(address arbiter, uint256 orderId) external returns (uint256) {
        bytes12 arbiterId = arbiterAddrToId[arbiter];

        if (arbiterId == bytes12(0)) {
            revert ArbiterContract__ArbiterNotExist();
        }

        address taskManagerContract = builderBuddy.getTaskContract(orderId);
        address arbiterAddr = arbiters[arbiterId];

        if (msg.sender != taskManagerContract) {
            revert ArbiterContract__NotTaskManager();
        }

        if (arbiterAddr == address(0)) {
            revert ArbiterContract__ArbiterNotExist();
        }

        ConflictDetails memory details = ConflictDetails({
            orderId: orderId,
            taskManager: taskManagerContract,
            status: Status.PENDING,
            remarks: ""
        });

        conflictDetails[arbiterId].push(details);

        return conflictDetails[arbiterId].length - 1;
    }

    function markConflictAsResolved(address arbiter, string memory remarks, uint256 conflictIdx) external {
        bytes12 arbiterUserId = arbiterAddrToId[arbiter];
        ConflictDetails memory details = conflictDetails[arbiterUserId][conflictIdx];

        if (msg.sender != details.taskManager) {
            revert ArbiterContract__NotAllocatedToArbiter();
        }

        conflictDetails[arbiterUserId][conflictIdx].remarks = remarks;
        conflictDetails[arbiterUserId][conflictIdx].status = Status.RESOLVED;
    }

    function getBuilderBuddy() external view returns (address) {
        return address(builderBuddy);
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getArbiterAddress(bytes12 userId) external view returns (address) {
        return arbiters[userId];
    }

    function getArbiterUserId(address arbiter) external view returns (bytes12) {
        return arbiterAddrToId[arbiter];
    }

    function getConflictDetails(bytes12 arbiterId, uint256 conflictIdx) external view returns (ConflictDetails memory) {
        return conflictDetails[arbiterId][conflictIdx];
    }

    function getAllArbiterConflicts(bytes12 arbiterId) external view returns (ConflictDetails[] memory) {
        return conflictDetails[arbiterId];
    }
}