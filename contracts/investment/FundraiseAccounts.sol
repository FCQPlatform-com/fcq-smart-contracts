//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../roles/IRoles.sol";

/**
 * @dev Storage for fundraise accounts and all data related to the accounts.
 */
contract FundraiseAccounts {
    using Counters for Counters.Counter;

    event FundraiseAccountCreated(uint256 indexed accountId, address investorWallet, uint256 tokensToBuy);
    event FundraiseAccountBlocklisted(uint256 indexed accountId);
    event InvestorWalletBlocklisted(address indexed investorWallet);

    // Account data
    struct Account {
        address _investorWallet;
        uint256 _amountToPayInUSD;
        uint256 _maxPaymentInFCQ;
        uint256 _tokensToBuy;
    }

    // Common roles for the FCQ smart contracts
    IRoles _roles;
    // Mapping from investor wallet to paid to bool. 
    mapping(address => bool) _blocklistedWallets;
    // Mapping from account id to bool. 
    mapping(uint256 => bool) _blocklistedAccounts;
    // All accounts ids.
    Counters.Counter _accountIds;
    // Mapping from account id to account data. 
    mapping(uint256 => Account) _accounts;

    modifier onlyPlatform() {
        require(_roles.isPlatform(msg.sender), "caller is not a platform");
        _;
    }

    constructor(IRoles roles_) {
        _roles = roles_;
    }

    /**
     * @dev Create fundraise account. 
     * Fundraise accounts contains all data related to fundraise like investor wallet, number of tokens to buy,
     * amount to pay for this tokens.
     * Without fundraise account investor cannot participate in fundraise.
     */
    function createFundraiseAccount(
        address payable investorWallet, 
        uint256 amountToPayInUSD,
        uint256 maxPaymentInFCQ,
        uint256 tokensToBuy
    ) 
        public 
        onlyPlatform
    {
        require(investorWallet != address(0), "FundraiseAccounts: empty wallet address");
        require(tokensToBuy > 0, "FundraiseAccounts: no tokens to buy");
        require(!_blocklistedWallets[investorWallet], "FundraiseAccounts: blocklisted wallet");

        _accountIds.increment();
        _accounts[_accountIds.current()] = Account({
            _amountToPayInUSD: amountToPayInUSD,
            _investorWallet: investorWallet,
            _maxPaymentInFCQ: maxPaymentInFCQ,
            _tokensToBuy: tokensToBuy
        });
        emit FundraiseAccountCreated(_accountIds.current(), investorWallet, tokensToBuy);
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

    /********************************** Validation ************************************/
    /**
     * @dev Check if account exist and is not blocklisted. 
     */
    function checkAccount(uint256 accountId, address wallet) public view returns(bool) {
        return !_blocklistedAccounts[accountId]
            && !_blocklistedWallets[wallet] 
            && _accounts[accountId]._investorWallet == wallet;
    }
    /**********************************************************************************/
}