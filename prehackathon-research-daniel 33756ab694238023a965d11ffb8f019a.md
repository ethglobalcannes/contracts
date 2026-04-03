# prehackathon-research-daniel

# Pre-Hackathon Research — Daniel

*EthGlobal Cannes — April 3rd, 2026Assumes you’ve read the architecture doc (v4.1). This is the drill-down on your perimeter.*

---

## 0. Your Role in 60 Seconds

You own the **on-chain security layer**. Every other team member depends on contracts you deploy: Marcos calls your relay contract to broadcast RFQs, Hamza’s FCE extension uses your `InstructionSender.sol` (OPType/OPCommand must match), Dex reads your event logs, and Marcos’ Smart Account calls your attestation verifier before settlement. You also own the **primary settlement path** — mock Opyn Gamma contract on Flare chainId 14, since Rysk is not deployed there. If your mock contract is not ready, there is no settlement path.

---

## Contents

```
0. Your Role in 60 Seconds
1. What You Own ................... RelayContract.sol + InstructionSender.sol
                                    AttestationVerifier.sol
                                    MockOptionsContract.sol
                                    Collateral approval flow
2. What You Receive ............... From Hamza: TEE key + OPType/OPCommand constants
                                    From Marcos: Smart Account address + submitRFQ shape
3. What You Produce ............... InstructionSender address + EXTENSION_ID -> Hamza
                                    OPType/OPCommand constants -> Hamza (before deploy)
                                    Relay ABI + address -> Marcos, Dex
                                    Mock contract ABI + address -> Marcos
                                    AttestationVerifier address -> Marcos
4. Interface Contracts ............ submitRFQ signature
                                    TeeInstructionsSent + QuoteSigned events
                                    verifyQuote signature
                                    OPType/OPCommand (bytes32 constants)
                                    EIP-712 domain params
5. Tasks by Risk .................. HIGH: mock contract (primary path), attestation verifier
                                    MEDIUM: relay contract, OPType/OPCommand constants
                                    LOW: collateral approval
6. Fallback ....................... emit-only settlement, hardcoded TEE key
```

---

## 1. What You Own

| Contract | Language | Notes |
| --- | --- | --- |
| `RelayContract.sol` | Solidity / Foundry | `submitRFQ()` from Marcos -> `TeeInstructionsSent` event -> FCE picks up |
| `InstructionSender.sol` | Solidity | From `fce-sign` template — OPType=`PRICING`, OPCommand=`QUOTE`; must match Hamza’s Python config |
| `AttestationVerifier.sol` | Solidity | Checks TEE key in `TeeExtensionRegistry`; validates EIP-712 Quote signature; optional price slippage bound |
| `MockOptionsContract.sol` | Solidity / Foundry | Opyn Gamma-compatible interface on Flare chainId 14 — the primary settlement path |
| Collateral approval | Solidity | ERC20 `approve` -> mock margin pool |

**What you do NOT own:** TEE agent (Hamza), frontend (Dex), Smart Account setup (Marcos).

---

## 2. What You Receive

### From Hamza — coordinate immediately, before deploy

| Item | Why you need it |
| --- | --- |
| `OPType` value | Hardcode in `InstructionSender.sol` as `bytes32("PRICING")` — must match Hamza’s Python exactly |
| `OPCommand` value | Hardcode as `bytes32("QUOTE")` — must match Hamza’s Python exactly |
| TEE public key / `EXTENSION_ID` | `AttestationVerifier.sol` looks up this key in `TeeExtensionRegistry` |

**OPType/OPCommand must be agreed BEFORE either of you deploys.** If they differ by a single character, Hamza’s FCE handler never receives the instruction — silent failure.

### From Marcos — before you finalise relay contract

| Item | Why you need it |
| --- | --- |
| Smart Account address | `onlySmartAccount` modifier in `RelayContract.sol` — only Marcos’ SA can call `submitRFQ` |
| `submitRFQ` parameter types | Function signature agreement — once deployed, cannot change |

---

## 3. What You Produce

### To Hamza — InstructionSender.sol address + EXTENSION_ID

Deploy `InstructionSender.sol` via `go run ./cmd/deploy-contract` (from `fce-sign/go/tools`). Give Hamza:

```
# These go into Hamza's .env
INSTRUCTION_SENDER=0x...   # deployed address on Coston2
EXTENSION_ID=0x...         # generated after: go run ./cmd/register-extension
```

These are required for Hamza to complete steps 3-8 of the FCE registration flow.

### To Hamza — OPType/OPCommand constants (agree before deploy)

```solidity
// In InstructionSender.sol — these bytes32 values must match Hamza's Python config
bytes32 constant OP_TYPE_PRICING  = bytes32("PRICING");
bytes32 constant OP_COMMAND_QUOTE = bytes32("QUOTE");
```

### To Marcos — relay contract ABI + address

After deploying `RelayContract.sol`:

```json
{
  "address": "0x...",
  "abi": [
    "function submitRFQ(address asset, uint256 strike, uint256 expiry, bool isPut, uint256 quantity) external returns (bytes32 rfqId)",
    "event TeeInstructionsSent(bytes32 indexed rfqId, bytes32 opType, bytes32 opCommand, bytes payload)",
    "event QuoteSigned(bytes32 indexed rfqId, address indexed maker, uint256 price, uint256 strike, uint256 expiry, bool isPut, bytes signature, bytes attestationToken)"
  ]
}
```

### To Marcos — mock contract ABI + address

```json
{
  "address": "0x...",
  "abi": [
    "function fillRFQ(tuple(address assetAddress, uint256 chainId, bool isPut, uint256 strike, uint256 expiry, address maker, uint256 nonce, uint256 price, uint256 quantity, bool isTakerBuy, uint256 validUntil, uint256 usd, address collateralAsset) quote, bytes sig) external",
    "event OptionFilled(bytes32 indexed rfqId, address taker, uint256 price, uint256 quantity)"
  ]
}
```

### To Dex — relay ABI + event topic hashes

Same relay ABI as above. Give Dex the deployed address + the exact event topic hashes (keccak256 of event signatures) so she can set up `provider.getLogs()` without guessing.

---

## 4. Interface Contracts

### `submitRFQ` — Marcos calls this, you implement it

```solidity
// RelayContract.sol
mapping(bytes32 => bool) public activeRFQs;

function submitRFQ(
    address assetAddress,  // fXRP token address on Flare chainId 14
    uint256 strike,        // 18 decimals
    uint256 expiry,        // Unix timestamp
    bool    isPut,
    uint256 quantity       // 18 decimals
) external onlySmartAccount returns (bytes32 rfqId) {
    rfqId = keccak256(abi.encodePacked(
        assetAddress, strike, expiry, isPut, quantity, block.timestamp
    ));
    activeRFQs[rfqId] = true;
    bytes memory payload = abi.encode(assetAddress, strike, expiry, isPut, quantity, rfqId);
    emit TeeInstructionsSent(rfqId, OP_TYPE_PRICING, OP_COMMAND_QUOTE, payload);
}
```

### Events — Dex subscribes, Marcos polls

```solidity
// Emitted by RelayContract — Hamza's FCE listens; Dex shows "computing" state
event TeeInstructionsSent(
    bytes32 indexed rfqId,
    bytes32         opType,    // bytes32("PRICING")
    bytes32         opCommand, // bytes32("QUOTE")
    bytes           payload    // ABI-encoded RFQ fields
);

// Emitted by RelayContract when TEE writes Quote back — Dex + Marcos read this
event QuoteSigned(
    bytes32 indexed rfqId,
    address indexed maker,
    uint256 price,             // call_price_mc, 18 dec
    uint256 strike,            // 18 dec
    uint256 expiry,            // unix ts
    bool    isPut,
    bytes   signature,         // EIP-712 sig from TEE key
    bytes   attestationToken   // FCE attestation token
);
```

### `verifyQuote` — Marcos calls this, you implement it

```solidity
// AttestationVerifier.sol
function verifyQuote(
    Quote memory  quote,
    bytes memory  sig
) external view returns (bool) {
    // 1. Recover signer from EIP-712 Quote hash + sig
    bytes32 digest = _hashTypedDataV4(_hashQuote(quote));
    address signer = ECDSA.recover(digest, sig);

    // 2. Verify signer is the registered TEE key for our extension
    address teeKey = ITeeExtensionRegistry(REGISTRY).getKeyForExtension(EXTENSION_ID);
    require(signer == teeKey, "signer is not registered TEE key");

    // 3. Optional: price slippage check (add if time permits)
    // uint256 spot = IFtsoV2(FTSO).getFeedByIdInWei(XRP_USD_FEED_ID);
    // require(quote.price <= computedFairValue * 110 / 100, "price out of band");

    return true;
}
```

### EIP-712 domain — must match Hamza’s Python EXACTLY

```solidity
// In AttestationVerifier.sol AND MockOptionsContract.sol — must be identical
string  constant EIP712_NAME    = "rysk";
string  constant EIP712_VERSION = "0.0.0";
// chainId: agree with Hamza — 114 for Coston2, 14 for Flare mainnet
// verifyingContract: your mock contract address (set after mock is deployed)
```

**This is the most common integration failure.** If Hamza’s Python uses `chainId=114` but your Solidity uses `chainId=14`, every `ecrecover` returns the wrong address and every `verifyQuote` returns false. Agree `chainId` and `verifyingContract` with Hamza before either of you writes a single line of signing code.

**Foundry test to validate before writing production code:**

```solidity
function test_verifyQuote_happyPath() public {
    uint256 testKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address tester  = vm.addr(testKey);

    // Pretend tester is the registered TEE key
    vm.mockCall(
        REGISTRY,
        abi.encodeWithSelector(ITeeExtensionRegistry.getKeyForExtension.selector, EXTENSION_ID),
        abi.encode(tester)
    );

    Quote memory q = Quote({...});  // fill with test values
    bytes32 digest = verifier.hashQuote(q);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(testKey, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    assertTrue(verifier.verifyQuote(q, sig));
}
```

If this test passes with the same domain params Hamza uses in Python, the production integration will pass.

### TeeExtensionRegistry — read-only interface

```solidity
address constant REGISTRY = 0xdE25c06982Ab8e4b6B4F910896E3f93Ac77FB44d;

interface ITeeExtensionRegistry {
    function getKeyForExtension(bytes32 extensionId) external view returns (address);
}
```

---

## 5. Tasks by Risk

### HIGH — build in parallel from hour 1

**[H1] MockOptionsContract.sol — this IS the primary settlement path**

Rysk is not deployed on Flare chainId 14. Your mock contract IS the settlement path for the demo. Do not treat it as a fallback. Deploy it in the first hour.

Minimum viable interface:

```solidity
// MockOptionsContract.sol
contract MockOptionsContract {
    using ECDSA for bytes32;

    mapping(bytes32 => bool) public filledRFQs;

    function fillRFQ(Quote calldata quote, bytes calldata sig) external {
        bytes32 rfqId = keccak256(abi.encode(quote));
        require(!filledRFQs[rfqId], "already filled");

        // Verify EIP-712 sig (stub: skip for now, add AttestationVerifier call later)
        filledRFQs[rfqId] = true;
        emit OptionFilled(rfqId, msg.sender, quote.price, quote.quantity);
    }

    event OptionFilled(bytes32 indexed rfqId, address taker, uint256 price, uint256 quantity);
}
```

**Deploy this first, even with the signature check stubbed out.** Get it on Coston2, confirm Marcos can call `fillRFQ`. Add the real sig check once `AttestationVerifier` is ready.

**[H2] AttestationVerifier.sol — EIP-712 domain must match Hamza exactly**

Coordinate with Hamza on day 1, BEFORE writing any signing code:
- Which `chainId`? (Coston2 testnet = 114)
- What is `verifyingContract`? (your mock contract address — known after H1 is deployed)

Write and run the Foundry test above with a test private key before wiring up the production flow. One passing test = confidence that production will work.

### MEDIUM — wire after H1, H2 unblocked

**[M1] RelayContract.sol**

Straightforward Solidity. Main risk is access control — only Marcos’ Smart Account should call `submitRFQ`. Use `onlySmartAccount` modifier. Agree with Marcos on their Smart Account address before deploying.

```bash
forge init relay-contracts
forge install OpenZeppelin/openzeppelin-contracts
# Write RelayContract.sol, AttestationVerifier.sol
forge test
forge create RelayContract --rpc-url $COSTON2_RPC --private-key $PK --broadcast
```

**[M2] InstructionSender.sol — OPType/OPCommand constants**

Copied from `fce-sign` template (`go/tools/cmd/deploy-contract` deploys it). Only change the constants:

```solidity
bytes32 constant OP_TYPE_PRICING  = bytes32("PRICING");
bytes32 constant OP_COMMAND_QUOTE = bytes32("QUOTE");
```

Coordinate with Hamza on the exact string values. Run `go run ./cmd/deploy-contract` from `fce-sign/go/tools` — this deployment is part of Hamza’s FCE registration flow.

### LOW — plumbing, build last

**[L1] Collateral approval flow**

```solidity
// In MockOptionsContract.fillRFQ or a pre-approval step
// For demo: stub this out entirely — emit OptionFilled without real transfer
// For production: IERC20(quote.collateralAsset).transferFrom(taker, address(this), amount)
```

The attestation story does not require real ERC20 movement. Stub it for the hackathon and flag as “TODO: real collateral” in the pitch.

---

## 6. Fallback

| Blocker | Degraded path |
| --- | --- |
| Mock Opyn Gamma interface mismatch | Strip `fillRFQ` entirely — emit `OptionFilled` with hardcoded values. Attestation verifier still proves TEE honesty. Settlement becomes cosmetic. |
| EIP-712 domain mismatch with Hamza | Skip `verifyQuote` in the gate; display the Quote and sig on Dex’s frontend for manual judge verification via attestation deeplink. |
| `TeeExtensionRegistry.getKeyForExtension` reverts | Hardcode TEE key address in `AttestationVerifier` for demo — log the registry integration as “TODO production hardening”. |
| Foundry deploy fails on Coston2 | Deploy via Remix IDE — paste contract, compile with 0.8.x, deploy to Coston2 in 5 minutes. Have this as backup. |
| Marcos’ Smart Account address unknown | Remove `onlySmartAccount` modifier — open access for demo. Add back for production. Never push to mainnet without access control. |