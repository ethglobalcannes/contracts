// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {Relay} from "../src/Relay.sol";

contract RelayScript is Script {
    function run() external returns (Relay relay) {
        address smartAccount = address(0);
        address quotePublisher = address(0);
        address instructionSender = address(0xFB1b157D9Ac73eE490C764c908a16E6E5097f99E);
        Relay relay = Relay(address(0x7BE27E427a0e1a605bf821CEA5E062c3a8ad15a7)); 

        vm.startBroadcast();
        relay.setQuotePublisher(0x8062909712F90a8f78e42c75401086De3eE95fBe);
        vm.stopBroadcast();
    }
}
