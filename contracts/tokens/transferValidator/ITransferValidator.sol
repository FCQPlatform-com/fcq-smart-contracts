//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

interface ITransferValidator {

    function canTransfer(address sender, address token, address from, address to, uint256 value, bytes calldata data)
        external view returns (bool);

    function tokensToTransfer(address sender, address token, address from, address to, uint256 value, bytes calldata data) external;
    
}
