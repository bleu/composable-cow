pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/value_factories/VestingContextFactory.sol";
import "../../src/interfaces/IVestingEscrow.sol";

contract VestingContexFactoryTest is Test {
    VestingContextFactory public vestingContextFactory;
    IVestingEscrow public vestingEscrow;

    function setUp() public {
        vestingContextFactory = new VestingContextFactory();
    }

    function test_BytesToAddress_concrete() public {
        address testAddress = address(
            0x1234567890123456789012345678901234567890
        );
        bytes memory addressBytes = abi.encodePacked(testAddress);
        address result = vestingContextFactory.bytesToAddress(addressBytes);
        assertEq(result, testAddress, "bytesToAddress conversion failed");
    }

    function test_GetValue_concrete() public {
        uint256 unclaimedValue = 100 ether;
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.unclaimed.selector),
            abi.encode(unclaimedValue)
        );

        bytes memory addressBytes = abi.encodePacked(address(vestingEscrow));
        bytes32 result = vestingContextFactory.getValue(addressBytes);

        (
            uint256 timestampResult,
            uint256 unclaimedResult
        ) = VestingContextEncoder.decode(result);

        assertEq(timestampResult, block.timestamp, "Timestamp mismatch");
        assertEq(unclaimedValue, unclaimedResult, "Unclaimed value mismatch");
    }

    function test_RevertOnValueOverflow_concrete() public {
        uint256 overflowValue = uint256(type(uint216).max) + 1;
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.unclaimed.selector),
            abi.encode(overflowValue + 1)
        );

        bytes memory addressBytes = abi.encodePacked(address(vestingEscrow));
        vm.expectRevert("Value too large");
        vestingContextFactory.getValue(addressBytes);
    }

    function test_FuzzGetValue_fuzz(
        uint40 timestampValue,
        uint216 unclaimedValue
    ) public {
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.unclaimed.selector),
            abi.encode(unclaimedValue)
        );
        vm.warp(timestampValue);

        bytes memory addressBytes = abi.encodePacked(address(vestingEscrow));
        bytes32 result = vestingContextFactory.getValue(addressBytes);

        (
            uint256 timestampResult,
            uint256 unclaimedResult
        ) = VestingContextEncoder.decode(result);

        assertEq(timestampResult, timestampValue, "Fuxx: Timestamp mismatch");
        assertEq(
            unclaimedResult,
            unclaimedValue,
            "Fuzz: Unclaimed value mismatch"
        );
    }

    function test_RevertOnValueOverflow_fuzz(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint216).max);
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.unclaimed.selector),
            abi.encode(overflowValue)
        );

        bytes memory addressBytes = abi.encodePacked(address(vestingEscrow));
        vm.expectRevert("Value too large");
        vestingContextFactory.getValue(addressBytes);
    }
}
