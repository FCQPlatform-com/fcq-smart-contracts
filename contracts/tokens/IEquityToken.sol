//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// This interface is based on core ERC-1400 standard (Security token)
// and is based on ERC-1726 (Dividend-Paying Token)
interface IEquityToken {

    // Transfers
    function transferWithData(address to, uint256 value, bytes calldata data) external;
    function transferFromWithData(address from, address to, uint256 value, bytes calldata _data) external;

    // Token Issuance
    function isIssuable() external view returns (bool);
    function issue(address tokenHolder, uint256 value, bytes calldata data) external;

    // Transfer Validity
    function canTransfer(address to, uint256 value, bytes calldata data) external view returns (bool, byte, bytes32);
    function canTransferFrom(address from, address to, uint256 value, bytes calldata data) 
        external view returns (bool, byte, bytes32);
    function setTransferValidator(address validator) external returns (bool);

    // Dividends
    function dividendOf(address owner) external view returns(uint256);
    function distributeDividends(uint256 amount) external;
    function withdrawDividend(address) external;
    function withdrawnDividendOf(address owner) external view returns(uint256);

    // Issuance / Redemption Events
    event Issued(address indexed operator, address indexed to, uint256 value, bytes data);

    // Validity events
    event TransferValidatorReplaced(address validator);

    // Dividend events
    event DividendsDistributed(address indexed from, uint256 weiAmount);
    event DividendWithdrawn(address indexed to, uint256 weiAmount);
}