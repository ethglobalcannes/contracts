// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AttestationVerifier} from "../src/AttestationVerifier.sol";

contract AttestationVerifierScript is Script {
    function run() external {
        vm.startBroadcast();

        AttestationVerifier verifier = new AttestationVerifier(
            address(0), // registry — set later
            bytes32(0), // extensionId — set later
            address(0)  // verifyingContract (MockGamma) — set later
        );

        vm.stopBroadcast();

        console.log("AttestationVerifier deployed at:", address(verifier));
    }
}
