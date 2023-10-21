const { ethers, network, deployments, getNamedAccounts } = require("hardhat");
const {
  networkConfig,
  localNetworks,
} = require("../../helper-hardhat-config.js");
const { assert, expect } = require("chai");

!localNetworks.includes(network.name)
  ? describe.skip
  : describe("User Registration Tests", function () {
      let chainId = network.config.chainId;
      let deployer;
      let userRegistration;
      let mocksFunctions;
      let builderBuddy;
      let constructorData = networkConfig[chainId];
      const donName = 'fun-local'

      beforeEach(async () => {
        const accounts = await ethers.getSigners();
        deployer = (await getNamedAccounts()).deployer;
        user = accounts[1];
        await deployments.fixture(["main"]);

        const userRegistrationInstance = await deployments.get("UserRegistration");
        userRegistration = await ethers.getContractAt("UserRegistration", userRegistrationInstance.address);

        const mockFunctionsRouter = await deployments.get("MockFunctionsRouter");
        mocksFunctions = await ethers.getContractAt("MockFunctionsRouter", mockFunctionsRouter.address);

        const builderBuddyInstance = await deployments.get("BuilderBuddy");
        builderBuddy = await ethers.getContractAt("BuilderBuddy", builderBuddyInstance.address);
      });

      describe("Constructor Testing", function () {
        it("Should have correct constructor values", async function () {
            const minScore = await userRegistration.minimumScore();
            const scorerId = await userRegistration.scorerId();
            const gasLimit = await userRegistration.gasLimit();
            const owner = await userRegistration.owner();
            
            assert.equal(owner, deployer, "Owner does not match");
            assert.equal(minScore, constructorData.minScore, "minScore does not match");
            assert.equal(scorerId, constructorData.scorerId, "scorerId does not match");
            assert.equal(gasLimit, constructorData.gasLimit, "gasLimit does not match");
        });
      });
      describe("register Testing", function () {
        it("Should register user", async function () {
            let userId = "0x";
            for (let i = 0; i < 24; i++) {
                let randomValue = Math.floor((Math.random() * 100) % 15);
                if (randomValue <= 9) {
                    userId += String.fromCharCode(48 + randomValue);
                }
                else {
                    userId += String.fromCharCode(97 + randomValue - 9); 
                }
            }
            let tx = await userRegistration.register( userId, 1, "Naman");
            let receipt = await tx.wait();
            let requestId = receipt.logs[0].topics[1]; // receipt.logs[1].topics[0]
            await mocksFunctions.fulfillRequest(requestId);

            let reqIdToUserInfo = await userRegistration.reqIdToUserInfo(requestId);
            assert.equal(reqIdToUserInfo.userId, userId, "userId does not match");
            assert.equal(reqIdToUserInfo.role, 1, "role does not match");
            assert.equal(reqIdToUserInfo.name, "Naman", "name does not match");
            assert.equal(reqIdToUserInfo.ethAddress, deployer, "ethAddress does not match");
        });

        describe("setBuilderBuddy Testing", function () {
            it("Should set builder buddy", async function () {
                const builderBuddyAddress = await userRegistration.builderBuddy();
                if (builderBuddyAddress == 0x0000000000000000000000000000000000000000) {
                    await userRegistration.setBuilderBuddy(builderBuddy.address);
                    assert.equal(builderBuddyAddress, builderBuddy.address, "builderBuddyAddress does not match");
                }
                else {
                    // await expect(userRegistration.setBuilderBuddy(builderBuddy.address)).to.be.revertedWithCustomError(userRegistration, "UserRegistration__BuilderBuddyAlreadySet()");
                }
            });
        });

        describe("getCollateralDeposited Testing", function () {
            it("Should get collateral deposited", async function () {
                let userId = "0x";
                for (let i = 0; i < 24; i++) {
                    let randomValue = Math.floor((Math.random() * 100) % 15);
                    if (randomValue <= 9) {
                        userId += String.fromCharCode(48 + randomValue);
                    }
                    else {
                        userId += String.fromCharCode(97 + randomValue - 9); 
                    }
                }
                let tx = await userRegistration.register( userId, 1, "Naman");
                let receipt = await tx.wait();
                let requestId = receipt.logs[0].topics[1];
                await mocksFunctions.fulfillRequest(requestId);
                const collateralDeposited = await userRegistration.getCollateralDeposited(userId);
                assert.equal(collateralDeposited, 0, "collateralDeposited does not match");
            });
        })

        describe("getContractorAddr Testing", function () {
          it("Should get contractor address", async function () {
              let userId = "0x";
              for (let i = 0; i < 24; i++) {
                  let randomValue = Math.floor((Math.random() * 100) % 15);
                  if (randomValue <= 9) {
                      userId += String.fromCharCode(48 + randomValue);
                  }
                  else {
                      userId += String.fromCharCode(97 + randomValue - 9); 
                  }
              }
              let tx = await userRegistration.register( userId, 1, "Naman");
              let receipt = await tx.wait();
              let requestId = receipt.logs[0].topics[1];
              await mocksFunctions.fulfillRequest(requestId);
              let contractorAddress = await userRegistration.getContractorAddr(userId);
              assert.equal(contractorAddress, deployer, "contractorAddress does not match");
          }) 
        });

        describe("getCustomerAddr Testing", function () {
          it("Should get customer address", async function () {
            let userId = "0x";
            for (let i = 0; i < 24; i++) {
                let randomValue = Math.floor((Math.random() * 100) % 15);
                if (randomValue <= 9) {
                    userId += String.fromCharCode(48 + randomValue);
                }
                else {
                    userId += String.fromCharCode(97 + randomValue - 9); 
                }
            }
            let tx = await userRegistration.register( userId, 0, "Naman");
            let receipt = await tx.wait();
            let requestId = receipt.logs[0].topics[1];
            await mocksFunctions.fulfillRequest(requestId);
            let customerAddress = await userRegistration.getCustomerAddr(userId);
            assert.equal(customerAddress, deployer, "customerAddress does not match");
          });
        });

        describe("getContractorInfo Testing", function () {
          it("Should get contractor info", async function () {
              let userId = "0x";
              for (let i = 0; i < 24; i++) {
                  let randomValue = Math.floor((Math.random() * 100) % 15);
                  if (randomValue <= 9) {
                      userId += String.fromCharCode(48 + randomValue);
                  }
                  else {
                      userId += String.fromCharCode(97 + randomValue - 9); 
                  }
              }
              let tx = await userRegistration.register( userId, 1, "Naman");
              let receipt = await tx.wait();
              let requestId = receipt.logs[0].topics[1];
              await mocksFunctions.fulfillRequest(requestId);
              let contractorInfo = await userRegistration.getContractorInfo(userId);
              assert.equal(contractorInfo.ethAddress, deployer, "contractorAddress does not match");
              assert.equal(contractorInfo.name, "Naman", "name does not match");
              assert.equal(contractorInfo.totalCollateralDeposited, 0, "totalCollateralDeposited does not match");
              assert.equal(contractorInfo.isAssigned, false, "isAssigned does not match");
              assert.equal(contractorInfo.level, 0, "level does not match");
              assert.equal(contractorInfo.score, 0, "score does not match");
          });
        });

        describe("getCustomerInfo Testing", function () {
          it("Should get customer info", async function () {
              let userId = "0x";
              for (let i = 0; i < 24; i++) {
                  let randomValue = Math.floor((Math.random() * 100) % 15);
                  if (randomValue <= 9) {
                      userId += String.fromCharCode(48 + randomValue);
                  }
                  else {
                      userId += String.fromCharCode(97 + randomValue - 9); 
                  }
              }
              let tx = await userRegistration.register( userId, 0, "Naman");
              let receipt = await tx.wait();
              let requestId = receipt.logs[0].topics[1];
              await mocksFunctions.fulfillRequest(requestId);
              let customerInfo = await userRegistration.getCustomerInfo(userId);
              assert.equal(customerInfo.ethAddress, deployer, "customerAddress does not match");
              assert.equal(customerInfo.name, "Naman", "name does not match");
          });
        });

        describe("setSubId Testing", function () {
          it("Should set subId", async function () {
            let newSubId = 7;
            await userRegistration.setSubId(newSubId);
            let subId = await userRegistration.subscriptionId();
            assert.equal(subId, newSubId, "subId does not match");
          });
        });

        describe("setSecrets Testing", function () {
          it("Should set secrets", async function () {
            let newSecrets = "0x";
            for (let i = 0; i < 64; i++) {
                let randomValue = Math.floor((Math.random() * 100) % 15);
                if (randomValue <= 9) {
                    newSecrets += String.fromCharCode(48 + randomValue);
                }
                else {
                    newSecrets += String.fromCharCode(97 + randomValue - 9); 
                }
            }
            await userRegistration.setSecrets(newSecrets);
            let secrets = await userRegistration.secrets();
            assert.equal(secrets, newSecrets, "secrets does not match");
          });
        });
      })  
    });
