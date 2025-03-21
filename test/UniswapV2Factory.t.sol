// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory factory;
    address tokenA = address(0x100);
    address tokenB = address(0x200);

    function setUp() public {
        // 部署 Factory 合约，owner 设置为当前合约地址（或其他测试地址）
        factory = new UniswapV2Factory(address(this));
    }

    function testCreatePair() public {
        // 创建交易对
        address pair = factory.createPair(tokenA, tokenB);
        assertTrue(pair != address(0), "Pair address should not be zero");

        // 验证 UniswapV2Pair 中 token 排序规则（假设内部通过 initialize 或构造函数设置 token0/token1）
        UniswapV2Pair pairContract = UniswapV2Pair(pair);
        address expectedToken0 = tokenA < tokenB ? tokenA : tokenB;
        address expectedToken1 = tokenA < tokenB ? tokenB : tokenA;
        assertEq(pairContract.token0(), expectedToken0, "token0 error");
        assertEq(pairContract.token1(), expectedToken1, "token1 error");
    }

    // 你可以添加测试：重复创建同一交易对时是否返回相同地址或者抛出错误
}
