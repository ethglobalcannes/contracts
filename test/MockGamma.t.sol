// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockGamma} from "../src/MockGamma.sol";
import {AttestationVerifier, ITeeExtensionRegistry} from "../src/AttestationVerifier.sol";

contract MockGammaTest is Test {
    MockGamma public gamma;
    AttestationVerifier public verifier;

    uint256 constant TEE_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address teeAddr;

    address taker = address(0xBEEF);
    address fxrp = address(0xF00D);
    address usdc = address(0xCA5E);

    function setUp() public {
        teeAddr = vm.addr(TEE_PK);

        // Deploy MockGamma first (need its address for verifier domain)
        gamma = new MockGamma(address(0));

        // Deploy verifier with MockGamma as verifyingContract
        verifier = new AttestationVerifier(address(0), bytes32(0), address(gamma));
        verifier.setTeeKeyOverride(teeAddr);

        // Wire them together
        gamma.setVerifier(address(verifier));
    }

    function _makeQuote() internal view returns (MockGamma.Quote memory) {
        return MockGamma.Quote({
            assetAddress: fxrp,
            chainId: block.chainid,
            isPut: false,
            strike: 2_000000000000000000,
            expiry: block.timestamp + 1 days,
            maker: teeAddr,
            nonce: 1,
            price: 50000000000000000,
            quantity: 1000000000000000000,
            isTakerBuy: true,
            validUntil: block.timestamp + 30,
            usd: 0,
            collateralAsset: usdc
        });
    }

    function _toVerifierQuote(MockGamma.Quote memory q) internal pure returns (AttestationVerifier.Quote memory) {
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

    function _signQuote(MockGamma.Quote memory q) internal view returns (bytes memory) {
        bytes32 digest = verifier.getDigest(_toVerifierQuote(q));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEE_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    // ── Happy path ──────────────────────────────────

    function test_fillRFQ_happyPath() public {
        MockGamma.Quote memory q = _makeQuote();
        bytes memory sig = _signQuote(q);

        vm.prank(taker);
        gamma.fillRFQ(q, sig);

        bytes32 quoteHash = keccak256(bytes.concat(
            abi.encode(q.assetAddress, q.chainId, q.isPut, q.strike, q.expiry, q.maker, q.nonce),
            abi.encode(q.price, q.quantity, q.isTakerBuy, q.validUntil, q.usd, q.collateralAsset)
        ));
        assertTrue(gamma.filledQuotes(quoteHash));

        (address t, address m, uint256 p, uint256 qty,,, bool isPut,) = gamma.quoteRecords(quoteHash);
        assertEq(t, taker);
        assertEq(m, teeAddr);
        assertEq(p, q.price);
        assertEq(qty, q.quantity);
        assertFalse(isPut);
    }

    function test_fillRFQ_emitsEvent() public {
        MockGamma.Quote memory q = _makeQuote();
        bytes memory sig = _signQuote(q);

        vm.expectEmit(true, true, true, true);
        emit MockGamma.OptionFilled(
            keccak256(bytes.concat(
                abi.encode(q.assetAddress, q.chainId, q.isPut, q.strike, q.expiry, q.maker, q.nonce),
                abi.encode(q.price, q.quantity, q.isTakerBuy, q.validUntil, q.usd, q.collateralAsset)
            )),
            taker, teeAddr, q.price, q.quantity, q.strike, q.expiry, false
        );

        vm.prank(taker);
        gamma.fillRFQ(q, sig);
    }

    function test_verifyQuote_standalone() public view {
        MockGamma.Quote memory q = _makeQuote();
        AttestationVerifier.Quote memory vq = _toVerifierQuote(q);
        bytes memory sig = _signQuote(q);

        (bool valid, address signer) = verifier.verifyQuote(vq, sig);
        assertTrue(valid);
        assertEq(signer, teeAddr);
    }

    function test_recoverQuoteSigner() public view {
        MockGamma.Quote memory q = _makeQuote();
        bytes memory sig = _signQuote(q);

        address recovered = verifier.recoverQuoteSigner(_toVerifierQuote(q), sig);
        assertEq(recovered, teeAddr);
    }

    // ── Revert cases ────────────────────────────────

    function test_fillRFQ_revert_doubleFill() public {
        MockGamma.Quote memory q = _makeQuote();
        bytes memory sig = _signQuote(q);

        vm.prank(taker);
        gamma.fillRFQ(q, sig);

        vm.expectRevert(MockGamma.AlreadyFilled.selector);
        vm.prank(taker);
        gamma.fillRFQ(q, sig);
    }

    function test_fillRFQ_revert_expired() public {
        MockGamma.Quote memory q = _makeQuote();
        q.validUntil = block.timestamp - 1;
        bytes memory sig = _signQuote(q);

        vm.expectRevert(MockGamma.QuoteExpired.selector);
        vm.prank(taker);
        gamma.fillRFQ(q, sig);
    }

    function test_fillRFQ_revert_wrongSigner() public {
        MockGamma.Quote memory q = _makeQuote();

        uint256 wrongPk = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
        bytes32 digest = verifier.getDigest(_toVerifierQuote(q));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(); // AttestationFailed
        vm.prank(taker);
        gamma.fillRFQ(q, sig);
    }

    function test_verifyQuote_returnsFalse_wrongSigner() public view {
        MockGamma.Quote memory q = _makeQuote();
        AttestationVerifier.Quote memory vq = _toVerifierQuote(q);

        uint256 wrongPk = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
        bytes32 digest = verifier.getDigest(vq);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        (bool valid,) = verifier.verifyQuote(vq, sig);
        assertFalse(valid);
    }

    // ── Registry integration ────────────────────────

    function test_fillRFQ_withRegistry() public {
        bytes32 extId = bytes32("test-extension");

        MockGamma g2 = new MockGamma(address(0));
        AttestationVerifier v2 = new AttestationVerifier(address(0x1234), extId, address(g2));
        g2.setVerifier(address(v2));

        vm.mockCall(
            address(0x1234),
            abi.encodeWithSelector(ITeeExtensionRegistry.getKeyForExtension.selector, extId),
            abi.encode(teeAddr)
        );

        MockGamma.Quote memory q = _makeQuote();
        AttestationVerifier.Quote memory vq = _toVerifierQuote(q);
        bytes32 digest = v2.getDigest(vq);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEE_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(taker);
        g2.fillRFQ(q, sig);
    }

    // ── Admin ───────────────────────────────────────

    function test_setVerifier_onlyOwner() public {
        vm.prank(taker);
        vm.expectRevert(MockGamma.NotOwner.selector);
        gamma.setVerifier(address(0x999));
    }

    function test_setTeeKeyOverride_onlyOwner() public {
        vm.prank(taker);
        vm.expectRevert(AttestationVerifier.NotOwner.selector);
        verifier.setTeeKeyOverride(address(0x999));
    }

    // ── Put option ──────────────────────────────────

    function test_fillRFQ_putOption() public {
        MockGamma.Quote memory q = _makeQuote();
        q.isPut = true;
        bytes memory sig = _signQuote(q);

        vm.prank(taker);
        gamma.fillRFQ(q, sig);
    }

    // ── Verifier not set ────────────────────────────

    function test_fillRFQ_revert_verifierNotSet() public {
        MockGamma g2 = new MockGamma(address(0));
        MockGamma.Quote memory q = _makeQuote();
        bytes memory sig = _signQuote(q);

        vm.expectRevert(MockGamma.VerifierNotSet.selector);
        vm.prank(taker);
        g2.fillRFQ(q, sig);


        (bytes4 selector) = MockGamma.fillRFQ.selector;
    }
}
