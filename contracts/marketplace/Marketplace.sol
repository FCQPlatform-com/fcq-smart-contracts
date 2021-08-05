//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../roles/IRoles.sol";

contract Marketplace {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    event OrderAdded(uint256 indexed nonce, address indexed creator, address tokenToSell, uint256 amountToSell, 
        address tokenToBuy, uint256 amountToBuy);
    event OrderRemoved(uint256 indexed nonce, address indexed creator);
    event OrderProcessed(uint256 indexed nonce, address indexed creator, address indexed acceptor, address tokenToSell, 
        uint256 amountToSell, address tokenToBuy, uint256 amountToBuy);

    struct Order {
        // Expiry in seconds since 1 January 1970
        uint256 _expiry;
        // Address of token to sell
        IERC20 _tokenToSell;
        // Amount of tokens to sell
        uint256 _amountToSell;
        // Address of token to pay
        IERC20 _tokenToBuy;
        // Amount of token to pay
        uint256 _amountToBuy;
        // Order creator
        address _creator;
        // Calculated fee for processing the order in payment token
        uint256 _fee;
    }

    // Common roles for FCQ platform
    IRoles _roles;
    // Address of the ERC20 token traded on this contract (e.g. EquityToken)
    address[] public _equityTokens;
    // Addresses of the ERC20 tokens accepted as a payment (e.g. USDT, USDC, DAI)
    address[] _paymentTokens;
    // Address of the wallet for exchange fees.
    address public _feeWallet;
    // Fee rate in 1/10000. For _feeRate 100, order fee will be 1% from both sides.
    uint256 _feeRate;
    // Unique nonce for order
    Counters.Counter _lastNonce;

    mapping(address => bool) _isEquityToken;
    mapping(address => bool) _isPaymentToken;
    mapping(uint256 => Order) _orders;

    modifier onlyPlatform() {
        require(_roles.isPlatform(msg.sender), "Marketplace: caller not a platform");
        _;
    }

    constructor(
        uint256 feeRate_, 
        address feeWallet_, 
        address[] memory equityTokens, 
        address[] memory paymentTokens, 
        IRoles roles) 
    {
        require(address(roles) != address(0), "Marketplace: roles not set");
        require(feeWallet_ != address(0), "Marketplace: fee wallet not set");
        _feeRate = feeRate_;
        _feeWallet = feeWallet_;
        _roles = roles;
        _setEquityTokens(equityTokens);
        _setPaymentTokens(paymentTokens);
    }

    /********************************** Orders **********************************/
    /**
     * @dev Adds new token exchange order to marketplace.
     */
    function addOrder(
        uint256 expiry,
        IERC20 tokenToSell,
        uint256 amountToSell,
        IERC20 tokenToBuy,
        uint256 amountToBuy
    ) 
        external 
    {
        _addOrder(msg.sender, expiry, tokenToSell, amountToSell, tokenToBuy, amountToBuy);
    }

    /**
     * @dev Adds new token exchange order to marketplace as a platform.
     * This function is used to cover transaction cost by platform.
     */
    function addOrderFor(
        address creator,
        uint256 expiry,
        IERC20 tokenToSell,
        uint256 amountToSell,
        IERC20 tokenToBuy,
        uint256 amountToBuy 
    ) 
        external onlyPlatform 
    {
        _addOrder(creator, expiry, tokenToSell, amountToSell, tokenToBuy, amountToBuy);
    }

    /**
     * @dev Returns locked funds with fees and removes orders from the storage.
     */
    function removeOrder(uint256 nonce) external {
        require(_orders[nonce]._creator == msg.sender, "Marketplace: order not found");

        uint256 amount = _orders[nonce]._amountToSell;
        if (isPaymentToken(address(_orders[nonce]._tokenToSell))) {
            amount = amount.add(_orders[nonce]._fee);
        }
        _orders[nonce]._tokenToSell.transfer(msg.sender, amount);
        delete _orders[nonce];
        emit OrderRemoved(nonce, msg.sender);
    }

    /**
     * @dev Process the order by the platform. 
     * After all formalities done (agreement signed and tokens approved), platform can process the order.
     */
    function processOrder(uint256 nonce, address acceptor) external onlyPlatform {
        require(_orders[nonce]._creator != address(0), "Marketplace: order not found");
        require(acceptor != address(0), "Marketplace: acceptor address not set");
        require(_orders[nonce]._expiry > block.timestamp, "Marketplace: order expired");

        uint256 fee = _orders[nonce]._fee;
        if (isPaymentToken(address(_orders[nonce]._tokenToBuy))) {
            // Lock tokens with fee
            _orders[nonce]._tokenToBuy.transferFrom(acceptor, address(this), _orders[nonce]._amountToBuy.add(fee));
            // Swap tokens
            _orders[nonce]._tokenToSell.transfer(acceptor, _orders[nonce]._amountToSell);
            _orders[nonce]._tokenToBuy.transfer(_orders[nonce]._creator, _orders[nonce]._amountToBuy.sub(fee));
            // Transfer fees (from order creator and acceptor)
            _orders[nonce]._tokenToBuy.transfer(_feeWallet, fee.add(fee));
        } else {
            // Lock tokens without fee 
            _orders[nonce]._tokenToBuy.transferFrom(acceptor, address(this), _orders[nonce]._amountToBuy);
            // Swap tokens
            _orders[nonce]._tokenToSell.transfer(acceptor, _orders[nonce]._amountToSell.sub(fee));
            _orders[nonce]._tokenToBuy.transfer(_orders[nonce]._creator, _orders[nonce]._amountToBuy);
            // Transfer fees (from order creator and acceptor)
            _orders[nonce]._tokenToSell.transfer(_feeWallet, fee.add(fee));
        }

        emit OrderProcessed(
            nonce, 
            _orders[nonce]._creator, 
            acceptor,
            address(_orders[nonce]._tokenToSell),
            _orders[nonce]._amountToSell,
            address(_orders[nonce]._tokenToBuy),
            _orders[nonce]._amountToBuy
        );
    }
    /***************************************************************************/

    /******************************** Tokens ***********************************/
    /**
     * @dev Overrides accepted payment tokens.
     */
    function setPaymentTokens(address[] calldata paymentTokens) external onlyPlatform {
        _setPaymentTokens(paymentTokens);
    }

    /**
     * @dev Overrides accepted equity tokens.
     */
    function setEquityTokens(address[] calldata equityTokens) external onlyPlatform {
        _setEquityTokens(equityTokens);
    }

    /**
     * @dev Add new equity token.
     */
    function addEquityToken(address equityToken) external onlyPlatform {
        require(_isEquityToken[equityToken] == false, "Marketplace: equity token already exists");
        _isEquityToken[equityToken] = true;
        _equityTokens.push(equityToken);
    }

    function isEquityToken(address token) public view returns(bool) {
        return _isEquityToken[token];
    }

    function isPaymentToken(address token) public view returns(bool) {
        return _isPaymentToken[token];
    }

    function setFeeRate(uint256 fee) external onlyPlatform {
        _feeRate = fee;
    }
    /***************************************************************************/

    /************************** Marketplace decription *************************/
    function feeWallet() public view returns(address) {
        return _feeWallet;
    }

    function feeRate() public view returns(uint256) {
        return _feeRate;
    }

    function order(uint256 nonce) public view returns(uint256, IERC20, uint256, IERC20, uint256, address, uint256) {
        return (
            _orders[nonce]._expiry,
            _orders[nonce]._tokenToSell,
            _orders[nonce]._amountToSell,
            _orders[nonce]._tokenToBuy,
            _orders[nonce]._amountToBuy,
            _orders[nonce]._creator,
            _orders[nonce]._fee
        );
    }

    /***************************************************************************/

    /**************************** INTERNAL FUNCTIONS ****************************/
    function _addOrder(
        address creator,
        uint256 expiry,
        IERC20 tokenToSell,
        uint256 amountToSell,
        IERC20 tokenToBuy,
        uint256 amountToBuy 
    ) 
        internal
    {
        require(amountToSell != 0, "Marketplace: amountToSell is 0");
        require(amountToBuy != 0, "Marketplace: amountToBuy is 0");
        require(
            (isEquityToken(address(tokenToSell)) && isPaymentToken(address(tokenToBuy))) || 
            (isPaymentToken(address(tokenToSell)) && isEquityToken(address(tokenToBuy))), 
            "Marketplace: not accepted token addresses");

        // Fee is calculated for payment token. 
        // If order wants to exchange payment token to equity token then amount + fee is locked.
        uint256 fee = 0;
        if (isPaymentToken(address(tokenToSell))) {
            fee = amountToSell.mul(_feeRate).div(10000);
            tokenToSell.transferFrom(creator, address(this), amountToSell.add(fee));
        } else {
            fee = amountToBuy.mul(_feeRate).div(10000);
            tokenToSell.transferFrom(creator, address(this), amountToSell);
        }

        _lastNonce.increment();
        _orders[_lastNonce.current()] = Order({
            _expiry: expiry,
            _tokenToSell: tokenToSell,
            _amountToSell: amountToSell,
            _tokenToBuy: tokenToBuy,
            _amountToBuy: amountToBuy,
            _creator: creator,
            _fee: fee
        });
       
        emit OrderAdded(
            _lastNonce.current(), 
            creator, 
            address(tokenToSell),
            amountToSell, 
            address(tokenToBuy), 
            amountToBuy
        );
    }

    function _setEquityTokens(address[] memory equityTokens) internal {
        for (uint i = 0; i<_equityTokens.length; i++){
            _isEquityToken[_equityTokens[i]] = false;
        } 
        for (uint i = 0; i<equityTokens.length; i++){
            _isEquityToken[equityTokens[i]] = true;
        }
        _equityTokens = equityTokens;
    }

    function _setPaymentTokens(address[] memory paymentTokens) internal {
        for (uint i = 0; i<_paymentTokens.length; i++){ 
            _isPaymentToken[_paymentTokens[i]] = false;
        } 
        for (uint i = 0; i<paymentTokens.length; i++){
            _isPaymentToken[paymentTokens[i]] = true;
        }
        _paymentTokens = paymentTokens;
    }
}