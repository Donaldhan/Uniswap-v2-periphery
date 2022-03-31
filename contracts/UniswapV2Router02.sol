pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }
    /**
    tokenA 和 tokenB 很好理解，但是为什么要有 amountADesired、amountADesired、amountAMin、amountBMin 呢？
    实际上因为用户在区块链上添加流动性并不是实时完成的，因此会因为其他用户的操作产生数据偏差，因此需要在这里指定一个为 tokenA 和 tokenB 添加流动性的数值范围。在添加流动性的过程中，
    首先会根据 amountADesired 计算出实际要添加的 amountB，如果 amountB 大于 amountBDesired 就换成根据 amountBDesired 计算出实际要添加的 amountA 
    

    在实际上，计算出来的 amountA 和 amountB 
    只需要满足这个公式：(amountAMin = amountA && amountBMin <= amountB <= amountBDesired) || (amountAMin <= amountA <= amountADesired && amountB = amountBDesired)
    */
    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA, // 添加流动性 tokenA 的地址
        address tokenB, // 添加流动性 tokenB 的地址
        uint amountADesired, // 期望添加 tokenA 的数量
        uint amountBDesired, // 期望添加 tokenB 的数量
        uint amountAMin, // 添加 tokenA 的最小数量
        uint amountBMin // 添加 tokenB 的最小数量
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        // 如果 tokenA,tokenB 的流动池不存在，就创建流动池
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
         // 获取 tokenA,tokenB 的目前库存数量
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
             // 如果库存数量为0，也就是新建 tokenA,tokenB 的流动池，那么实际添加的amountA, amountB 就是 amountADesired 和 amountBDesired
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // amountADesired*reserveB/reserveA，算出实际要添加的 tokenB 数量 amountBOptimal
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                 // 如果 amountBMin <= amountBOptimal <= amountBDesired，amountA 和 amountB 就是 amountADesired 和 amountBOptimal
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                 // amountBDesired*reserveA/reserveB，算出实际要添加的 tokenA 数量 amountAOptimal
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                // 如果 amountAMin <= amountAOptimal <= amountADesired，amountA 和 amountB 就是 amountAOptimal 和 amountBDesired
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    //添加流动性
    function addLiquidity(
        address tokenA, // 添加流动性 tokenA 的地址
        address tokenB, // 添加流动性 tokenB 的地址
        uint amountADesired, // 期望添加 tokenA 的数量
        uint amountBDesired, // 期望添加 tokenB 的数量
        uint amountAMin, // 添加 tokenA 的最小数量
        uint amountBMin, // 添加 tokenB 的最小数量
        address to, // 获得的 LP 发送到的地址
        uint deadline // 过期时间
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        //获取tokenA，B的实际数量
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        //获取token A、Bpair的地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        //从tokenA、B的 msg.sender账号中，分别转移amountA， amountB到pair账号
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        //挖取流动性LP TOKEN
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    /**
     * addLiquidityETH 函数的不同之处在于使用了 ETH 作为 tokenB，因此不需要指定 tokenB 的地址和期望数量;
     * 因为 tokenB 的地址就是 WETH 的地址，tokenB 的期望数量就是用户发送的 ETH 数量。但这样也多了将 ETH 换成 WETH，并向用户返还多余 ETH 的操作。
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        // 计算实际添加的 amountToken, amountETH
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        // 获取 token, WETH 的流动池地址
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 从用户向流动池发送数量为 amountToken 的 token
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
         // Router将用户发送的 ETH 置换成 WETH
        IWETH(WETH).deposit{value: amountETH}();
        //// Router向流动池发送数量为 amountETH 的 WETH
        assert(IWETH(WETH).transfer(pair, amountETH));
         // 流动池向 to 地址发送数量为 liquidity 的 LP
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        // 如果用户发送的 ETH > amountETH，Router就向用户返还多余的 ETH
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    /**
     * 用户在移除流动性时，需要销毁 LP 换回 tokenA 和 tokenB。由于操作不是实时的，
     * 因此同样需要指定 amountAMin 和 amountBMin，如果实际获得的 amountA 小于 amountAMin 或者 amountB 小于 amountBMin，那么移除流动性的操作都会失败。
     * 移除流动性并不会检查你是否是流动性的添加者，只要你拥有 LP，那么就拥有了流动性的所有权。因此一定要保管好自己的 LP。
     */
    function removeLiquidity(
        address tokenA, // 移除流动性 tokenA 的地址
        address tokenB, // 移除流动性 tokenB 的地址
        uint liquidity, // 销毁 LP 的数量
        uint amountAMin, // 获得 tokenA 数量的最小值
        uint amountBMin, // 获得 tokenB 数量的最小值
        address to, // 获得的 tokenA、tokenB 发送到的地址
        uint deadline // 过期时间
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
         // 获取 token, WETH 的流动池地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 用户向流动池发送数量为 liquidity 的 LP
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        // 流动池销毁 LP 并向 to 地址发送数量为 amount0 的 token0 和 amount1 的 token1
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        // 计算出 tokenA, tokenB 中谁是 token0
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        // 如果实际获得的 amountA < amountAMin 或者 amountB < amountBMin，那么交易失败
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    /**
     * 移除流动性的是 ETH，不需要传入 ETH 的地址，改为使用 WETH
     * 流动池中质押的是 WETH，在移除流动性时需要把 WETH 换回 ETH。
     */
    function removeLiquidityETH(
        address token, // 移除流动性 token 的地址
        uint liquidity, // 销毁 LP 的数量
        uint amountTokenMin, // 获得 token 数量的最小值
        uint amountETHMin, // 获得 ETH 数量的最小值
        address to, // 获得的 token、ETH 发送到的地址
        uint deadline // 过期时间
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
       // 移除流动性，Router获得数量为 amountToken 的 token，amountETH 的 WETH
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 向 to 地址发送数量为 amountToken 的 token
        TransferHelper.safeTransfer(token, to, amountToken);
        // 将数量为 amountETH 的 WETH 换成 ETH
        IWETH(WETH).withdraw(amountETH);
        // 向 to 地址发送数量为 amountToken 的 ETH
        TransferHelper.safeTransferETH(to, amountETH);
    }
    /**
     *  函数 removeLiquidityWithPermit 这个实现了签名授权 Router 使用用户的 LP。首先要明确的是，合约调用用户的代币需要用户的授权才能进行，
     *  而 LP 的授权既可以发送一笔交易，也可以使用签名。而使用 removeLiquidityWithPermit 可以让用户免于发送一笔授权交易，转而使用签名，从而简化用户的操作。
     *  使用签名进行授权，简化了用户的操作，但有些人可能会利用用户对签名的不了解，盗窃用户资产。
     */
    function removeLiquidityWithPermit(
        address tokenA, // 移除流动性 tokenA 的地址
        address tokenB, // 移除流动性 tokenB 的地址
        uint liquidity, // 销毁 LP 的数量
        uint amountAMin, // 获得 tokenA 数量的最小值
        uint amountBMin, // 获得 tokenB 数量的最小值
        address to, // 获得的 tokenA、tokenB 发送到的地址
        uint deadline, // 过期时间
        bool approveMax, // 是否授权为最大值
        uint8 v, bytes32 r, bytes32 s // 签名 v,r,s
    ) external virtual override returns (uint amountA, uint amountB) {
         // 获取 tokenA, tokenB 的流动池地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 获取授权 LP 的数量
        uint value = approveMax ? uint(-1) : liquidity;
        // 授权 Router 使用用户数量为 value 的 LP
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 移除流动性
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    /**
     *  因为移除流动性的是 ETH，因此不需要传入 ETH 的地址，改为使用 WETH
     */
    function removeLiquidityETHWithPermit(
        address token, // 移除流动性 token 的地址
        uint liquidity, // 销毁 LP 的数量
        uint amountTokenMin, // 获得 token 数量的最小值
        uint amountETHMin, // 获得 ETH 数量的最小值
        address to, // 获得的 token、ETH 发送到的地址
        uint deadline, // 过期时间
        bool approveMax,  // 是否授权为最大值
        uint8 v, bytes32 r, bytes32 s // 签名 v,r,s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        // 获取 tokenA, WETH 的流动池地址
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 获取授权 LP 的数量
        uint value = approveMax ? uint(-1) : liquidity;
        // 授权 Router 使用用户数量为 value 的 LP
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 移除 ETH 流动性
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    /**
     * 相比于 removeLiquidityETH，removeLiquidityETHSupportingFeeOnTransferTokens 少了一个出参。
     * 这是因为函数 removeLiquidityETHSupportingFeeOnTransferTokens 的主要功能是支持第三方为用户支付手续费并收取一定的代币，
     * 因此 amountToken 中有一部分会被第三方收取，用户真实获取的代币数量会比 amountToken 少。具体见 ERC865
     */
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token, // 移除流动性 token 的地址
        uint liquidity, // 销毁 LP 的数量
        uint amountTokenMin, // 获得 token 数量的最小值
        uint amountETHMin, // 获得 ETH 数量的最小值
        address to, // 获得的 token、ETH 发送到的地址
        uint deadline // 过期时间
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    /**
     * 
     */
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // 无费用的swap

    // requires the initial amount to have already been sent to the first pair
    // 函数 _swap 实现了由多重交易组成的交易集合。path 数组里定义了执行代币交易的顺序，
    // amounts 数组里定义了每次交换获得代币的期望数量，_to 则是最后获得代币发送到的地址
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            // 从 path 中取出 input 和 output
            (address input, address output) = (path[i], path[i + 1]);
               // 从 input 和 output 中算出谁是 token0
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            // 期望交易获得的代币数量
            uint amountOut = amounts[i + 1];
             // 如果 input == token0，那么 amount0Out 就是0，amount1Out 就是 amountOut；反之则相反
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
             // 如果这是最后的一笔交易，那么 to 地址就是 _to，否则 to 地址是下一笔交易的流动池地址
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 执行 input 和 output 的交易
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    /**
     * 函数 swapExactTokensForTokens 实现了用户使用数量精确的 tokenA 交易数量不精确的 tokenB 的流程。
     * 用户使用确定的 amountIn 数量的 tokenA ，交易获得 tokenB 的数量不会小于 amountOutMin，
     * 但具体 tokenB 的数量只有交易完成之后才能知道。这同样是由于区块链上交易不是实时的，实际交易和预期交易相比会有一定的偏移。
     * 由于区块链上的实际交易和预期交易有偏差是常见的事情，因此在设计链上交易的时候逻辑会比较复杂，条件选择会有很多。
     */
    function swapExactTokensForTokens(
        uint amountIn,// 交易支付代币数量
        uint amountOutMin,// 交易获得代币最小值
        address[] calldata path, // 交易路径列表
        address to, // 交易获得的 token 发送到的地址
        uint deadline // 过期时间
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 获取 path 列表下，支付 amountIn 数量的 path[0] 代币，各个代币交易的预期数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 如果最终获得的代币数量小于 amountOutMin，则交易失败
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
         // 将 amounts[0] 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 按 path 列表执行交易集合
        _swap(amounts, path, to);
    }
    /**
     * 用户使用数量不精确的 tokenA 交易数量精确的 tokenB 的流程。用户会使用数量不大于 amountInMax 数量的 tokenA，交易获得 amountOut 数量的 tokenB。
     * 函数 swapTokensForExactTokens 完全是函数 swapExactTokensForTokens 的相反操作。
     * 一般来说，swapExactTokensForTokens 用于出售确定数量的代币，swapTokensForExactTokens 用于购买确定数量的代币。
     */
    function swapTokensForExactTokens(
        uint amountOut, // 交易获得的代币数量
        uint amountInMax, // 交易支付代币的最多数量
        address[] calldata path, // 交易路径列表
        address to, // 交易获得的 token 发送到的地址
        uint deadline // 过期时间
    ) external virtual override ensure(deadline) returns (uint[] memory amounts // 交易期望数量列表) {
         // 获取 path 列表下，获得 amountIn 数量的 path[path.length-1] 代币，各个代币交易的预期数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 如果 path[0] 代币数量大于 amountInMax，则交易失败
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
         // 将 amounts[0] 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
          // 按 path 列表执行交易集合
        _swap(amounts, path, to);
    }
    /**
     *  函数 swapExactETHForTokens 和函数 swapExactTokensForTokens 的逻辑几乎一样，
     * 只是把支付精确数量的 token 换成了支付精确数量的 ETH。因此多了一些和 ETH 相关的额外操作。
     * 此函数一般用于出售确定数量的 ETH，获得不确定数量代币。
     */
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 检查 path[0] 是否为 WETH 地址
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
         // 获取 path 列表下，支付 amountIn 数量的 path[0] 代币，各个代币交易的预期数量
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
         // 如果最终获得的代币数量小于 amountOutMin，则交易失败
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 把用户支付的 ETH 换成 WETH
        IWETH(WETH).deposit{value: amounts[0]}();
        // 将 amounts[0] 数量的 WETH 代币从 Router 中转移到 path[0], path[1] 的流动池
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 按 path 列表执行交易集合
        _swap(amounts, path, to);
    }
    /**
     * 函数 swapTokensForExactETH 和 函数 swapExactETHForTokens 相比，仅交换了一下代币的交易顺序，执行逻辑还是差不多的。
     * 此函数一般用于购买确定数量的 ETH，用不定数量的代币交换。
     */
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
         // 检查 path[path.length - 1] 是否为 WETH 地址
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
         // 获取 path 列表下，获得 amountOut 数量的 path[path.length-1] 代币，各个代币交易的预期数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 如果最终获得的代币数量小于 amountOutMin，则交易失败
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将 amounts[0] 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 按 path 列表执行交易集合
        _swap(amounts, path, address(this));
        // 将 WETH 换成 ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
         // 把 ETH 发送给 to 地址
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    /**
    *  函数 swapExactTokensForETH 和 函数 swapTokensForExactETH 相比，是更换了输入精确数量代币的顺序。
    *  此函数一般用于出售确定数量代币，获得不确定数量的 ETH。
    */
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
          // 检查 path[path.length - 1] 是否为 WETH 地址
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 获取 path 列表下，支付 amountIn 数量的 path[0] 代币，各个代币交易的预期数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 如果最终获得的代币数量小于 amountOutMin，则交易失败
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
         // 将 amounts[0] 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
           // 按 path 列表执行交易集
        _swap(amounts, path, address(this));
        // 将 WETH 换成 ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
          // 把 ETH 发送给 to 地址
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    /**
     * 函数 swapETHForExactTokens 和 函数 swapExactTokensForETH 相比，更换了代币交易的顺序。
     * 此函数一般用于购买确定数量代币，支付不确定数量的 ETH。
     */ 
    function swapETHForExactTokens( 
        uint amountOut, // 交易获得的代币数量
        address[] calldata path, // 交易路径列表
        address to, // 交易获得的 token 发送到的地址
        uint deadline // 过期时间)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 检查 path[0] 是否为 WETH 地址
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
         // 获取 path 列表下，获得 amountOut 数量的 path[path.length-1] 代币，各个代币交易的预期数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 如果 ETH 数量小于 amounts[0]，交易失败
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将 WETH 换成 ETH
        IWETH(WETH).deposit{value: amounts[0]}();
          // 将 amounts[0] 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
         // 按 path 列表执行交易集合
        _swap(amounts, path, to);
        // 如果 ETH 数量大于 amounts[0]，返还多余的 ETH
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    /**
     * 
     */
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path, // 交易路径列表
        address _to // 交易获得的 token 发送到的地址
        ) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            //pair
            (address input, address output) = (path[i], path[i + 1]);
            //获取小地址的token
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            //获取pair对
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            //获取储备量量
            (uint reserve0, uint reserve1,) = pair.getReserves();
             // 如果 input == token0，那么 (reserveInput,reserveOutput) 就是 (reserve0, reserve1)；反之则相反
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
              // amountInput 等于流动池余额减去 reserveInput
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            // 获取 amountOutput
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
             // 如果 input == token0，那么 amount0Out 就是0，amount1Out 就是 amountOut；反之则相反
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
             // 执行 input 和 output 的交易
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
     /** 
     *  函数 swapExactTokensForTokensSupportingFeeOnTransferTokens 相比函数 swapExactTokensForTokens，少了 amounts，因为交易后可变数量的代币不能做amounts的预测。
     *  函数适用于支付确定数量的代币，获得不定数量的代币，且在 path 路径列表中有交易后数量可变的代币。
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
          uint amountIn,// 交易支付代币数量
        uint amountOutMin, // 交易获得代币最小值
        address[] calldata path, // 交易路径列表
        address to, // 交易获得的 token 发送到的地址
        uint deadline // 过期时间
    ) external virtual override ensure(deadline) {
         // 将 amountIn 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
         // 记录 to 地址 path[path.length - 1] 代币的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        // 按 path 列表执行交易集合
        _swapSupportingFeeOnTransferTokens(path, to);
        // 如果 to 地址获得的代币数量小于 amountOutMin，交易失败
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
     /**
     *  函数 swapExactETHForTokensSupportingFeeOnTransferTokens 相比函数 swapExactETHForTokens，同样少了 amounts，因为交易后可变数量的代币不能做amounts的预测
     *  该函数适用于支付确定数量的 ETH，获得不定数量的代币，且在 path 路径列表中有交易后数量可变的代币。
     */
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
       uint amountOutMin, // 交易获得代币最小值
        address[] calldata path, // 交易路径列表
        address to, // 交易获得的 token 发送到的地址
        uint deadline // 过期时间
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        // 检查 path[0] 是否为 WETH
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 获取 amountIn
        uint amountIn = msg.value;
        // 把 ETH 换成 WETH
        IWETH(WETH).deposit{value: amountIn}();
        // 将 amountIn 数量的 path[0] 代币从用户账户中转移到 path[0], path[1] 的流动池
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        // 记录 to 地址 path[path.length - 1] 代币的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        // 按 path 列表执行交易集合
        _swapSupportingFeeOnTransferTokens(path, to);
        // 如果 to 地址获得的代币数量小于 amountOutMin，交易失败
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
     /**
     *  函数 swapExactTokensForETHSupportingFeeOnTransferTokens 相比函数 swapExactTokensForETH，也少了 amounts，因为交易后可变数量的代币不能做amounts的预测。
     * 该函数适用于支付确定数量的 token，获得不定数量的 WETH，且在 path 路径列表中有交易后数量可变的代币。
     */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,// 交易支付代币数量
        uint amountOutMin, // 交易获得代币最小值
        address[] calldata path, // 交易路径列表
        address to, // 交易获得的 token 发送到的地址
        uint deadline // 过期时间
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
