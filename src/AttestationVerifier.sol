// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface ITeeExtensionRegistry {
    function getKeyForExtension(bytes32 extensionId) external view returns (address);
}

contract AttestationVerifier {
    // ──────────────────────────────────────────────
    // Rysk EIP-712 Quote struct — field order matters
    // ──────────────────────────────────────────────
    struct Quote {
        address assetAddress;
        uint256 chainId;
        bool isPut;
        uint256 strike;       // 18 decimals
        uint256 expiry;       // unix timestamp
        address maker;
        uint256 nonce;
        uint256 price;        // premium, 18 decimals
        uint256 quantity;     // 18 decimals
        bool isTakerBuy;
        uint256 validUntil;   // unix timestamp
        uint256 usd;
        address collateralAsset;
    }

    bytes32 public constant QUOTE_TYPEHASH = keccak256(
        "Quote(address assetAddress,uint256 chainId,bool isPut,uint256 strike,uint256 expiry,"
        "address maker,uint256 nonce,uint256 price,uint256 quantity,bool isTakerBuy,"
        "uint256 validUntil,uint256 usd,address collateralAsset)"
    );

    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant NAME_HASH = keccak256("rysk");
    bytes32 private constant VERSION_HASH = keccak256("0.0.0");

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────
    address public owner;
    ITeeExtensionRegistry public registry;
    bytes32 public extensionId;
    address public teeKeyOverride;
    address public verifyingContract; // MockGamma address

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────
    error NotOwner();
    error VerifyingContractNotSet();

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────
    constructor(
        address registry_,
        bytes32 extensionId_,
        address verifyingContract_
    ) {
        owner = msg.sender;
        if (registry_ != address(0)) {
            registry = ITeeExtensionRegistry(registry_);
        }
        extensionId = extensionId_;
        verifyingContract = verifyingContract_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ──────────────────────────────────────────────
    // Core: verify a TEE-signed quote
    // ──────────────────────────────────────────────
    function verifyQuote(Quote calldata quote, bytes calldata sig) external view returns (bool valid, address signer) {
        signer = recoverQuoteSigner(quote, sig);
        valid = (signer == _getTeeKey());
    }

    function recoverQuoteSigner(Quote calldata quote, bytes calldata sig) public view returns (address) {
        bytes32 digest = getDigest(quote);
        return ECDSA.recover(digest, sig);
    }

    // ──────────────────────────────────────────────
    // EIP-712 hashing
    // ──────────────────────────────────────────────
    function getDigest(Quote calldata q) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            getDomainSeparator(),
            hashQuote(q)
        ));
    }

    function hashQuote(Quote calldata q) public pure returns (bytes32) {
        bytes memory first = abi.encode(
            QUOTE_TYPEHASH,
            q.assetAddress,
            q.chainId,
            q.isPut,
            q.strike,
            q.expiry,
            q.maker,
            q.nonce
        );
        bytes memory second = abi.encode(
            q.price,
            q.quantity,
            q.isTakerBuy,
            q.validUntil,
            q.usd,
            q.collateralAsset
        );
        return keccak256(bytes.concat(first, second));
    }

    function getDomainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            NAME_HASH,
            VERSION_HASH,
            block.chainid,
            verifyingContract
        ));
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────
    function setTeeKeyOverride(address key) external onlyOwner {
        teeKeyOverride = key;
    }

    function setRegistry(address registry_, bytes32 extensionId_) external onlyOwner {
        registry = ITeeExtensionRegistry(registry_);
        extensionId = extensionId_;
    }

    function setVerifyingContract(address verifyingContract_) external onlyOwner {
        verifyingContract = verifyingContract_;
    }

    // ──────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────
    function _getTeeKey() internal view returns (address) {
        if (teeKeyOverride != address(0)) {
            return teeKeyOverride;
        }
        if (address(registry) != address(0)) {
            return registry.getKeyForExtension(extensionId);
        }
        return address(0);
    }
}
