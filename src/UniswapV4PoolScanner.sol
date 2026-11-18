// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IPoolScanner} from "./IPoolScanner.sol";

contract UniswapV4PoolScanner is IPoolScanner {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;

    uint256 public constant MAX_CANDIDATES = 64;

    error InvalidToken();
    error TooManyCandidates();
    error InvalidConfiguration();

    constructor(address _poolManager) {
        if (_poolManager == address(0)) {
            revert InvalidToken();
        }
        poolManager = IPoolManager(_poolManager);
    }

    function checkPool(
        PoolKey calldata key
    )
        external
        view
        override
        returns (
            bool initialized,
            PoolInfo memory info
        )
    {
        return _checkPool(key);
    }

    function _checkPool(
        PoolKey memory key
    )
        internal
        view
        returns (
            bool initialized,
            PoolInfo memory info
        )
    {
        PoolId id = key.toId();

        (
            uint160 sqrtPriceX96,
            int24 tick,
            ,
        ) = poolManager.getSlot0(id);

        if (sqrtPriceX96 == 0) {
            return (false, info);
        }

        uint128 liquidity = poolManager.getLiquidity(id);

        info = PoolInfo({
            poolId: PoolId.unwrap(id),
            currency0: Currency.unwrap(key.currency0),
            currency1: Currency.unwrap(key.currency1),
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: address(key.hooks),
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            liquidity: liquidity
        });

        return (true, info);
    }

    function scanPair(
        address tokenA,
        address tokenB,
        uint24[] calldata fees,
        int24[] calldata tickSpacings,
        address[] calldata hooks
    )
        external
        view
        override
        returns (PoolInfo[] memory pools)
    {
        if (
            tokenA == address(0) ||
            tokenB == address(0) ||
            tokenA == tokenB
        ) {
            revert InvalidToken();
        }

        uint256 total =
            fees.length *
            tickSpacings.length *
            hooks.length;

        if (total > MAX_CANDIDATES) {
            revert TooManyCandidates();
        }

        if (total == 0) {
            revert InvalidConfiguration();
        }

        address token0 =
            tokenA < tokenB ? tokenA : tokenB;
        address token1 =
            tokenA < tokenB ? tokenB : tokenA;

        PoolInfo[] memory results =
            new PoolInfo[](total);

        uint256 found;

        for (uint256 i; i < fees.length; ++i) {
            for (
                uint256 j;
                j < tickSpacings.length;
                ++j
            ) {
                for (
                    uint256 k;
                    k < hooks.length;
                    ++k
                ) {
                    PoolKey memory key = PoolKey({
                        currency0: Currency.wrap(token0),
                        currency1: Currency.wrap(token1),
                        fee: fees[i],
                        tickSpacing: tickSpacings[j],
                        hooks: IHooks(hooks[k])
                    });

                    (
                        bool initialized,
                        PoolInfo memory info
                    ) = _checkPool(key);

                    if (initialized) {
                        results[found] = info;
                        ++found;
                    }
                }
            }
        }

        pools = new PoolInfo[](found);

        for (uint256 i; i < found; ++i) {
            pools[i] = results[i];
        }
    }

    function getPoolDiagnostic(
        PoolKey calldata key
    )
        external
        view
        returns (
            bytes32 poolId,
            uint160 sqrtPriceX96,
            int24 currentTick,
            uint128 activeLiquidity,
            uint256 currentTickBitmap
        )
    {
        PoolId id = key.toId();

        (
            sqrtPriceX96,
            currentTick,
            ,
        ) = poolManager.getSlot0(id);

        activeLiquidity = poolManager.getLiquidity(id);

        int24 compressedTick =
            currentTick / key.tickSpacing;

        int16 wordPos = int16(compressedTick >> 8);

        currentTickBitmap =
            poolManager.getTickBitmap(id, wordPos);

        poolId = PoolId.unwrap(id);
    }
}
