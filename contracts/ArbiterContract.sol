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

    struct ConflictDetails {
        uint256 orderId;
        address taskManager;
        string remarks;
    }

    struct Arbiter {
        address ethAddress;
        bool isAssigned;
    }

    mapping(address => Arbiter) private arbiters;
    IBuilderBuddy private builderBuddy;
    address private immutable i_owner;
    mapping(address => ConflictDetails[]) conflictDetails;

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

    function addArbiter(address arbiter) external onlyOwner {
        if (arbiters[arbiter].ethAddress != address(0)) {
            revert ArbiterContract__ArbiterAlreadyAdded();
        }

        arbiters[arbiter] = Arbiter({
            ethAddress: arbiter,
            isAssigned: false
        });

        emit ArbiterAdded(arbiter);
    }

    function assignArbiterToResolveConflict(address arbiter, uint256 orderId) external {
        address taskManagerContract = builderBuddy.getTaskContract(orderId);

        if (msg.sender != taskManagerContract) {
            revert ArbiterContract__NotTaskManager();
        }

        if (arbiters[arbiter].ethAddress == address(0)) {
            revert ArbiterContract__ArbiterNotExist();
        }

        if (arbiters[arbiter].isAssigned) {
            revert ArbiterContract__AssignedToOtherWork();
        }

        Arbiter storage currArbiter = arbiters[arbiter];

        currArbiter.isAssigned = true;

        ConflictDetails memory details = ConflictDetails({
            orderId: orderId,
            taskManager: taskManagerContract,
            remarks: ""
        });

        conflictDetails[arbiter].push(details);
    }

    function markConflictAsResolved(address arbiter, string memory remarks) external {
        uint256 conflictIdx = conflictDetails[arbiter].length - 1;
        ConflictDetails memory details = conflictDetails[arbiter][conflictIdx];

        if (msg.sender != details.taskManager) {
            revert ArbiterContract__NotAllocatedToArbiter();
        }

        arbiters[arbiter].isAssigned = false;
        conflictDetails[arbiter][conflictIdx].remarks = remarks;
    }
}