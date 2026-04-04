import {
  encodeFunctionData,
  encodeAbiParameters,
  keccak256,
  toHex,
  type Address,
} from "viem";

// ─── Addresses ──────────────────────────────────────
const MOCK_GAMMA_ADDRESS: Address =
  "0xaFB1F635bB000851bC7e2cE7e92CE078BE3C233b";
const MASTER_ACCOUNT_CONTROLLER: Address =
  "0x434936d47503353f06750Db1A444DBDC5F0AD37c";

// ─── MockGamma ABI (fillRFQ only) ──────────────────
const mockGammaAbi = [
  {
    type: "function",
    name: "fillRFQ",
    inputs: [
      {
        name: "quote",
        type: "tuple",
        components: [
          { name: "assetAddress", type: "address" },
          { name: "chainId", type: "uint256" },
          { name: "isPut", type: "bool" },
          { name: "strike", type: "uint256" },
          { name: "expiry", type: "uint256" },
          { name: "maker", type: "address" },
          { name: "nonce", type: "uint256" },
          { name: "price", type: "uint256" },
          { name: "quantity", type: "uint256" },
          { name: "isTakerBuy", type: "bool" },
          { name: "validUntil", type: "uint256" },
          { name: "usd", type: "uint256" },
          { name: "collateralAsset", type: "address" },
        ],
      },
      { name: "sig", type: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

// ─── Quote values (fill with real values) ───────────
const quote = {
  assetAddress: "0x0b6A3645c240605887a5532109323A3E12273dc7" as Address, // FXRP
  chainId: 114n, // Coston2
  isPut: false,
  strike: 2000000000000000000n, // 2.0 (18 decimals)
  expiry: 1720000000n,
  maker: "0x8062909712F90a8f78e42c75401086De3eE95fBe" as Address,
  nonce: 1n,
  price: 50000000000000000n, // 0.05 premium (18 decimals)
  quantity: 1000000000000000000n, // 1.0 (18 decimals)
  isTakerBuy: true,
  validUntil: 1720000000n,
  usd: 5n,
  collateralAsset: "0x0000000000000000000000000000000000000000" as Address,
};

const sig: `0x${string}` = "0x"; // TEE EIP-712 signature (empty for registration)

// ─── Step 1: Encode fillRFQ calldata ────────────────
const calldata = encodeFunctionData({
  abi: mockGammaAbi,
  functionName: "fillRFQ",
  args: [quote, sig],
});

// ─── Step 2: Build CustomCall array ─────────────────
type CustomCall = {
  targetContract: Address;
  value: bigint;
  data: `0x${string}`;
};

const customCalls: CustomCall[] = [
  {
    targetContract: MOCK_GAMMA_ADDRESS,
    value: 0n,
    data: calldata,
  },
];

// ─── Step 3: Compute call hash (same as MasterAccountController) ──
// Formula: bytes32(uint256(keccak256(abi.encode(calls))) & ((1 << 240) - 1))
const encoded = encodeAbiParameters(
  [
    {
      type: "tuple[]",
      components: [
        { name: "targetContract", type: "address" },
        { name: "value", type: "uint256" },
        { name: "data", type: "bytes" },
      ],
    },
  ],
  [customCalls]
);

const rawHash = keccak256(encoded);
const MASK_30_BYTES = (1n << 240n) - 1n;
const callHash =
  "0x" +
  (BigInt(rawHash) & MASK_30_BYTES).toString(16).padStart(64, "0");

// ─── Step 4: Build 32-byte payment reference ────────
// Byte 1: 0xff (custom instruction identifier)
// Byte 2: walletId (0 for default)
// Bytes 3-32: 30-byte call hash
const walletId = 0;
const paymentRef =
  "0xff" + toHex(walletId, { size: 1 }).slice(2) + callHash.slice(6);

// ─── Output ─────────────────────────────────────────
console.log("=== Custom Instruction for MockGamma.fillRFQ() ===\n");
console.log("Calldata:", calldata);
console.log("\nCalldata length:", calldata.length / 2 - 1, "bytes");
console.log("\nRaw hash:", rawHash);
console.log("Call hash (30-byte masked):", callHash);
console.log("\n=== For Marcos ===\n");
console.log("Payment reference (32 bytes):", paymentRef);
console.log("Target contract:", MOCK_GAMMA_ADDRESS);
console.log("MasterAccountController:", MASTER_ACCOUNT_CONTROLLER);
console.log(
  "\nCustom instruction array (for registerCustomInstruction):"
);
console.log(
  JSON.stringify(
    customCalls,
    (_, v) => (typeof v === "bigint" ? v.toString() : v),
    2
  )
);
