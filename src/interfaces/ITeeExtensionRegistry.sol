// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface ITeeExtensionRegistry {
    struct TeeInstructionParams {
        bytes32 opType;
        bytes32 opCommand;
        bytes message;
        address[] cosigners;
        uint64 cosignersThreshold;
        address claimBackAddress;
    }

    function sendInstructions(
        address[] memory _teeIds,
        TeeInstructionParams memory _instructionParams
    ) external payable returns (bytes32 _instructionId);

    function extensionsCounter() external view returns (uint256);

    function getTeeExtensionInstructionsSender(uint256 _extensionId)
        external view returns (address);
}