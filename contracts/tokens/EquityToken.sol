//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "eth-token-recover/contracts/TokenRecover.sol";
import "./IEquityToken.sol";
import "./transferValidator/ITransferValidator.sol";

// This token represents equity in investment.
contract EquityToken is IEquityToken, ERC20, TokenRecover {
    using SafeMath for uint256;

    bool _isIssuable;
    address _issuer;
    ITransferValidator _validator;

    /************************************* Dividends ************************************/
    // Token used for dividends payment
    IERC20 _usdtToken;
    // With `multiplier`, we can properly distribute dividends even if the amount to distribute is small.
    // It solves rounding error problem.
    uint256 _multiplier = 1000000000000000000;
    // Amount of dividend per token. This amount is increased everytime owner call distributeDividends.
    uint256 _dividendPerShare;

    // Mapping from address to withdrawn dividends
    mapping(address => uint256) _withdrawnDividends;
    // Mapping from address to dividend balance
    mapping(address => uint256) _dividendBalance;
    // Mapping from address to last dividend update
    mapping(address => uint256) _lastDividendPerShare;
    /************************************************************************************/

    modifier onlyIssuer() {
        require(isIssuer(msg.sender), "EquityToken: caller not issuer");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address validator,
        IERC20 usdtToken
    )
        ERC20(name, symbol)
    {
        _setupDecimals(0);
        _validator = ITransferValidator(validator);
        _isIssuable = true;
        _usdtToken = usdtToken;
    }

    function setTransferValidator(address validator) 
        external override
        onlyOwner
        returns (bool) 
    {
        _validator = ITransferValidator(validator);

        emit TransferValidatorReplaced(validator);
        return true;
    }

    /********************************** Transfers **********************************/
    function transfer(address to, uint256 value) public override returns (bool) {
        _validator.tokensToTransfer(msg.sender, address(this), msg.sender, to, value, "");
        _updateDividend(msg.sender);
        _updateDividend(to);
        super.transfer(to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _validator.tokensToTransfer(msg.sender, address(this), from, to, value, "");
        _updateDividend(from);
        _updateDividend(to);
        super.transferFrom(from, to, value);
        return true;
    }

    /**
     * @dev Transfer the amount of tokens from the address 'msg.sender' to the address 'to'.
     * @param to Token recipient.
     * @param value Number of tokens to transfer.
     * @param data Information attached to the transfer, by the token holder.
    */
    function transferWithData(address to, uint256 value, bytes calldata data) external override {
        _validator.tokensToTransfer(msg.sender, address(this), msg.sender, to, value, data);
        _updateDividend(msg.sender);
        _updateDividend(to);
        super.transfer(to, value);
    }

   /**
    * @dev Transfer the amount of tokens on behalf of the address 'from' to the address 'to'.
    * @param from Token holder (or 'address(0)' to set from to 'msg.sender').
    * @param to Token recipient.
    * @param value Number of tokens to transfer.
    * @param data Information attached to the transfer, and intended for the token holder ('from').
    */
    function transferFromWithData(address from, address to, uint256 value, bytes calldata data) external override {
        _validator.tokensToTransfer(msg.sender, address(this), from, to, value, data);
        _updateDividend(from);
        _updateDividend(to);
        super.transferFrom(from, to, value);
    }
    /************************************************************************************/

    /********************************** Token Issuence **********************************/
    function isIssuable() external view override returns (bool) {
        return _isIssuable;
    }

    function isIssuer(address addr) public view returns (bool) {
        return addr == _issuer;
    }

    function setIssuer(address issuer) external onlyOwner {
        require(issuer != address(0), "EquityToken: issuer cannot be zero address");
        _issuer = issuer;
    }

    /**
     * @dev Issue tokens.
     * @param tokenHolder Address for which we want to issue tokens.
     * @param value Number of tokens issued.
     * @param data Information attached to the issuance, by the issuer.
     */
    function issue(address tokenHolder, uint256 value, bytes calldata data) 
        external override
        onlyIssuer
    {
        require(_isIssuable, "EquityToken: token not issuable");
        _mint(tokenHolder, value);
        emit Issued(msg.sender, tokenHolder, value, data);
    }

    function renounceIssuance() external onlyIssuer {
        _isIssuable = false;
    }
    /************************************************************************************/

    /******************************** Transfers validity ********************************/
    function canTransfer(address to, uint256 value, bytes calldata data) 
        external view override 
        returns (bool, byte, bytes32) 
    {
        return _canTransfer(msg.sender, to, value, data);
    }

    function canTransferFrom(address from, address to, uint256 value, bytes calldata data) 
        external view override 
        returns (bool, byte, bytes32) 
    {
        return _canTransfer(from, to, value, data);
    }
    /************************************************************************************/

    /************************************* Dividends ************************************/
    function dividendOf(address investor) public view override returns(uint256) {
        return _dividendsOwing(investor).add(_dividendBalance[investor]).sub(_withdrawnDividends[investor]);
    }

    function distributeDividends(uint256 amount) external override onlyOwner {
        _dividendPerShare = _dividendPerShare.add((amount.mul(_multiplier)).div(totalSupply()));
        emit DividendsDistributed(msg.sender, amount);
    }

    function withdrawDividend(address investor) public override {
        uint256 amount = dividendOf(investor);
        require(amount > 0, "EquityToken: no dividand to withdraw");
        _withdrawnDividends[investor] = _withdrawnDividends[investor].add(amount);
        _usdtToken.transfer(investor, amount);
    }

    function withdrawDividends(address[] memory investors) external {
        for (uint i = 0; i<investors.length; i++) {
            withdrawDividend(investors[i]);
        }
    }

    function withdrawnDividendOf(address investor) external view override returns(uint256) {
        return _withdrawnDividends[investor];
    }
    /************************************************************************************/

    /******************************** INTERNAL FUNCTIONS ********************************/
    function _canTransfer(address from, address to, uint256 value, bytes memory data) 
        internal view
        returns (bool, byte, bytes32) 
    {
        if (from != msg.sender && value > allowance(from, msg.sender))
            return (false, 0x53, bytes32(0));

        else if (from == msg.sender && balanceOf(from) < value)
            return (false, 0x52, bytes32(0));

        else if (to == address(0))
            return (false, 0x57, bytes32(0));

        else if (!checkAdd(balanceOf(to), value))
            return (false, 0x50, bytes32(0));

        else if (!_validator.canTransfer(msg.sender, address(this), from, to, value, data)) 
            return (false, 0x54, bytes32(0));
        
        return (true, 0x51, bytes32(0));
    }

    function _dividendsOwing(address investor) internal view returns(uint256) {
        uint256 dividendPerShare = _dividendPerShare.sub(_lastDividendPerShare[investor]);
        return (balanceOf(investor).mul(dividendPerShare)).div(_multiplier);
    }

    function _updateDividend(address investor) internal {
        uint256 owing = _dividendsOwing(investor);
        if (owing > 0) {
            _dividendBalance[investor] = _dividendBalance[investor].add(owing);
            _lastDividendPerShare[investor] = _dividendPerShare;
        }
    }

    function checkAdd(uint256 a, uint256 b) internal pure returns (bool) {
        uint256 c = a + b;
        if (c < a)
            return false;
        else
            return true;
    }
}