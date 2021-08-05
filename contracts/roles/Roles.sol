//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./IRoles.sol";

// Common roles for the platform.
// It is used to not duplicate the roles logic for every smart contract
contract Roles is IRoles, AccessControl {

    // All automatic operations are done by platform
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");

    // All manual operations are done by operator
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address platform, address operator) {
        // Grant the contract deployer the default admin role: it will be able to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PLATFORM_ROLE, platform);
        _setupRole(OPERATOR_ROLE, operator);
    }

    function isAdmin(address addr) external view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, addr);
    }

    function isOperator(address addr) external view override returns (bool) {
        return hasRole(OPERATOR_ROLE, addr);
    }

    function isPlatform(address addr) external view override returns (bool) {
        return hasRole(PLATFORM_ROLE, addr);
    }

}