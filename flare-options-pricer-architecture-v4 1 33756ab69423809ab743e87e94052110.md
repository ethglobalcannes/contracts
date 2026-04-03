# flare-options-pricer-architecture-v4.1

# Flare TEE Market Maker — Project Architecture Notes v4.1

*EthGlobal Cannes — April 3rd, 2026*

---

## 0. What We’re Building — 30-Second Pitch

**For anyone:** When you trade options, you trust the market maker priced them fairly. Today there is no way to verify that. We built a market maker whose entire pricing computation runs inside tamper-proof hardware and publishes a cryptographic proof on-chain with every single quote. Anyone can verify the exact model that ran, the inputs it used, and the hardware it ran on. The quote is either honest — or the proof doesn’t verify.

**For the technically curious:** Our TEE runs as a Flare Compute Extension (FCE) — deployed locally via Docker + cloudflared tunnel, with Intel TDX attestation registered on Coston2. The enclave holds the maker’s signing key, runs a Monte Carlo options pricer, and signs EIP-712 Quotes with the attested key. XRPL users access as takers through Flare Smart Accounts — no EVM wallet needed. An on-chain verifier checks TEE key registration against `TeeExtensionRegistry` and price slippage before settlement executes via Opyn Gamma. Attestation is published on-chain with every quote. That’s not a claim. It’s a proof.

---

## 1. Project Concept

A TEE-powered **attested options market maker** for fXRP covered calls and cash-secured puts, integrated with Rysk Finance’s RFQ protocol on Flare. The TEE agent computes fair option premiums via Monte Carlo inside a Flare Compute Extension (FCE) — running locally via Docker + cloudflared tunnel with Intel TDX attestation registered on Coston2 — signs quotes with its hardware-attested key, and responds to live RFQs. XRPL users holding XRP can access the protocol as option buyers (takers) via Flare Smart Accounts — no EVM wallet required. The FCE attestation token proves every quote was priced by verified code running on verified hardware, not a manipulated bot.

**The gap we fill:** RFQ-based options markets rely on market makers quoting fairly — today there is no mechanism to prove they did. Our TEE acts as a transparent, auditable market maker: anyone can verify the exact Docker image that ran inside the enclave, the inputs it used (FTSO spot, Deribit IV, on-chain SecureRandom seed), and the resulting premium. Quote integrity is hardware-bound and stored on-chain. This is not a claim — it’s a proof.

**Team:**
- Hamza — TEE service, pricing engine, ryskV12_py integration, pitch
- Dex — frontend, data pipelines, RFQ visualization, pitch deck
- Marcos — Smart Account RFQ trigger, XRPL ↔︎ Flare bridge
- Daniel — relay contract, Smart Account integration, on-chain attestation verifier, EIP-712 security

**Prize targets:** $8k main (TEE + Smart Accounts combined) + $2k bonus (Best Smart Account App).

---

## 2. Full Workflow (Happy Path)

```
[1] TAKER INTENT — Xaman → Flare Smart Account
    XRPL user sends a standard XRP Payment from Xaman to the Smart Account operator address.
    Memo field (hex) encodes a 32-byte instruction (type 0xff):
      action=RFQ | underlying=fXRP | amount | strike | expiry | isPut
    FDC Payment attestation verifies the payment and decodes the memo on-chain (~90–180s).
    Smart Account holds fXRP collateral (or bridges XRP → fXRP via FXRP minting).

        ↓

[2] RFQ BROADCAST — Smart Account → Rysk Protocol
    Smart Account submits an RFQ to Rysk (asset=fXRP, strike, expiry, quantity, isPut).
    Rysk broadcasts the RFQ over WebSocket to all connected maker bots.
    [Fallback: if Rysk not yet deployed on Flare (chainId 14), Smart Account calls Daniel's mock
     options contract implementing the Opyn Gamma interface — same flow, simulated counterparty.]

        ↓

[3] TEE PRICING — FCE Python extension (local Docker + cloudflared on Coston2)
    TEE maker bot (ryskV12_py SDK) listens on wss://v12.rysk.finance/rfqs/<assetAddress>.
    For each RFQ (asset, strike K, expiry T, isPut, quantity):
      • S0    — FTSO XRP/USD feed (getFeedByIdInWei, ~1.8s update)
      • sigma — Deribit mark_iv via Web2Json FDC attestation
      • seed  — on-chain SecureRandom (reproducible, stored on-chain)
    Runs GBM Monte Carlo (10k paths): call_price = e^{-rT} · mean(max(S_T – K, 0))
    Runs Black-Scholes as convergence check. Computes delta = N(d1), vega.

        ↓

[4] QUOTE RESPONSE — TEE → Rysk RFQ Server
    TEE signs an EIP-712 Quote struct with its attested key.
      domain: name="rysk", version="0.0.0", verifyingContract=Rysk address on chain
      Quote.price = MC fair value (18 decimals), isTakerBuy=true, validUntil = now + 30s
    Sends via ryskV12_py → /maker WebSocket → Rysk server.
    Pricing inputs + FCE attestation token stored on-chain via relay contract event.

        ↓

[5] SETTLEMENT — Smart Account + On-Chain Attestation Verifier
    Smart Account receives the best quote. Daniel's on-chain verifier checks:
      (a) Quote signed by the registered TEE key (verified against TeeExtensionRegistry)
      (b) Quoted price within acceptable slippage of FTSO + IV-derived fair value
    IF verified → Smart Account accepts → Rysk (Opyn Gamma) locks fXRP collateral,
                  mints ERC20 option token to taker. Settlement at expiry by protocol.
    IF rejected → Smart Account holds fXRP; emits rejection event with reason.

        ↓

[6] FRONTEND — Dex
    RFQ timeline: request broadcast → TEE quote latency → settlement confirmation.
    Fairness panel: call_price_mc vs call_price_bs · delta · vega · seed · inputs used.
    Attestation deeplink: FCE attestation token + extension hash → "verify this computation."
    Historical feed: all past quotes + settlements, on-chain event log, publicly auditable.
```

---

## 3. Complexity & Risk Assessment

### [A] Data Acquisition — Dex

| Task | Owner | Complexity | Risk | Notes |
| --- | --- | --- | --- | --- |
| Web2Json: Deribit mark_iv | Dex | Medium | Low | `get_book_summary_by_currency?currency=XRP` — mark_iv only; no auth; attest alongside compute |
| FTSO spot fetch (XRP/USD) | Dex | Low | Low | View call, free, ~1.8s update — `getFeedByIdInWei` |

### [B] Compute Layer — Hamza

| Task | Owner | Complexity | Risk | Notes |
| --- | --- | --- | --- | --- |
| **FCE extension registration on Coston2** | **Hamza** | **High** | **High** | `fce-sign` template (Python). 7-step flow: deploy `InstructionSender.sol` → `register-extension` → `docker compose up -d` → `cloudflared tunnel --url http://localhost:6676` → `allow-tee-version` → `register-tee -l` → `run-test`. **Blocker: Coston2 C-chain indexer DB credentials** for `extension_proxy.toml` — get from Flare team at venue. `TeeExtensionRegistry` at `0xdE25c06982Ab8e4b6B4F910896E3f93Ac77FB44d` |
| **ryskV12_py maker bot loop** | **Hamza** | **Medium** | **Medium** | Python SDK wrapping ryskV12-cli binary. Connects to `/rfqs/<asset>` WebSocket, parses `Request`, calls MC pricer, sends signed `Quote` via `/maker` channel. EIP-712 signing from TEE-held key. |
| Monte Carlo (GBM, 10k paths) | Hamza | Low | Low | `dS = μS dt + σS dW`; vectorize with NumPy; call_price = e^{-rT} · mean(max(S_T – K, 0)); < 1s |
| Black-Scholes convergence check | Hamza | Low | Low | 5 variables, ~10 lines — BS confirms MC output for same (K, T, sigma) |
| Option premium output + greeks | Hamza | Low | Low | call_price_mc (18 dec), delta = N(d1), vega; all included in Quote attestation payload |

### [C] Execution Layer — Daniel + Marcos

| Task | Owner | Complexity | Risk | Notes |
| --- | --- | --- | --- | --- |
| **Smart Account RFQ trigger** | **Marcos** | **High** | **High** | Newest primitive, thin docs — prototype first, timebox to 3h. Creates Rysk RFQ (or mock contract call); FDC Payment attestation trigger. |
| **Mock options contract** | **Daniel** | **High** | **High** | Opyn Gamma-compatible interface on Flare chainId 14 — this is the **primary settlement path** (Rysk not on chainId 14). Start from hour 1, not as afterthought. Foundry deploy + forge tests. |
| **On-chain attestation verifier** | **Daniel** | **High** | **High** | Verifies TEE key against `TeeExtensionRegistry`; validates EIP-712 Quote signature; checks price within slippage bound. EIP-712 domain params (`name`, `version`, `verifyingContract`) must match exactly. |
| **Relay contract (secure)** | **Daniel** | **High** | **Medium** | Emits `TeeInstructionsSent`; routes to `InstructionSender.sol` via OPType/OPCommand; Foundry + forge tests; Solidity security patterns (access control, reentrancy guards) |
| Collateral approval flow | Daniel | Medium | Low | ERC20 `approve` → `MMarket` (Rysk margin pool); safe patterns, exact amount checks |
| XRPL payment + memo encoding | Marcos | Medium | Low | Standard XRPL Payment (Xaman handles natively); `0xff` in memo field; FDC Payment attestation available |
|  |  |  |  |  |

### [D] Frontend — Dex

| Task | Owner | Complexity | Risk | Notes |
| --- | --- | --- | --- | --- |
| Intent entry form | Dex | Low | Low | User inputs: asset, amount, strike, expiry, isPut — encoded as Payment memo |
| Fairness panel | Dex | Low | Low | call_price_mc vs call_price_bs · delta · vega · seed · inputs used; model transparency |
| MC vs BS convergence chart | Dex | Low | Low | Side-by-side prices — proves MC converges to closed-form |
| Greeks gauges | Dex | Low | Low | Delta (directional exposure), vega (vol sensitivity) |
| Attestation deeplink | Dex | Low | Low | vTPM token + Docker image hash → “verify this computation” |
| Historical execution feed | Dex | Low | Low | On-chain event log: all past quotes + settlements, publicly auditable |

**Critical path:** Xaman payment → FDC attestation → Smart Account (Marcos) → RFQ broadcast → TEE maker bot prices with MC (Hamza) → EIP-712 Quote signed by attested key → Rysk server → Smart Account receives quote → Daniel’s attestation verifier checks → settles via Opyn Gamma (or mock contract) → frontend.

**Fallback (Rysk not on Flare):** Daniel deploys a mock Opyn Gamma-compatible options contract on Flare chainId 14. Smart Account sends RFQ to mock contract. TEE responds via same flow. Attestation story is identical. Build this in parallel from day 1 — it is not a backup, it is likely the primary path.
**Fallback (TEE layer):** If cloudflared tunnel or Coston2 indexer DB credentials are unavailable, set `LOCAL_MODE=true` in `.env` — `docker compose up` still runs, compute is correct, attestation becomes simulated. Label clearly as `[LOCAL RUN]`. Architecture and interface are identical. **Primary blocker:** indexer DB credentials for Coston2 C-chain (`config/proxy/extension_proxy.toml`) — get from Flare team at venue on arrival.
**Fallback (Smart Account layer):** If Smart Account trigger is blocked, replace with a direct EVM call to the relay contract. Preserves full TEE + MC + attestation story. Loses XRPL UX narrative; frame as roadmap item.

---

## 4. Key Architectural Decisions

| Decision | Rationale |
| --- | --- |
| **Rysk fXRP options as target** | Live RFQ options protocol with mentor validation. Settlement via Opyn Gamma (battle-tested, audited by Trust Security). fXRP = natural XRP derivative on Flare. |
| **TEE acts as maker, not taker** | Only the maker-side SDK (`ryskV12_py`) is publicly available and documented. TEE’s attested key signs EIP-712 Quotes — this is the attestation story. XRPL users access as takers via Smart Account. |
| **Covered call as primary instrument** | fXRP holder sells upside for premium (covered call). Covered call = yield strategy. Put (cash-secured) as V1b extension if time permits. |
| **GBM Monte Carlo + BS convergence** | MC runs inside TEE; BS is closed-form sanity check. Both visible in frontend. MC is future-proof for path-dependent payoffs (V2). |
| **Vol input: Deribit mark_iv via Web2Json** | No auth, one API call, attestable via FDC. Decentralized vol feed is weeks of work; Web2Json is sound for V1. |
| **Randomness: one SecureRandom seed** | One on-chain seed per block; in-memory PRNG (xoshiro256+) for all N draws. Seed stored on-chain → anyone can reproduce the draw sequence. |
| **EIP-712 Quote signed by TEE key** | Rysk’s settlement mechanism requires a signed Quote struct. Domain: `name="rysk"`, `version="0.0.0"`, `verifyingContract=Rysk` address on chain. Key lives inside TDX enclave — attestation proves key provenance. |
| **Mock Opyn Gamma contract on Flare (fallback)** | `CHAIN_ID_HYPE = 999` in ryskV12-cli maps to HyperEVM (Hyperliquid), not Flare. Flare mainnet (chainId 14) is absent from Rysk’s contract map. Daniel deploys an Opyn Gamma-compatible mock on chainId 14 from day 1. Same on-chain flow, same attestation story. |
| **Smart Account = taker access layer** | XRPL user (no EVM wallet) creates RFQ via Smart Account. TEE prices and responds. Smart Account verifies attestation before accepting. Makes Smart Account architecturally necessary — not cosmetic. |
| **Quote rejection → hold in Smart Account** | If best quote fails attestation check, fXRP held safely. Refund to XRPL via PMW in V2. |
| **TEE: FCE Python extension (local Docker + cloudflared)** | FCE repos (`fce-sign` / `fce-weather-api`) now public. `docker compose up` + `cloudflared tunnel --url http://localhost:6676` → real Intel TDX attestation on Coston2, no GCP required. `LOCAL_MODE=false` for real attestation; `LOCAL_MODE=true` for local dev without attestation. 7-step Coston2 registration. **Blocker:** indexer DB credentials (`config/proxy/extension_proxy.toml`) from Flare team. |

---

## 5. Hackathon Day Checklist

### Hour 0–6: Infrastructure baseline

- [ ]  **FIRST on arrival: get Coston2 C-chain indexer DB credentials from Flare team** — needed for `config/proxy/extension_proxy.toml` before `docker compose up` works (Hamza)
- [ ]  Clone `fce-sign`, set `LANGUAGE=python` in `.env`, run 7-step Coston2 registration: `deploy-contract` → `register-extension` → `docker compose up -d` → `cloudflared tunnel --url http://localhost:6676` → `allow-tee-version` → `register-tee -l` → `run-test` (Hamza)
- [ ]  Confirm `ryskV12_py` installs and CLI binary connects to `wss://v12.rysk.finance/maker`; ask Rysk team about TEE maker key whitelisting (Hamza)
- [ ]  Deploy Daniel’s mock Opyn Gamma-compatible contract on Flare chainId 14 with Foundry — this is the primary path, start immediately (Daniel)
- [ ]  Deploy relay contract emitting `TeeInstructionsSent` events; confirm OPType/OPCommand constants in `InstructionSender.sol` match FCE Python handler (Daniel + Hamza)
- [ ]  Prototype Smart Account RFQ trigger (Marcos): XRPL payment → FDC attestation → `MasterAccountController` → emit RFQ

### Hour 6–24: Core integration

- [ ]  Implement MC + BS in Python inside TEE container; confirm ATM call price convergence (Hamza)
- [ ]  Integrate ryskV12_py maker loop: parse `Request`, call MC, return `Quote` with correct EIP-712 struct (Hamza)
- [ ]  Attest Deribit mark_iv endpoint via Web2Json FDC; confirm FTSO XRP/USD read on Flare (Dex)
- [ ]  Daniel’s on-chain attestation verifier: TEE key check + EIP-712 Quote signature validation + price slippage gate (Daniel)
- [ ]  Collateral ERC20 `approve` → MMarket flow (Daniel)
- [ ]  Connect Smart Account RFQ trigger to mock contract; end-to-end test on testnet (Marcos + Daniel)

### Hour 24–48: Integration + frontend

- [ ]  Store vTPM attestation token + inputs on-chain via relay contract (Hamza)
- [ ]  Frontend RFQ timeline + fairness panel + attestation deeplink (Dex)
- [ ]  Historical feed from on-chain events (Dex)
- [ ]  Full end-to-end demo run: Xaman → Smart Account → TEE quote → verifier → settlement
- [ ]  Pitch deck final pass (Hamza + Dex)

### Nice to have

- [ ]  Connect to live Rysk WebSocket if team confirms Flare deployment or HyperEVM demo approved
- [ ]  Greeks panel on frontend (delta, vega)
- [ ]  PMW refund path scoping for V2

---

## 6. MVP → V2 Roadmap

### Hackathon V1

- fXRP covered call (primary); cash-secured put as V1b extension if time permits
- Underlying: fXRP — Flare-native XRP derivative; Deribit options for IV input
- Vol input: Deribit ATM XRP implied vol via Web2Json FDC attestation
- TEE maker bot responds to Rysk RFQs (or mock contract RFQs) with MC-priced EIP-712 signed quotes
- Smart Account enables XRPL users to create RFQs without an EVM wallet (FDC Payment attestation trigger)
- On-chain attestation verifier gates quote acceptance: TEE key registration + price slippage check
- Output stored on-chain: call_price_mc, call_price_bs, delta, vega, seed, FCE attestation token, settlement status
- Trigger chain: Xaman (Payment, `0xff` memo) → Smart Account → RFQ broadcast → TEE prices via MC → EIP-712 Quote signed → Rysk/mock settles → ERC20 option token to taker
- Fallback: Daniel’s mock Opyn Gamma contract on Flare chainId 14 (primary path if Rysk not on chainId 14)

### V2 — Retail upgrades

| Feature | What it adds |
| --- | --- |
| Full Greeks (gamma, vega, theta) | Complete risk profile |
| Vol smile interpolation | Fetch multiple strikes from Deribit, interpolate surface |
| Barrier / Asian options | Path-dependent payoffs — MC shines here |
| Historical vol alternative | FTSO price history → realized vol on-chain |
| Return result to XRPL | PMW threshold co-signing — closes the cross-chain loop |

### V2 — Institutional upgrades (longer term)

| Feature | What it adds |
| --- | --- |
| Vol surface (SVI/SSVI) | Full smile calibration, not just ATM IV |
| XVA-lite | CVA estimation on option position |
| SIMM-equivalent margin | IM calculation for structured products |

---

## 7. Pitch Structure (3 angles)

1. **Honest builder opening:** *“RFQ options markets ask you to trust your market maker. There is no proof they computed fairly. We asked: what if there was? The answer is a TEE-powered maker that publishes its pricing proof on-chain.”*
2. **Infrastructure gap landing:** *“Our pricing engine runs inside a Flare Compute Extension — Intel TDX hardware isolation, deployed locally with a cloudflared tunnel and registered on Coston2’s TEE Extension Registry. The attestation token is stored on-chain with every single quote. Anyone can verify the exact extension hash that ran, the inputs used — FTSO spot, Deribit IV, on-chain seed — and the resulting option premium. That’s not a claim. That’s a proof.”*
3. **Composability close:** *“One Xaman payment. Smart Account decodes the intent. TEE market maker prices the option inside hardware isolation and signs the quote with its attested key. Smart Account verifies attestation on-chain before accepting. Rysk settles via Opyn Gamma. When Flare’s FCE relay goes live, our service registers as a Compute Extension — same interface, network-level consensus added. The rest is already done.”*

### What the Attestation Proves (and Doesn’t)

| Claim | Proved? | Notes |
| --- | --- | --- |
| Computation was honest | ✅ | Extension hash + FCE attestation token (Intel TDX, Coston2 TEE Extension Registry) |
| Output is bound to inputs | ✅ | Cryptographically linked |
| FTSO spot price was accurate | ❌ | Feed is decentralized but theoretically gameable |
| Deribit vol was accurate | ❌ | Off-chain source — attested but not verified |
| Model is correct | ❌ | TEE proves the model ran; model validation is separate |

**Attestation proves computational integrity, not input integrity.** FTSO decentralization and Deribit’s credibility are the input integrity story.

---

*Last updated: April 3, 2026 — v4.1, FCE stack replaces GCP/flare-ai-kit throughout; 7-step Coston2 registration; §0 pitch added; §3 tables reordered by risk (High→Medium→Low); fallback updated to LOCAL_MODE; mock contract elevated to primary path*

---

## 8. Context Log

| Question | Status | Answer |
| --- | --- | --- |
| Can `0xff` call TEE Extension directly from `MasterAccountController`? | ✅ Answered | No direct call — requires intermediary relay contract. Flow: `MasterAccountController` → relay contract → FCE. |
| Is FCE / TEE testnet publicly available? | ✅ Confirmed (Apr 3) | FCE repos are now public: `fce-sign`, `fce-weather-api`, `fce-extension-scaffold`. Local deployment: Docker + cloudflared, no GCP. `fce-sign` is the exact template for our use case — TEE holds private key, signs messages (maps to: hold maker key, sign EIP-712 Quotes). `LOCAL_MODE=false` for real attestation on Coston2. **Blocker:** Coston2 C-chain indexer DB credentials for `config/proxy/extension_proxy.toml` — get from Flare team at venue. |
| FXRP minting rate — variable or fixed? | ✅ N/A | 1:1 backed by design. May need `collateralReservationFee` from `AssetManager` for exact XRP cost, but second-order for demo. |
| Does Xaman support `0xff` custom instruction UI? | ✅ Clarified | Xaman only parses standard XRPL transaction types. **The XRPL trigger IS a standard Payment** — Xaman handles it natively. The `0xff` lives in the memo field (hex data). Xaman shows “you’re sending X XRP to this address.” |
| Which Deribit endpoint for Web2Json attestation? | ✅ Decided | `get_book_summary_by_currency?currency=XRP&kind=option` — `mark_iv` per instrument, one call, no auth. |
| What is Rysk’s `CHAIN_ID_HYPE = 999`? | ✅ Resolved | **HyperEVM (Hyperliquid)**, not Flare. `chain.go` in ryskV12-cli names it `CHAIN_ID_HYPE`. Flare mainnet (chainId 14) is absent from Rysk’s contract map. The `app.rysk.finance?chainId=999` URL points to HyperEVM. **Risk mitigated**: Daniel deploys mock Opyn Gamma contract on Flare chainId 14. |
| Is the ryskV12 SDK taker-side or maker-side? | ✅ Resolved | **Maker-side only.** CLI README: “cli to interact with rysk v12 as a MM.” Commands: `connect`, `quote`, `transfer`, `balances`, `positions`. No `buy` or `rfq-create` command. Takers use the website UI. Our TEE is the maker; Smart Account acts as the taker. |
| Rysk EIP-712 domain parameters? | ✅ Found | `name="rysk"`, `version="0.0.0"`, `verifyingContract = Rysk` address on chain (per `eip712.go`). Quote struct fields: `assetAddress, chainId, isPut, strike, expiry, maker, nonce, price, quantity, isTakerBuy, validUntil, usd, collateralAsset`. |
| Is Rysk audited? | ✅ Answered | Settlement engine is Opyn Gamma (battle-tested, publicly audited). Protocol accounting audited by Trust Security (`@trust__90`). Audit report not public yet (contains sensitive implementation details); new public audit starting soon. No security incidents or valid bounty reports to date. |
| Can TEE key be registered as a maker on Rysk? | ⚠️ Open | Maker registration may require whitelisting by Rysk team. **Ask Rysk at venue on day 1.** If not possible, TEE quotes against Daniel’s mock contract instead. |
| Rysk contract addresses on HyperEVM (chainId 999)? | ✅ Found | `Rysk (EIP-712 verifying): 0x8c8bcb6d2c0e31c5789253ecc8431ca6209b4e35`, `MarginPool: 0x24a44f1dc25540c62c1196FfC297dFC951C91aB4`, `MMarket (approve target): 0x691a5fc3a81a144e36c6C4fBCa1fC82843c80d0d`, `StrikeAsset: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb`. These are HyperEVM not Flare. |

---

## Changelog

| Version | Date | Summary |
| --- | --- | --- |
| v2.0 | Mar 2026 | Options pricer framing — SparkDEX Eternal, quote-on-demand |
| v3.0 | Mar 2026 | Reframe to conditional execution guard; Upshift/earnXRP target; FXRP minting rate category error corrected; `risk_ratio = vault_apy / atm_put_annual` formula established; full workflow rewrite |
| v3.1 | Mar 29, 2026 | Pre-hackathon context integrated: TEE mock strategy (FCE unavailable before Apr 3); relay pattern confirmed (intermediary contract); `0x20` atomicity confirmed; risk_ratio default recalibrated to 0.10 with calibration note in §4; Upshift APY endpoint confirmed (`/annualized_apy`, API-only); Deribit `mark_iv` endpoint decided for V1 attestation; Xaman payment flow clarified (standard Payment, memo-encoded intent); Section 3 restructured into modules [A] Data / [B] Compute / [C] Execution / [D] Frontend; Section 10 updated with answered context log |
| v3.2 | Mar 29, 2026 | TEE layer upgraded: `flare-ai-kit` (Python, GCP Confidential Space / Intel TDX) replaces mock; `tee-proxy POST /direct` is the documented bypass for hackathon use (data provider consensus skipped); `TeeExtensionRegistry` at `0xdE25c06982Ab8e4b6B4F910896E3f93Ac77FB44d` identified; vTPM attestation quote stored on-chain; FCE blocker downgraded from ⚠️ to ✅ in Section 10; Section 9 pitch updated to reference real hardware attestation; fallback tiered (GCP deploy fail → local run; Smart Account block → direct EVM call) |
| v3.3 | Mar 29, 2026 | Document refactor: §1 tightened (removed duplicate covered-short-put block, dropped stale FXRP framing, updated to vTPM language); §2 compressed from 5 verbose steps to 5 supersteps; §4 replaced with decision table (strict minimum); §5 updated to concrete `flare-ai-kit`/`tee-proxy` tasks; §8 V1 trigger chain trimmed to one line |
| v4.0 | Apr 3, 2026 | Full reframe: TEE as attested options market maker on Rysk (Upshift/earnXRP retired). Workflow rewritten for RFQ model (6 steps). Daniel added as 4th member (SC + cybersecurity: relay contract, attestation verifier, mock contract, EIP-712 security). Section 3: relay contract + attestation verifier → Daniel; ryskV12_py maker loop added → Hamza; Upshift APY row removed. Section 4: Upshift/risk_ratio decisions replaced by Rysk/covered-call/EIP-712/mock-fallback decisions. Section 5: rewritten as 3-phase hackathon day checklist. Section 6 V1: Rysk RFQ flow, no vault APY. Section 7: pitch rewritten. Section 8: 6 new context entries (chainId=999 = HyperEVM; maker-only SDK; EIP-712 domain params; Trust Security audit; maker registration open question; contract addresses). |
| v4.1 | Apr 3, 2026 | FCE stack replaces GCP/flare-ai-kit throughout. §0 30-second pitch added. §3 tables reordered by risk (High→Medium→Low within each subsection). [B] row updated: `flare-ai-kit on GCP` → `FCE extension registration on Coston2` (HIGH). [C] mock contract elevated to HIGH (primary path). Fallback block updated: `LOCAL_MODE=true` replaces “run without deploy-tee.sh”. §4 TEE decision row updated. §5 Hour 0-6 checklist: FCE 7-step registration, indexer DB credential step added. §7 pitch angle 2 updated. §8 FCE context entry updated with confirmed repo availability. Footer updated. |