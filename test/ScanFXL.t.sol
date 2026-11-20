//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {IPoolScanner} from "../src/IPoolScanner.sol";

contract ScanFXLTest is Test {
    UniswapV4PoolScanner public scanner;
    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant V4_SCANNER = 0xB442ce9A9f3480a7Cad578296917649d9a451cc7;
    address constant FXL = 0x9b8E987e6fEc8Cf1380C4dcA7071e2C7853AEEA1;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    function setUp() public {
        vm.createSelectFork(
            "https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6",
            133660000
        );
        scanner = UniswapV4PoolScanner(V4_SCANNER);
    }

    function test_scan_fxl_usdt() public view {
        address[] memory hooksList = new address[](1);
        hooksList[0] = address(0);

        // Batch 1: fees 100-1000, ts 1-60
        uint24[] memory f1 = new uint24[](4);
        f1[0] = 100; f1[1] = 200; f1[2] = 500; f1[3] = 1000;
        int24[] memory t1 = new int24[](4);
        t1[0] = 1; t1[1] = 4; t1[2] = 10; t1[3] = 60;
        _scan("Batch1 (fee 100-1000, ts 1-60)", f1, t1, hooksList);

        // Batch 2: fees 100-1000, ts 100-2000
        int24[] memory t2 = new int24[](4);
        t2[0] = 100; t2[1] = 200; t2[2] = 400; t2[3] = 2000;
        _scan("Batch2 (fee 100-1000, ts 100-2000)", f1, t2, hooksList);

        // Batch 3: fees 2000-10000, ts 1-60
        uint24[] memory f2 = new uint24[](4);
        f2[0] = 2000; f2[1] = 3000; f2[2] = 5000; f2[3] = 10000;
        _scan("Batch3 (fee 2000-10000, ts 1-60)", f2, t1, hooksList);

        // Batch 4: fees 2000-10000, ts 100-2000
        _scan("Batch4 (fee 2000-10000, ts 100-2000)", f2, t2, hooksList);

        // Batch 5: fees 20000-800000, ts 1-60
        uint24[] memory f3 = new uint24[](4);
        f3[0] = 20000; f3[1] = 50000; f3[2] = 100000; f3[3] = 800000;
        _scan("Batch5 (fee 20000-800000, ts 1-60)", f3, t1, hooksList);

        // Batch 6: fees 20000-800000, ts 100-2000
        _scan("Batch6 (fee 20000-800000, ts 100-2000)", f3, t2, hooksList);
    }

    function _scan(
        string memory label,
        uint24[] memory fees,
        int24[] memory tickSpacings,
        address[] memory hooksList
    ) internal view {
        IPoolScanner.PoolInfo[] memory pools = scanner.scanPair(
            FXL, USDT, fees, tickSpacings, hooksList
        );

        if (pools.length > 0) {
            console.log("=== FOUND pools in %s ===", label);
            for (uint256 i = 0; i < pools.length; i++) {
                console.log("  fee=%s ts=%s", pools[i].fee, uint256(uint24(pools[i].tickSpacing)));
                console.log("  sqrtPrice=%s", uint256(pools[i].sqrtPriceX96));
                console.log("  liquidity=%s", uint256(pools[i].liquidity));
                console.log("  tick=%s", uint256(int256(pools[i].tick)));
            }
        } else {
            console.log("No pools in %s", label);
        }
    }
}
