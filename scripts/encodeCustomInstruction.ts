import {
  encodeFunctionData,
  encodeAbiParameters,
  keccak256,
  toHex,
  type Address,
} from "viem";

// ─── Addresses ──────────────────────────────────────
const MOCK_GAMMA_ADDRESS: Address =
  "0x97E812a7187E5ce2f6c522A017F517e6bcdc678B";
const MASTER_ACCOUNT_CONTROLLER: Address =
  "0x434936d47503353f06750Db1A444DBDC5F0AD37c";

// ─── MockGamma ABI (current fillRFQ) ───────────────
const mockGammaAbi = [
  {
    type: "function",
    name: "fillRFQ",
    inputs: [],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

// ─── Step 1: Encode fillRFQ calldata ────────────────
// Per the current MockGamma implementation, fillRFQ() takes no arguments,
// so the calldata is just the 4-byte selector.
const calldata = encodeFunctionData({
  abi: mockGammaAbi,
  functionName: "fillRFQ",
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
