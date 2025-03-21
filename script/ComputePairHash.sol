// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "../src/UniswapV2Pair.sol";

contract ComputePairHash {
    // 此函数返回 UniswapV2Pair 合约 creation code 的 keccak256 哈希值
    function getPairHash() external pure returns (bytes32) {
        return keccak256(type(UniswapV2Pair).creationCode);
    }
}
