// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InstructionSender} from "../src/InstructionSender.sol";
import {MockGamma} from "../src/MockGamma.sol";

address constant TEE_EXTENSION_REGISTRY = 0x3d478d43426081BD5854be9C7c5c183bfe76C981;
address constant TEE_MACHINE_REGISTRY = 0x5918Cd58e5caf755b8584649Aa24077822F87613;
address constant INSTRUCTION_SENDER = 0xe578e001cb877849672f24A065060702F3eb1DB5;
address constant MASTER_ACCOUNT_CONTROLLER = 0x434936d47503353f06750Db1A444DBDC5F0AD37c;
address constant MOCK_GAMMA = 0x51947aC30bB1F289F20bA740E1664cE20E23F94A;

interface IMasterAccountController {
    struct CustomCall {
        address targetContract;
        uint256 value;
        bytes data;
    }

    function registerCustomInstruction(CustomCall[] calldata _customInstruction) external;
    function encodeCustomInstruction(CustomCall[] calldata _customInstruction) external view returns (bytes32);
}

contract RegisterExtensionIdScript is Script {
    function run() external {
        vm.startBroadcast();
        InstructionSender(INSTRUCTION_SENDER).setExtensionId();
        vm.stopBroadcast();
    }
}

contract InstructionSenderScript is Script {
    function run() external {

        vm.startBroadcast();

        address newInstruction = address(new InstructionSender(TEE_EXTENSION_REGISTRY, TEE_MACHINE_REGISTRY));
        console.log("New InstructionSender deployed at:", newInstruction);

        vm.stopBroadcast(); 
    }
}

contract RegisterCustomInstructionScript is Script {
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;

    function run() external {
        // Build the fillRFQ calldata in Solidity (no more hardcoded hex)
        MockGamma.Quote memory quote = MockGamma.Quote({
            assetAddress: FXRP,
            chainId: 114,
            isPut: false,
            strike: 2000000000000000000,
            expiry: 1720000000,
            maker: 0x8062909712F90a8f78e42c75401086De3eE95fBe,
            nonce: 1,
            price: 50000000000000000,
            quantity: 1000000000000000000,
            isTakerBuy: true,
            validUntil: 1720000000,
            usd: 5,
            collateralAsset: address(0)
        });
        bytes memory sig = "";

        bytes memory callData = abi.encodeWithSelector(MockGamma.fillRFQ.selector, quote, sig);

        IMasterAccountController.CustomCall[] memory calls = new IMasterAccountController.CustomCall[](1);
        calls[0] = IMasterAccountController.CustomCall({
            targetContract: MOCK_GAMMA,
            value: 0,
            data: callData
        });

        vm.startBroadcast();
        IMasterAccountController(MASTER_ACCOUNT_CONTROLLER).registerCustomInstruction(calls);
        vm.stopBroadcast();

        // Get the call hash for the XRPL payment reference
        bytes32 callHash = IMasterAccountController(MASTER_ACCOUNT_CONTROLLER).encodeCustomInstruction(calls);
        console.log("Custom instruction registered");
        console.log("Call hash:", vm.toString(callHash));

        // Build the 32-byte payment reference: 0xff + walletId(0) + 30-byte hash
        bytes32 paymentRef = bytes32(
            uint256(0xff) << 248 |
            uint256(0x00) << 240 |
            uint256(callHash)
        );
        console.log("Payment reference:", vm.toString(paymentRef));
    }
}
