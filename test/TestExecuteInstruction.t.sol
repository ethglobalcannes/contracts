// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockGamma} from "../src/MockGamma.sol";

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
    address constant MOCK_GAMMA = 0xEe5b0Ba2793267da967E800Ac926620742620D13;
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;

    address public caller = 0xcA0Bf4Cbc1Cf8c4b5FD7984b42AF907099084466;

    function setUp() public {
        vm.createSelectFork("https://coston2-api.flare.network/ext/C/rpc");
    }

    function _buildCalldata() internal pure returns (bytes memory) {
        MockGamma.Quote memory quote = MockGamma.Quote({
            assetAddress: FXRP,
            chainId: 114,
            isPut: false,
            strike: 2000000000000000000,
            expiry: 1720000000,
            maker: 0x8062909712F90a8f78e42c75401086De3eE95fBe,
            nonce: 1,
            price: 50000000000000000,
            quantity: 1000000000000000000,
            isTakerBuy: true,
            validUntil: 1720000000,
            usd: 5,
            collateralAsset: address(0)
        });
        bytes memory sig = "";

        return abi.encodeWithSelector(MockGamma.fillRFQ.selector, quote, sig);
    }

    // Test 1: Compare Solidity-encoded vs TS-encoded calldata byte-by-byte
    function test_compareCalldata() public pure {
        bytes memory solidityCalldata = _buildCalldata();

        bytes memory tsCalldata = hex"e7b1faf10000000000000000000000000b6a3645c240605887a5532109323a3e12273dc7000000000000000000000000000000000000000000000000000000000000007200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000000000000066851e000000000000000000000000008062909712f90a8f78e42c75401086de3ee95fbe000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000b1a2bc2ec500000000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000066851e000000000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000";

        console.log("Solidity calldata length:", solidityCalldata.length);
        console.log("TS calldata length:", tsCalldata.length);

        console.log("\nSolidity calldata:");
        console.logBytes(solidityCalldata);

        console.log("\nTS calldata:");
        console.logBytes(tsCalldata);

        assertEq(keccak256(solidityCalldata), keccak256(tsCalldata), "Calldata mismatch between Solidity and TS!");
    }

    // Test 2: Compute call hash locally and compare with contract
    function test_hashComparison() public view {
        bytes memory callData = _buildCalldata();

        IMasterAccountController.CustomCall[] memory calls = new IMasterAccountController.CustomCall[](1);
        calls[0] = IMasterAccountController.CustomCall({
            targetContract: MOCK_GAMMA,
            value: 0,
            data: callData
        });

        // Local computation (same formula from Flare docs)
        bytes32 rawHash = keccak256(abi.encode(calls));
        bytes32 localHash = bytes32(uint256(rawHash) & ((1 << 240) - 1));

        // Contract computation
        bytes32 contractHash = IMasterAccountController(MASTER_ACCOUNT_CONTROLLER).encodeCustomInstruction(calls);

        console.log("Local call hash: ", vm.toString(localHash));
        console.log("Contract call hash:", vm.toString(contractHash));

        assertEq(localHash, contractHash, "Hash mismatch between local and contract!");
    }

    // Test 3: Register with TS calldata, then check if Solidity calldata produces same hash
    function test_tsVsSolidityHash() public {
        bytes memory tsCalldata = hex"e7b1faf10000000000000000000000000b6a3645c240605887a5532109323a3e12273dc7000000000000000000000000000000000000000000000000000000000000007200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000000000000066851e000000000000000000000000008062909712f90a8f78e42c75401086de3ee95fbe000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000b1a2bc2ec500000000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000066851e000000000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000";
        bytes memory solCalldata = _buildCalldata();

        IMasterAccountController mac = IMasterAccountController(MASTER_ACCOUNT_CONTROLLER);

        // Hash with TS calldata
        IMasterAccountController.CustomCall[] memory calls = new IMasterAccountController.CustomCall[](1);
        calls[0] = IMasterAccountController.CustomCall({
            targetContract: MOCK_GAMMA,
            value: 0,
            data: tsCalldata
        });
        bytes32 tsHash = mac.encodeCustomInstruction(calls);

        // Hash with Solidity calldata
        calls[0].data = solCalldata;
        bytes32 solHash = mac.encodeCustomInstruction(calls);

        console.log("TS calldata hash:      ", vm.toString(tsHash));
        console.log("Solidity calldata hash:", vm.toString(solHash));
        console.log("TS calldata length:    ", tsCalldata.length);
        console.log("Solidity calldata length:", solCalldata.length);

        if (tsHash != solHash) {
            console.log("\n>>> BUG FOUND: calldata differs between TS and Solidity encoding");
        } else {
            console.log("\n>>> Calldata matches - bug is elsewhere");
        }
    }

    // Test 4: Full flow - register then simulate execution
    function test_registerAndExecute_onFork() public {
        bytes memory callData = _buildCalldata();

        IMasterAccountController.CustomCall[] memory calls = new IMasterAccountController.CustomCall[](1);
        calls[0] = IMasterAccountController.CustomCall({
            targetContract: MOCK_GAMMA,
            value: 0,
            data: callData
        });

        IMasterAccountController mac = IMasterAccountController(MASTER_ACCOUNT_CONTROLLER);

        // Register
        vm.prank(caller);
        mac.registerCustomInstruction(calls);

        // Get hash
        bytes32 callHash = mac.encodeCustomInstruction(calls);
        console.log("Registered call hash:", vm.toString(callHash));

        // Build the 32-byte payment reference: 0xff + walletId(0) + 30-byte hash
        bytes32 paymentRef = bytes32(
            uint256(0xff) << 248 |  // byte 1: 0xff
            uint256(0x00) << 240 |  // byte 2: walletId = 0
            uint256(callHash)       // bytes 3-32: call hash (already masked to 30 bytes)
        );
        console.log("Payment reference:", vm.toString(paymentRef));
    }
}
