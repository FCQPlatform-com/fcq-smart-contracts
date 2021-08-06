//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "../roles/IRoles.sol";

/**
 * @dev Storage for fundraise accounts.
 */
contract FundraiseAccounts {

    event FundraiseAccountBlocklisted(uint256 indexed accountId);
    event InvestorWalletBlocklisted(address indexed investorWallet);

    // Common roles for the FCQ smart contracts
    IRoles _roles;
    // Mapping from investor wallet to paid to bool. 
    mapping(address => bool) _blocklistedWallets;
    // Mapping from account id to bool. 
    mapping(uint256 => bool) _blocklistedAccounts;

    modifier onlyPlatform() {
        require(_roles.isPlatform(msg.sender), "caller is not a platform");
        _;
    }

    constructor(IRoles roles_) {
        _roles = roles_;
    }

    /********************************** Blocklist **********************************/
    /**
     * @dev Blocklist account.
     * Blocklisted accounts have been forbidden to perform certain actions (e.g. participate in a fundraise)
     */
    function blocklistAccount(uint256 accountId) external onlyPlatform {
        _blocklistedAccounts[accountId] = true;
        emit FundraiseAccountBlocklisted(accountId);
    }

    function isBlocklistedAccount(uint256 accountId) public view returns (bool) {
        return _blocklistedAccounts[accountId];
    }

    /**
     * @dev Blocklist wallet.
     * Blocklisted wallets have been forbidden to perform certain actions (e.g. participate in a fundraise)
     */
    function blocklistWallet(address wallet) external onlyPlatform {
        _blocklistedWallets[wallet] = true;
        emit InvestorWalletBlocklisted(wallet);
    }

    function isBlocklistedWallet(address wallet) public view returns (bool) {
        return _blocklistedWallets[wallet];
    }
    /**********************************************************************************/
}