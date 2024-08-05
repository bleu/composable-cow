// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IVestingEscrow} from "../../../interfaces/IVestingEscrow.sol";
import {VestingContextEncoder} from "./VestingContextEncoder.sol";

contract VestingContext is VestingContextEncoder {
    uint256 private constant _TIMESTAMP_BITS = 40;
    uint256 private constant _VALUE_BITS = 104;

    uint256 private constant _TIMESTAMP_MASK = (1 << _TIMESTAMP_BITS) - 1;
    uint256 private constant _VALUE_MASK = (1 << _VALUE_BITS) - 1;

    function getValue(bytes memory data) public view returns (bytes32) {
        IVestingEscrow vestingContract = IVestingEscrow(bytesToAddress(data));
        return
            VestingContextEncoder.encode(
                block.timestamp,
                vestingContract.unclaimed()
            );
    }

    function bytesToAddress(bytes memory _bytes) public pure returns (address) {
        require(_bytes.length == 20, "Invalid address length");
        address addr;
        assembly {
            addr := mload(add(_bytes, 20))
        }
        return addr;
    }
}
