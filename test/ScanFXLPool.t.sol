//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {IPoolScanner} from "../src/IPoolScanner.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

contract ScanFXLPoolTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    UniswapV4PoolScanner public scanner;
    IPoolManager public constant pm = IPoolManager(0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF);
    address constant V4_SCANNER = 0xB442ce9A9f3480a7Cad578296917649d9a451cc7;

    address constant FXL = 0x9b8E987e6fEc8Cf1380C4dcA7071e2C7853AEEA1;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant NVDAon = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    address constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    address constant AAPLon = 0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4;

    bytes32 constant TARGET = 0xe938c0c41f47546ea4cbe570020bb513df88d4e91c29308d4e7d42b923f32997;

    function setUp() public {
        vm.createSelectFork(
            "https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6",
            133843992
        );
        scanner = UniswapV4PoolScanner(V4_SCANNER);
    }

    function test_find_target_pool() public view {
        console.log("Target poolId:");
        console.logBytes32(TARGET);

        // Probar FXL/USDT con combinaciones amplias
        _tryAllKeys("FXL/USDT", FXL, USDT);
        
        // Si no encuentra, probar otros pares conocidos
        _tryAllKeys("NVDAon/NVDAB", NVDAon, NVDAB);
        _tryAllKeys("NVDAB/USDT", NVDAB, USDT);
        _tryAllKeys("AAPLon/USDT", AAPLon, USDT);
    }

    function _tryAllKeys(string memory label, address tokenA, address tokenB) internal view {
        address t0 = tokenA < tokenB ? tokenA : tokenB;
        address t1 = tokenA < tokenB ? tokenB : tokenA;

        uint24[12] memory fees = [
            uint24(100), 200, 500, 1000, 2000, 3000,
            5000, 10000, 20000, 50000, 100000, 800000
        ];
        int24[10] memory tss = [
            int24(1), 2, 4, 8, 10, 60, 100, 200, 400, 2000
        ];

        bool found = false;
        for (uint256 i = 0; i < fees.length; i++) {
            for (uint256 j = 0; j < tss.length; j++) {
                PoolKey memory key = PoolKey({
                    currency0: Currency.wrap(t0),
                    currency1: Currency.wrap(t1),
                    fee: fees[i],
                    tickSpacing: tss[j],
                    hooks: IHooks(address(0))
                });

                PoolId id = key.toId();
                if (PoolId.unwrap(id) == TARGET) {
                    found = true;
                    (uint160 sqrtPriceX96, int24 tick, , ) = pm.getSlot0(id);
                    uint128 liq = pm.getLiquidity(id);
                    console.log("=== MATCH in %s ===", label);
                    console.log("  fee=%s ts=%s", fees[i], uint256(uint24(tss[j])));
                    console.log("  sqrtPrice=%s", uint256(sqrtPriceX96));
                    console.log("  liquidity=%s", uint256(liq));
                    console.log("  tick=%s", uint256(int256(tick)));
                }
            }
        }
        if (!found) {
            console.log("No match in %s", label);
        }
    }
}
