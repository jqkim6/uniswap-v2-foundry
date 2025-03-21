// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 引入 Foundry 标准库
import "forge-std/Test.sol";

// 引入你项目中的合约（路径根据实际项目结构调整）
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Router02.sol";
import "../src/interfaces/IWETH.sol";
import "../src/libraries/UniswapV2Library.sol";


//
// Mock ERC20 合约，用于测试
//
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint public totalSupply;

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint _totalSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
    }

    // 在这里加上 virtual 关键字
    function transfer(address to, uint amount) public virtual returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    // 用于测试中增发代币
    function mint(address to, uint amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

//
// Mock WETH 合约，继承自 MockERC20 并实现 IWETH 接口
//
contract MockWETH is MockERC20, IWETH {
    constructor() MockERC20("Wrapped ETH", "WETH", 18, 0) {}

    // 明确重写 transfer 函数，覆盖基类和接口中的定义
    function transfer(address to, uint value)
        public
        override(MockERC20, IWETH)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    function deposit() public payable override {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
    }

    function withdraw(uint amount) public override {
        require(balanceOf[msg.sender] >= amount, "Insufficient WETH");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        payable(msg.sender).transfer(amount);
    }

    // 允许直接转账时调用 deposit
    receive() external payable {
        deposit();
    }
}

//
// UniswapV2Factory 测试
//
contract UniswapV2FactoryTest is Test {
    UniswapV2Factory factory;
    address feeToSetter = address(0x123);
    address tokenA = address(0x111);
    address tokenB = address(0x222);

    function setUp() public {
        factory = new UniswapV2Factory(feeToSetter);
    }

    function testCreatePair() public {
        address pair = factory.createPair(tokenA, tokenB);
        assertTrue(pair != address(0), "pair address should not be 0");
        // 检查两个方向的映射
        assertEq(factory.getPair(tokenA, tokenB), pair);
        assertEq(factory.getPair(tokenB, tokenA), pair);
        assertEq(factory.allPairsLength(), 1);
    }

    function testCreatePairIdenticalAddresses() public {
        vm.expectRevert("UniswapV2: IDENTICAL_ADDRESSES");
        factory.createPair(tokenA, tokenA);
    }

    function testCreatePairZeroAddress() public {
        vm.expectRevert("UniswapV2: ZERO_ADDRESS");
        factory.createPair(address(0), tokenB);
    }

    function testCreatePairDuplicate() public {
        factory.createPair(tokenA, tokenB);
        vm.expectRevert("UniswapV2: PAIR_EXISTS");
        factory.createPair(tokenA, tokenB);
    }

    function testSetFeeTo() public {
        // feeToSetter 可以调用
        vm.prank(feeToSetter);
        factory.setFeeTo(address(0x999));
        assertEq(factory.feeTo(), address(0x999));

        // 非 feeToSetter 调用将 revert
        vm.prank(address(0xabc));
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeTo(address(0x888));
    }

    function testSetFeeToSetter() public {
        vm.prank(feeToSetter);
        factory.setFeeToSetter(address(0x777));
        assertEq(factory.feeToSetter(), address(0x777));

        vm.prank(address(0xabc));
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeToSetter(address(0x666));
    }
}

//
// UniswapV2Pair 测试
//
contract UniswapV2PairTest is Test {
    UniswapV2Factory factory;
    UniswapV2Pair pair;
    MockERC20 tokenA;
    MockERC20 tokenB;

    // 选择一个测试账户
    address user = address(0x100);

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        tokenA = new MockERC20("TokenA", "TKA", 18, 1e24);
        tokenB = new MockERC20("TokenB", "TKB", 18, 1e24);
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = UniswapV2Pair(pairAddress);
    }

    function testInitialize() public view{
        // 因为 initialize 只能由工厂调用，所以 pair 部署时已设置好 token0/token1
        (address t0, address t1) = (pair.token0(), pair.token1());
        (address token0, address token1) = UniswapV2Library.sortTokens(address(tokenA), address(tokenB));
        assertEq(t0, token0);
        assertEq(t1, token1);
    }

    // 模拟流动性添加（先将 token 转入 pair，再调用 mint）
    function testMintAndBurn() public {
        uint amountA = 1e18;
        uint amountB = 2e18;
        // 将代币直接转给 pair
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        uint liquidity = pair.mint(user);
        assertGt(liquidity, 0);

        // 检查总供应量（注意：mint 时会锁定 MINIMUM_LIQUIDITY）
        uint totalSupplyAfterMint = pair.totalSupply();
        assertEq(totalSupplyAfterMint, liquidity + pair.getMinimumLiquidity());


        // 模拟销毁流动性：将 user 持有的流动性代币转回 pair，再调用 burn
        vm.prank(user);
        uint userLiquidity = pair.balanceOf(user);
        vm.prank(user);
        pair.transfer(address(pair), userLiquidity);
        (uint amountAOut, uint amountBOut) = pair.burn(user);
        assertGt(amountAOut, 0);
        assertGt(amountBOut, 0);
    }

    function testSwap() public {
        // 添加流动性后再测试 swap
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        pair.mint(address(this));

        // 向 pair 转入一部分 tokenA 作为输入
        uint swapInput = 1e17;
        tokenA.transfer(address(pair), swapInput);
        // 这里选择交换输出 tokenB（amount0Out = 0, amount1Out > 0）
        uint amountBOut = 1e16;
        pair.swap(0, amountBOut, address(this), "");
        // 检查收到 tokenB 增加（测试中简单断言非 0）
        assertGt(tokenB.balanceOf(address(this)), 0);
    }

    function testSkimAndSync() public {
        // 添加初始流动性
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        pair.mint(address(this));

        // 向 pair 额外发送一些代币（不计入内部储备）
        tokenA.transfer(address(pair), 1e17);
        tokenB.transfer(address(pair), 1e17);
        // 调用 skim 将多余的余额转走
        pair.skim(address(this));
        // 检查多余部分被清空
        uint extraA = tokenA.balanceOf(address(pair)) > amountA ? tokenA.balanceOf(address(pair)) - amountA : 0;
        uint extraB = tokenB.balanceOf(address(pair)) > amountB ? tokenB.balanceOf(address(pair)) - amountB : 0;
        assertEq(extraA, 0);
        assertEq(extraB, 0);

        // 测试 sync：先人为增加 pair 余额，再调用 sync 更新储备
        tokenA.transfer(address(pair), 1e17);
        tokenB.transfer(address(pair), 1e17);
        pair.sync();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertGe(reserve0, amountA + 1e17);
        assertGe(reserve1, amountB + 1e17);
    }

    function testPriceAccumulatorAndBurn() public {
        // --- 测试 _update 内 price 累加、mint 中 Math.min 分支 以及 burn 中 fee 模式的 kLast 更新 ---
        // 1. 开启 fee 模式
        factory.setFeeTo(address(0x999));

        // 2. 初始添加流动性
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        uint liq1 = pair.mint(address(this));
        assertGt(liq1, 0);

        // 3. 时间前进，确保 _update 中 timeElapsed > 0，触发 price 累加逻辑（lines 86-87）
        vm.warp(block.timestamp + 20);

        // 4. 模拟追加非完全按比例的额外流动性（这里两边均增加 1e17）
        uint extra = 1e17;
        tokenA.transfer(address(pair), extra);
        tokenB.transfer(address(pair), extra);
        uint liq2 = pair.mint(address(this));
        assertGt(liq2, 0);

        // 5. 检查 price 累加器是否被更新（覆盖 lines 86-87）
        uint p0 = pair.price0CumulativeLast();
        uint p1 = pair.price1CumulativeLast();
        assertGt(p0, 0, "price0CumulativeLast should be updated");
        assertGt(p1, 0, "price1CumulativeLast should be updated");

        // 6. 调用 burn 模拟销毁流动性，此时 fee 模式下 burn 内部会执行 if (feeOn) kLast = uint(reserve0) * reserve1 (line 161)
        uint liquidity = pair.balanceOf(address(this));
        // 将所有流动性代币发送回 pair
        pair.transfer(address(pair), liquidity);
        (uint amountOutA, uint amountOutB) = pair.burn(address(this));
        assertGt(amountOutA, 0);
        assertGt(amountOutB, 0);

        // 7. 检查 burn 后 kLast 被更新（应大于 0，因为 fee 模式开启，覆盖 line 161）
        uint newKLast = pair.kLast();
        assertGt(newKLast, 0, "kLast should be updated after burn with fee mode on");
    }


}

//
// UniswapV2Router02 测试
//
contract UniswapV2RouterTest is Test {
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockWETH weth;

    // 测试用账户
    address user = address(0x200);

    // 为使测试合约能够接收 ETH
    receive() external payable {}

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        weth = new MockWETH();
        router = new UniswapV2Router02(address(factory), address(weth));
        tokenA = new MockERC20("TokenA", "TKA", 18, 1e24);
        tokenB = new MockERC20("TokenB", "TKB", 18, 1e24);
    }

    function testAddLiquidity() public {
        uint amountA = 1e18;
        uint amountB = 2e18;
        // 先为路由合约批准代币
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        (uint amountAUsed, uint amountBUsed, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        assertGt(liquidity, 0);
        assertEq(amountAUsed, amountA);
        assertEq(amountBUsed, amountB);
    }

    function testAddLiquidityETH() public {
        uint amountTokenDesired = 1e18;
        uint amountETH = 1e18;
        tokenA.approve(address(router), amountTokenDesired);
        (, uint amountETHUsed, uint liquidity) = router.addLiquidityETH{value: amountETH}(
            address(tokenA),
            amountTokenDesired,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        assertGt(liquidity, 0);
        assertLe(amountETHUsed, amountETH);
    }

    function testRemoveLiquidity() public {
        // 先添加流动性
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        ( , , uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        // 移除流动性前，先批准流动性代币给路由合约
        address pair = UniswapV2Library.pairFor(address(factory), address(tokenA), address(tokenB));
        IUniswapV2Pair(pair).approve(address(router), liquidity);

        (uint amountARemoved, uint amountBRemoved) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        assertGt(amountARemoved, 0);
        assertGt(amountBRemoved, 0);
    }

    function testRemoveLiquidityETH() public {
        // 添加 ETH 流动性
        uint amountTokenDesired = 1e18;
        uint amountETH = 1e18;
        tokenA.approve(address(router), amountTokenDesired);
        (, , uint liquidity) = router.addLiquidityETH{value: amountETH}(
            address(tokenA),
            amountTokenDesired,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        // 移除流动性前批准流动性代币给路由合约
        address pair = UniswapV2Library.pairFor(address(factory), address(tokenA), address(weth));
        IUniswapV2Pair(pair).approve(address(router), liquidity);
        
        // 调用 removeLiquidityETH
        (uint amountTokenRemoved, uint amountETHRemoved) = router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        assertGt(amountTokenRemoved, 0);
        assertGt(amountETHRemoved, 0);
    }

    function testSwapExactTokensForTokens() public {
        // 为 tokenA-tokenB 对添加流动性
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        // 调用 swapExactTokensForTokens
        uint amountIn = 1e17;
        uint amountOutMin = 1;
        tokenA.approve(address(router), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1000
        );
        assertGt(amounts[1], 0);
    }

    function testSwapExactETHForTokens() public {
        // 为 WETH-tokenB 对添加流动性
        uint amountWETH = 1e18;
        uint amountB = 1e18;
        weth.deposit{value: amountWETH}();
        weth.approve(address(router), amountWETH);
        tokenB.approve(address(router), amountB);
        router.addLiquidity(
            address(weth),
            address(tokenB),
            amountWETH,
            amountB,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenB);
        // 对 swap 操作，确保 WETH 已批准给路由合约
        uint amountIn = 1e17;
        weth.approve(address(router), amountIn);
        uint[] memory amounts = router.swapExactETHForTokens{value: amountIn}(
            1,
            path,
            address(this),
            block.timestamp + 1000
        );
        assertGt(amounts[1], 0);
    }

    function testSwapExactTokensForETH() public {
        // 为 tokenA-WETH 对添加流动性
        uint amountToken = 1e18;
        uint amountWETH = 1e18;
        tokenA.approve(address(router), amountToken);
        weth.deposit{value: amountWETH}();
        // 此处也批准 WETH 给路由合约
        weth.approve(address(router), amountWETH);
        router.addLiquidity(
            address(tokenA),
            address(weth),
            amountToken,
            amountWETH,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        uint amountIn = 1e17;
        uint amountOutMin = 1;
        tokenA.approve(address(router), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        uint[] memory amounts = router.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1000
        );
        assertGt(amounts[1], 0);
    }

    // 测试支持手续费代币的 swap 函数
    function testSwapExactTokensForTokensSupportingFeeOnTransferTokens() public {
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        uint amountIn = 1e17;
        tokenA.approve(address(router), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint balBefore = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp + 1000
        );
        uint balAfter = tokenB.balanceOf(address(this));
        assertGt(balAfter - balBefore, 0);
    }

    function testSwapExactETHForTokensSupportingFeeOnTransferTokens() public {
        uint amountWETH = 1e18;
        uint amountB = 1e18;
        // 先用 ETH 存入 WETH，确保测试合约拥有 WETH 余额
        weth.deposit{value: amountWETH}();
        // 为了让路由在 addLiquidity 时能正确转走 WETH，提前批准
        weth.approve(address(router), amountWETH);
        // 为 tokenB 也批准足够额度（用于流动性添加）
        tokenB.approve(address(router), amountB);
        // 添加流动性时使用 WETH 和 tokenB
        router.addLiquidity(
            address(weth),
            address(tokenB),
            amountWETH,
            amountB,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        // 构造交换路径：从 WETH 到 tokenB
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenB);
        uint balBefore = tokenB.balanceOf(address(this));
        // 注意：swapExactETHForTokensSupportingFeeOnTransferTokens 接收 ETH（msg.value）并在内部调用 deposit，
        // 此时路由合约会成为 WETH 的持有者并转出 WETH 给 Pair
        // 此处直接发送 1e17 ETH，无需额外批准（因为 deposit 不依赖 approve）
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1e17}(
            1,
            path,
            address(this),
            block.timestamp + 1000
        );
        uint balAfter = tokenB.balanceOf(address(this));
        assertGt(balAfter - balBefore, 0);
    }

    function testSwapExactTokensForETHSupportingFeeOnTransferTokens() public {
        uint amountToken = 1e18;
        uint amountWETH = 1e18;
        // 为 tokenA 批准足够额度以便在添加流动性和 swap 时使用
        tokenA.approve(address(router), amountToken);
        // 存入 ETH 换取 WETH，注意这里调用 deposit 后 msg.sender（路由合约调用内部函数）会使路由获得 WETH
        weth.deposit{value: amountWETH}();
        // 同时，为了添加流动性时能正确使用 WETH，也提前批准 WETH 给路由合约
        weth.approve(address(router), amountWETH);
        // 添加 tokenA-WETH 流动性
        router.addLiquidity(
            address(tokenA),
            address(weth),
            amountToken,
            amountWETH,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );
        uint amountIn = 1e17;
        // 在 swap 前再次为 tokenA 批准（确保额度足够）
        tokenA.approve(address(router), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        // 记录调用前合约的 ETH 余额
        uint ethBefore = address(this).balance;
        // 调用支持 fee-on-transfer 的 swap 函数将 tokenA 兑换为 ETH
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp + 1000
        );
        uint ethAfter = address(this).balance;
        assertGt(ethAfter, ethBefore);
    }
}

