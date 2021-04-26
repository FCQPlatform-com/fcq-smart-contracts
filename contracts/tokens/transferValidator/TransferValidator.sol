//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ITransferValidator.sol";

contract TransferValidator is ITransferValidator {

    // Mapping from (token, nonce) to "used" status to ensure a certificate can be used only once 
    mapping(address => mapping(address => uint256)) internal _usedCertificate;
    // Mapping from token to token authorities.
    mapping(address => address[]) internal _tokenAuthorities;
    // Mapping from (token, address) to token authority status.
    mapping(address => mapping(address => bool)) internal _isTokenAuthority;

    function isTokenAuthority(address token, address authority) public view returns(bool) {
        return authority == Ownable(token).owner() || _isTokenAuthority[token][authority];
    }

    function registerTokenAuthorities(address token, address[] calldata authorities) external {
        require(isTokenAuthority(token, msg.sender), "Sender is not a token authority.");
        _setTokenAuthorities(token, authorities);
    }

    function addTokenAuthority(address token, address authority) external {
        require(isTokenAuthority(token, msg.sender), "Sender is not a token authority.");
        _isTokenAuthority[token][authority] = true;
        _tokenAuthorities[token].push(authority);
    }

    function canTransfer(address sender, address token, address from, address to, uint256 value, bytes calldata data)
        external view override
        returns (bool)
    {
        // Transfer can be executed by authority or with authorized certificate
        if (isTokenAuthority(token, sender)) {
            return true;
        }
        return _canValidateCertificateToken(sender, token, from, to, value, data);
    }

    function tokensToTransfer(address msgSender, address token, address from, address to, uint256 value, bytes calldata data) 
        external override 
    {
        // Transfer can be executed by authority or with authorized certificate
        if (isTokenAuthority(token, msgSender)) {
            return;
        }
        require(_canValidateCertificateToken(msgSender, token, from, to, value, data), "TransferValidator: transfer is forbidden - invalid certificate");
        // prevent from reuse the same certificate
        _usedCertificate[token][msgSender] += 1;
    }

    /**
     * @dev Get state of certificate (used or not).
     * @param token Token address.
     * @param sender Address whom to check the counter of.
     * @return uint256 Number of transaction already sent for this token contract.
     */
    function usedCertificateNonce(address token, address sender) external view returns (uint256) {
        return _usedCertificate[token][sender];
    }

    function _canValidateCertificateToken(
        address msgSender,
        address token, 
        address from, 
        address to, 
        uint256 value, 
        bytes memory certificate
    ) 
        internal view 
        returns (bool)
    {
        // Certificate should be 97 bytes long
        // Certificate encoding format is: <expirationTime (32 bytes)>@<r (32 bytes)>@<s (32 bytes)>@<v (1 byte)>
        if (certificate.length != 97) {
            //return false;
        }

        uint256 e;
        uint8 v;

        // Extract certificate information and expiration time from payload
        assembly {
            // Retrieve expirationTime & ECDSA elements from certificate which is a 97 long bytes
            // Certificate encoding format is: <expirationTime (32 bytes)>@<r (32 bytes)>@<s (32 bytes)>@<v (1 byte)>
            e := mload(add(certificate, 0x20))
            v := byte(0, mload(add(certificate, 0x80)))
        }

        // Certificate should not be expired
        if (e < block.timestamp) {
            //return false;
        }

        if (v < 27) {
            v += 27;
        }

        if (v == 27 || v == 28) {
            // Pack and hash
            uint256 nonce = _usedCertificate[token][msgSender];
            bytes memory pack = abi.encodePacked(
                msgSender,
                token,
                from,
                to,
                value,
                e,
                nonce
            );
            bytes32 hash = keccak256(pack);
            bytes memory prefix = "\x19Ethereum Signed Message:\n32";
            bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash));

            bytes32 r;
            bytes32 s;
            // Extract certificate information and expiration time from payload
            assembly {
                // Retrieve ECDSA elements (r, s) from certificate which is a 97 long bytes
                // Certificate encoding format is: <expirationTime (32 bytes)>@<r (32 bytes)>@<s (32 bytes)>@<v (1 byte)>
                r := mload(add(certificate, 0x40))
                s := mload(add(certificate, 0x60))
            }

            // bool res = isTokenAuthority(token, ecrecover(hash, v, r, s));
            return isTokenAuthority(token, ecrecover(prefixedHash, v, r, s));
        }

        return false;
    }

    function _setTokenAuthorities(address token, address[] memory authorities) internal {
        for (uint i = 0; i<_tokenAuthorities[token].length; i++){
            _isTokenAuthority[token][_tokenAuthorities[token][i]] = false;
        }
        for (uint j = 0; j<authorities.length; j++){
            _isTokenAuthority[token][authorities[j]] = true;
        }
        _tokenAuthorities[token] = authorities;
    }
}
