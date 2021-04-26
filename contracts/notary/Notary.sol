//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "./INotary.sol";
import "../roles/IRoles.sol";

contract Notary is INotary {

    IRoles _roles;

    struct Doc {
        string docURI;
        bytes32 docHash;
    }

    // Mapping from name to documents.
    mapping(bytes32 => Doc) internal _documents;

    constructor(IRoles roles_) {
        _roles = roles_;
    }

    /**
     * @dev Access a document.
     * @param name Short name (represented as a bytes32) associated to the document.
     * @return Requested document + document hash.
     */
    function getDocument(bytes32 name) external override view returns (string memory, bytes32) {
        return (
            _documents[name].docURI,
            _documents[name].docHash
        );
    }

    /**
    * @dev Set a document. Function can be called only by platform or operator.
    * @param name Short name (represented as a bytes32) associated to the document.
    * @param uri Document content.
    * @param documentHash Hash of the document.
    */
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) external override {
        require(_roles.isPlatform(msg.sender) 
            || _roles.isOperator(msg.sender), "Notary: Caller is not a platform or operator");
        require(name != bytes32(0), "Zero value is not allowed");
        
        _documents[name] = Doc({
            docURI: uri,
            docHash: documentHash
        });
        emit Document(name, uri, documentHash);
    }
}