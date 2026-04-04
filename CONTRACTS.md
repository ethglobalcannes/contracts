# Smart Contracts Architecture

All contracts are deployed on **Flare Coston2 (chainId 114)**.

## Deployed Addresses

| Contract | Address |
|---|---|
| Relay | `0x8795e6384Fdc1F902f480c86C24c8F30649C52d8` |
| InstructionSender | `0xFB1b157D9Ac73eE490C764c908a16E6E5097f99E` |
| AttestationVerifier | `0x027f7874bc35A691984f2545c05ac0E3C8616e2f` |
| MockGamma | `0xEe5b0Ba2793267da967E800Ac926620742620D13` |

### Flare System Contracts (not ours)

| Contract | Address |
|---|---|
| TeeExtensionRegistry | `0x3d478d43426081BD5854be9C7c5c183bfe76C981` |
| TeeMachineRegistry | `0x5918Cd58e5caf755b8584649Aa24077822F87613` |
| MasterAccountController | `0x434936d47503353f06750Db1A444DBDC5F0AD37c` |
| FXRP | `0x0b6A3645c240605887a5532109323A3E12273dc7` |

---

## Contract Responsibilities

### 1. InstructionSender

**Purpose:** On-chain entry point that sends instructions to the TEE via Flare's official FCE pipeline.

**How it works:**
- Wraps `TeeExtensionRegistry.sendInstructions()` — the standard Flare way to communicate with TEEs
- Uses `TeeMachineRegistry.getRandomTeeIds()` to pick an available TEE node
- Sends instructions with `OP_TYPE = "PRICING"` and `OP_COMMAND = "QUOTE"`
- After deployment, `setExtensionId()` must be called once (after the extension is registered in the TeeExtensionRegistry)

**Key function:**
- `sendInstruction(bytes message)` — sends an ABI-encoded payload to a TEE. Called by the Relay.

---

### 2. Relay

**Purpose:** The orchestrator that manages the RFQ (Request For Quote) lifecycle. It connects the Smart Account to the TEE and publishes the TEE's response.

**How it works:**
- The Smart Account calls `submitRFQ()` with option parameters (asset, strike, expiry, isPut, quantity)
- The Relay generates a unique `rfqId`, stores the RFQ, and forwards the request to the TEE via the InstructionSender
- When the TEE responds with a signed quote, a backend operator calls `publishQuote()` to post the result on-chain
- The `QuoteSigned` event is emitted — the frontend and Smart Account can read the price from here

**Key functions:**
- `submitRFQ(asset, strike, expiry, isPut, quantity)` — creates an RFQ and sends the pricing request to the TEE. Called by the Smart Account. Payable (forwards value to `sendInstructions`).
- `publishQuote(rfqId, maker, price, signature, attestationToken)` — posts the TEE's signed quote on-chain. Called by the `quotePublisher` backend.
- `cancelRFQ(rfqId)` — cancels an active RFQ. Called by the Smart Account.
- `getRFQ(rfqId)` — returns the RFQ data.

**Access control:**
- `submitRFQ` / `cancelRFQ` — only callable by the registered `smartAccount` address
- `publishQuote` — only callable by the registered `quotePublisher` address
- Admin setters — only callable by `owner`

---

### 3. AttestationVerifier

**Purpose:** Verifies that a quote was genuinely signed by the TEE's hardware-bound private key using EIP-712.

**How it works:**
- Takes a Quote struct + signature, recovers the signer address via `ecrecover`
- Compares the recovered signer against the registered TEE key
- TEE key is resolved in priority order:
  1. `teeKeyOverride` — hardcoded address (for demo/testing)
  2. `TeeExtensionRegistry.getKeyForExtension(extensionId)` — production lookup

**EIP-712 domain (must match what the TEE signs with):**
```
name: "rysk"
version: "0.0.0"
chainId: 114 (Coston2)
verifyingContract: <MockGamma address>
```

**Key functions:**
- `verifyQuote(quote, sig)` — returns `(bool valid, address signer)`. Called by MockGamma during settlement, or by anyone as a standalone check.
- `recoverQuoteSigner(quote, sig)` — returns the recovered address (useful for debugging).
- `getDigest(quote)` — returns the EIP-712 digest the TEE should sign.
- `getDomainSeparator()` — returns the domain separator (share with Hamza to verify match).

**Quote struct (13 fields, order matters):**
```
assetAddress, chainId, isPut, strike, expiry, maker, nonce,
price, quantity, isTakerBuy, validUntil, usd, collateralAsset
```

---

### 4. MockGamma

**Purpose:** The settlement contract. When the Smart Account accepts a quote, this contract verifies the attestation and records the fill. It is a simplified mock of Opyn's Gamma protocol.

**How it works:**
- Receives a Quote + EIP-712 signature from the caller
- Delegates verification to the AttestationVerifier
- If valid: records the fill, prevents double-fills, emits `OptionFilled`
- No real token transfers — the attestation proof is the deliverable for this demo

**Key functions:**
- `fillRFQ(quote, sig)` — verifies the quote via AttestationVerifier, records the settlement. Called by the Smart Account.
- `setVerifier(address)` — admin function to update the AttestationVerifier address.

**Emits:**
- `OptionFilled(quoteHash, taker, maker, price, quantity, strike, expiry, isPut)` — the proof that a deal was settled on-chain with a verified TEE attestation.

---

## End-to-End Flow

```
Step 1: Smart Account calls Relay.submitRFQ(asset, strike, expiry, isPut, quantity)
           |
           v
Step 2: Relay stores the RFQ and calls InstructionSender.sendInstruction(payload)
           |
           v
Step 3: InstructionSender calls TeeExtensionRegistry.sendInstructions()
         (official Flare FCE event is emitted — TEE picks it up)
           |
           v
Step 4: TEE computes the fair premium using Monte Carlo pricing
         TEE signs the full Quote struct with EIP-712 using its hardware-bound key
           |
           v
Step 5: Backend operator calls Relay.publishQuote(rfqId, maker, price, sig, attestation)
         QuoteSigned event is emitted — frontend displays the price
           |
           v
Step 6: Smart Account accepts the quote, calls MockGamma.fillRFQ(quote, sig)
           |
           v
Step 7: MockGamma delegates to AttestationVerifier.verifyQuote(quote, sig)
         Verifier recovers the signer and checks it matches the registered TEE key
           |
           v
Step 8: If valid — fill is recorded, OptionFilled event is emitted
         Settlement complete.
```

---

## Contract Dependencies

```
InstructionSender
  -> TeeExtensionRegistry (Flare)
  -> TeeMachineRegistry (Flare)

Relay
  -> InstructionSender

MockGamma
  -> AttestationVerifier

AttestationVerifier
  -> TeeExtensionRegistry (Flare, optional — can use teeKeyOverride instead)
```

---

## What Each Team Member Needs

**Hamza (TEE):**
- MockGamma address = `0xEe5b0Ba2793267da967E800Ac926620742620D13` (this is the `verifyingContract` for EIP-712 signing)
- ChainId = `114`
- The Quote struct field order (13 fields listed above)
- EIP-712 domain: `name="rysk"`, `version="0.0.0"`
- OPType/OPCommand the TEE should listen for: `"PRICING"` / `"QUOTE"`

**Marcos (Smart Account):**
- Relay address = `0x8795e6384Fdc1F902f480c86C24c8F30649C52d8` to call `submitRFQ()`
- MockGamma address = `0xEe5b0Ba2793267da967E800Ac926620742620D13` to call `fillRFQ(quote, sig)`
- AttestationVerifier address = `0x027f7874bc35A691984f2545c05ac0E3C8616e2f` to call `verifyQuote()` standalone

**Dex (Frontend):**
- Listen for `QuoteSigned` events on the Relay to display quotes
- Listen for `OptionFilled` events on MockGamma to confirm settlement
- Relay `getRFQ(rfqId)` to show RFQ status
