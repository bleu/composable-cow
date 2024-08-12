// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

library VestingMathLib {
    using Math for uint256;
    using SafeMath for uint256;

    function lockedAt(
        uint256 time,
        uint256 startTime,
        uint256 endTime,
        uint256 totalLocked,
        uint256 cliffLength
    ) public pure returns (uint256) {
        if (time <= startTime + cliffLength) {
            return totalLocked;
        }
        if (time >= endTime) {
            return 0;
        }

        return totalLocked.mulDiv(endTime.sub(time), endTime.sub(startTime));
    }

    function calculatePeriod(
        uint256 claimAmount,
        uint256 endTime,
        uint256 orderCreationTime,
        uint256 initialVestingLocked
    ) public pure returns (uint256) {
        if (claimAmount > initialVestingLocked) {
            return 0;
        }
        return
            claimAmount.mulDiv(
                endTime.sub(orderCreationTime),
                initialVestingLocked
            );
    }

    function calculateBatchLenght(
        uint256 claimAmount,
        uint256 initialVestingLocked
    ) public pure returns (uint256) {
        return initialVestingLocked.div(claimAmount);
    }

    function verifyClaimAmount(
        uint256 claimAmount,
        uint256 initialVestingLocked
    ) public pure returns (bool) {
        return claimAmount > 0 && claimAmount.div(2) < initialVestingLocked;
    }
}
