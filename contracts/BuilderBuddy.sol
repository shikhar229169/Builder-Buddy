// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { UserRegistration } from "./UserRegistration.sol";

contract BuilderBuddy is UserRegistration {


    constructor(address router, uint256 _minimumScore, string memory _scorerId, string memory _source, uint64 _subscriptionId, uint32 _gasLimit, bytes memory _secrets, string memory donName) UserRegistration(router, _minimumScore, _scorerId, _source, _subscriptionId, _gasLimit, _secrets, donName) {

    }


}