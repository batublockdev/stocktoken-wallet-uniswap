//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {IPoolScanner} from "../src/IPoolScanner.sol";

contract ScanSIRENTest is Test {
    UniswapV4PoolScanner public scanner;
    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant V4_SCANNER = 0xB442ce9A9f3480a7Cad578296917649d9a451cc7;
    address constant SIREN = 0x997A58129890bBdA032231A52eD1ddC845fc18e1;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    function setUp() public {
        vm.createSelectFork(
            "https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6",
            133660000
        );
        scanner = UniswapV4PoolScanner(V4_SCANNER);
    }

    function test_scan_siren() public view {
        uint24[] memory fees = new uint24[](12);
        fees[0] = 100; fees[1] = 200; fees[2] = 500; fees[3] = 1000;
        fees[4] = 2000; fees[5] = 3000; fees[6] = 5000; fees[7] = 10000;
        fees[8] = 20000; fees[9] = 50000; fees[10] = 100000; fees[11] = 800000;

        int24[] memory tss = new int24[](10);
        tss[0] = 1; tss[1] = 2; tss[2] = 4; tss[3] = 8; tss[4] = 10;
        tss[5] = 60; tss[6] = 100; tss[7] = 200; tss[8] = 400; tss[9] = 2000;

        address[] memory hooks = new address[](1);
        hooks[0] = address(0);

        // Batch 1: fees 0-7 x tss 0-4 (8x5=40)
        uint24[] memory f1 = new uint24[](8);
        f1[0]=100; f1[1]=200; f1[2]=500; f1[3]=1000; f1[4]=2000; f1[5]=3000; f1[6]=5000; f1[7]=10000;
        int24[] memory t1 = new int24[](5);
        t1[0]=1; t1[1]=2; t1[2]=4; t1[3]=8; t1[4]=10;
        _scan("Batch1", f1, t1, hooks);

        // Batch 2: fees 0-7 x tss 5-9 (8x5=40)
        int24[] memory t2 = new int24[](5);
        t2[0]=60; t2[1]=100; t2[2]=200; t2[3]=400; t2[4]=2000;
        _scan("Batch2", f1, t2, hooks);

        // Batch 3: fees 8-11 x tss 0-4 (4x5=20)
        uint24[] memory f2 = new uint24[](4);
        f2[0]=20000; f2[1]=50000; f2[2]=100000; f2[3]=800000;
        _scan("Batch3", f2, t1, hooks);

        // Batch 4: fees 8-11 x tss 5-9 (4x5=20)
        _scan("Batch4", f2, t2, hooks);
    }

    function _scan(string memory label, uint24[] memory fees, int24[] memory tss, address[] memory hooks) internal view {
        IPoolScanner.PoolInfo[] memory pools = scanner.scanPair(SIREN, USDT, fees, tss, hooks);
        if (pools.length > 0) {
            console.log("=== %s: %s pools ===", label, pools.length);
            for (uint256 i = 0; i < pools.length; i++) {
                console.log("  fee=%s ts=%s", pools[i].fee, uint256(uint24(pools[i].tickSpacing)));
                console.log("  sqrtPrice=%s", uint256(pools[i].sqrtPriceX96));
                console.log("  liquidity=%s", uint256(pools[i].liquidity));
                console.log("  tick=%s", uint256(int256(pools[i].tick)));
                console.log("  poolId:");
                console.logBytes32(pools[i].poolId);
            }
        } else {
            console.log("%s: no pools", label);
        }
    }
}
