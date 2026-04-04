// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

interface IMasterAccountController {
    struct CustomCall {
        address targetContract;
        uint256 value;
        bytes data;
    }

    function registerCustomInstruction(CustomCall[] calldata _customInstruction) external;
    function encodeCustomInstruction(CustomCall[] calldata _customInstruction) external view returns (bytes32);
}

contract TestExecuteInstruction is Test {
    address constant MASTER_ACCOUNT_CONTROLLER = 0x434936d47503353f06750Db1A444DBDC5F0AD37c;
    address constant MOCK_GAMMA = 0x51947aC30bB1F289F20bA740E1664cE20E23F94A;

    // Test: encode custom instruction with simple fillRFQ() calldata
    function test_encodeCustomInstruction() public {
        // fillRFQ() has no params, calldata is just the 4-byte selector
        bytes memory callData = abi.encodeWithSignature("fillRFQ()");

        IMasterAccountController.CustomCall[] memory calls = new IMasterAccountController.CustomCall[](1);
        calls[0] = IMasterAccountController.CustomCall({
            targetContract: MOCK_GAMMA,
            value: 0,
            data: callData
        });

        // Encode and log the instruction hash
        bytes32 callHash = IMasterAccountController(MASTER_ACCOUNT_CONTROLLER).encodeCustomInstruction(calls);
        console.log("Call hash:", vm.toString(callHash));

        // Verify hash is non-zero (masked to 30 bytes)
        assertTrue(callHash != bytes32(0), "Call hash should be non-zero");
    }

    function test_sadf() public 
}
