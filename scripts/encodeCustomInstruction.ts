import { encodeFunctionData, type Address } from "viem";

// MockGamma address on Coston2
const MOCK_GAMMA_ADDRESS: Address =
  "0xEe5b0Ba2793267da967E800Ac926620742620D13";

// MockGamma ABI (only fillRFQ)
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

// ---------- Fill these with real values ----------

const quote = {
  assetAddress: "0x0b6A3645c240605887a5532109323A3E12273dc7" as Address, // FXRP
  chainId: 114n, // Coston2
  isPut: false,
  strike: 2000000000000000000n, // 2.0 (18 decimals)
  expiry: 1720000000n, // unix timestamp
  maker: "0xFB1b157D9Ac73eE490C764c908a16E6E5097f99E" as Address, // TEE address
  nonce: 1n,
  price: 50000000000000000n, // 0.05 premium (18 decimals)
  quantity: 1000000000000000000n, // 1.0 (18 decimals)
  isTakerBuy: true,
  validUntil: 1720000000n, // unix timestamp
  usd: 5n,
  collateralAsset: "0x0000000000000000000000000000000000000000" as Address,
};

const sig: `0x${string}` = "0x"; // TEE EIP-712 signature

// ---------- Encode ----------

type CustomInstruction = {
  targetContract: Address;
  value: bigint;
  data: `0x${string}`;
};

const customInstructions: CustomInstruction[] = [
  {
    targetContract: MOCK_GAMMA_ADDRESS,
    value: 0n,
    data: encodeFunctionData({
      abi: mockGammaAbi,
      functionName: "fillRFQ",
      args: [quote, sig],
    }),
  },
];

console.log("Custom instruction for MockGamma.fillRFQ():");
console.log(
  JSON.stringify(
    customInstructions,
    (_, v) => (typeof v === "bigint" ? v.toString() : v),
    2
  )
);
console.log("\nCalldata:", customInstructions[0].data);
