// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {Relay} from "../src/Relay.sol";

contract RelayScript is Script {
    function run() external returns (Relay relay) {
        address smartAccount = address(0);
        address quotePublisher = address(0);

        vm.startBroadcast();
        relay = new Relay(smartAccount, quotePublisher);
        vm.stopBroadcast();
    }
}
