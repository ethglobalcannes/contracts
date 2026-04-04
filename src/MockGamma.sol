// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AttestationVerifier} from "./AttestationVerifier.sol";

contract MockGamma {
    // Re-export Quote type for callers
    struct Quote {
        address assetAddress;
        uint256 chainId;
        bool isPut;
        uint256 strike;
        uint256 expiry;
        address maker;
        uint256 nonce;
        uint256 price;
        uint256 quantity;
        bool isTakerBuy;
        uint256 validUntil;
        uint256 usd;
        address collateralAsset;
    }

    struct QuoteRecord {
        address taker;
        address maker;
        uint256 price;
        uint256 quantity;
        uint256 strike;
        uint256 expiry;
        bool isPut;
        uint256 filledAt;
    }

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────
    address public owner;
    AttestationVerifier public verifier;

    mapping(bytes32 => bool) public filledQuotes;
    mapping(bytes32 => QuoteRecord) public quoteRecords;

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────
    error AlreadyFilled();
    error QuoteExpired();
    error AttestationFailed(address signer);
    error NotOwner();
    error VerifierNotSet();

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────
    event OptionFilled();

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────
    constructor(address verifier_) {
        owner = msg.sender;
        if (verifier_ != address(0)) {
            verifier = AttestationVerifier(verifier_);
        }
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ──────────────────────────────────────────────
    // Core: fill an RFQ with a TEE-signed quote
    // ──────────────────────────────────────────────
    function fillRFQ() external payable {
        emit OptionFilled();
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────
    function setVerifier(address verifier_) external onlyOwner {
        verifier = AttestationVerifier(verifier_);
    }

    // ──────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────
    function _hashQuote(Quote calldata q) internal pure returns (bytes32) {
        bytes memory first = abi.encode(
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

    function _toVerifierQuote(Quote calldata q) internal pure returns (AttestationVerifier.Quote memory) {
        return AttestationVerifier.Quote({
            assetAddress: q.assetAddress,
            chainId: q.chainId,
            isPut: q.isPut,
            strike: q.strike,
            expiry: q.expiry,
            maker: q.maker,
            nonce: q.nonce,
            price: q.price,
            quantity: q.quantity,
            isTakerBuy: q.isTakerBuy,
            validUntil: q.validUntil,
            usd: q.usd,
            collateralAsset: q.collateralAsset
        });
    }
}
