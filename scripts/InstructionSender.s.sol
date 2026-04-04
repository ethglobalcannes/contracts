// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InstructionSender} from "../src/InstructionSender.sol";

contract InstructionSenderScript is Script {
    address constant TEE_EXTENSION_REGISTRY = 0x3d478d43426081BD5854be9C7c5c183bfe76C981;
    address constant TEE_MACHINE_REGISTRY = 0x5918Cd58e5caf755b8584649Aa24077822F87613;

    function run() external {
        vm.startBroadcast();

        InstructionSender sender = new InstructionSender(TEE_EXTENSION_REGISTRY, TEE_MACHINE_REGISTRY);

        vm.stopBroadcast();

        console.log("InstructionSender deployed at:", address(sender));
    }
}
