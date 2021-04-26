//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDAIToken is ERC20 {
    constructor() ERC20("DAI Token", "DAI") {
        _setupDecimals(18);
        _mint(msg.sender, 1000000000000000000000000);
    }
}