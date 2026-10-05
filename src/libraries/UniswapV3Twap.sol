// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./FullMath.sol";
import "./TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
library UniswapV3Twap {
    error InvalidToken();
    error InvalidPeriod();

    function getTwapAmountOut(
        address pool,
        address tokenIn,
        uint128 amountIn,
        uint32 dt
    ) internal view returns (uint256 amountOut) {
        if (dt == 0) {
            revert InvalidPeriod();
        }

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(pool);

        address token0 = uniswapPool.token0();
        address token1 = uniswapPool.token1();

        if (tokenIn != token0 && tokenIn != token1) {
            revert InvalidToken();
        }

        address tokenOut = tokenIn == token0 ? token1 : token0;

        uint32[] memory secondsAgos = new uint32[](2);

        secondsAgos[0] = dt;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = uniswapPool.observe(secondsAgos);

        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 arithmeticMeanTick = int24(
            tickCumulativeDelta / int56(uint56(dt))
        );

        // Solidity rounds integer division toward zero.
        // Uniswap's arithmetic mean tick must round toward
        // negative infinity.
        if (
            tickCumulativeDelta < 0 &&
            (tickCumulativeDelta % int56(uint56(dt))) != 0
        ) {
            arithmeticMeanTick--;
        }

        return getQuoteAtTick(arithmeticMeanTick, amountIn, tokenIn, tokenOut);
    }

    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;

            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );

            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
