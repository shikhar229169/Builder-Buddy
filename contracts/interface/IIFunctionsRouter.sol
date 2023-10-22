// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IIFunctionsRouter {
    function addConsumer(uint64 subscriptionId, address consumer) external;
}