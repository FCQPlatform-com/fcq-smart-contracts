//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDTToken is ERC20 {
    constructor() ERC20("USD Token", "USDT") {
        _setupDecimals(6);
        _mint(msg.sender, 1000000000000000);
    }
}