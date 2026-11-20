//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {IPoolScanner} from "../src/IPoolScanner.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapMath} from "v4-core/libraries/SwapMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";

/**
 * @title DiscoverV4PoolsTest
 * @notice Flujo completo V4 en test:
 *   1. Recibe datos de pools V4 del Trading API (off-chain, hardcoded)
 *   2. Verifica pools on-chain via scanner (liquidez, sqrtPrice, tick)
 *   3. Construye quote V4 on-chain usando SwapMath de v4-core (iterando ticks)
 *   4. Ejecuta swap V4 via Universal Router (V4_SWAP = 0x10)
 */
contract DiscoverV4PoolsTest is Test {
    UniswapV4PoolScanner public scanner;

    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant V4_SCANNER = 0xB442ce9A9f3480a7Cad578296917649d9a451cc7;
    address constant UNIVERSAL_ROUTER =
        0x1906c1d672b88cD1B9aC7593301cA990F94Eae07;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant NVDA = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    address constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    // V4 Action codes (from v4-periphery Actions.sol)
    uint8 constant ACTION_SWAP_EXACT_IN_SINGLE = 6;
    uint8 constant ACTION_SETTLE_ALL = 12;
    uint8 constant ACTION_TAKE_ALL = 15;

    // Universal Router command
    bytes1 constant CMD_V4_SWAP = bytes1(0x10);

    // MSG_SENDER sentinel for recipient
    address constant MSG_SENDER = 0x0000000000000000000000000000000000000001;

    address testUser;

    function setUp() public {
        vm.createSelectFork(
            "https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6",
            133660000
        );
        scanner = UniswapV4PoolScanner(V4_SCANNER);
        testUser = makeAddr("testUser");
        vm.deal(testUser, 100 ether);
    }

    struct V4PoolAPIData {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    function _buildPoolKey(
        V4PoolAPIData memory data
    ) internal pure returns (PoolKey memory key) {
        address token0 = data.tokenIn < data.tokenOut
            ? data.tokenIn
            : data.tokenOut;
        address token1 = data.tokenIn < data.tokenOut
            ? data.tokenOut
            : data.tokenIn;
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: data.fee,
            tickSpacing: data.tickSpacing,
            hooks: IHooks(data.hooks)
        });
    }

    function _isZeroForOne(
        address tokenIn,
        address tokenOut
    ) internal pure returns (bool) {
        return tokenIn < tokenOut;
    }

    // ==========================================================
    //  PASO 1: Verificar pools V4 on-chain
    // ==========================================================

    function test_verify_v4_pools_from_api() public view {
        V4PoolAPIData[2] memory apiPools = [
            V4PoolAPIData(NVDA, NVDAB, 200, 4, address(0)),
            V4PoolAPIData(NVDAB, USDT, 20000, 400, address(0))
        ];

        for (uint256 i = 0; i < apiPools.length; i++) {
            PoolKey memory key = _buildPoolKey(apiPools[i]);
            (bool initialized, IPoolScanner.PoolInfo memory info) = scanner
                .checkPool(key);

            console.log("=== POOL %s ===", i + 1);
            console.log("  initialized:  %s", initialized ? 1 : 0);
            console.log("  sqrtPriceX96: %s", uint256(info.sqrtPriceX96));
            console.log("  tick:         %s", uint256(int256(info.tick)));
            console.log("  liquidity:    %s", uint256(info.liquidity));
            console.log("  fee:          %s", uint256(info.fee));
            console.log(
                "  tickSpacing:  %s",
                uint256(uint24(info.tickSpacing))
            );

            assertTrue(initialized, "Pool should be initialized");
            assertGt(uint256(info.sqrtPriceX96), 0, "sqrtPrice > 0");
            assertGt(uint256(info.liquidity), 0, "liquidity > 0");
            assertEq(info.fee, apiPools[i].fee, "fee mismatch");
            assertEq(
                info.tickSpacing,
                apiPools[i].tickSpacing,
                "tickSpacing mismatch"
            );
        }
    }

    // ==========================================================
    //  PASO 2: Quote V4 on-chain (SwapMath iterando ticks)
    // ==========================================================

    function _quoteV4(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        int24 tickSpacing,
        uint24 fee,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint256 totalAmountOut) {
        uint256 remainingAmount = amountIn;
        uint160 currentSqrtPrice = sqrtPriceX96;
        int24 currentTick = tick;

        for (uint256 i = 0; i < 100; i++) {
            if (remainingAmount == 0 || liquidity == 0) break;

            int24 tickNext = zeroForOne
                ? currentTick - tickSpacing
                : currentTick + tickSpacing;

            if (tickNext < TickMath.MIN_TICK) tickNext = TickMath.MIN_TICK;
            if (tickNext > TickMath.MAX_TICK) tickNext = TickMath.MAX_TICK;

            uint160 sqrtPriceTargetX96 = TickMath.getSqrtPriceAtTick(tickNext);

            (
                uint160 sqrtPriceNextX96,
                uint256 amountInConsumed,
                uint256 amountOut,
                uint256 feeAmount
            ) = SwapMath.computeSwapStep(
                    currentSqrtPrice,
                    sqrtPriceTargetX96,
                    liquidity,
                    -int256(remainingAmount),
                    fee
                );

            totalAmountOut += amountOut;
            remainingAmount -= amountInConsumed + feeAmount;

            if (sqrtPriceNextX96 == sqrtPriceTargetX96) {
                currentTick = tickNext;
                currentSqrtPrice = sqrtPriceNextX96;
            } else {
                currentSqrtPrice = sqrtPriceNextX96;
                break;
            }
        }
    }

    function test_quote_v4_multihop() public view {
        uint256 amountIn = 1e18;

        PoolKey memory key1 = _buildPoolKey(
            V4PoolAPIData(NVDA, NVDAB, 200, 4, address(0))
        );
        (, IPoolScanner.PoolInfo memory pool1) = scanner.checkPool(key1);
        uint256 amountOut1 = _quoteV4(
            pool1.sqrtPriceX96,
            pool1.liquidity,
            pool1.tick,
            pool1.tickSpacing,
            pool1.fee,
            amountIn,
            _isZeroForOne(NVDA, NVDAB)
        );

        PoolKey memory key2 = _buildPoolKey(
            V4PoolAPIData(NVDAB, USDT, 20000, 400, address(0))
        );
        (, IPoolScanner.PoolInfo memory pool2) = scanner.checkPool(key2);
        uint256 amountOut2 = _quoteV4(
            pool2.sqrtPriceX96,
            pool2.liquidity,
            pool2.tick,
            pool2.tickSpacing,
            pool2.fee,
            amountOut1,
            _isZeroForOne(NVDAB, USDT)
        );

        console.log("=== QUOTE V4 MULTI-HOP ===");
        console.log("  Hop 1: NVDAon -> NVDAB: %s", amountOut1);
        console.log("  Hop 2: NVDAB -> USDT:   %s", amountOut2);
        console.log("  TOTAL: 1 NVDAon -> %s USDT", amountOut2);
        console.log("  API said: 153406641492481582735 USDT (~153)");

        assertGt(amountOut2, 0, "Quote V4 > 0");
    }

    // ==========================================================
    //  PASO 3: Swap V4 via Universal Router
    // ==========================================================

    function _encodeV4Actions(
        bytes memory actions,
        bytes[] memory params
    ) internal pure returns (bytes memory) {
        return abi.encode(actions, params);
    }

    /// @dev Construye el param para SWAP_EXACT_IN_SINGLE
    /// El decoder hace: swapParams := add(params.offset, calldataload(params.offset))
    /// Lee el primer word como offset al struct. abi.encode de campos planos
    /// con bytes hookData al final PRODUCE el offset automáticamente.
    function _encodeSwapExactInSingle(
        PoolKey memory key,
        bool zeroForOne,
        uint128 amountIn,
        uint128 amountOutMin
    ) internal pure returns (bytes memory) {
        ExactInputSingleParams memory swapParams = ExactInputSingleParams({
            poolKey: key,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            hookData: bytes("")
        });

        return abi.encode(swapParams);
    }

    function test_execute_swap_v4_single_hop() public {
        // Swap: NVDAon -> NVDAB (single hop)
        deal(NVDA, testUser, 1e18);

        vm.startPrank(testUser);
        IERC20(NVDA).approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(
            NVDA,
            UNIVERSAL_ROUTER,
            uint160(1e18),
            uint48(block.timestamp + 1 days)
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(NVDAB),
            currency1: Currency.wrap(NVDA),
            fee: 200,
            tickSpacing: 4,
            hooks: IHooks(address(0))
        });

        // Quote
        (, IPoolScanner.PoolInfo memory pool) = scanner.checkPool(key);
        uint256 quotedOut = _quoteV4(
            pool.sqrtPriceX96,
            pool.liquidity,
            pool.tick,
            pool.tickSpacing,
            pool.fee,
            1e18,
            false
        );
        uint256 amountOutMin = (quotedOut * 995) / 1000;

        console.log("=== SWAP V4 SINGLE-HOP ===");
        console.log("  amountIn:     %s NVDAon", uint256(1e18));
        console.log("  quotedOut:    %s NVDAB", quotedOut);
        console.log("  amountOutMin: %s NVDAB", amountOutMin);

        // Actions: SWAP_EXACT_IN_SINGLE(6) + SETTLE_ALL(12) + TAKE_ALL(15)
        // SETTLE_ALL: (address currency, uint256 maxAmount) — settle toda la deuda
        // TAKE_ALL: (address currency, uint256 minAmount) — tomar todo el credit
        bytes memory actions = abi.encodePacked(
            bytes1(ACTION_SWAP_EXACT_IN_SINGLE),
            bytes1(ACTION_SETTLE_ALL),
            bytes1(ACTION_TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        // SWAP_EXACT_IN_SINGLE
        params[0] = _encodeSwapExactInSingle(
            key,
            false,
            uint128(1e18),
            uint128(amountOutMin)
        );
        // SETTLE_ALL: pagar NVDAon (maxAmount=1e18)
        params[1] = abi.encode(NVDA, uint256(1e18));
        // TAKE_ALL: tomar NVDAB (minAmount=0, tomar todo)
        params[2] = abi.encode(NVDAB, uint256(0));

        bytes memory v4Input = _encodeV4Actions(actions, params);

        bytes memory commands = abi.encodePacked(CMD_V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = v4Input;

        uint256 nvdabBefore = IERC20(NVDAB).balanceOf(testUser);

        IUniversalRouter(UNIVERSAL_ROUTER).execute(
            commands,
            inputs,
            block.timestamp + 60
        );

        uint256 nvdabAfter = IERC20(NVDAB).balanceOf(testUser);
        uint256 received = nvdabAfter - nvdabBefore;

        console.log("");
        console.log("  NVDAB received: %s", received);

        vm.stopPrank();

        assertGt(received, 0, "Should receive NVDAB");
    }

    function test_execute_swap_v4_multihop() public {
        // Swap: NVDAon -> NVDAB -> USDT (multi-hop)
        deal(NVDA, testUser, 1e18);

        vm.startPrank(testUser);
        IERC20(NVDA).approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(
            NVDA,
            UNIVERSAL_ROUTER,
            uint160(1e18),
            uint48(block.timestamp + 1 days)
        );

        PoolKey memory key1 = PoolKey({
            currency0: Currency.wrap(NVDAB),
            currency1: Currency.wrap(NVDA),
            fee: 200,
            tickSpacing: 4,
            hooks: IHooks(address(0))
        });

        PoolKey memory key2 = PoolKey({
            currency0: Currency.wrap(NVDAB),
            currency1: Currency.wrap(USDT),
            fee: 20000,
            tickSpacing: 400,
            hooks: IHooks(address(0))
        });

        // Quote
        (, IPoolScanner.PoolInfo memory p1) = scanner.checkPool(key1);
        uint256 hop1Out = _quoteV4(
            p1.sqrtPriceX96,
            p1.liquidity,
            p1.tick,
            p1.tickSpacing,
            p1.fee,
            1e18,
            false
        );

        (, IPoolScanner.PoolInfo memory p2) = scanner.checkPool(key2);
        uint256 hop2Out = _quoteV4(
            p2.sqrtPriceX96,
            p2.liquidity,
            p2.tick,
            p2.tickSpacing,
            p2.fee,
            hop1Out,
            true
        );

        uint256 amountOutMin = (hop2Out * 995) / 1000;

        console.log("=== SWAP V4 MULTI-HOP ===");
        console.log("  amountIn:     %s NVDAon", uint256(1e18));
        console.log("  hop1Out:      %s NVDAB", hop1Out);
        console.log("  hop2Out:      %s USDT", hop2Out);
        console.log("  amountOutMin: %s USDT", amountOutMin);

        // Actions: SWAP(6) + SWAP(6) + SETTLE_ALL(12) + TAKE_ALL(15)
        // Hop 2 usa amountIn=0 que significa OPEN_DELTA (usar todo el balance del router)
        bytes memory actions = abi.encodePacked(
            bytes1(ACTION_SWAP_EXACT_IN_SINGLE), // 0x06 - hop 1
            bytes1(ACTION_SWAP_EXACT_IN_SINGLE), // 0x06 - hop 2
            bytes1(ACTION_SETTLE_ALL), // 0x0c - pagar NVDAon
            bytes1(ACTION_TAKE_ALL) // 0x0f - recibir USDT
        );

        bytes[] memory params = new bytes[](4);
        // Hop 1: NVDAon -> NVDAB
        params[0] = _encodeSwapExactInSingle(
            key1,
            false,
            uint128(1e18),
            uint128(0)
        );
        // Hop 2: NVDAB -> USDT (amountIn=0 = OPEN_DELTA = usar todo el balance)
        params[1] = _encodeSwapExactInSingle(
            key2,
            true,
            uint128(0),
            uint128(amountOutMin)
        );
        // SETTLE_ALL: pagar NVDAon (maxAmount=1e18)
        params[2] = abi.encode(NVDA, uint256(1e18));
        // TAKE_ALL: tomar USDT (minAmount=0, tomar todo)
        params[3] = abi.encode(USDT, uint256(0));

        bytes memory v4Input = _encodeV4Actions(actions, params);

        bytes memory commands = abi.encodePacked(CMD_V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = v4Input;

        uint256 usdtBefore = IERC20(USDT).balanceOf(testUser);

        IUniversalRouter(UNIVERSAL_ROUTER).execute(
            commands,
            inputs,
            block.timestamp + 60
        );

        uint256 usdtAfter = IERC20(USDT).balanceOf(testUser);
        uint256 received = usdtAfter - usdtBefore;

        console.log("");
        console.log("  USDT received: %s", received);

        vm.stopPrank();

        assertGt(received, 0, "Should receive USDT");
    }

    // ==========================================================
    //  Comparación V3 vs V4
    // ==========================================================

    function test_compare_v3_vs_v4() public view {
        uint256 amountIn = 1e18;

        PoolKey memory key1 = _buildPoolKey(
            V4PoolAPIData(NVDA, NVDAB, 200, 4, address(0))
        );
        (, IPoolScanner.PoolInfo memory p1) = scanner.checkPool(key1);
        uint256 v4Hop1 = _quoteV4(
            p1.sqrtPriceX96,
            p1.liquidity,
            p1.tick,
            p1.tickSpacing,
            p1.fee,
            amountIn,
            false
        );

        PoolKey memory key2 = _buildPoolKey(
            V4PoolAPIData(NVDAB, USDT, 20000, 400, address(0))
        );
        (, IPoolScanner.PoolInfo memory p2) = scanner.checkPool(key2);
        uint256 v4Total = _quoteV4(
            p2.sqrtPriceX96,
            p2.liquidity,
            p2.tick,
            p2.tickSpacing,
            p2.fee,
            v4Hop1,
            true
        );

        console.log("=== COMPARACION V3 vs V4 ===");
        console.log("  V4 quote: %s USDT", v4Total);
        console.log("  V3 quote: (pendiente)");

        assertGt(v4Total, 0, "V4 quote > 0");
    }

    function test_nonexistent_pool() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(NVDA),
            currency1: Currency.wrap(USDT),
            fee: 9999,
            tickSpacing: 100,
            hooks: IHooks(address(0))
        });

        (bool initialized, ) = scanner.checkPool(key);
        assertFalse(initialized, "Non-existent pool should not be initialized");
    }
}

// ============
//  INTERFACES
// ============

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
}

interface IPermit2 {
    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external;
}

interface IUniversalRouter {
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;
}
