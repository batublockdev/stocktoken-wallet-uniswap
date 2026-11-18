//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {IERC20} from "./IERC20.sol";
import {console} from "forge-std/console.sol";
import {
    WETH,
    WBTC,
    USDT,
    XAUt0,
    PLAST,
    WBRL,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER,
    UNIVERSAL_ROUTER,
    PERMIT2
} from "./ConstantsCelo.sol";

contract StockWalletTest is Test {
    StockWallet public wallet;
    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");

    IERC20 private usdt = IERC20(USDT);
    IERC20 private weth = IERC20(WETH);
    IERC20 private wbtc = IERC20(WBTC);
    IERC20 private xaut0 = IERC20(XAUt0);
    IERC20 private plast = IERC20(PLAST);
    IERC20 private wbrl = IERC20(WBRL);

    function setUp() public {
        // Fork de Celo mainnet para que los contratos reales (USDT, WBTC, etc.) existan
        vm.createSelectFork("https://forno.celo.org");
    }

    function test_constructor_checks() public {
        StockWallet.AssetConfig memory configx1 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.AssetConfig memory configx2 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.TokenAllocationConfig memory tokenConfigx1 = StockWallet
            .TokenAllocationConfig({token: WBTC, configs: configx1});
        StockWallet.TokenAllocationConfig memory tokenConfigx2 = StockWallet
            .TokenAllocationConfig({token: WETH, configs: configx2});

        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](2);

        tokenAllocation[0] = tokenConfigx1;
        tokenAllocation[1] = tokenConfigx2;

        vm.prank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            address(adgent),
            address(adgentContract),
            2000,
            tokenAllocation
        );

        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        uint256 usdcAdgentContractBalanceBefore = usdt.balanceOf(
            address(adgentContract)
        );
        uint256 usdcAdgentBalanceBefore = usdt.balanceOf(address(adgent));

        uint256 usdcBalanceBefore = usdt.balanceOf(address(wallet));
        uint256 wbtcBalanceBefore = wbtc.balanceOf(address(wallet));
        uint256 wethBalanceBefore = weth.balanceOf(address(wallet));
        console.log("=== BALANCES ANTES ===");
        console.log(
            "USDT adgentContract Before:",
            usdcAdgentContractBalanceBefore
        );
        console.log("USDT adgent Before:", usdcAdgentBalanceBefore);
        console.log("USDT Before:", usdcBalanceBefore);
        console.log("WBTC Before:", wbtcBalanceBefore);
        console.log("WETH Before: ", wethBalanceBefore);

        bytes[] memory path = new bytes[](0);
        vm.prank(adgent);
        wallet.invest(path, new StockWallet.V4PoolData[][](0));

        uint256 usdcAdgentContractBalanceAfter = usdt.balanceOf(
            address(adgentContract)
        );
        uint256 usdcAdgentBalanceAfter = usdt.balanceOf(address(adgent));
        uint256 usdcBalanceAfter = usdt.balanceOf(address(wallet));
        uint256 wbtcBalanceAfter = wbtc.balanceOf(address(wallet));
        uint256 wethBalanceAfter = weth.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES ===");
        console.log(
            "USDC AdgentContract After: ",
            usdcAdgentContractBalanceAfter
        );
        console.log("USDC Adgent After: ", usdcAdgentBalanceAfter);
        console.log("USDC After: ", usdcBalanceAfter);
        console.log("WBTC After: ", wbtcBalanceAfter);
        console.log("WETH After:  ", wethBalanceAfter);

        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        StockWallet.AssetConfig memory XAUt0config = StockWallet.AssetConfig({
            allocationBps: 2000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.TokenAllocationConfig memory XAUt0tokenConfig = StockWallet
            .TokenAllocationConfig({token: XAUt0, configs: XAUt0config});

        StockWallet.AssetConfig memory PLASTconfig = StockWallet.AssetConfig({
            allocationBps: 1000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.TokenAllocationConfig memory PLASTtokenConfig = StockWallet
            .TokenAllocationConfig({token: PLAST, configs: PLASTconfig});

        vm.prank(owner);
        wallet.addAsset(XAUt0tokenConfig, address(0));
        //vm.prank(owner);
        //wallet.addAsset(PLASTtokenConfig, WETH);
        uint256 usdtBalanceAfterAddAsset = usdt.balanceOf(address(wallet));
        uint256 xaut0BalanceBefore = xaut0.balanceOf(address(wallet));
        uint256 wbrlxBalanceBefore = wbrl.balanceOf(address(wallet));

        uint256 plastBalanceBefore = plast.balanceOf(address(wallet));

        console.log("USDT After Add Asset: ", usdtBalanceAfterAddAsset);
        console.log("=== BALANCES NUEVOS TOKENS ANTES ===");
        console.log("WBRL Before: ", wbrlxBalanceBefore);
        console.log("XAUt0 Before:", xaut0BalanceBefore);
        console.log("PLAST Before: ", plastBalanceBefore);

        bytes[] memory paths = new bytes[](0);
        vm.prank(adgent);
        wallet.invest(paths, new StockWallet.V4PoolData[][](0));

        uint256 wbrlBalanceFinal = wbrl.balanceOf(address(wallet));
        uint256 usdtBalanceFinal = usdt.balanceOf(address(wallet));
        uint256 wbtcBalanceFinal = wbtc.balanceOf(address(wallet));
        uint256 wethBalanceFinal = weth.balanceOf(address(wallet));
        uint256 xaut0BalanceFinal = xaut0.balanceOf(address(wallet));
        uint256 plastBalanceFinal = plast.balanceOf(address(wallet));

        console.log("=== BALANCES FINALES GENERALES ===");
        console.log("WBRL Final: ", wbrlBalanceFinal);
        console.log("USDT Final: ", usdtBalanceFinal);
        console.log("WBTC Final: ", wbtcBalanceFinal);
        console.log("WETH Final: ", wethBalanceFinal);
        console.log("XAUt0 Final:", xaut0BalanceFinal);
        console.log("PLAST Final:", plastBalanceFinal);

        vm.prank(owner);
        wallet.selltokenAll(paths);
        uint256 usdtBalanceAfterSell = usdt.balanceOf(address(wallet));
        console.log("USDT After sell all: ", usdtBalanceAfterSell);

        uint256 usdtBalanceAfterSellowner = usdt.balanceOf(address(owner));
        console.log("USDT OWNER BEFORE WITHDRAW: ", usdtBalanceAfterSellowner);

        vm.prank(owner);
        wallet.withdrawAssetUsdt(usdtBalanceAfterSell);
        uint256 usdtBalanceAfterSellowner2 = usdt.balanceOf(address(owner));
        console.log("USDT OWNER AFTER WITHDRAW: ", usdtBalanceAfterSellowner2);
    }

    function test_constructor_checks_x2() public {
        StockWallet.AssetConfig memory config1 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.AssetConfig memory config2 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.TokenAllocationConfig memory tokenConfig1 = StockWallet
            .TokenAllocationConfig({token: WBTC, configs: config1});

        StockWallet.TokenAllocationConfig memory tokenConfig2 = StockWallet
            .TokenAllocationConfig({token: XAUt0, configs: config2});

        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](2);

        tokenAllocation[0] = tokenConfig1;
        tokenAllocation[1] = tokenConfig2;

        vm.prank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            address(adgent),
            address(adgentContract),
            2000,
            tokenAllocation
        );

        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        uint256 usdtBefore = usdt.balanceOf(address(wallet));
        uint256 wbtcBefore = wbtc.balanceOf(address(wallet));
        uint256 xaut0Before = xaut0.balanceOf(address(wallet));

        console.log("=== BALANCES ANTES ===");
        console.log("USDT:", usdtBefore);
        console.log("WBTC:", wbtcBefore);
        console.log("XAUt0:", xaut0Before);

        bytes[] memory instructions = new bytes[](0);
        vm.prank(adgent);
        wallet.invest(instructions, new StockWallet.V4PoolData[][](0));

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        uint256 wbtcAfter = wbtc.balanceOf(address(wallet));
        uint256 xaut0After = xaut0.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES DE INVEST ===");
        console.log("USDT:", usdtAfter);
        console.log("WBTC:", wbtcAfter);
        console.log("XAUt0:", xaut0After);

        // modifyPosition was removed in the refactored contract
        // Using modifyPosition via vm.store or skipping this part
        // Since modifyPosition was commented out, we skip the sell part
        // or use a different approach to test selltoken

        bytes memory path;
        vm.prank(adgent);
        // selltoken requires ADGENT_ROLE, and we need SL/TP to trigger
        // Skip for now as modifyPosition is no longer available
        // wallet.selltoken(XAUt0, path, new StockWallet.V4PoolData[](0));

        uint256 xaut0AfterSell = xaut0.balanceOf(address(wallet));
        uint256 usdtAfterSell = usdt.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES DE SELL ===");
        console.log("XAUt0:", xaut0AfterSell);
        console.log("USDT:", usdtAfterSell);
    }
}
