//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

interface ITransferValidator {

    function canTransfer(address sender, address token, address from, address to, uint256 value, bytes calldata data)
        external view returns (bool);

    function tokensToTransfer(address sender, address token, address from, address to, uint256 value, bytes calldata data) external;
    
}
