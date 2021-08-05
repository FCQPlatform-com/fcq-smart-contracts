//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

interface IRoles {
    // Check if address has Admin role. 
    // Admin manages all roles.    
    function isAdmin(address addr) external view returns (bool);

    // Check if address has Operator role.
    // Operator address works in the name of contract owner, can perform manual operations like finalizing STO. 
    function isOperator(address addr) external view returns (bool);

    // Check if address has Platfrom role.
    // Platform address performs automatic operations like add new investment offer, pay dividends.
    function isPlatform(address addr) external view returns (bool);
}
