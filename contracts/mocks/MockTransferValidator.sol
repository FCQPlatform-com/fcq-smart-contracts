//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "../tokens/transferValidator/ITransferValidator.sol";

contract MockTransferValidator is ITransferValidator {

    function tokensToTransfer(address, address, address, address, uint256, bytes calldata) 
        external override 
    {}

     function canTransfer(address, address, address, address, uint256, bytes calldata)
        external pure override
        returns (bool)
    {
        return true;
    }
}
