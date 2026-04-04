// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InstructionSender} from "../src/InstructionSender.sol";

address constant TEE_EXTENSION_REGISTRY = 0x3d478d43426081BD5854be9C7c5c183bfe76C981;
address constant TEE_MACHINE_REGISTRY = 0x5918Cd58e5caf755b8584649Aa24077822F87613;
address constant INSTRUCTION_SENDER = 0xFB1b157D9Ac73eE490C764c908a16E6E5097f99E;
address constant MASTER_ACCOUNT_CONTROLLER = 0x434936d47503353f06750Db1A444DBDC5F0AD37c;
address constant MOCK_GAMMA = 0xEe5b0Ba2793267da967E800Ac926620742620D13;

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
    function run() external {
        // Paste your calldata from encodeCustomInstruction.ts here
        bytes memory callData = "0xe7b1faf10000000000000000000000000b6a3645c240605887a5532109323a3e12273dc7000000000000000000000000000000000000000000000000000000000000007200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000000000000066851e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000b1a2bc2ec500000000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000066851e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000";

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
    }
}
