// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {Relay} from "../src/Relay.sol";

contract RelayScript is Script {
    function run() external returns (Relay relay) {
        address smartAccount = address(0);
        address quotePublisher = address(0);
        address instructionSender = address(0xFB1b157D9Ac73eE490C764c908a16E6E5097f99E);

        vm.startBroadcast();
        relay = new Relay(smartAccount, quotePublisher, instructionSender);
        vm.stopBroadcast();
    }
}
