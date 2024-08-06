// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW} from "../../ComposableCoW.sol";

import {IConditionalOrder, IConditionalOrderGenerator, GPv2Order, BaseConditionalOrder, IERC20} from "../../BaseConditionalOrder.sol";
import "./libraries/TWAPOrder.sol";
import {IVestingEscrow} from "../../interfaces/IVestingEscrow.sol";
import {VestingContextEncoder} from "./libraries/VestingContextEncoder.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {VestingMathLib} from "./libraries/VestingMathLib.sol";

// --- error strings

string constant NOT_WITHIN_SPAN = "not within span";
string constant VESTING_END = "vesting end";
string constant LOW_FIRST_BATCH = "low first batch";
string constant INVALID_CLAIM_AMOUNT = "invalid claim amount";

contract VestingTWAP is BaseConditionalOrder {
    using SafeCast for uint256;

    ComposableCoW public immutable composableCow;

    constructor(ComposableCoW _composableCow) {
        composableCow = _composableCow;
    }

    struct Data {
        IERC20 buyToken;
        address receiver;
        IVestingEscrow vesting;
        uint256 claimAmount;
        bytes32 appDataTwap; // should containg claim hook
        bytes32 appDataFirstOrder; // shouldn't contain claim hook
        uint256 minPartLimit;
        uint256 span;
        uint256 minFirstPartLimit;
    }

    function getTradeableOrder(
        address owner,
        address,
        bytes32 ctx,
        bytes calldata staticInput,
        bytes calldata
    ) public view override returns (GPv2Order.Data memory order) {
        Data memory data = abi.decode(staticInput, (Data));

        (
            uint256 orderCreationTime,
            uint256 initialClaimAmount
        ) = VestingContextEncoder.decode(composableCow.cabinet(owner, ctx));

        uint256 endTime = data.vesting.endTime();

        if (orderCreationTime > endTime) {
            revert IConditionalOrder.OrderNotValid(VESTING_END);
        }

        uint256 initialVestingLocked = VestingMathLib.lockedAt(
            orderCreationTime,
            data.vesting.startTime(),
            endTime,
            data.vesting.totalLocked(),
            data.vesting.cliffLength()
        );

        if (
            !VestingMathLib.verifyClaimAmount(
                data.claimAmount,
                initialVestingLocked
            )
        ) {
            revert IConditionalOrder.OrderNotValid(INVALID_CLAIM_AMOUNT);
        }

        uint256 period = VestingMathLib.calculatePeriod(
            data.claimAmount,
            endTime,
            orderCreationTime,
            initialVestingLocked
        );

        uint256 firstBatchValidFrom = orderCreationTime + period;

        if (block.timestamp > firstBatchValidFrom) {
            order = _twapOrder(
                data,
                firstBatchValidFrom,
                period,
                initialVestingLocked
            );
        } else {
            order = _firstOrder(data, firstBatchValidFrom, initialClaimAmount);
        }

        if (!(block.timestamp <= order.validTo)) {
            revert IConditionalOrder.OrderNotValid(NOT_WITHIN_SPAN);
        }
    }

    function _twapOrder(
        Data memory data,
        uint256 firstBatchValidFrom,
        uint256 period,
        uint256 initialVestingLocked
    ) internal view returns (GPv2Order.Data memory order) {
        uint256 n = VestingMathLib.calculateBatchLenght(
            data.claimAmount,
            initialVestingLocked
        );

        TWAPOrder.Data memory twap = TWAPOrder.Data({
            sellToken: data.vesting.token(),
            buyToken: data.buyToken,
            receiver: data.receiver,
            partSellAmount: data.claimAmount,
            minPartLimit: data.minPartLimit,
            t0: firstBatchValidFrom,
            n: n,
            t: period,
            span: data.span,
            appData: data.appDataTwap
        });

        order = TWAPOrder.orderFor(twap);
    }

    function _firstOrder(
        Data memory data,
        uint256 firstBatchValidFrom,
        uint256 initialClaimAmount
    ) internal view returns (GPv2Order.Data memory order) {
        IERC20 sellToken = data.vesting.token();

        if (data.buyToken == sellToken) {
            revert IConditionalOrder.OrderNotValid(INVALID_SAME_TOKEN);
        }

        if (
            !(address(data.buyToken) != address(0) &&
                address(data.buyToken) != address(0))
        ) {
            revert IConditionalOrder.OrderNotValid(INVALID_TOKEN);
        }

        if (firstBatchValidFrom > type(uint32).max) {
            revert IConditionalOrder.OrderNotValid(INVALID_START_TIME);
        }

        if (initialClaimAmount < data.claimAmount) {
            revert IConditionalOrder.PollTryAtEpoch(
                firstBatchValidFrom,
                LOW_FIRST_BATCH
            );
        }

        order = GPv2Order.Data({
            sellToken: sellToken,
            buyToken: data.buyToken,
            receiver: data.receiver,
            sellAmount: initialClaimAmount,
            buyAmount: data.minFirstPartLimit,
            validTo: (firstBatchValidFrom + data.span).toUint32(),
            appData: data.appDataFirstOrder,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }
}
