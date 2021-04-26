//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "eth-token-recover/contracts/TokenRecover.sol";

abstract contract ContractFallbacks {
    function receiveApproval(address from, uint256 _amount, IERC20 _token, bytes memory _data) public virtual;
    function onTokenTransfer(address from, uint256 amount, bytes memory data) public virtual returns (bool success);
}

// based on implementation https://etherscan.io/address/0x6710cee627fa3a988200ffd5687cc1c814cef0f6#code
contract FCQToken is ERC20Burnable, TokenRecover {
    constructor() ERC20("Fortem Capital Token", "FCQ") {
        _setupDecimals(0);
        _mint(msg.sender, 210000000);
    }

    /**
     * @dev function that allow to approve for transfer and call contract in one transaction
     * @param _spender contract address
     * @param _amount amount of tokens
     * @param _extraData optional encoded data to send to contract
     * @return success true if function call was successfully
     */
    function approveAndCall(address _spender, uint256 _amount, bytes calldata _extraData) external returns (bool success)
    {
        require(approve(_spender, _amount), "ERC20: Approve unsuccesfull");
        ContractFallbacks(_spender).receiveApproval(msg.sender, _amount, IERC20(this), _extraData);
        return true;
    }

    /**
     * @dev function that transer tokens to diven address and call function on that address
     * @param _to address to send tokens and call
     * @param _value amount of tokens
     * @param _data optional extra data to process in calling contract
     * @return success True if all succedd
     */
    function transferAndCall(address _to, uint _value, bytes calldata _data) external returns (bool success)
    {
        _transfer(msg.sender, _to, _value);
        ContractFallbacks(_to).onTokenTransfer(msg.sender, _value, _data);
        return true;
    }
}