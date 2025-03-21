// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router02.sol";
import "../src/UniswapV2Pair.sol";

/// @notice 简单的 ERC20 模拟合约，用于测试 Router 中的代币交互
contract ERC20Mock {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint256 _supply) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupply = _supply;
        balanceOf[msg.sender] = _supply;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] -= amount;
        return true;
    }
}

contract UniswapV2Router02Test is Test {
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    function setUp() public {
        // 部署 Factory 和 Router 合约
        factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(0));



        // 部署两个模拟 ERC20 代币
        tokenA = new ERC20Mock("TokenA", "TKA", 1e24);
        tokenB = new ERC20Mock("TokenB", "TKB", 1e24);

        // 为 Router 授权（允许 Router 转移代币）
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // 通过 Factory 创建交易对
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testAddLiquidity() public {
        uint256 amountA = 1e18;
        uint256 amountB = 2e18;
        address pairFromFactory = IUniswapV2Factory(factory).getPair(address(tokenA), address(tokenB));
        address pairFromLibrary = UniswapV2Library.pairFor(address(factory), address(tokenA), address(tokenB));
        console.log("pairFromFactory:");
        console.logAddress(pairFromFactory);
        console.log("pairFromLibrary:");
        console.logAddress(pairFromLibrary);

        // 调用 Router 的 addLiquidity 方法添加流动性
        (uint256 amountAUsed, uint256 amountBUsed, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,                      // 最小接收数量：测试时可设为 0
            0,                      // 同上
            address(this),
            block.timestamp + 1000
        );

        // 检查返回值是否大于 0
        console.log("amountAUsed:", amountAUsed);
        console.log("amountBUsed:", amountBUsed);
        console.log("liquidity:", liquidity);
        assertTrue(amountAUsed > 0 && amountBUsed > 0 && liquidity > 0, "Liquidity addition failed");
    }

    // 示例：测试 removeLiquidity（添加流动性后再移除流动性）
    function testRemoveLiquidity() public {
        // 你可以先调用 testAddLiquidity 添加流动性，再调用 removeLiquidity 检查返回的代币数量是否正确
        // 此处为伪代码示例：
        //
        // (uint256 amountAUsed, uint256 amountBUsed, uint256 liquidity) = router.addLiquidity(...);
        // (uint256 returnedA, uint256 returnedB) = router.removeLiquidity(...);
        // assertEq(returnedA, expectedA);
        // assertEq(returnedB, expectedB);
    }

    // 示例：测试 swapExactTokensForTokens（交换代币）
    function testSwapExactTokensForTokens() public {
        // 在进行 swap 之前，确保交易对中已有一定的流动性
        // 此处为伪代码示例：
        //
        // uint256 amountIn = 1e17;
        // address[] memory path = new address[](2);
        // path[0] = address(tokenA);
        // path[1] = address(tokenB);
        // uint256[] memory amounts = router.swapExactTokensForTokens(
        //     amountIn,
        //     0,                      // 最小输出数量设为 0 简化测试
        //     path,
        //     address(this),
        //     block.timestamp + 1000
        // );
        // assertTrue(amounts[amounts.length - 1] > 0, "Swap failed");
    }
}
