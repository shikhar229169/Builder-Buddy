// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { FunctionsClient, FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UserRegistration is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // Enums
    enum Role {
        CUSTOMER,
        CONTRACTOR
    }

    struct UserRequestInfo {
        address user;
        Role role;
    }

    // Errors
    error UserRegistration__AlreadyRegistered();
    error UserRegistration__NotOwner();

    // State Variables

    // GitCoin Related
    uint256 public minimumScore;
    mapping(bytes32 reqId => UserRequestInfo user) public reqIdToUserInfo;
    string public scorerId;
    string public source;
    uint64 public subscriptionId;
    uint32 public gasLimit;
    bytes32 public donId;
    bytes public secrets;
    address public owner;



    mapping(address user => Role role) public userToRole;



    // Testing
    bytes public success;
    string public errror;

    // Events
    event Registered(address indexed user, Role indexed role);
    event RegistrationUnsuccessful(address indexed user, uint256 indexed score);
    
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert UserRegistration__NotOwner();
        }
        _;
    }

    constructor(address router, uint256 _minimumScore, string memory _scorerId, string memory _source, uint64 _subscriptionId, uint32 _gasLimit, bytes memory _secrets, string memory donName) FunctionsClient(router) {
        minimumScore = _minimumScore;
        scorerId = _scorerId;
        source = _source;
        subscriptionId = _subscriptionId;
        gasLimit = _gasLimit;
        donId = bytes32(abi.encodePacked(donName));
        secrets = _secrets;
        owner = msg.sender;
    }

    function register(bytes32 userId, Role role, string memory name) external {
        // if (role == Role.NO_ROLE) {
        //     revert();
        // }

        // if (userToRole[msg.sender] != Role.NO_ROLE) {
        //     revert UserRegistration__AlreadyRegistered();
        // }


        // get the scorer id, user address, and api key for gitcoin
        // Then place an api call to check if the score is satisfied via chainlink functions
        FunctionsRequest.Request memory req;
        req.initializeRequest(FunctionsRequest.Location.Inline, FunctionsRequest.CodeLanguage.JavaScript, source);

        string[] memory args = new string[](2);
        args[0] = scorerId;
        args[1] = Strings.toHexString(uint256(uint160(msg.sender)), 20);

        req.setArgs(args);

        req.addSecretsReference(secrets);

        bytes32 reqId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        reqIdToUserInfo[reqId] = UserRequestInfo(msg.sender, role);
    }

    function setSecrets(bytes memory newSecrets) external onlyOwner {
        secrets = newSecrets;
    }

    function setSubId(uint64 newSubId) external onlyOwner {
        subscriptionId = newSubId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal virtual override {
        UserRequestInfo memory userInfo = reqIdToUserInfo[requestId];
        success = response;
        errror = string(err);
        if (response.length > 0) {
            uint256 score = abi.decode(response, (uint256));
            if (score >= minimumScore) {
                // Registration Successful
                userToRole[userInfo.user] = userInfo.role;

                emit Registered(userInfo.user, userInfo.role);
            }
            else {
                emit RegistrationUnsuccessful(userInfo.user, score);
            }
        }
        else {
            emit RegistrationUnsuccessful(userInfo.user, 0);
        }
    }
}