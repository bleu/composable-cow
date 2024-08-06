// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

import {ComposableCoW} from "../src/ComposableCoW.sol";

import {VestingTWAP} from "../src/types/twap/VestingTWAP.sol";
import {VestingContextFactory} from "../src/value_factories/VestingContextFactory.sol";

contract DeployVestingTwap is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address composableCow = vm.envAddress("COMPOSABLE_COW");
        vm.startBroadcast(deployerPrivateKey);

        new VestingTWAP(ComposableCoW(composableCow));
        new VestingContextFactory();

        vm.stopBroadcast();
    }
}
