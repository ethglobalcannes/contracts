// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Relay {
    bytes32 public constant OP_TYPE_PRICING = bytes32("PRICING");
    bytes32 public constant OP_COMMAND_QUOTE = bytes32("QUOTE");

    enum RFQStatus {
        None,
        Active,
        Quoted,
        Cancelled
    }

    struct RFQ {
        address requester;
        address asset;
        uint256 strike;
        uint256 expiry;
        uint256 quantity;
        bool isPut;
        RFQStatus status;
    }

    error NotOwner();
    error NotSmartAccount();
    error NotQuotePublisher();
    error ZeroAddress();
    error InvalidExpiry();
    error InvalidStrike();
    error InvalidQuantity();
    error InvalidPrice();
    error RFQNotActive();
    error RFQNotFound();
    error RFQAlreadyFinalized();

    event SmartAccountUpdated(address indexed oldSmartAccount, address indexed newSmartAccount);
    event QuotePublisherUpdated(address indexed oldQuotePublisher, address indexed newQuotePublisher);
    event TeeInstructionsSent(
        bytes32 indexed rfqId,
        bytes32 opType,
        bytes32 opCommand,
        bytes payload
    );
    event QuoteSigned(
        bytes32 indexed rfqId,
        address indexed maker,
        uint256 price,
        uint256 strike,
        uint256 expiry,
        bool isPut,
        bytes signature,
        bytes attestationToken
    );
    event RFQCancelled(bytes32 indexed rfqId);

    address public owner;
    address public smartAccount;
    address public quotePublisher;
    uint256 public nextNonce;

    mapping(bytes32 => RFQ) public rfqs;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlySmartAccount() {
        if (msg.sender != smartAccount) revert NotSmartAccount();
        _;
    }

    modifier onlyQuotePublisher() {
        if (msg.sender != quotePublisher) revert NotQuotePublisher();
        _;
    }

    constructor(address smartAccount_, address quotePublisher_) {
        owner = msg.sender;
        smartAccount = smartAccount_;
        quotePublisher = quotePublisher_;
    }

    function submitRFQ(
        address asset,
        uint256 strike,
        uint256 expiry,
        bool isPut,
        uint256 quantity
    ) external onlySmartAccount returns (bytes32 rfqId) {
        if (asset == address(0)) revert ZeroAddress();
        if (strike == 0) revert InvalidStrike();
        if (quantity == 0) revert InvalidQuantity();
        if (expiry <= block.timestamp) revert InvalidExpiry();

        uint256 nonce = nextNonce;
        unchecked {
            nextNonce = nonce + 1;
        }

        rfqId = keccak256(
            abi.encode(address(this), block.chainid, nonce, asset, strike, expiry, isPut, quantity)
        );

        rfqs[rfqId] = RFQ({
            requester: msg.sender,
            asset: asset,
            strike: strike,
            expiry: expiry,
            quantity: quantity,
            isPut: isPut,
            status: RFQStatus.Active
        });

        bytes memory payload = abi.encode(asset, strike, expiry, isPut, quantity, rfqId);
        emit TeeInstructionsSent(rfqId, OP_TYPE_PRICING, OP_COMMAND_QUOTE, payload);
    }

    function publishQuote(
        bytes32 rfqId,
        address maker,
        uint256 price,
        bytes calldata signature,
        bytes calldata attestationToken
    ) external onlyQuotePublisher {
        RFQ storage rfq = rfqs[rfqId];
        if (rfq.status == RFQStatus.None) revert RFQNotFound();
        if (rfq.status != RFQStatus.Active) revert RFQNotActive();
        if (maker == address(0)) revert ZeroAddress();
        if (price == 0) revert InvalidPrice();

        rfq.status = RFQStatus.Quoted;

        emit QuoteSigned(
            rfqId,
            maker,
            price,
            rfq.strike,
            rfq.expiry,
            rfq.isPut,
            signature,
            attestationToken
        );
    }

    function cancelRFQ(bytes32 rfqId) external onlySmartAccount {
        RFQ storage rfq = rfqs[rfqId];
        if (rfq.status == RFQStatus.None) revert RFQNotFound();
        if (rfq.status == RFQStatus.Quoted || rfq.status == RFQStatus.Cancelled) {
            revert RFQAlreadyFinalized();
        }

        rfq.status = RFQStatus.Cancelled;
        emit RFQCancelled(rfqId);
    }

    function setSmartAccount(address newSmartAccount) external onlyOwner {
        if (newSmartAccount == address(0)) revert ZeroAddress();

        address oldSmartAccount = smartAccount;
        smartAccount = newSmartAccount;
        emit SmartAccountUpdated(oldSmartAccount, newSmartAccount);
    }

    function setQuotePublisher(address newQuotePublisher) external onlyOwner {
        if (newQuotePublisher == address(0)) revert ZeroAddress();

        address oldQuotePublisher = quotePublisher;
        quotePublisher = newQuotePublisher;
        emit QuotePublisherUpdated(oldQuotePublisher, newQuotePublisher);
    }

    function getRFQ(bytes32 rfqId) external view returns (RFQ memory) {
        return rfqs[rfqId];
    }
}
