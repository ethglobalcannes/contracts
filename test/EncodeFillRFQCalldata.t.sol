// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract EncodeFillRFQCalldataTest is Test {
    function getFillRFQCalldata() public pure returns (bytes memory) {
        return abi.encodeWithSignature("fillRFQ()");
    }

    function test_getFillRFQCalldata() public pure {
        bytes memory callData = getFillRFQCalldata();
        assertEq(callData, hex"a9b9b162", "fillRFQ() calldata mismatch");
    }
}
