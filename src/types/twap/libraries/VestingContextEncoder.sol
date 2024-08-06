// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant TIMESTAMP_TOO_LARGE = "Timestamp too large";
string constant VALUE_TOO_LARGE = "Value too large";

library VestingContextEncoder {
    uint256 private constant _TIMESTAMP_BITS = 40;
    uint256 private constant _VALUE_BITS = 216; // Increased to use all remaining bits

    uint256 private constant _TIMESTAMP_MASK = (1 << _TIMESTAMP_BITS) - 1;
    uint256 private constant _VALUE_MASK = (1 << _VALUE_BITS) - 1;

    function encode(
        uint256 timestamp,
        uint256 value
    ) public pure returns (bytes32) {
        require(timestamp <= _TIMESTAMP_MASK, TIMESTAMP_TOO_LARGE);
        require(value <= _VALUE_MASK, VALUE_TOO_LARGE);

        return bytes32((value << _TIMESTAMP_BITS) | timestamp);
    }

    function decode(
        bytes32 encoded
    ) public pure returns (uint256 timestamp, uint256 value) {
        uint256 decoded = uint256(encoded);

        timestamp = decoded & _TIMESTAMP_MASK;
        value = (decoded >> _TIMESTAMP_BITS) & _VALUE_MASK;
    }
}
