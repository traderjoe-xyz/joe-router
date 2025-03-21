// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WNative is ERC20 {
    function test() public pure {} // To avoid this contract to be included in coverage
    constructor() ERC20("Wrapped Native", "WNATIVE") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "WNATIVE: withdraw failed");
    }

    function mint(address to, uint256 amount) external {
        transfer(to, amount);
    }
}
