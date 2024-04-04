// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library TransferHelper {
    function safeTransfer(address token, address to, uint value) internal {
        (bool success, ) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(success, "TransferHelper: TRANSFER_FAILED");
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint value
    ) internal {
        (bool success, ) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(success, "TransferHelper: TRANSFER_FROM_FAILED");
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }
}

interface ISwapV2Router {
    function factory() external pure returns (address);

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut);

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountIn);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface ISwapV2Factory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}

interface ISwapV2Pair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint);

    function transfer(address to, uint value) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint) external;
}

contract LongSwap {
    using SafeMath for uint256;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "LongSwap: EXPIRED");
        _;
    }

    receive() external payable {}

    function getAmountsOut(
        address _router,
        uint256 amountIn,
        address[] memory path
    ) public view returns (uint[] memory amounts) {
        return ISwapV2Router(_router).getAmountsOut(amountIn, path);
    }

    function getAmountOut(
        address _router,
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure returns (uint amountOut) {
        return
            ISwapV2Router(_router).getAmountOut(
                amountIn,
                reserveIn,
                reserveOut
            );
    }

    function getAmountsIn(
        address _router,
        uint amountOut,
        address[] memory path
    ) public view returns (uint[] memory amounts) {
        return ISwapV2Router(_router).getAmountsIn(amountOut, path);
    }

    function getPair(
        address _router,
        address tokenA,
        address tokenB
    ) public view returns (address pair) {
        ISwapV2Factory _factory = ISwapV2Factory(
            ISwapV2Router(_router).factory()
        );
        return _factory.getPair(tokenA, tokenB);
    }

    function getReserves(
        address _router,
        address tokenA,
        address tokenB
    ) public view returns (uint256, uint256) {
        ISwapV2Pair pair = ISwapV2Pair(getPair(_router, tokenA, tokenB));
        address token0 = pair.token0();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveIn, uint256 reserveOut) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);

        return (reserveIn, reserveOut);
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) public pure returns (address token0, address token1) {
        require(tokenA != tokenB);
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0));
    }

    function _swap(
        address _router,
        address[] memory path,
        address _to
    ) private {
        ISwapV2Factory factory = ISwapV2Factory(
            ISwapV2Router(_router).factory()
        );

        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            ISwapV2Pair pair = ISwapV2Pair(factory.getPair(input, output));
            uint256 amountInput;
            uint256 amountOutput;
            // scope to avoid stack too deep errors
            {
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(
                    reserveInput
                );
                amountOutput = getAmountOut(
                    _router,
                    amountInput,
                    reserveInput,
                    reserveOutput
                );
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2
                ? factory.getPair(output, path[i + 2])
                : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function checkSwap(
        address _router,
        address[] memory path,
        uint256 amount,
        uint256 amountOutMin,
        uint256 taxBuy,
        uint256 taxSell
    ) public virtual {
        address srcToken = path[0];
        address dstToken = path[path.length - 1];

        uint256 beforeBal = IERC20(dstToken).balanceOf(msg.sender);

        safeSwap(
            _router,
            path,
            amount,
            amountOutMin,
            taxBuy,
            msg.sender,
            block.timestamp
        );

        uint256 afterBal = IERC20(dstToken).balanceOf(msg.sender) - beforeBal;

        path[0] = dstToken;
        path[path.length - 1] = srcToken;

        safeSwap(
            _router,
            path,
            afterBal.div(100),
            0,
            taxSell,
            msg.sender,
            block.timestamp
        );
    }

    function checkSwapETHForToken(
        address _router,
        address[] memory path,
        uint256 amountOutMin,
        uint256 taxBuy,
        uint256 taxSell
    ) public payable virtual {
        address srcToken = path[0];
        address dstToken = path[path.length - 1];

        uint256 beforeBal = IERC20(dstToken).balanceOf(msg.sender);

        safeSwapETHForToken(
            _router,
            path,
            amountOutMin,
            taxBuy,
            msg.sender,
            block.timestamp
        );

        uint256 afterBal = IERC20(dstToken).balanceOf(msg.sender) - beforeBal;

        path[0] = dstToken;
        path[path.length - 1] = srcToken;

        safeSwap(
            _router,
            path,
            afterBal.div(100),
            0,
            taxSell,
            msg.sender,
            block.timestamp
        );
    }

    function safeSwap(
        address _router,
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 tax,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) {
        address srcToken = path[0];
        bool hasPaid;

        if (amountIn == 0) {
            hasPaid = true;
            amountIn = IERC20(srcToken).balanceOf(address(this));
        }

        pay(
            srcToken,
            hasPaid ? address(this) : msg.sender,
            getPair(_router, srcToken, path[1]),
            amountIn
        );

        uint amountOut = getAmountsOut(_router, amountIn, path)[
            path.length - 1
        ];
        require(amountOut >= amountOutMin, "LongSwap: Slippage is too low");

        IERC20 dstToken = IERC20(path[path.length - 1]);
        uint256 beforeBal = dstToken.balanceOf(to);

        _swap(_router, path, to);

        uint256 afterBal = dstToken.balanceOf(to);

        uint256 checkAmountOut = amountOut.sub(amountOut.mul(tax).div(1000));

        require(
            afterBal.sub(beforeBal) >= checkAmountOut,
            "LongSwap: Taxes are too low"
        );
    }

    function safeSwapETHForToken(
        address _router,
        address[] memory path,
        uint256 amountOutMin,
        uint256 tax,
        address to,
        uint256 deadline
    ) public payable virtual {
        IWETH wrapETH = IWETH(path[0]);
        wrapETH.deposit{value: msg.value}();
        safeSwap(_router, path, 0, amountOutMin, tax, to, deadline);
    }

    function safeSwapTokenForETH(
        address _router,
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 tax,
        address to,
        uint256 deadline
    ) public virtual {
        safeSwap(
            _router,
            path,
            amountIn,
            amountOutMin,
            tax,
            address(this),
            deadline
        );

        IWETH wrapETH = IWETH(path[path.length - 1]);
        uint256 balance = wrapETH.balanceOf(address(this));
        wrapETH.withdraw(balance);
        TransferHelper.safeTransferETH(to, balance);
    }

    function safeSwapAndTransfer(
        address _router,
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 tax,
        address to,
        uint256 deadline
    ) public virtual {
        safeSwap(_router, path, amountIn, amountOutMin, tax, to, deadline);

        TransferHelper.safeTransferFrom(
            path[path.length - 1],
            to,
            address(0xdead),
            1
        );
    }

    function safeSwapETHForTokenAndTransfer(
        address _router,
        address[] memory path,
        uint256 amountOutMin,
        uint256 tax,
        address to,
        uint256 deadline
    ) public payable virtual {
        safeSwapETHForToken(_router, path, amountOutMin, tax, to, deadline);

        TransferHelper.safeTransferFrom(
            path[path.length - 1],
            to,
            address(0xdead),
            1
        );
    }

    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (payer == address(this)) {
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
