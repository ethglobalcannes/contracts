// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITeeExtensionRegistry} from "./interfaces/ITeeExtensionRegistry.sol";
import {ITeeMachineRegistry} from "./interfaces/ITeeMachineRegistry.sol";

contract InstructionSender {
    bytes32 public constant OP_TYPE_PRICING = bytes32("PRICING");
    bytes32 public constant OP_COMMAND_QUOTE = bytes32("QUOTE");

    ITeeExtensionRegistry public immutable TEE_EXTENSION_REGISTRY;
    ITeeMachineRegistry public immutable TEE_MACHINE_REGISTRY;

    address public owner; 

    uint256 private _extensionId;

    constructor(
        address _teeExtensionRegistry,
        address _teeMachineRegistry
    ) {
        TEE_EXTENSION_REGISTRY = ITeeExtensionRegistry(_teeExtensionRegistry);
        TEE_MACHINE_REGISTRY = ITeeMachineRegistry(_teeMachineRegistry);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Not the owner"); 
        _; 
    }

    /// @notice Finds and sets this contract's extension ID. Can only be set once.
    function setExtensionId() external {
        require(_extensionId == 0, "Extension ID already set.");

        uint256 c = TEE_EXTENSION_REGISTRY.extensionsCounter();
        for (uint256 i = 0; i < c; ++i) {
            if (TEE_EXTENSION_REGISTRY.getTeeExtensionInstructionsSender(i) == address(this)) {
                _extensionId = i;
                return;
            }
        }
        revert("Extension ID not found.");
    }

    /// @notice Send an instruction to the TEE.
    /// @param message ABI-encoded instruction params
    function sendInstruction(bytes calldata message) external payable onlyOwner returns (bytes32) {
        address[] memory teeIds = TEE_MACHINE_REGISTRY.getRandomTeeIds(_getExtensionId(), 1);
        address[] memory cosigners = new address[](0);

        ITeeExtensionRegistry.TeeInstructionParams memory params = ITeeExtensionRegistry.TeeInstructionParams({
            opType: OP_TYPE_PRICING,
            opCommand: OP_COMMAND_QUOTE,
            message: message,
            cosigners: cosigners,
            cosignersThreshold: 0,
            claimBackAddress: msg.sender
        });

        return TEE_EXTENSION_REGISTRY.sendInstructions{value: msg.value}(teeIds, params);
    }

    function getExtensionId() external view returns (uint256) {
        return _getExtensionId();
    }

    function _getExtensionId() internal view returns (uint256) {
        require(_extensionId != 0, "Extension ID is not set.");
        return _extensionId;
    }
}
