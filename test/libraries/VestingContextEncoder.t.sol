// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/types/twap/libraries/VestingContextEncoder.sol";
import "../../src/interfaces/IVestingEscrow.sol";

contract VestingContextEncoderTest is Test {
    function test_Encode_concrete() public {
        uint256 timestamp = 1234567890; // Example timestamp
        uint256 value = 1 ether; // Example value
        bytes32 encoded = VestingContextEncoder.encode(timestamp, value);

        assertEq(
            uint256(encoded) & ((1 << 40) - 1),
            timestamp,
            "Timestamp encoding failed"
        );
        assertEq(uint256(encoded) >> 40, value, "Value encoding failed");
    }

    function test_Decode_concrete() public {
        uint256 timestamp = 1234567890;
        uint256 value = 1 ether;
        bytes32 encoded = VestingContextEncoder.encode(timestamp, value);

        (uint256 decodedTimestamp, uint256 decodedValue) = VestingContextEncoder
            .decode(encoded);

        assertEq(decodedTimestamp, timestamp, "Timestamp decoding failed");
        assertEq(decodedValue, value, "Value decoding failed");
    }

    function test_EncodeMaxValue_concrete() public {
        uint256 maxTimestamp = (1 << 40) - 1;
        uint256 maxValue = (1 << 216) - 1;
        bytes32 encoded = VestingContextEncoder.encode(maxTimestamp, maxValue);

        (uint256 decodedTimestamp, uint256 decodedValue) = VestingContextEncoder
            .decode(encoded);

        assertEq(
            decodedTimestamp,
            maxTimestamp,
            "Max timestamp encoding/decoding failed"
        );
        assertEq(decodedValue, maxValue, "Max value encoding/decoding failed");
    }

    function test_FailOnEncodeTimestampTooLarge_concrete() public {
        uint256 tooLargeTimestamp = 1 << 40;
        uint256 value = 1 ether;

        vm.expectRevert("Timestamp too large");
        VestingContextEncoder.encode(tooLargeTimestamp, value);
    }

    function test_FailOnEncodeValueTooLarge_concrete() public {
        uint256 timestamp = 1234567890;
        uint256 tooLargeValue = 1 << 216;

        vm.expectRevert("Value too large");
        VestingContextEncoder.encode(timestamp, tooLargeValue);
    }

    function test_EncodeDecode_fuzz(uint40 timestamp, uint216 value) public {
        bytes32 encoded = VestingContextEncoder.encode(timestamp, value);
        (uint256 decodedTimestamp, uint256 decodedValue) = VestingContextEncoder
            .decode(encoded);
        assertEq(
            decodedTimestamp,
            timestamp,
            "Fuzz: Timestamp encoding/decoding failed"
        );
        assertEq(decodedValue, value, "Fuzz: Value encoding/decoding failed");
    }

    function test_EncodeTimestampTooLarge_fuzz(uint256 timestamp) public {
        vm.assume(timestamp > ((1 << 40) - 1));
        uint256 value = 1 ether;

        vm.expectRevert("Timestamp too large");
        VestingContextEncoder.encode(timestamp, value);
    }

    function test_EncodeValueTooLarge_fuzz(uint256 value) public {
        vm.assume(value > ((1 << 216) - 1));
        uint256 timestamp = 1234567890;

        vm.expectRevert("Value too large");
        VestingContextEncoder.encode(timestamp, value);
    }
}
