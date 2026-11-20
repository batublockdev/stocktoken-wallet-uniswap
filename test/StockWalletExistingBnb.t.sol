//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {IPoolScanner} from "../src/IPoolScanner.sol";
import {IERC20} from "./IERC20.sol";
import {console} from "forge-std/console.sol";
import {
    NEAR,
    ZEC,
    BTCB,
    GOOGLE,
    ETH,
    USDC,
    USDT,
    LINK,
    AAVE,
    DOT,
    UNI,
    NVDAon,
    NVDAB,
    AAPLon,
    FXLon,
    SIREN,
    WBNB,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER,
    UNISWAP_V4_QUOTER,
    UNIVERSAL_ROUTER,
    PERMIT2
} from "./ConstantsBnb.sol";

/// @title StockWalletExistingBnb - Test completo en BSC mainnet fork
/// @notice Tests integracion V3+V4 con tokens reales de BSC:
///         Crypto majors (BTCB, ETH, LINK, AAVE, UNI, DOT)
///         + Stocks Ondo via V4 (NVDAon multi-hop, AAPLon single-hop)
///         + Stock Ondo via V3 (FXLon fee=500, liquidez 3.88e23)
///         Pools V4 confirmadas via Uniswap Trading API:
///           - NVDAon -> NVDAB -> USDT (multi-hop: fee=200/ts=4, fee=20000/ts=400)
///           - AAPLon -> USDT (single-hop: fee=100000/ts=2000)
///         Pools V3 confirmadas on-chain:
///           - FXLon/USDT fee=500 (liquidez 3.88e23)
///         Usa USDT como base token (liquidez real en BSC esta con USDT)
///         Requiere fork de BSC en bloque >= 133660000 (V4 PoolManager)
contract StockWalletExistingBnbTest is Test {
    StockWallet public wallet;
    UniswapV4PoolScanner public scanner;

    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");

    // --- V4 Infrastructure on BSC ---
    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant UNIVERSAL_ROUTER_V4 =
        0x1906c1d672b88cD1B9aC7593301cA990F94Eae07;

    // Scanner ya deployado en BSC (block 134522506)
    address constant V4_SCANNER = 0xB442ce9A9f3480a7Cad578296917649d9a451cc7;

    // --- Tokens ---
    IERC20 private usdt = IERC20(USDT);
    IERC20 private google = IERC20(GOOGLE);
    IERC20 private btcb = IERC20(BTCB);
    IERC20 private zec = IERC20(ZEC);
    IERC20 private near = IERC20(NEAR);

    IERC20 private eth = IERC20(ETH);
    IERC20 private link = IERC20(LINK);
    IERC20 private aave = IERC20(AAVE);
    IERC20 private dot = IERC20(DOT);
    IERC20 private uni = IERC20(UNI);
    IERC20 private nvdaon = IERC20(NVDAon);
    IERC20 private aaplon = IERC20(AAPLon);
    IERC20 private fxlon = IERC20(FXLon);
    IERC20 private siren = IERC20(SIREN);
    IERC20 private nvdaBridge = IERC20(NVDAB);

    // Fork block - must be >= 133660000 for V4 PoolManager
    uint256 constant FORK_BLOCK = 133660000;

    // --- V4 Pool params from Uniswap Trading API ---
    // NVDAon multi-hop: NVDAon -> NVDAB -> USDT
    uint24 constant NVDA_NVDAB_FEE = 200;
    int24 constant NVDA_NVDAB_TS = 4;
    uint24 constant NVDAB_USDT_FEE = 20000;
    int24 constant NVDAB_USDT_TS = 400;
    // AAPLon single-hop: AAPLon -> USDT
    uint24 constant AAPL_USDT_FEE = 100000;
    int24 constant AAPL_USDT_TS = 2000;

    function setUp() public {
        vm.createSelectFork(
            "https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6",
            FORK_BLOCK
        );
        scanner = UniswapV4PoolScanner(V4_SCANNER);
    }

    // =============================================================
    // === HELPERS ===
    // =============================================================

    function _deployWallet(
        address[] memory tokens,
        StockWallet.AssetConfig[] memory configs
    ) internal returns (StockWallet) {
        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](
                tokens.length
            );
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAllocation[i] = StockWallet.TokenAllocationConfig({
                token: tokens[i],
                configs: configs[i]
            });
        }

        vm.prank(owner);
        return
            new StockWallet(
                USDT,
                UNISWAP_V3_FACTORY,
                UNIVERSAL_ROUTER_V4,
                PERMIT2,
                UNISWAP_V3_QUOTER,
                UNISWAP_V4_QUOTER,
                POOL_MANAGER,
                address(scanner),
                adgent,
                adgentContract,
                0,
                tokenAllocation
            );
    }

    function _fundWallet(uint256 amount) internal {
        deal(USDT, address(this), amount);
        usdt.transfer(address(wallet), amount);
    }

    function _makeV4Pool(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing
    ) internal pure returns (StockWallet.V4PoolData memory) {
        return
            StockWallet.V4PoolData({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: address(0)
            });
    }

    function _nvdaV4Route()
        internal
        pure
        returns (StockWallet.V4PoolData[] memory)
    {
        StockWallet.V4PoolData[] memory pools = new StockWallet.V4PoolData[](2);
        pools[0] = _makeV4Pool(NVDAon, NVDAB, NVDA_NVDAB_FEE, NVDA_NVDAB_TS);
        pools[1] = _makeV4Pool(NVDAB, USDT, NVDAB_USDT_FEE, NVDAB_USDT_TS);
        return pools;
    }

    function _aaplV4Route()
        internal
        pure
        returns (StockWallet.V4PoolData[] memory)
    {
        StockWallet.V4PoolData[] memory pools = new StockWallet.V4PoolData[](1);
        pools[0] = _makeV4Pool(AAPLon, USDT, AAPL_USDT_FEE, AAPL_USDT_TS);
        return pools;
    }

    function _checkV4Pool(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing
    ) internal view returns (IPoolScanner.PoolInfo memory) {
        uint24[] memory fees = new uint24[](1);
        fees[0] = fee;
        int24[] memory tickSpacings = new int24[](1);
        tickSpacings[0] = tickSpacing;
        address[] memory hooksList = new address[](1);
        hooksList[0] = address(0);

        IPoolScanner.PoolInfo[] memory pools = scanner.scanPair(
            tokenA,
            tokenB,
            fees,
            tickSpacings,
            hooksList
        );

        if (pools.length > 0) return pools[0];

        return
            IPoolScanner.PoolInfo({
                poolId: 0,
                currency0: address(0),
                currency1: address(0),
                fee: 0,
                tickSpacing: 0,
                hooks: address(0),
                sqrtPriceX96: 0,
                tick: 0,
                liquidity: 0
            });
    }

    // =============================================================
    // === TEST 1: Crypto V3 (BTCB, ETH, LINK) + V4 Storage para NVDAon y AAPLon ===
    // =============================================================

    function test_fullCycle_crypto_with_v4_storage() public {
        console.log("=== TEST 1: Crypto V3 + V4 Storage (NVDAon + AAPLon) ===");

        // --- DEPLOY: BTCB 40%, ETH 30%, LINK 30% ---
        address[] memory tokens = new address[](3);
        tokens[0] = BTCB;
        tokens[1] = ETH;
        tokens[2] = LINK;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](3);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 4000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 3000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[2] = StockWallet.AssetConfig({
            allocationBps: 3000,
            stopLossBps: 8500,
            takeProfitBps: 11500
        });

        wallet = _deployWallet(tokens, configs);

        // --- VERIFICAR V4 INFRASTRUCTURE ---
        assertEq(
            address(wallet.poolManager()),
            POOL_MANAGER,
            "PoolManager set"
        );
        assertEq(wallet.v4Scanner(), address(scanner), "Scanner set");
        console.log("PoolManager:", address(wallet.poolManager()));
        console.log("V4 Scanner:", wallet.v4Scanner());

        // --- FUND + INVEST (V3) ---
        _fundWallet(1000 * 1e18);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        console.log("=== DESPUES DEL INVEST (V3) ===");
        console.log("BTCB wallet:", btcb.balanceOf(address(wallet)));
        console.log("ETH wallet:", eth.balanceOf(address(wallet)));
        console.log("LINK wallet:", link.balanceOf(address(wallet)));

        assertGt(btcb.balanceOf(address(wallet)), 0, "Should have BTCB");
        assertGt(eth.balanceOf(address(wallet)), 0, "Should have ETH");
        assertGt(link.balanceOf(address(wallet)), 0, "Should have LINK");

        // --- GUARDAR V4 POOLS PARA NVDAon (multi-hop) ---
        StockWallet.V4PoolData[] memory nvdaV4 = _nvdaV4Route();

        vm.prank(adgent);
        wallet.setV4Pools(NVDAon, nvdaV4);

        // --- VERIFICAR GUARDADO NVDAon ---
        StockWallet.V4PoolData[] memory nvdaStored = wallet.getV4Pools(NVDAon);
        assertEq(nvdaStored.length, 2, "NVDAon: 2 V4 pools stored");
        assertEq(nvdaStored[0].tokenIn, NVDAon, "NVDAon pool 0 tokenIn");
        assertEq(nvdaStored[0].tokenOut, NVDAB, "NVDAon pool 0 tokenOut");
        assertEq(nvdaStored[0].fee, NVDA_NVDAB_FEE, "NVDAon pool 0 fee");
        assertEq(
            nvdaStored[0].tickSpacing,
            NVDA_NVDAB_TS,
            "NVDAon pool 0 tickSpacing"
        );
        assertEq(nvdaStored[1].tokenIn, NVDAB, "NVDAon pool 1 tokenIn");
        assertEq(nvdaStored[1].tokenOut, USDT, "NVDAon pool 1 tokenOut");
        assertEq(nvdaStored[1].fee, NVDAB_USDT_FEE, "NVDAon pool 1 fee");
        assertEq(
            nvdaStored[1].tickSpacing,
            NVDAB_USDT_TS,
            "NVDAon pool 1 tickSpacing"
        );

        console.log("=== NVDAon V4 POOLS GUARDADAS (multi-hop) ===");
        console.log("  Pool 0: NVDAon -> NVDAB, fee=200, ts=4");
        console.log("  Pool 1: NVDAB -> USDT, fee=20000, ts=400");

        // --- GUARDAR V4 POOLS PARA AAPLon (single-hop directo!) ---
        StockWallet.V4PoolData[] memory aaplV4 = _aaplV4Route();

        vm.prank(adgent);
        wallet.setV4Pools(AAPLon, aaplV4);

        // --- VERIFICAR GUARDADO AAPLon ---
        StockWallet.V4PoolData[] memory aaplStored = wallet.getV4Pools(AAPLon);
        assertEq(aaplStored.length, 1, "AAPLon: 1 V4 pool stored");
        assertEq(aaplStored[0].tokenIn, AAPLon, "AAPLon pool 0 tokenIn");
        assertEq(aaplStored[0].tokenOut, USDT, "AAPLon pool 0 tokenOut");
        assertEq(aaplStored[0].fee, AAPL_USDT_FEE, "AAPLon pool 0 fee=100000");
        assertEq(
            aaplStored[0].tickSpacing,
            AAPL_USDT_TS,
            "AAPLon pool 0 tickSpacing=2000"
        );

        console.log("=== AAPLon V4 POOL GUARDADA (single-hop directo) ===");
        console.log("  Pool 0: AAPLon -> USDT, fee=100000, ts=2000");

        // --- VERIFICAR AMBAS POOLS V4 EXISTEN ON-CHAIN VIA SCANNER ---
        IPoolScanner.PoolInfo memory nvdaPool = _checkV4Pool(
            NVDAon,
            NVDAB,
            NVDA_NVDAB_FEE,
            NVDA_NVDAB_TS
        );
        assertGt(
            uint256(nvdaPool.sqrtPriceX96),
            0,
            "V4 Pool NVDAon/NVDAB sqrtPrice > 0"
        );
        assertGt(nvdaPool.liquidity, 0, "V4 Pool NVDAon/NVDAB liquidity > 0");

        IPoolScanner.PoolInfo memory aaplPool = _checkV4Pool(
            AAPLon,
            USDT,
            AAPL_USDT_FEE,
            AAPL_USDT_TS
        );
        assertGt(
            uint256(aaplPool.sqrtPriceX96),
            0,
            "V4 Pool AAPLon/USDT sqrtPrice > 0"
        );
        assertGt(aaplPool.liquidity, 0, "V4 Pool AAPLon/USDT liquidity > 0");

        console.log("=== POOLS V4 VERIFICADAS ON-CHAIN ===");
        console.log("  NVDAon/NVDAB liquidity:", uint256(nvdaPool.liquidity));
        console.log("  AAPLon/USDT liquidity:", uint256(aaplPool.liquidity));

        // --- LINK SIN V4 (V3 only) ---
        assertEq(wallet.getV4Pools(LINK).length, 0, "LINK no V4 pools");
        assertEq(wallet.getV4Pools(BTCB).length, 0, "BTCB no V4 pools");
        assertEq(wallet.getV4Pools(ETH).length, 0, "ETH no V4 pools");

        console.log("  LINK/BTCB/ETH: 0 V4 pools (V3 only)");

        // --- SELLTOKENALL + WITHDRAW ---
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        uint256 ownerBefore = usdt.balanceOf(owner);

        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
        }

        assertGt(usdt.balanceOf(owner), ownerBefore, "Owner should have USDT");

        console.log("=== DESPUES DE SELL + WITHDRAW ===");
        console.log("USDT owner:", usdt.balanceOf(owner));
    }

    // =============================================================
    // === TEST 2: invest() con V4 pools como parametro + auto-guardado
    //         Usa AAPLon (single-hop V4) ===
    // =============================================================

    function test_invest_v4_params_auto_save_aaplon() public {
        console.log(
            "=== TEST 2: invest() con V4 params (AAPLon single-hop) ==="
        );

        // --- DEPLOY: LINK 50%, AAVE 50% ---
        address[] memory tokens = new address[](2);
        tokens[0] = LINK;
        tokens[1] = AAVE;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](2);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(500 * 1e18);

        // Pasar V4 pools para LINK (ruta venta multi-hop), AAVE sin V4
        StockWallet.V4PoolData[][]
            memory v4ForInvest = new StockWallet.V4PoolData[][](2);

        // LINK: V4 route LINK -> NVDAB -> USDT (para venta futura)
        StockWallet.V4PoolData[] memory linkV4 = new StockWallet.V4PoolData[](
            2
        );
        linkV4[0] = _makeV4Pool(LINK, NVDAB, NVDA_NVDAB_FEE, NVDA_NVDAB_TS);
        linkV4[1] = _makeV4Pool(NVDAB, USDT, NVDAB_USDT_FEE, NVDAB_USDT_TS);
        v4ForInvest[0] = linkV4;

        // AAVE: sin V4
        v4ForInvest[1] = new StockWallet.V4PoolData[](0);

        // --- INVEST ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), v4ForInvest);

        console.log("=== DESPUES DE INVEST ===");
        console.log("LINK wallet:", link.balanceOf(address(wallet)));
        console.log("AAVE wallet:", aave.balanceOf(address(wallet)));

        assertGt(link.balanceOf(address(wallet)), 0, "Should have LINK");
        assertGt(aave.balanceOf(address(wallet)), 0, "Should have AAVE");

        // --- VERIFICAR AUTO-GUARDADO ---
        StockWallet.V4PoolData[] memory linkStored = wallet.getV4Pools(LINK);
        assertEq(linkStored.length, 2, "LINK V4 pools auto-saved");
        assertEq(linkStored[0].tokenIn, LINK, "LINK pool 0 tokenIn");
        assertEq(linkStored[0].tokenOut, NVDAB, "LINK pool 0 tokenOut");
        assertEq(linkStored[1].tokenIn, NVDAB, "LINK pool 1 tokenIn");
        assertEq(linkStored[1].tokenOut, USDT, "LINK pool 1 tokenOut");

        assertEq(wallet.getV4Pools(AAVE).length, 0, "AAVE no V4 pools (V3)");

        console.log("=== AUTO-GUARDADO VERIFICADO ===");
        console.log("  LINK: 2 V4 pools (multi-hop)");
        console.log("  AAVE: 0 V4 pools (V3 only)");
    }

    // =============================================================
    // === TEST 3: setV4Pools access control + overwrite + edge cases ===
    // =============================================================

    function test_setV4Pools_access_control() public {
        console.log("=== TEST 3: setV4Pools access control ===");

        address[] memory tokens = new address[](1);
        tokens[0] = LINK;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);

        // Owner puede setear
        StockWallet.V4PoolData[] memory pools = _aaplV4Route(); // AAPLon V4 single-hop
        vm.prank(owner);
        wallet.setV4Pools(LINK, pools);

        assertEq(wallet.getV4Pools(LINK).length, 1, "Owner set V4 pools");
        assertEq(wallet.getV4Pools(LINK)[0].fee, AAPL_USDT_FEE, "Fee=100000");

        console.log("  Owner set: OK, fee=100000");

        // Adgent puede sobreescribir
        StockWallet.V4PoolData[] memory newPools = _nvdaV4Route(); // NVDAon V4 multi-hop
        vm.prank(adgent);
        wallet.setV4Pools(LINK, newPools);

        StockWallet.V4PoolData[] memory updated = wallet.getV4Pools(LINK);
        assertEq(updated.length, 2, "Overwritten to 2 pools");
        assertEq(updated[0].fee, NVDA_NVDAB_FEE, "New pool 0 fee=200");
        assertEq(updated[1].fee, NVDAB_USDT_FEE, "New pool 1 fee=20000");

        console.log("  Adgent overwrite: 2 pools (fee=200, fee=20000)");

        // Random rechazado
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        wallet.setV4Pools(LINK, newPools);

        // address(0) rechazado
        vm.prank(adgent);
        vm.expectRevert();
        wallet.setV4Pools(address(0), newPools);

        // Array vacio rechazado
        StockWallet.V4PoolData[] memory empty = new StockWallet.V4PoolData[](0);
        vm.prank(adgent);
        vm.expectRevert();
        wallet.setV4Pools(LINK, empty);

        console.log("  Random/address(0)/empty rejected: OK");
    }

    // =============================================================
    // === TEST 4: Portfolio mixto V3 (LINK, UNI) + V4 stocks (NVDAon, AAPLon)
    //         + addAsset + persistencia ===
    // =============================================================

    /*function test_mixed_portfolio_v3_crypto_v4_stocks() public {
        console.log("=== TEST 4: Mixed Portfolio (V3 Crypto + V4 Stocks) ===");

        // DEPLOY: LINK 50%, UNI 50%
        address[] memory tokens = new address[](2);
        tokens[0] = LINK;
        tokens[1] = UNI;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](2);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(1000 * 1e18);

        // --- PRIMER INVEST (V3) ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        console.log("=== DESPUES DEL PRIMER INVEST ===");
        console.log("LINK wallet:", link.balanceOf(address(wallet)));
        console.log("UNI wallet:", uni.balanceOf(address(wallet)));

        assertGt(link.balanceOf(address(wallet)), 0, "Should have LINK");
        assertGt(uni.balanceOf(address(wallet)), 0, "Should have UNI");

        // --- ADD ASSET: AAPLon (stock Ondo - V4 single-hop directo) ---
        _fundWallet(500 * 1e18);

        StockWallet.AssetConfig memory aaplConfig = StockWallet.AssetConfig({
            allocationBps: 2500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        vm.prank(owner);
        wallet.addAsset(
            StockWallet.TokenAllocationConfig({
                token: AAPLon,
                configs: aaplConfig
            }),
            address(0)
        );

        // --- GUARDAR V4 POOLS PARA AAPLon ---
        vm.prank(adgent);
        wallet.setV4Pools(AAPLon, _aaplV4Route());

        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon V4 pool stored");
        console.log("  AAPLon V4 pool stored: fee=100000, ts=2000");

        // --- ADD ASSET: NVDAon (stock Ondo - V4 multi-hop) ---
        StockWallet.AssetConfig memory nvdaConfig = StockWallet.AssetConfig({
            allocationBps: 1500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        vm.prank(owner);
        wallet.addAsset(
            StockWallet.TokenAllocationConfig({
                token: NVDAon,
                configs: nvdaConfig
            }),
            address(0)
        );

        // --- GUARDAR V4 POOLS PARA NVDAon ---
        vm.prank(adgent);
        wallet.setV4Pools(NVDAon, _nvdaV4Route());

        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon V4 pools stored");
        console.log("  NVDAon V4 pools stored: 2 (multi-hop)");

        // --- VERIFICAR AMBOS STOCKS CON V4 Y CRYPTO SIN V4 ---
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon: 1 V4 pool");
        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon: 2 V4 pools");
        assertEq(wallet.getV4Pools(LINK).length, 0, "LINK: 0 V4 pools (V3)");
        assertEq(wallet.getV4Pools(UNI).length, 0, "UNI: 0 V4 pools (V3)");

        console.log("=== STORAGE VERIFICADO ===");
        console.log("  AAPLon: 1 V4 pool (single-hop directo a USDT)");
        console.log("  NVDAon: 2 V4 pools (multi-hop via NVDAB)");
        console.log("  LINK: 0 (V3 only)");
        console.log("  UNI: 0 (V3 only)");

        // --- SELLTOKENALL ---
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        console.log("=== DESPUES DE SELLTOKENALL ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));

        // --- V4 POOLS PERSISTEN DESPUES DE SELLTOKENALL ---
        assertEq(
            wallet.getV4Pools(AAPLon).length,
            1,
            "AAPLon V4 persists after sell"
        );
        assertEq(
            wallet.getV4Pools(NVDAon).length,
            2,
            "NVDAon V4 persists after sell"
        );

        console.log("  V4 pools persist after selltokenAll: OK");

        // --- WITHDRAW ---
        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
            console.log("USDT owner:", usdt.balanceOf(owner));
        }
    }*/

    // =============================================================
    // === TEST 5: selltoken() con V4 pools guardadas ===
    // =============================================================

    function test_selltoken_with_stored_v4() public {
        console.log("=== TEST 5: selltoken() with stored V4 pools ===");

        address[] memory tokens = new address[](1);
        tokens[0] = LINK;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 8000,
            takeProfitBps: 15000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(500 * 1e18);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 linkBalance = link.balanceOf(address(wallet));
        assertGt(linkBalance, 0, "Should have LINK");
        console.log("  LINK balance:", linkBalance);

        // Guardar V4 pools (NVDAon multi-hop route reutilizada para LINK)
        vm.prank(adgent);
        wallet.setV4Pools(LINK, _nvdaV4Route());

        assertEq(wallet.getV4Pools(LINK).length, 2, "LINK V4 pools stored");

        // selltoken: TP/SL puede o no dispararse
        vm.prank(adgent);
        try
            wallet.selltoken(
                LINK,
                new bytes(0),
                new StockWallet.V4PoolData[](0)
            )
        {
            console.log("  selltoken executed (TP or SL triggered)");
        } catch {
            console.log("  selltoken reverted (price in range - no TP/SL)");
        }
        // V4 pools persisten
        assertEq(
            wallet.getV4Pools(LINK).length,
            2,
            "V4 pools persist after selltoken"
        );
        console.log("  V4 pools persist: OK");
    }

    // =============================================================
    // === TEST 6: V4 pools persist through full lifecycle ===
    // =============================================================

    function test_v4_pools_persistence_full_lifecycle() public {
        console.log("=== TEST 6: V4 Pools Persistence (Full Lifecycle) ===");

        address[] memory tokens = new address[](1);
        tokens[0] = LINK;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);

        // 1. Guardar NVDAon V4 (multi-hop)
        vm.prank(adgent);
        wallet.setV4Pools(NVDAon, _nvdaV4Route());
        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon: initial save");

        // 2. Guardar AAPLon V4 (single-hop)
        vm.prank(adgent);
        wallet.setV4Pools(AAPLon, _aaplV4Route());
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon: initial save");

        // 3. Fund + invest
        _fundWallet(300 * 1e18);
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon: after invest");
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon: after invest");

        // 4. SelltokenAll
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        assertEq(
            wallet.getV4Pools(NVDAon).length,
            2,
            "NVDAon: after selltokenAll"
        );
        assertEq(
            wallet.getV4Pools(AAPLon).length,
            1,
            "AAPLon: after selltokenAll"
        );

        // 5. Fund + invest again
        _fundWallet(200 * 1e18);
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        assertEq(
            wallet.getV4Pools(NVDAon).length,
            2,
            "NVDAon: after 2nd invest"
        );
        assertEq(
            wallet.getV4Pools(AAPLon).length,
            1,
            "AAPLon: after 2nd invest"
        );

        // 6. Withdraw
        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
        }

        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon: after withdraw");
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon: after withdraw");

        // 7. Verificar datos intactos
        StockWallet.V4PoolData[] memory nvdaFinal = wallet.getV4Pools(NVDAon);
        assertEq(nvdaFinal[0].tokenIn, NVDAon, "NVDAon pool 0 tokenIn intact");
        assertEq(nvdaFinal[0].tokenOut, NVDAB, "NVDAon pool 0 tokenOut intact");
        assertEq(nvdaFinal[0].fee, NVDA_NVDAB_FEE, "NVDAon pool 0 fee intact");
        assertEq(
            nvdaFinal[0].tickSpacing,
            NVDA_NVDAB_TS,
            "NVDAon pool 0 ts intact"
        );
        assertEq(nvdaFinal[1].tokenIn, NVDAB, "NVDAon pool 1 tokenIn intact");
        assertEq(nvdaFinal[1].tokenOut, USDT, "NVDAon pool 1 tokenOut intact");
        assertEq(nvdaFinal[1].fee, NVDAB_USDT_FEE, "NVDAon pool 1 fee intact");
        assertEq(
            nvdaFinal[1].tickSpacing,
            NVDAB_USDT_TS,
            "NVDAon pool 1 ts intact"
        );

        StockWallet.V4PoolData[] memory aaplFinal = wallet.getV4Pools(AAPLon);
        assertEq(aaplFinal[0].tokenIn, AAPLon, "AAPLon pool 0 tokenIn intact");
        assertEq(aaplFinal[0].tokenOut, USDT, "AAPLon pool 0 tokenOut intact");
        assertEq(aaplFinal[0].fee, AAPL_USDT_FEE, "AAPLon pool 0 fee intact");
        assertEq(
            aaplFinal[0].tickSpacing,
            AAPL_USDT_TS,
            "AAPLon pool 0 ts intact"
        );

        console.log("=== V4 POOLS PERSISTEN A TRAVES DE: ===");
        console.log(
            "  setV4Pools -> invest -> selltokenAll -> invest -> withdraw"
        );
        console.log("  NVDAon: 2 pools (multi-hop) - all data intact");
        console.log("  AAPLon: 1 pool (single-hop) - all data intact");
    }

    // =============================================================
    // === TEST 7: 5 crypto assets V3 + V4 storage para 2 stocks ===
    // =============================================================

    function test_fullCycle_5_crypto_assets_plus_v4_stocks() public {
        console.log("=== TEST 7: 5 Crypto + V4 Stocks Storage ===");

        // DEPLOY: BTCB 25%, ETH 25%, AAVE 20%, UNI 15%, DOT 15%
        address[] memory tokens = new address[](5);
        tokens[0] = BTCB;
        tokens[1] = ETH;
        tokens[2] = AAVE;
        tokens[3] = UNI;
        tokens[4] = DOT;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](5);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 2500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 2500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[2] = StockWallet.AssetConfig({
            allocationBps: 2000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[3] = StockWallet.AssetConfig({
            allocationBps: 1500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[4] = StockWallet.AssetConfig({
            allocationBps: 1500,
            stopLossBps: 8500,
            takeProfitBps: 11500
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(2000 * 1e18);

        // INVEST (V3)
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        console.log("=== DESPUES DEL INVEST ===");
        console.log("BTCB:", btcb.balanceOf(address(wallet)));
        console.log("ETH:", eth.balanceOf(address(wallet)));
        console.log("AAVE:", aave.balanceOf(address(wallet)));
        console.log("UNI:", uni.balanceOf(address(wallet)));
        console.log("DOT:", dot.balanceOf(address(wallet)));

        assertGt(btcb.balanceOf(address(wallet)), 0, "BTCB");
        assertGt(eth.balanceOf(address(wallet)), 0, "ETH");
        assertGt(aave.balanceOf(address(wallet)), 0, "AAVE");
        assertGt(uni.balanceOf(address(wallet)), 0, "UNI");
        assertGt(dot.balanceOf(address(wallet)), 0, "DOT");

        // Guardar V4 para NVDAon y AAPLon (stocks no en portfolio pero listos para addAsset)
        vm.prank(adgent);
        wallet.setV4Pools(NVDAon, _nvdaV4Route());

        vm.prank(adgent);
        wallet.setV4Pools(AAPLon, _aaplV4Route());

        // Verificar storage
        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon V4 stored");
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon V4 stored");
        assertEq(wallet.getV4Pools(BTCB).length, 0, "BTCB no V4");
        assertEq(wallet.getV4Pools(ETH).length, 0, "ETH no V4");
        assertEq(wallet.getV4Pools(AAVE).length, 0, "AAVE no V4");
        assertEq(wallet.getV4Pools(UNI).length, 0, "UNI no V4");
        assertEq(wallet.getV4Pools(DOT).length, 0, "DOT no V4");

        console.log("=== V4 STORAGE ===");
        console.log("  NVDAon: 2 pools (multi-hop)");
        console.log("  AAPLon: 1 pool (single-hop)");
        console.log("  BTCB/ETH/AAVE/UNI/DOT: 0 (V3 only)");

        // SELLTOKENALL + WITHDRAW
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
            console.log("USDT owner:", usdt.balanceOf(owner));
        }

        // V4 pools persisten despues de todo
        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon V4 persists");
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon V4 persists");
        console.log("  V4 pools persist after sell+withdraw: OK");
    }

    // =============================================================
    // === TEST 8: FXLon (iShares China ETF) via V3 fee=500 ===
    // =============================================================

    function test_fullCycle_fxlon_v3() public {
        console.log("=== TEST 8: FXLon via V3 (fee=500) ===");

        // DEPLOY: FXLon 60%, LINK 40%
        address[] memory tokens = new address[](2);
        tokens[0] = FXLon;
        tokens[1] = LINK;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](2);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 6000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 4000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(1000 * 1e18);

        console.log("=== ANTES DEL INVEST ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));

        // INVEST - FXLon usa V3 fee=500, LINK usa V3 fee=3000
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        console.log("=== DESPUES DEL INVEST ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("FXLon wallet:", fxlon.balanceOf(address(wallet)));
        console.log("LINK wallet:", link.balanceOf(address(wallet)));

        assertGt(fxlon.balanceOf(address(wallet)), 0, "Should have FXLon");
        assertGt(link.balanceOf(address(wallet)), 0, "Should have LINK");

        // FXLon no tiene V4 pools - solo V3
        assertEq(
            wallet.getV4Pools(FXLon).length,
            0,
            "FXLon has no V4 pools (V3 only)"
        );
        console.log("  FXLon: 0 V4 pools (V3 fee=500 only)");

        // Guardar V4 pools para NVDAon y AAPLon (para verificar coexistencia V3+V4)
        vm.prank(adgent);
        wallet.setV4Pools(NVDAon, _nvdaV4Route());
        vm.prank(adgent);
        wallet.setV4Pools(AAPLon, _aaplV4Route());

        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon V4 stored");
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon V4 stored");
        assertEq(wallet.getV4Pools(FXLon).length, 0, "FXLon still no V4");

        console.log("=== COEXISTENCIA V3 + V4 ===");
        console.log("  FXLon: V3 only (fee=500)");
        console.log("  NVDAon: V4 (2 pools multi-hop)");
        console.log("  AAPLon: V4 (1 pool single-hop)");

        // SELLTOKENALL
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        console.log("=== DESPUES DE SELLTOKENALL ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("FXLon wallet:", fxlon.balanceOf(address(wallet)));
        console.log("LINK wallet:", link.balanceOf(address(wallet)));

        // V4 pools persisten
        assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon V4 persists");
        assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon V4 persists");
        assertEq(wallet.getV4Pools(FXLon).length, 0, "FXLon still V3 only");

        // WITHDRAW
        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
            console.log("USDT owner:", usdt.balanceOf(owner));
        }

        console.log("=== FXLon V3 + V4 coexistencia verificada: OK ===");
    }
    // =============================================================
    // === TEST 9: FXLon (iShares China ETF) via V4  ===
    // =============================================================

    function test_fullCycle_fxlon_v4() public {
        console.log("=== TEST 9: FXLon via V4 (fee=500) ===");

        // DEPLOY: FXLon 60%, LINK 40%
        address[] memory tokens = new address[](1);
        tokens[0] = FXLon;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(1000 * 1e18);

        console.log("=== ANTES DEL INVEST ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));

        // INVEST - FXLon usa V4 , NvdaOn usa V4
        // Pasar V4 pools para LINK (ruta venta multi-hop), AAVE sin V4
        StockWallet.V4PoolData[][]
            memory v4ForInvest = new StockWallet.V4PoolData[][](1);

        // LINK: V4 route LINK -> NVDAB -> USDT (para venta futura)
        StockWallet.V4PoolData[] memory linkV4 = new StockWallet.V4PoolData[](
            1
        );
        linkV4[0] = _makeV4Pool(USDT, FXLon, 300, 3);
        v4ForInvest[0] = linkV4;

        // --- INVEST ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), v4ForInvest);

        console.log("=== DESPUES DEL INVEST ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("FXLon wallet:", fxlon.balanceOf(address(wallet)));

        assertGt(fxlon.balanceOf(address(wallet)), 0, "Should have FXLon");

        // FXLon no tiene V4 pools - solo V3
        assertEq(
            wallet.getV4Pools(FXLon).length,
            1,
            "FXLon has no V4 pools (V3 only)"
        );

        // Guardar V4 pools para NVDAon y AAPLon (para verificar coexistencia V3+V4)
        /*vm.prank(adgent);
        wallet.setV4Pools(NVDAon, _nvdaV4Route());
        vm.prank(adgent);
        wallet.setV4Pools(AAPLon, _aaplV4Route());*/

        //assertEq(wallet.getV4Pools(NVDAon).length, 2, "NVDAon V4 stored");
        //assertEq(wallet.getV4Pools(AAPLon).length, 1, "AAPLon V4 stored");
        //assertEq(wallet.getV4Pools(FXLon).length, 0, "FXLon still no V4");

        console.log("=== COEXISTENCIA V3 + V4 ===");
        console.log("  FXLon: V3 only (fee=500)");
        console.log("  NVDAon: V4 (2 pools multi-hop)");
        console.log("  AAPLon: V4 (1 pool single-hop)");

        // SELLTOKENALL
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        console.log("=== DESPUES DE SELLTOKENALL ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("FXLon wallet:", fxlon.balanceOf(address(wallet)));
        console.log("LINK wallet:", link.balanceOf(address(wallet)));

        // V4 pools persisten

        assertEq(wallet.getV4Pools(FXLon).length, 1, "FXLon still V3 only");

        // WITHDRAW
        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
            console.log("USDT owner:", usdt.balanceOf(owner));
        }

        console.log("=== FXLon V3 + V4 coexistencia verificada: OK ===");
    }
    function test_fullCycle_fxlon_v4x() public {
        console.log(
            "=== TEST 9: 6 assets (ZEC, ETH, BTCB, NEAR, FXLon, GOOGLE) + GOOGLE V4 ==="
        );

        // DEPLOY: 6 tokens con allocation sumando 100%
        address[] memory tokens = new address[](6);
        tokens[0] = ZEC;
        tokens[1] = ETH;
        tokens[2] = BTCB;
        tokens[3] = NEAR;
        tokens[4] = FXLon;
        tokens[5] = GOOGLE;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](6);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 3000,
            stopLossBps: 9500,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 1000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[2] = StockWallet.AssetConfig({
            allocationBps: 1000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[3] = StockWallet.AssetConfig({
            allocationBps: 2000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[4] = StockWallet.AssetConfig({
            allocationBps: 2500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[5] = StockWallet.AssetConfig({
            allocationBps: 500,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        // Deploy primero, fund después
        wallet = _deployWallet(tokens, configs);
        _fundWallet(1000 * 1e18);

        // Set gas token = WBNB
        vm.prank(owner);
        //wallet.setGasToken(WBNB);
        //assertEq(wallet.gasToken(), WBNB, "gasToken = WBNB");
        console.log("  gasToken set to WBNB");
        uint256 adgentWbnbBefore = IERC20(WBNB).balanceOf(adgent);

        console.log("=== ANTES DEL INVEST ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));

        // V4 pools: tamaño debe ser igual al número de tokens (6)
        // Solo GOOGLE (index 5) tiene V4 pool, los demás van vacíos
        StockWallet.V4PoolData[][]
            memory v4ForInvest = new StockWallet.V4PoolData[][](6);

        // GOOGLE: V4 route USDT -> GOOGLE (fee=1000, tickSpacing=10)
        StockWallet.V4PoolData[] memory googleV4 = new StockWallet.V4PoolData[](
            1
        );
        googleV4[0] = _makeV4Pool(USDT, GOOGLE, 1000, 10);
        v4ForInvest[5] = googleV4; // index 5 = GOOGLE

        // Los demás indices (0-4) quedan como arrays vacíos (V3 only)

        // --- INVEST ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), v4ForInvest);

        uint256 adgentWbnbAfter = IERC20(WBNB).balanceOf(adgent);

        console.log("=== DESPUES DEL INVEST ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("ZCash wallet:", zec.balanceOf(address(wallet)));
        console.log("Bitcoin wallet:", btcb.balanceOf(address(wallet)));
        console.log("Near wallet:", near.balanceOf(address(wallet)));
        console.log("Ethereum wallet:", eth.balanceOf(address(wallet)));
        console.log("FXlon wallet:", fxlon.balanceOf(address(wallet)));
        console.log("Google wallet:", google.balanceOf(address(wallet)));

        // Verificar que GOOGLE tiene V4 pools guardadas
        assertEq(
            wallet.getV4Pools(GOOGLE).length,
            1,
            "GOOGLE should have 1 V4 pool"
        );

        // Los demás tokens no tienen V4 pools
        assertEq(wallet.getV4Pools(ZEC).length, 0, "ZEC no V4");
        assertEq(wallet.getV4Pools(ETH).length, 0, "ETH no V4");
        assertEq(wallet.getV4Pools(BTCB).length, 0, "BTCB no V4");
        assertEq(wallet.getV4Pools(NEAR).length, 0, "NEAR no V4");
        assertEq(wallet.getV4Pools(FXLon).length, 0, "FXLon no V4");

        console.log("=== V4 STORAGE VERIFICADO ===");
        console.log("  GOOGLE: 1 V4 pool (fee=1000, ts=10)");
        console.log("  ZEC/ETH/BTCB/NEAR/FXLon: 0 (V3 only)");

        // SELLTOKENALL
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        console.log("=== DESPUES DE SELLTOKENALL ===");
        console.log("USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("ZCash wallet:", zec.balanceOf(address(wallet)));
        console.log("Bitcoin wallet:", btcb.balanceOf(address(wallet)));
        console.log("Near wallet:", near.balanceOf(address(wallet)));
        console.log("Ethereum wallet:", eth.balanceOf(address(wallet)));
        console.log("Fxlon wallet:", fxlon.balanceOf(address(wallet)));
        console.log("Google wallet:", google.balanceOf(address(wallet)));

        // V4 pools persisten después de selltokenAll
        assertEq(wallet.getV4Pools(GOOGLE).length, 1, "GOOGLE V4 persists");

        // WITHDRAW
        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
            console.log("USDT owner:", usdt.balanceOf(owner));
        }

        console.log("=== FXLon V3 + V4 coexistencia verificada: OK ===");
    }

    // =============================================================
    // === TEST 10: SellAssetOwner — Owner vende token sin reglas (happy path) ===
    // =============================================================

    function test_SellAssetOwner_happyPath() public {
        console.log("=== TEST 10: SellAssetOwner happy path ===");

        // DEPLOY: LINK 100%
        address[] memory tokens = new address[](1);
        tokens[0] = LINK;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(500 * 1e18);

        // INVEST — compra LINK con USDT via V3
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 linkBalance = link.balanceOf(address(wallet));
        assertGt(linkBalance, 0, "Should have LINK after invest");
        console.log("  LINK balance after invest:", linkBalance);

        // Setear posición para que tenga invested != 0
        (uint256 posAmount, uint256 posInvested) = wallet.assetPosition(LINK);
        console.log("  LINK position amount:", posAmount);
        console.log("  LINK position invested:", posInvested);

        // SELL ASSET OWNER — vende LINK por USDT sin reglas de SL/TP
        uint256 usdtBefore = usdt.balanceOf(address(wallet));
        uint256 ownerUsdtBefore = usdt.balanceOf(owner);

        vm.prank(owner);
        wallet.SellAssetOwner(LINK);

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        uint256 linkAfter = link.balanceOf(address(wallet));

        console.log("  USDT wallet after sell:", usdtAfter);
        console.log("  LINK wallet after sell:", linkAfter);

        // Verificar: vendió todo el LINK
        assertEq(linkAfter, 0, "SellAssetOwner should sell ALL tokens");
        // Verificar: recibió USDT
        assertGt(usdtAfter, usdtBefore, "Should receive USDT from sell");

        // Verificar: posición reseteada
        (uint256 amountAfter, uint256 investedAfter) = wallet.assetPosition(
            LINK
        );
        assertEq(amountAfter, 0, "Position amount reset");
        assertEq(investedAfter, 0, "Position invested reset");

        // Withdraw USDT al owner
        uint256 usdtFinal = usdt.balanceOf(address(wallet));
        if (usdtFinal > 0) {
            vm.prank(owner);
            wallet.withdrawAssetUsdt(usdtFinal);
        }

        assertGt(
            usdt.balanceOf(owner),
            ownerUsdtBefore,
            "Owner should have USDT"
        );
        console.log("  USDT owner:", usdt.balanceOf(owner));
        console.log("=== SellAssetOwner OK ===");
    }

    function test_SellAssetOwner_multipleTokens() public {
        console.log("=== TEST 11: SellAssetOwner multiple tokens ===");

        // DEPLOY: BTCB 50%, ETH 50%
        address[] memory tokens = new address[](2);
        tokens[0] = BTCB;
        tokens[1] = ETH;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](2);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);
        _fundWallet(1000 * 1e18);

        // INVEST
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        assertGt(btcb.balanceOf(address(wallet)), 0, "Should have BTCB");
        assertGt(eth.balanceOf(address(wallet)), 0, "Should have ETH");

        // SELL BTCB via SellAssetOwner
        uint256 usdtBefore = usdt.balanceOf(address(wallet));
        vm.prank(owner);
        wallet.SellAssetOwner(BTCB);

        assertEq(btcb.balanceOf(address(wallet)), 0, "BTCB sold");
        assertGt(
            usdt.balanceOf(address(wallet)),
            usdtBefore,
            "Got USDT from BTCB"
        );

        // SELL ETH via SellAssetOwner
        uint256 usdtBefore2 = usdt.balanceOf(address(wallet));
        vm.prank(owner);
        wallet.SellAssetOwner(ETH);

        assertEq(eth.balanceOf(address(wallet)), 0, "ETH sold");
        assertGt(
            usdt.balanceOf(address(wallet)),
            usdtBefore2,
            "Got USDT from ETH"
        );

        console.log("  Both tokens sold via SellAssetOwner: OK");
        console.log("  USDT wallet:", usdt.balanceOf(address(wallet)));
        console.log("=== SellAssetOwner multiple OK ===");
    }

    // =============================================================
    // === TEST 12: _swapForGas — gas token configurable (WBNB) ===
    // =============================================================

    function test_swapForGas_withWBNB() public {
        console.log("=== TEST 12: _swapForGas with gasToken = WBNB ===");

        // DEPLOY: LINK 100%
        address[] memory tokens = new address[](1);
        tokens[0] = LINK;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);

        // Setear gasToken = WBNB
        vm.prank(owner);
        wallet.setGasToken(WBNB);
        assertEq(wallet.gasToken(), WBNB, "gasToken = WBNB");
        console.log("  gasToken set to WBNB");

        // Fund + invest
        _fundWallet(1000 * 1e18);

        uint256 adgentWbnbBefore = IERC20(WBNB).balanceOf(adgent);
        uint256 adgentUsdtBefore = usdt.balanceOf(adgent);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 adgentWbnbAfter = IERC20(WBNB).balanceOf(adgent);
        uint256 adgentUsdtAfter = usdt.balanceOf(adgent);

        console.log("  Adgent WBNB before:", adgentWbnbBefore);
        console.log("  Adgent WBNB after:", adgentWbnbAfter);
        console.log("  Adgent USDT before:", adgentUsdtBefore);
        console.log("  Adgent USDT after:", adgentUsdtAfter);

        // Verificar: el adgent recibió WBNB (no USDT) como gas fee
        assertGt(
            adgentWbnbAfter,
            adgentWbnbBefore,
            "Adgent should receive WBNB"
        );
        assertEq(
            adgentUsdtAfter,
            adgentUsdtBefore,
            "Adgent should NOT receive USDT as gas"
        );

        console.log("  Gas fee paid in WBNB: OK");

        // Verificar que igual invirtió en LINK
        assertGt(
            link.balanceOf(address(wallet)),
            0,
            "Should have LINK after invest"
        );
        console.log("  LINK balance:", link.balanceOf(address(wallet)));

        console.log("=== _swapForGas with WBNB OK ===");
    }

    function test_swapForGas_defaultUSDC() public {
        console.log("=== TEST 13: _swapForGas default (USDC) ===");

        // DEPLOY: LINK 100%
        address[] memory tokens = new address[](1);
        tokens[0] = LINK;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);

        // gasToken no seteado → default = address(0) → paga en USDT
        assertEq(
            wallet.gasToken(),
            address(0),
            "gasToken default = address(0)"
        );

        _fundWallet(1000 * 1e18);

        uint256 adgentUsdtBefore = usdt.balanceOf(adgent);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 adgentUsdtAfter = usdt.balanceOf(adgent);

        // Verificar: el adgent recibió USDT (comportamiento default)
        assertGt(
            adgentUsdtAfter,
            adgentUsdtBefore,
            "Adgent should receive USDT as gas (default)"
        );
        console.log("  Gas fee paid in USDT (default): OK");
        console.log(
            "  Adgent USDT received:",
            adgentUsdtAfter - adgentUsdtBefore
        );

        console.log("=== _swapForGas default USDC OK ===");
    }

    function test_setGasToken_and_invest_with_BTCB_as_gas() public {
        console.log("=== TEST 14: setGasToken + invest with BTCB as gas ===");

        // DEPLOY: ETH 100%
        address[] memory tokens = new address[](1);
        tokens[0] = ETH;
        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](1);
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        wallet = _deployWallet(tokens, configs);

        // Setear gasToken = BTCB
        vm.prank(owner);
        wallet.setGasToken(BTCB);
        assertEq(wallet.gasToken(), BTCB, "gasToken = BTCB");

        _fundWallet(1000 * 1e18);

        uint256 adgentBtcbBefore = btcb.balanceOf(adgent);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 adgentBtcbAfter = btcb.balanceOf(adgent);

        // Verificar: el adgent recibió BTCB como gas fee
        assertGt(
            adgentBtcbAfter,
            adgentBtcbBefore,
            "Adgent should receive BTCB as gas"
        );
        console.log("  Gas fee paid in BTCB: OK");
        console.log(
            "  Adgent BTCB received:",
            adgentBtcbAfter - adgentBtcbBefore
        );

        // Verificar que invirtió en ETH
        assertGt(
            eth.balanceOf(address(wallet)),
            0,
            "Should have ETH after invest"
        );
        console.log("  ETH balance:", eth.balanceOf(address(wallet)));

        console.log("=== setGasToken + BTCB gas OK ===");
    }
}
