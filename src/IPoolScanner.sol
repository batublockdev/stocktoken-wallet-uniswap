// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";

interface IPoolScanner {
    struct PoolInfo {
        bytes32 poolId;
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
    }

    function checkPool(PoolKey calldata key) external view returns (bool initialized, PoolInfo memory info);
    function scanPair(
        address tokenA,
        address tokenB,
        uint24[] calldata fees,
        int24[] calldata tickSpacings,
        address[] calldata hooks
    ) external view returns (PoolInfo[] memory pools);
}
