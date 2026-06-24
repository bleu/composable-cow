// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW} from "../../ComposableCoW.sol";

import {
    IConditionalOrder,
    IConditionalOrderGenerator,
    GPv2Order,
    BaseConditionalOrder
} from "../../BaseConditionalOrder.sol";
import {TWAPOrder} from "./libraries/TWAPOrder.sol";

// --- error strings

/// @dev The order is not within the TWAP bundle's span.
string constant NOT_WITHIN_SPAN = "not within span";

/// @dev Polling hint reason: current block is before `t0`, the first part's start.
string constant BEFORE_FIRST_PART = "before first part";

/// @dev Polling hint reason: every part of the TWAP has been settled / passed.
string constant ALL_PARTS_SETTLED = "all parts settled";

/// @dev Polling hint reason: in-progress TWAP, currently between parts (current
/// part's `validTo` is in the past and the next part has not started yet).
string constant BETWEEN_PARTS = "between parts";

/**
 * @title TWAP Conditional Order
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @notice TWAP conditional orders allow for splitting an order into a series of orders that are
 * executed at a fixed interval. This is useful for ensuring that a trade is executed at a
 * specific price, even if the price of the token changes during the trade.
 * @dev Designed to be used with the CoW Protocol Conditional Order Framework.
 */
contract TWAP is BaseConditionalOrder {
    ComposableCoW public immutable composableCow;

    constructor(ComposableCoW _composableCow) {
        composableCow = _composableCow;
    }

    /**
     * @inheritdoc IConditionalOrderGenerator
     * @dev `owner`, `sender` and `offchainInput` is not used.
     */
    function getTradeableOrder(address owner, address, bytes32 ctx, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory order)
    {
        /**
         * @dev Decode the payload into a TWAP bundle and get the order. `orderFor` will revert if
         * there is no current valid order.
         * NOTE: This will return an order even if the part of the TWAP bundle that is currently
         * valid is filled. This is safe as CoW Protocol ensures that each `orderUid` is only
         * settled once.
         */
        TWAPOrder.Data memory twap = abi.decode(staticInput, (TWAPOrder.Data));

        /**
         * @dev If `twap.t0` is set to 0, then get the start time from the context.
         */
        if (twap.t0 == 0) {
            twap.t0 = uint256(composableCow.cabinet(owner, ctx));
        }

        /**
         * @dev Validate the bundle FIRST so that invalid configurations (bad token, invalid
         * `n`, invalid `t`, etc.) still surface as `OrderNotValid(...)` exactly like before,
         * rather than being shadowed by the polling-hint branches below. `validate()` is
         * idempotent — `orderFor()` (called later) calls it again, but it is `pure` and
         * cheap, so the duplication is benign.
         */
        TWAPOrder.validate(twap);

        /**
         * @dev Precise polling hints for watch towers.
         *
         * `IConditionalOrder` defines `PollTryAtEpoch` and `PollNever` specifically for
         * watch-tower polling optimisation, but `TWAP.sol` historically reverted with the
         * generic `OrderNotValid("not within span")` (and `orderFor` would revert with
         * `OrderNotValid("before twap start")` / `"after twap finish"`) — neither of which
         * tells a watch tower when to retry. The branches below replace those generic
         * reverts with precise polling hints; the existing `OrderNotValid(NOT_WITHIN_SPAN)`
         * remains as a defensive fallback at the bottom (should be unreachable).
         */

        // Before the first part starts → tell the watch tower to retry at `t0`.
        if (block.timestamp < twap.t0) {
            revert IConditionalOrder.PollTryAtEpoch(twap.t0, BEFORE_FIRST_PART);
        }

        // After the last part has ended → tell the watch tower to stop polling.
        // `validate()` above guarantees `n > 1` and `t > 0`, so `twap.n * twap.t` cannot
        // underflow / be zero here. The end timestamp is exclusive: `block.timestamp ==
        // t0 + n*t` is already done.
        if (block.timestamp >= twap.t0 + twap.n * twap.t) {
            revert IConditionalOrder.PollNever(ALL_PARTS_SETTLED);
        }

        order = TWAPOrder.orderFor(twap);

        /**
         * @dev If `block.timestamp > order.validTo` we are between parts of an in-progress
         * TWAP (the current part's span has elapsed but the next part hasn't started yet).
         * Compute the next part's start timestamp and tell the watch tower to retry then.
         *
         * Math: `part = (block.timestamp - twap.t0) / twap.t` is the 0-indexed current part;
         * the next part starts at `twap.t0 + (part + 1) * twap.t`. Bounds are guaranteed by
         * the two checks above: `block.timestamp >= twap.t0` and
         * `block.timestamp < twap.t0 + twap.n * twap.t`, so `part < twap.n` and
         * `(part + 1) * twap.t <= twap.n * twap.t` cannot overflow under the same bounds
         * that `TWAPOrderMathLib.calculateValidTo` already asserts on.
         */
        if (block.timestamp > order.validTo) {
            uint256 nextPartStart = twap.t0 + (((block.timestamp - twap.t0) / twap.t) + 1) * twap.t;
            revert IConditionalOrder.PollTryAtEpoch(nextPartStart, BETWEEN_PARTS);
        }

        /// @dev Defensive fallback — the three branches above should cover every case
        /// where `block.timestamp > order.validTo` for a valid TWAP; this keeps the original
        /// taxonomy entry so any unknown edge surfaces as a well-known error rather than
        /// returning a stale order.
        if (!(block.timestamp <= order.validTo)) {
            revert IConditionalOrder.OrderNotValid(NOT_WITHIN_SPAN);
        }
    }
}
