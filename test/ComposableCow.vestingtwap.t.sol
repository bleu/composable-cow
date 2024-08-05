// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import "../src/types/twap/VestingTWAP.sol";
import {VestingContextEncoder} from "../src/types/twap/libraries/VestingContextEncoder.sol";

contract ComposableCowVestingTWAPTest is Test, VestingContextEncoder {
    using SafeCast for uint256;

    ComposableCoW composableCow;
    VestingTWAP vestingTWAP;
    IVestingEscrow vestingEscrow;
    address owner;
    IERC20 sellToken;
    IERC20 buyToken;
    bytes32 appDataFirstOrder;
    bytes32 appDataTwap;
    bytes32 ctx;

    function setUp() public {
        vestingTWAP = new VestingTWAP(composableCow);
        sellToken = IERC20(address(0x01));
        buyToken = IERC20(address(0x02));
        owner = address(0x03);
        appDataFirstOrder = bytes32(abi.encodePacked(address(0x4)));
        appDataTwap = bytes32(abi.encodePacked(address(0x5)));
        ctx = keccak256("twapvesting");
    }

    function mockTwapVestingData(
        uint256 claimAmount,
        uint256 minPartLimit,
        uint256 minFirstPartLimit,
        uint256 span
    ) public returns (VestingTWAP.Data memory) {
        return
            VestingTWAP.Data({
                buyToken: buyToken,
                receiver: owner,
                vesting: vestingEscrow,
                claimAmount: claimAmount,
                appDataTwap: appDataTwap,
                appDataFirstOrder: appDataFirstOrder,
                minPartLimit: minPartLimit,
                span: span,
                minFirstPartLimit: minFirstPartLimit
            });
    }

    function mockContext(
        uint256 orderCreationTime,
        uint256 totalVested,
        uint256 startTime,
        uint256 endTime
    ) public {
        uint256 initialLockedAt = VestingMathLib.lockedAt(
            block.timestamp,
            startTime,
            endTime,
            totalVested,
            0
        );
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.totalLocked.selector),
            abi.encode(totalVested)
        );
        vm.mockCall(
            address(composableCow),
            abi.encodeWithSignature("cabinet(address,bytes32)", owner, ctx),
            abi.encode(
                VestingContextEncoder.encode(
                    orderCreationTime,
                    totalVested - initialLockedAt // assuming that the vesting contract was never claimed to simplify the tests
                )
            )
        );
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.startTime.selector),
            abi.encode(startTime)
        );
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.end_time.selector),
            abi.encode(endTime)
        );
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.cliffLength.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(vestingEscrow),
            abi.encodeWithSelector(IVestingEscrow.token.selector),
            abi.encode(sellToken)
        );
    }

    function test_VestingMathLib_lockedAt() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 100 days;
        uint256 totalLocked = 1e18;
        uint256 cliffLength = 10 days;

        assertEq(
            VestingMathLib.lockedAt(
                startTime,
                startTime,
                endTime,
                totalLocked,
                cliffLength
            ),
            totalLocked
        );

        assertEq(
            VestingMathLib.lockedAt(
                startTime + cliffLength,
                startTime,
                endTime,
                totalLocked,
                cliffLength
            ),
            totalLocked
        );

        assertEq(
            VestingMathLib.lockedAt(
                startTime + cliffLength + 1 days,
                startTime,
                endTime,
                totalLocked,
                cliffLength
            ),
            8.9e17
        );

        assertEq(
            VestingMathLib.lockedAt(
                endTime,
                startTime,
                endTime,
                totalLocked,
                cliffLength
            ),
            0
        );

        assertEq(
            VestingMathLib.lockedAt(
                endTime + 1,
                startTime,
                endTime,
                totalLocked,
                cliffLength
            ),
            0
        );
    }

    function test_VestingMathLib_calculatePeriod() public {
        uint256 initialVestingLocked = 1e18;
        uint256 endTime = block.timestamp + 100 days;
        uint256 orderCreationTime = block.timestamp;

        assertEq(
            VestingMathLib.calculatePeriod(
                1e17,
                endTime,
                orderCreationTime,
                initialVestingLocked
            ),
            10 days
        );
        assertEq(
            VestingMathLib.calculatePeriod(
                1e19,
                endTime,
                orderCreationTime,
                initialVestingLocked
            ),
            0
        );
    }

    function test_VestingMathLib_calculateBatchLength() public {
        uint256 initialVestingLocked = 1e18;

        assertEq(
            VestingMathLib.calculateBatchLenght(1e17, initialVestingLocked),
            10
        );
        assertEq(
            VestingMathLib.calculateBatchLenght(1e17 + 1, initialVestingLocked),
            9
        );
        assertEq(
            VestingMathLib.calculateBatchLenght(1e19, initialVestingLocked),
            0
        );
    }

    function test_getTradeableOrder_concrete() public {
        vm.warp(1722878593);
        uint256 totalVested = 2e20;
        uint256 minFirstPartLimit = 1e7;
        uint256 span = 0;
        uint256 claimAmount = 1e19;
        uint256 minPartLimit = 1e6;
        VestingTWAP.Data memory data = mockTwapVestingData(
            claimAmount,
            minPartLimit,
            minFirstPartLimit,
            span
        );
        bytes memory staticInput = abi.encode(data);

        mockContext(
            block.timestamp,
            totalVested,
            block.timestamp - 10 days,
            block.timestamp + 10 days
        );

        // check first order
        GPv2Order.Data memory order = vestingTWAP.getTradeableOrder(
            owner,
            address(0),
            ctx,
            staticInput,
            ""
        );

        assertEq(address(order.buyToken), address(buyToken));
        assertEq(address(order.sellToken), address(sellToken));
        assertEq(order.receiver, data.receiver);
        assertEq(order.sellAmount, 1e20);
        assertEq(order.buyAmount, data.minFirstPartLimit);
        assertGt(order.validTo, block.timestamp);
        assertEq(order.appData, data.appDataFirstOrder);
        assertEq(uint256(order.feeAmount), 0);
        assertEq(uint256(order.kind), uint256(GPv2Order.KIND_SELL));
        assertFalse(order.partiallyFillable);
        assertEq(
            uint256(order.sellTokenBalance),
            uint256(GPv2Order.BALANCE_ERC20)
        );
        assertEq(
            uint256(order.buyTokenBalance),
            uint256(GPv2Order.BALANCE_ERC20)
        );

        // test first twap order
        vm.warp(block.timestamp + 2 days);

        // check first order
        order = vestingTWAP.getTradeableOrder(
            owner,
            address(0),
            ctx,
            staticInput,
            ""
        );

        assertEq(address(order.buyToken), address(buyToken));
        assertEq(address(order.sellToken), address(sellToken));
        assertEq(order.receiver, data.receiver);
        assertEq(order.sellAmount, claimAmount);
        assertEq(order.buyAmount, data.minPartLimit);
        assertGt(order.validTo, block.timestamp);
        assertEq(order.appData, data.appDataTwap);
        assertEq(uint256(order.feeAmount), 0);
        assertEq(uint256(order.kind), uint256(GPv2Order.KIND_SELL));
        assertFalse(order.partiallyFillable);
        assertEq(
            uint256(order.sellTokenBalance),
            uint256(GPv2Order.BALANCE_ERC20)
        );
        assertEq(
            uint256(order.buyTokenBalance),
            uint256(GPv2Order.BALANCE_ERC20)
        );
    }

    function test_RevertOnVestingEnd_fuzz(
        uint256 orderCreationTime,
        uint256 vestingStartTime,
        uint256 span,
        uint256 vestingEndTime
    ) public {
        vm.assume(orderCreationTime > vestingEndTime);

        // guard against overflow
        vm.assume(orderCreationTime < type(uint32).max);
        vm.assume(vestingStartTime < type(uint32).max);
        vm.assume(vestingEndTime < type(uint32).max);
        vm.assume(span < type(uint32).max);

        VestingTWAP.Data memory data = mockTwapVestingData(
            1e16,
            1e16,
            1e16,
            span
        );
        bytes memory staticInput = abi.encode(data);

        mockContext(orderCreationTime, 1e20, vestingStartTime, vestingEndTime);

        vm.warp(vestingEndTime + span + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConditionalOrder.OrderNotValid.selector,
                VESTING_END
            )
        );

        vestingTWAP.getTradeableOrder(owner, address(0), ctx, staticInput, "");
    }

    function test_RevertLowFirstBatch_concrete() public {
        vm.warp(1722878593);

        uint256 totalVested = 1e18;
        uint256 claimAmount = 1e17;
        uint256 vestingPeriod = 10 days;
        VestingTWAP.Data memory data = mockTwapVestingData(
            claimAmount,
            0,
            0,
            0
        );

        bytes memory staticInput = abi.encode(data);

        uint256 twapPeriod = VestingMathLib.calculatePeriod(
            claimAmount,
            block.timestamp + vestingPeriod,
            block.timestamp,
            totalVested
        );

        mockContext(
            block.timestamp,
            totalVested,
            block.timestamp,
            block.timestamp + vestingPeriod
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IConditionalOrder.PollTryAtEpoch.selector,
                twapPeriod + block.timestamp,
                LOW_FIRST_BATCH
            )
        );
        vestingTWAP.getTradeableOrder(owner, address(0), ctx, staticInput, "");
    }

    function test_RevertInvalidClaimAmount_fuzz(
        uint256 claimAmount,
        uint256 totalVested
    ) public {
        vm.warp(1722878593);

        vm.assume(claimAmount < 1e40);
        vm.assume(totalVested < 1e40);

        vm.assume(claimAmount * 2 > totalVested || claimAmount == 0);

        uint256 startTime = block.timestamp - 10 days;
        VestingTWAP.Data memory data = mockTwapVestingData(
            claimAmount,
            0,
            0,
            0
        );

        bytes memory staticInput = abi.encode(data);

        mockContext(block.timestamp, totalVested, startTime, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConditionalOrder.OrderNotValid.selector,
                INVALID_CLAIM_AMOUNT
            )
        );
        vestingTWAP.getTradeableOrder(owner, address(0), ctx, staticInput, "");
    }
}
