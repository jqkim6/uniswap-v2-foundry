// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

// 引入相关合约（根据你的项目目录结构调整路径）
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router02.sol";
import "../src/libraries/UniswapV2Library.sol";
import "../src/interfaces/IWETH.sol";

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

contract UniswapV2RouterAdditionalTest is Test {
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockWETH weth;

    // 测试账户
    address user = address(0x200);

    // 接收 ETH
    receive() external payable {}

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        weth = new MockWETH();
        router = new UniswapV2Router02(address(factory), address(weth));
        tokenA = new MockERC20("TokenA", "TKA", 18, 1e24);
        tokenB = new MockERC20("TokenB", "TKB", 18, 1e24);
    }

    /////////////////////////////////
    // _addLiquidity 分支测试
    /////////////////////////////////

    // 分支1：当 quote(amountADesired, reserveA, reserveB) <= amountBDesired 时走 if 分支
    function testAddLiquidityOptimalBranch1() public {
        // 第一次调用添加流动性初始化储备
        tokenA.approve(address(router), 1e18);
        tokenB.approve(address(router), 1e18);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 第二次添加流动性时，desired 为 (1e18, 2e18)
        tokenA.approve(address(router), 1e18);
        tokenB.approve(address(router), 2e18);
        (uint amountAUsed, uint amountBUsed, ) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1e18,
            2e18,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        assertEq(amountAUsed, 1e18);
        // 根据计算，amountBOptimal 应为 1e18
        assertEq(amountBUsed, 1e18);
    }

    // 分支2：当 quote(amountADesired, reserveA, reserveB) > amountBDesired 时走 else 分支
    function testAddLiquidityOptimalBranch2() public {
        // 初始添加流动性，设置比例为 (1e18, 2e18)
        tokenA.approve(address(router), 1e18);
        tokenB.approve(address(router), 2e18);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1e18,
            2e18,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 第二次调用：desired 为 (1e18, 1e18)
        tokenA.approve(address(router), 1e18);
        tokenB.approve(address(router), 1e18);
        (uint amountAUsed, uint amountBUsed, ) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 此时 amountAOptimal = quote(amountBDesired, reserveB, reserveA)
        // 根据初始储备 (1e18,2e18)，amountAOptimal 约为 5e17
        assertEq(amountAUsed, 5e17);
        assertEq(amountBUsed, 1e18);
    }

    /////////////////////////////////
    // 含 permit 的移除流动性测试（移除部分流动性）
    /////////////////////////////////

    // 测试 removeLiquidityWithPermit
    function testRemoveLiquidityWithPermit() public {
        // 添加流动性
        tokenA.approve(address(router), 1e18);
        tokenB.approve(address(router), 1e18);
        (, , uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 只移除一半流动性
        uint removeLiquidityAmount = liquidity / 2;
        // 计算 pair 地址
        address pair = UniswapV2Library.pairFor(address(factory), address(tokenA), address(tokenB));
        // 模拟 permit 调用（返回成功）
        vm.mockCall(
            pair,
            abi.encodeWithSelector(bytes4(keccak256("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))),
            abi.encode()
        );
        // 手动设置批准额度，模拟 permit 调用成功后的效果
        IUniswapV2Pair(pair).approve(address(router), liquidity);
        (uint amountA, uint amountB) = router.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            removeLiquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1000,
            false, 27, bytes32(0), bytes32(0)
        );
        assertGt(amountA, 0);
        assertGt(amountB, 0);
    }


    // 测试 removeLiquidityETHWithPermit
    function testRemoveLiquidityETHWithPermit() public {
        // 添加 ETH 流动性
        uint amountTokenDesired = 1e18;
        uint amountETH = 1e18;
        tokenA.approve(address(router), amountTokenDesired);
        (, , uint liquidity) = router.addLiquidityETH{value: amountETH}(
            address(tokenA),
            amountTokenDesired,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        uint removeLiquidityAmount = liquidity / 2;
        address pair = UniswapV2Library.pairFor(address(factory), address(tokenA), address(weth));
        vm.mockCall(
            pair,
            abi.encodeWithSelector(bytes4(keccak256("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))),
            abi.encode()
        );
        IUniswapV2Pair(pair).approve(address(router), liquidity);
        (uint amountToken, uint amountETHRemoved) = router.removeLiquidityETHWithPermit(
            address(tokenA),
            removeLiquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1000,
            false, 27, bytes32(0), bytes32(0)
        );
        assertGt(amountToken, 0);
        assertGt(amountETHRemoved, 0);
    }

    // 测试 removeLiquidityETHWithPermitSupportingFeeOnTransferTokens
    function testRemoveLiquidityETHWithPermitSupportingFeeOnTransferTokens() public {
        // 添加 ETH 流动性
        uint amountTokenDesired = 1e18;
        uint amountETH = 1e18;
        tokenA.approve(address(router), amountTokenDesired);
        (, , uint liquidity) = router.addLiquidityETH{value: amountETH}(
            address(tokenA),
            amountTokenDesired,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        uint removeLiquidityAmount = liquidity / 2;
        address pair = UniswapV2Library.pairFor(address(factory), address(tokenA), address(weth));
        vm.mockCall(
            pair,
            abi.encodeWithSelector(bytes4(keccak256("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))),
            abi.encode()
        );
        IUniswapV2Pair(pair).approve(address(router), liquidity);
        uint amountETHRemoved = router.removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
            address(tokenA),
            removeLiquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1000,
            false, 27, bytes32(0), bytes32(0)
        );
        assertGt(amountETHRemoved, 0);
    }

    /////////////////////////////////
    // Swap 系列函数测试（提高最大输入值）
    /////////////////////////////////

    // 测试 swapTokensForExactTokens
    function testSwapTokensForExactTokens() public {
        // 添加 tokenA-tokenB 流动性
        uint amountA = 1e18;
        uint amountB = 1e18;
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 要求获得 5e17 的 tokenB，允许最大输入 1.1e18
        uint amountOut = 5e17;
        uint amountInMax = 1.1e18;
        tokenA.approve(address(router), amountInMax);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp + 1000
        );
        assertEq(amounts[amounts.length - 1], amountOut);
    }

    // 测试 swapTokensForExactETH
    function testSwapTokensForExactETH() public {
        // 添加 tokenA-WETH 流动性
        uint amountToken = 1e18;
        uint amountWETH = 1e18;
        tokenA.approve(address(router), amountToken);
        weth.deposit{value: amountWETH}();
        weth.approve(address(router), amountWETH);
        router.addLiquidity(
            address(tokenA),
            address(weth),
            amountToken,
            amountWETH,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 要求获得 5e17 的 ETH，允许最大输入 1.1e18
        uint amountOutETH = 5e17;
        uint amountInMax = 1.1e18;
        tokenA.approve(address(router), amountInMax);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        uint[] memory amounts = router.swapTokensForExactETH(
            amountOutETH,
            amountInMax,
            path,
            address(this),
            block.timestamp + 1000
        );
        assertEq(amounts[amounts.length - 1], amountOutETH);
    }

    // 测试 swapETHForExactTokens
    function testSwapETHForExactTokens() public {
        // 添加 WETH-tokenB 流动性
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
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        // 要求获得 5e17 的 tokenB，提供 1.1e18 ETH
        uint amountOut = 5e17;
        uint ethProvided = 1.1e18;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenB);
        uint[] memory amounts = router.swapETHForExactTokens{value: ethProvided}(
            amountOut,
            path,
            address(this),
            block.timestamp + 1000
        );
        assertEq(amounts[amounts.length - 1], amountOut);
    }

    /////////////////////////////////
    // 调用库函数（公开接口）测试
    /////////////////////////////////

    function testLibraryFunctions() public view{
        uint amount = 1e18;
        uint reserveA = 2e18;
        uint reserveB = 4e18;
        uint quoted = router.quote(amount, reserveA, reserveB);
        assertEq(quoted, 2e18);

        uint amountOut = router.getAmountOut(amount, reserveA, reserveB);
        uint expectedOut = UniswapV2Library.getAmountOut(amount, reserveA, reserveB);
        assertEq(amountOut, expectedOut);

        uint amountIn = router.getAmountIn(amount, reserveA, reserveB);
        uint expectedIn = UniswapV2Library.getAmountIn(amount, reserveA, reserveB);
        assertEq(amountIn, expectedIn);
    }
}