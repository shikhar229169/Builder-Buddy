// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { FunctionsClient, FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract UserRegistration is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // Enums
    enum Role {
        CUSTOMER,
        CONTRACTOR
    }

    // for setting up users info corresponding to request id for chainlink functions
    struct UserRequestInfo {
        bytes12 userId;
        address ethAddress;
        Role role;
        string name;
    }

    // mapped with userId
    struct Customer {
        address ethAddress;
        string name;
        uint256[] worksRequested;
    }

    struct Contractor {
        address ethAddress;
        string name;
        uint256 score;
        uint8 level;
        bool isAssigned;
        uint256 totalCollateralDeposited;
        uint256[] acceptedContracts;        
    }

    // Errors
    error UserRegistration__AlreadyRegistered();
    error UserRegistration__NotOwner();
    error UserRegistration__InvalidUserId();

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


    mapping(bytes12 userId => Customer) public customers;
    mapping(bytes12 userId => Contractor) public contractors;
    mapping(address userAddr => bytes12 userId) public userAddrToUserId;


    // Testing
    bytes public success;
    string public errror;

    // Events
    event Registered(bytes12 indexed userId, address indexed ethAddress, Role indexed role);
    event RegistrationUnsuccessful(address indexed ethAddress, uint256 indexed score);
    event AlreadyRegistered(bytes12 indexed userId, address indexed ethAddress);
    
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

    function register(bytes12 userId, Role role, string memory name) external {
        if (userId == bytes12(0)) {
            revert UserRegistration__InvalidUserId();
        }


        if (customers[userId].ethAddress != address(0) || contractors[userId].ethAddress != address(0)) {
            revert UserRegistration__AlreadyRegistered();
        }

        if (userAddrToUserId[msg.sender] != bytes12(0)) {
            revert UserRegistration__AlreadyRegistered();
        }

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
        reqIdToUserInfo[reqId] = UserRequestInfo(userId, msg.sender, role, name);
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
            if (userAddrToUserId[userInfo.ethAddress] != bytes12(0)) {
                emit AlreadyRegistered(userInfo.userId, userInfo.ethAddress);
                return;
            }

            uint256 score = abi.decode(response, (uint256));
            if (score >= minimumScore) {
                // Registration Successful
                
                if (userInfo.role == Role.CUSTOMER) {
                    customers[userInfo.userId] = Customer({
                        ethAddress: userInfo.ethAddress,
                        name: userInfo.name,
                        worksRequested: new uint256[](0)
                    });
                }
                else if (userInfo.role == Role.CONTRACTOR) {
                    contractors[userInfo.userId] = Contractor({
                        ethAddress: userInfo.ethAddress,
                        name: userInfo.name,
                        score: 0,
                        level: 0,
                        isAssigned: false,
                        totalCollateralDeposited: 0,
                        acceptedContracts: new uint256[](0)
                    });
                }

                userAddrToUserId[userInfo.ethAddress] = userInfo.userId;

                emit Registered(userInfo.userId, userInfo.ethAddress, userInfo.role);
            }
            else {
                emit RegistrationUnsuccessful(userInfo.ethAddress, score);
            }
        }
        else {
            emit RegistrationUnsuccessful(userInfo.ethAddress, 0);
        }
    }

    function setSecrets(bytes memory newSecrets) external onlyOwner {
        secrets = newSecrets;
    }

    function setSubId(uint64 newSubId) external onlyOwner {
        subscriptionId = newSubId;
    }
}