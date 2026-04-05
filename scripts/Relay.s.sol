// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {Relay} from "../src/Relay.sol";

contract RelayScript is Script {
    function run() external returns (Relay relay) {
        address submitter = address(0x79d4a60F6da5f5d2fFa8B7833F592e6b4DF3ac4b);
        address quotePublisher = address(0x8062909712F90a8f78e42c75401086De3eE95fBe);
        address instructionSender = address(0xe578e001cb877849672f24A065060702F3eb1DB5);
        Relay relay = Relay(address(0x675b77bbd1d54B9358b44Ca9bf58244A37Ed5e59)); 

        vm.startBroadcast();
        relay.setSubmitter(0x0D729a3143fa3E78E3A3ebb2Df3207CCFB1857da);
        vm.stopBroadcast();
    }
}
