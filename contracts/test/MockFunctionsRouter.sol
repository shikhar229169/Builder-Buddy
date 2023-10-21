// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface Consumer {
    function handleOracleFulfillment(bytes32 requestId, bytes memory response, bytes memory err) external;
}

contract MockFunctionsRouter {
    error MockFunctionsRouter__RequestNotExist();
    error MockFunctionsRouter__AlreadyServed();

    uint256 counter = 1;

    struct Request {
        uint64 subId;
        bytes data;
        uint16 dataVersion;
        uint32 gasLimit;
        bytes32 donId;
        address consumer;
        bool served;
    }

    mapping(bytes32 req => Request) reqInfo;

    function sendRequest(
    uint64 subscriptionId,
    bytes calldata data,
    uint16 dataVersion,
    uint32 callbackGasLimit,
    bytes32 donId
  ) external returns (bytes32) {


    bytes32 ct = bytes32(counter);

    reqInfo[ct] = Request(subscriptionId, data, dataVersion, callbackGasLimit, donId, msg.sender, false);

    counter++;

    return ct;
  }

  function fulfillRequest(bytes32 reqId) external {
    if (reqInfo[reqId].consumer == address(0)) {
        revert MockFunctionsRouter__RequestNotExist();
    }

    if (reqInfo[reqId].served) {
        revert MockFunctionsRouter__AlreadyServed();
    }

    reqInfo[reqId].served = true;

    uint256 score = 100;


    Consumer(reqInfo[reqId].consumer).handleOracleFulfillment(reqId, abi.encode(score), "");
  }
}