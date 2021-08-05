//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDTToken is ERC20 {
    constructor() ERC20("USD Token", "USDT") {
        _mint(msg.sender, 1000000000000000);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}