//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "./roles/Roles.sol";
import "./tokens/EquityToken.sol";
import "./investment/InvestmentFundraise.sol";

contract InvestmentFactory {

    event InvestmentCreated(bytes32 indexed name, address indexed contractAddr, address token);

    IRoles _roles;

    mapping(bytes32 => address) investments;

    modifier onlyPlatform() {
        require(_roles.isPlatform(msg.sender), "InvestmentFactory: caller not platform");
        _;
    }

    constructor(address platform, address operator) {
        _roles = new Roles(platform, operator);
    } 

    function create(
        // name should be unique for the investment and the equity token
        bytes32 name,

        // fundraising parameters
        uint256 amountToCollectInUSD,
        uint256 endTime,
        address payable wallet,
        IEquityToken equityToken,
        // first payment token address is FCQ token
        IERC20[] memory paymentTokens,
        // list of payment tokens rates 
        int256[] memory tokenRates
    ) 
        external
        onlyPlatform 
        returns (bool)
    {
        address investmentContract = address(new InvestmentFundraise(
            name,
            amountToCollectInUSD,
            endTime,
            wallet,
            _roles,
            equityToken,
            paymentTokens,
            tokenRates
        ));
        investments[name] = investmentContract;

        emit InvestmentCreated(name, investmentContract, address(equityToken));
        return true;
    }

    function investment(bytes32 name) external view returns(address) {
        return investments[name];
    }

    function roles() external view returns(address) {
        return address(_roles);
    }
}