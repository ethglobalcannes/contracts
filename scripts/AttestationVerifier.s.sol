// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AttestationVerifier} from "../src/AttestationVerifier.sol";

address constant attestationVerifier = 0x027f7874bc35A691984f2545c05ac0E3C8616e2f; 
address constant registry = 0x3d478d43426081BD5854be9C7c5c183bfe76C981; 
address constant mockGamma = 0xEe5b0Ba2793267da967E800Ac926620742620D13;  

contract AttestationVerifierScript is Script {
    function run() external {
        vm.startBroadcast();

        AttestationVerifier(attestationVerifier).setRegistry(registry, "0x");
    
        vm.stopBroadcast();

       
    }
}
