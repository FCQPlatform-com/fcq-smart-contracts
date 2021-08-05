//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

interface INotary {
    event Document(bytes32 indexed name, string uri, bytes32 documentHash);

    function getDocument(bytes32 name) external view returns (string memory, bytes32);
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) external;
}