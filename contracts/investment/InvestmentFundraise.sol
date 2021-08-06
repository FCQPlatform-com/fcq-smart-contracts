//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../tokens/FCQToken.sol";
import "./FundraiseAccounts.sol";
import "../tokens/IEquityToken.sol";

/**
 * InvestmentFundraise is STO contract.
 * Sold tokens represent equity in the investment. Contract accepts payments in USDT and FCQ tokens.
 * Every investor has to have created fundraise account and signed an agreement to join STO.
 */
contract InvestmentFundraise is FundraiseAccounts {
    using SafeMath for uint256;

    // Data used to process the payment.
    struct PaymentInfo {
        // payment token, it should be one of accepted payment tokens
        IERC20 tokenAddress;
        // investor address
        address sender;
        // unique account number created for single investment agreement
        uint256 accountId;
        // amount of tokens sent to fundraise contract
        uint256 value;
        // overall payment amount, the value can be lower than amountToPay (investor can pay full amount in parts)
        uint256 amountToPay;
        // number of equity tokens investor will get after full payment.
        uint256 tokensToBuy;
    }

    event FundraiseFinalized(bool successfully);
    event Refunded(address indexed refundee, uint256 indexed accountId);
    event TokensWithdrawn(
        address indexed beneficiary,
        uint256 indexed accountId,
        uint256 amount
    );
    event TokensPurchased(
        address indexed buyer,
        uint256 indexed accountId,
        uint256 amount
    );
    event PaymentAccepted(
        address indexed sender,
        uint256 indexed accountId,
        address token,
        uint256 amount
    );

    // This value must be included whenever signature is generated
    mapping(uint256 => uint256) public nonces;

    bytes32 public constant PAY_TYPEHASH = keccak256("Pay(PaymentInfo paymentInfo,address signer,uint8 v,bytes32 r,bytes32 s)");

    bytes32 _name;
    IERC20[] _paymentTokens;
    mapping(address => bool) _isPaymentToken;
    IERC20 _fcqToken;
    IEquityToken _equityToken;

    // Address where funds are collected after successful fundraising
    address payable _wallet;

    // The token to USD exchange rate
    // How many USD units token is worth.
    // Example: 2,000,000 means that 1.0 token = 0.000,001 USD * 2,000,000 (1.0 Token = 2.0 USD)
    // Example 2: -1,000 means that 1.0 token = 0.000,001 USD / 1,000 (1.0 Token = 0.000,000,0001 USD)
    mapping(address => int256) _tokenRates;

    mapping(address => uint256) _tokenRaised;
    uint256 _cap;
    uint256 _endTime;
    bool _finalized;
    bool _refundEnabled;

    // Mapping from investor wallet to paid amount [token -> investor -> amount].
    mapping(address => mapping(address => uint256)) _paidByInvestor;
    // Mapping from token -> investor -> amount.
    mapping(address => mapping(uint256 => uint256)) _paid;
    // Mapping from account id to bool.
    mapping(uint256 => bool) _isPaid;
    // Mapping from account id to equity token balance.
    mapping(uint256 => uint256) _balances;
    // Mapping from account id to wallet address.
    mapping(uint256 => address) _accountWallet;

    modifier onlyOperator() {
        require(
            _roles.isOperator(msg.sender),
            "caller is not a operatoran operator"
        );
        _;
    }

    constructor(
        bytes32 name_,
        uint256 cap_,
        uint256 endTime_,
        address payable wallet_,
        IRoles roles_,
        IEquityToken equityToken_,
        IERC20[] memory paymentTokens_,
        int256[] memory tokenRates_
    ) FundraiseAccounts(roles_) {
        require(
            name_ != bytes32(0),
            "InvestmentFundraise: empty name is not allowed"
        );
        require(
            wallet_ != address(0),
            "InvestmentFundraise: wallet is the zero address"
        );
        require(
            paymentTokens_.length != 0,
            "InvestmentFundraise: no payment tokens"
        );
        require(cap_ > 0, "InvestmentFundraise: cap is 0");
        require(
            address(equityToken_) != address(0),
            "InvestmentFundraise: token cannot be zero address"
        );
        require(
            address(roles_) != address(0),
            "InvestmentFundraise: roles contract cannot be zero address"
        );
        require(
            paymentTokens_.length == tokenRates_.length,
            "InvestmentFundraise: number of tokens doesn't match the number of rates"
        );

        _wallet = wallet_;
        _paymentTokens = paymentTokens_;
        _fcqToken = _paymentTokens[0];
        _cap = cap_;
        _endTime = endTime_;
        _equityToken = equityToken_;
        _name = name_;
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            _isPaymentToken[address(_paymentTokens[i])] = true;
            _tokenRates[address(_paymentTokens[i])] = tokenRates_[i];
        }
    }

    /************************************* Payment **************************************/
    /**
     * @dev before payment fundraising contract has to be approved to transfer payment tokens
     */
    function pay(
        PaymentInfo memory paymentInfo,
        address signer,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(_roles.isPlatform(signer), "signer is not a platform");

        bytes32 hashStruct = keccak256(
            abi.encode(
                PAY_TYPEHASH,
                paymentInfo,
                nonces[paymentInfo.accountId]++
            ));

        require(verifyPersonalSign(signer, hashStruct, v, r, s), "invalid signature");
        _accountWallet[paymentInfo.accountId] = paymentInfo.sender;

        _preValidatePayment(paymentInfo);
        _processPayment(paymentInfo);
    }

    /**************************************************************************************/

    /******************************* Timed fundraise *******************************/
    function endTime() public view returns (uint256) {
        return _endTime;
    }

    function hasClosed() public view returns (bool) {
        return block.timestamp > _endTime;
    }

    /*******************************************************************************/

    /******************************* Capped fundraise *******************************/
    function cap() public view returns (uint256) {
        return _cap;
    }

    function capReached() public view returns (bool) {
        return totalRaised() >= _cap;
    }

    /*******************************************************************************/

    /********************************* Finalizable *********************************/
    /**
     * @dev Returns true if the fundraise is finalized, false otherwise.
     */

    function finalized() public view returns (bool) {
        return _finalized;
    }

    function wasSuccessfullyFinalized() public view returns (bool) {
        return _finalized && !_refundEnabled;
    }

    /**
     * @dev Must be called to end fundraising.
     * Calls the contract's finalization function.
     * Operator can finalize successfully the fundraising before it ends.
     */
    function finalize(bool successfully) public onlyOperator {
        require(!_finalized, "InvestmentFundraise: already finalized");

        _finalized = true;
        if (successfully) {
            // transfer all funds to the wallet
            for (uint256 i = 0; i < _paymentTokens.length; i++) {
                _paymentTokens[i].transfer(
                    wallet(),
                    _tokenRaised[address(_paymentTokens[i])]
                );
            }
        } else {
            _refundEnabled = true;
        }

        emit FundraiseFinalized(successfully);
    }

    /*******************************************************************************/

    /********************************* Refundable **********************************/
    /**
     * @dev Investors can claim refunds here if fundraise was unsuccessful
     * or investor wallet was blocklisted.
     */
    function claimRefund(address refundee) public {
        require(
            _refundEnabled || isBlocklistedWallet(refundee),
            "InvestmentFundraise: refund forbidden"
        );
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            uint256 amount =
            _paidByInvestor[address(_paymentTokens[i])][refundee];
            _paidByInvestor[address(_paymentTokens[i])][refundee] = 0;
            _paymentTokens[i].transfer(refundee, amount);
        }
        emit Refunded(refundee, 0);
    }

    /**
     * @dev Investors can claim refunds for their account when fundraise was unsuccessful or
     * account was blocklisted or account didn't buy tokens (investor didn't pay full amount for the tokens)
     */
    function claimRefundForAccount(uint256 accountId) public {
        require(
            _refundEnabled ||
            isBlocklistedAccount(accountId) ||
            (_finalized && !_isPaid[accountId]),
            "InvestmentFundraise: refund forbidden"
        );
        address investor = _accountWallet[accountId];
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            uint256 amount = _paid[address(_paymentTokens[i])][accountId];
            _paidByInvestor[address(_paymentTokens[i])][
            investor
            ] = _paidByInvestor[address(_paymentTokens[i])][investor].sub(
                amount
            );
            _paid[address(_paymentTokens[i])][accountId] = 0;
            _paymentTokens[i].transfer(investor, amount);
        }
        emit Refunded(investor, accountId);
    }

    /*******************************************************************************/

    /********************************* Token withdrawl **********************************/
    function withdrawTokens(uint256 accountId) public {
        require(
            wasSuccessfullyFinalized(),
            "InvestmentFundraise: not successfully finalized"
        );
        require(
            !isBlocklistedAccount(accountId),
            "InvestmentFundraise: account is blocklisted"
        );
        require(
            !isBlocklistedWallet(_accountWallet[accountId]),
            "InvestmentFundraise: wallet is blocklisted"
        );
        uint256 amount = _balances[accountId];
        require(
            amount > 0,
            "InvestmentFundraise: beneficiary is not due any tokens"
        );

        _balances[accountId] = 0;
        bytes memory data;
        _equityToken.issue(_accountWallet[accountId], amount, data);
        emit TokensWithdrawn(
            _accountWallet[accountId],
            accountId,
            amount
        );
    }

    function withdrawAccountsTokens(uint256[] memory accounts) public {
        for (uint256 i = 0; i < accounts.length; i++) {
            withdrawTokens(accounts[i]);
        }
    }

    /************************************************************************************/

    /******************************* Fundraise Description *******************************/
    function isPaid(uint256 accountId) public view returns (bool) {
        return _isPaid[accountId];
    }

    function paid(address tokenAddress, address investorWallet)
    public
    view
    returns (uint256)
    {
        return _paidByInvestor[tokenAddress][investorWallet];
    }

    function paidForAccount(address tokenAddress, uint256 accountId)
    public
    view
    returns (uint256)
    {
        return _paid[tokenAddress][accountId];
    }

    function totalRaised() public view returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            if (_paymentTokens[i] != _fcqToken) {
                result = result.add(_tokenRaised[address(_paymentTokens[i])]);
            }
        }
        return result.add(_tokenRaised[address(_fcqToken)]);
    }

    function paymentTokens() public view returns (IERC20[] memory) {
        return _paymentTokens;
    }

    function fcqToken() public view returns (IERC20) {
        return _fcqToken;
    }

    function tokenRate(address tokenAddress) public view returns (int256) {
        return _tokenRates[tokenAddress];
    }

    function wallet() public view returns (address payable) {
        return _wallet;
    }

    function getAmountPaidInUSD(uint256 accountId)
    public
    view
    returns (uint256)
    {
        uint256 result = 0;
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            if (_paymentTokens[i] != _fcqToken) {
                result = result.add(
                    fromTokenToUSD(
                        _paid[address(_paymentTokens[i])][accountId],
                        _tokenRates[address(_paymentTokens[i])]
                    )
                );
            }
        }
        return
        result.add(
            fromTokenToUSD(
                _paid[address(_fcqToken)][accountId],
                _tokenRates[address(_fcqToken)]
            )
        );
    }

    function token() public view returns (address) {
        return address(_equityToken);
    }

    function name() public view returns (bytes32) {
        return _name;
    }

    function fromTokenToUSD(uint256 value, int256 rate)
    public
    pure
    returns (uint256)
    {
        if (rate > 0) {
            return value.mul(uint256(rate));
        }
        return value.div(uint256(- rate));
    }

    function fromUSDToToken(uint256 value, int256 rate)
    public
    pure
    returns (uint256)
    {
        if (rate < 0) {
            return value.mul(uint256(- rate));
        }
        return value.div(uint256(rate));
    }

    /************************************************************************************************/

    /************************************* INTERNAL FUNCTIONS ***************************************/

    function _processPayment(PaymentInfo memory info) internal {
        // value to pay in USD with 6 decimals
        uint256 toPay = info.amountToPay.sub(getAmountPaidInUSD(info.accountId));

        uint256 amountInUSD = fromTokenToUSD(info.value, _tokenRates[address(info.tokenAddress)]);
        if (amountInUSD > toPay) {
            amountInUSD = toPay;
            info.value = fromUSDToToken(amountInUSD, _tokenRates[address(info.tokenAddress)]);
        }

        _paid[address(info.tokenAddress)][info.accountId] = _paid[address(info.tokenAddress)][info.accountId].add(info.value);
        _paidByInvestor[address(info.tokenAddress)][info.sender] = _paidByInvestor[address(info.tokenAddress)][info.sender].add(info.value);

        if (getAmountPaidInUSD(info.accountId) == info.amountToPay) {
            _tokenRaised[address(info.tokenAddress)] = _tokenRaised[address(info.tokenAddress)]
            .add(_paid[address(info.tokenAddress)][info.accountId]);
            _processPurchase(info.sender, info.accountId, info.tokensToBuy);
        }
        info.tokenAddress.transferFrom(info.sender, address(this), info.value);
        emit PaymentAccepted(info.sender, info.accountId, address(info.tokenAddress), info.value);
    }

    function _preValidatePayment(PaymentInfo memory info) internal view virtual {
        require(
            !isBlocklistedWallet(info.sender) && !isBlocklistedAccount(info.accountId),
            "InvestmentFundraise: invalid fundraise account"
        );
        require(
            info.value > 0,
            "InvestmentFundraise: amount should be grater than 0"
        );
        require(
            block.timestamp <= _endTime,
            "InvestmentFundraise: time to invest has ended"
        );
        require(
            totalRaised().add(info.amountToPay) <= _cap,
            "InvestmentFundraise: cap exceeded"
        );
        require(!_finalized, "InvestmentFundraise: already finalized");
        require(
            _isPaymentToken[address(info.tokenAddress)],
            "InvestmentFundraise: token address is not accepted for payment"
        );
    }

    function _processPurchase(address sender, uint256 accountId, uint256 tokensToBuy) internal {
        _isPaid[accountId] = true;
        _balances[accountId] = _balances[accountId].add(
            tokensToBuy
        );
        emit TokensPurchased(
            sender,
            accountId,
            tokensToBuy
        );
    }

    function bytesToUint256(bytes memory data)
    internal
    pure
    returns (uint256 value)
    {
        assembly {
            value := mload(add(data, 0x20))
        }
    }
    /************************************************************************************************/

    function verifyPersonalSign(address target, bytes32 hashStruct, uint8 v, bytes32 r, bytes32 s) internal pure returns (bool) {
        bytes32 hash = prefixed(hashStruct);
        address signer = ecrecover(hash, v, r, s);
        return (signer != address(0) && signer == target);
    }

    // Builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}
