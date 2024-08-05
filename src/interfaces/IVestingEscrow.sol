// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;
import {IERC20} from "../BaseConditionalOrder.sol";

/**
 * @title TBD
 * @dev TBD
 */
interface IVestingEscrow {
    function token() external view returns (IERC20);
    /* solhint-disable-next-line func-name-mixedcase*/
    function open_claim() external view returns (bool);
    function unclaimed() external view returns (uint256);
    function locked() external view returns (uint256);
    function recipient() external view returns (address);
    /* solhint-disable-next-line func-name-mixedcase*/
    function end_time() external view returns (uint256);
    function startTime() external view returns (uint256);
    function totalLocked() external view returns (uint256);
    function cliffLength() external view returns (uint256);
}
