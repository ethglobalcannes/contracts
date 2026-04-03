// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockGamma} from "../src/MockGamma.sol";
import {AttestationVerifier} from "../src/AttestationVerifier.sol";

contract MockGammaScript is Script {

    address constant ATTESTATION_VERIFIER_ADDRESS = 0x027f7874bc35A691984f2545c05ac0E3C8616e2f;

    function run() external {

        vm.startBroadcast();

        MockGamma gamma = new MockGamma(ATTESTATION_VERIFIER_ADDRESS);

        vm.stopBroadcast();

        console.log("MockGamma:", address(gamma));
    }
}
