// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/UniswapV2Pair.sol";
import "./ComputePairHash.sol";

contract ComputePairHashScript is Script {
    function run() external {
        ComputePairHash helper = new ComputePairHash();
        bytes32 hash = helper.getPairHash();
        console.logBytes32(hash);
    }
}
