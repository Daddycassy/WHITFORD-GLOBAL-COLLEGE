// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Whitford Global College Credential (ERC-721, soulbound)
// One unique token per award (certificate, diploma, degree). Holds only a document hash,
// the programme code, the NFQ level and the award date. No name or grades on-chain.
// The document hash must be a SALTED hash made off-chain, so that it cannot be guessed.
// Built on OpenZeppelin Contracts v5. In Remix the imports below resolve automatically.

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract WhitfordCredential is ERC721, Ownable, Pausable {
    struct Credential {
        bytes32 documentHash;   // salted hash of the official certificate file (kept off-chain)
        string programmeCode;   // e.g. "MSC-DATA-L9"
        uint8 nfqLevel;         // National Framework of Qualifications level, 1 to 10
        uint64 awardDate;       // unix timestamp
        bool revoked;           // set by the registrar if an award is withdrawn
    }

    uint256 private _nextId = 1;
    mapping(uint256 => Credential) public credentials;
    mapping(bytes32 => uint256) public tokenByHash;       // lets an employer look up a document by its hash
    mapping(string => string) public programmeURI;        // IPFS metadata link, one design per programme

    event CredentialIssued(uint256 indexed tokenId, address indexed student, string programmeCode, uint8 nfqLevel);
    event CredentialRevoked(uint256 indexed tokenId, string reason);
    event CredentialReissued(uint256 indexed oldId, uint256 indexed newId, address indexed newWallet);

    // 'registrar' is the issuing address. In production this should be a multisig wallet.
    constructor(address registrar)
        ERC721("Whitford Global College Credential", "WGCCRED")
        Ownable(registrar)
    {}

    // Link a programme to its IPFS metadata, e.g. ipfs://<CID>/MSC-DATA-L9.json
    function setProgrammeURI(string calldata programmeCode, string calldata uri) external onlyOwner {
        programmeURI[programmeCode] = uri;
    }

    // The registrar issues a credential to the student's own wallet after the award is approved.
    function issue(
        address to,
        bytes32 documentHash,
        string calldata programmeCode,
        uint8 nfqLevel,
        uint64 awardDate
    ) external onlyOwner whenNotPaused returns (uint256 tokenId) {
        require(tokenByHash[documentHash] == 0, "Document already registered");
        require(nfqLevel >= 1 && nfqLevel <= 10, "Invalid NFQ level");
        require(awardDate <= block.timestamp, "Award date in the future");
        tokenId = _nextId++;
        credentials[tokenId] = Credential(documentHash, programmeCode, nfqLevel, awardDate, false);
        tokenByHash[documentHash] = tokenId;
        _mint(to, tokenId);
        emit CredentialIssued(tokenId, to, programmeCode, nfqLevel);
    }

    // Withdraw an award (for example after an academic misconduct finding).
    // The token stays on the chain but verification now reports it as invalid.
    function revoke(uint256 tokenId, string calldata reason) external onlyOwner {
        _requireOwned(tokenId);
        credentials[tokenId].revoked = true;
        emit CredentialRevoked(tokenId, reason);
    }

    // Lost wallet: because the credential is soulbound, the student cannot move it.
    // After re-verifying the student, the registrar burns the old token and issues a new one.
    function reissue(uint256 oldId, address newWallet)
        external
        onlyOwner
        whenNotPaused
        returns (uint256 newId)
    {
        _requireOwned(oldId);
        Credential memory c = credentials[oldId];
        require(!c.revoked, "Credential revoked");
        _burn(oldId);
        newId = _nextId++;
        credentials[newId] = c;
        tokenByHash[c.documentHash] = newId;
        _mint(newWallet, newId);
        emit CredentialReissued(oldId, newId, newWallet);
    }

    // Anyone (an employer, another college, QQI) can check a credential for free.
    function verify(uint256 tokenId)
        external
        view
        returns (bool valid, address holder, string memory programmeCode, uint8 nfqLevel, uint64 awardDate)
    {
        holder = _ownerOf(tokenId);
        if (holder == address(0)) {
            return (false, address(0), "", 0, 0);
        }
        Credential memory c = credentials[tokenId];
        return (!c.revoked, holder, c.programmeCode, c.nfqLevel, c.awardDate);
    }

    // The employer hashes the certificate file they were given (with the salt the student shares)
    // and checks here that the same hash was issued by the college and is still valid.
    function verifyDocument(bytes32 documentHash) external view returns (bool valid, uint256 tokenId) {
        tokenId = tokenByHash[documentHash];
        if (tokenId == 0 || _ownerOf(tokenId) == address(0)) {
            return (false, 0);
        }
        return (!credentials[tokenId].revoked, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return programmeURI[credentials[tokenId].programmeCode];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Soulbound: allow only minting (from == 0) and burning (to == 0). Any transfer reverts.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address)
    {
        address from = _ownerOf(tokenId);
        require(from == address(0) || to == address(0), "Soulbound: transfers disabled");
        return super._update(to, tokenId, auth);
    }
}
