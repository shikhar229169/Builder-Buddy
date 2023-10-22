// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUsdc is ERC20 {
    constructor() ERC20("USDC Mock", "USDCM") {

    }

    function mint(address user, uint256 amount) external {
        _mint(user, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}