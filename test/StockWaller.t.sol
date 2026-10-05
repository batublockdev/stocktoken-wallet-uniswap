//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
//import {DeployContract} from "../script/aurDeploy.s.sol";
import {IERC20} from "./IERC20.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {
    DAI,
    WETH,
    WBTC,
    USDC,
    AAVE,
    LINK,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_SWAP_ROUTER_03
} from "./Constants.sol";
contract StockWalletTest is Test {
    StockWallet public wallet;
    address public member1 = makeAddr("member1");
    address public member2 = makeAddr("member2");

    IERC20 private usdc = IERC20(USDC);
    IERC20 private aave = IERC20(AAVE);
    IERC20 private link = IERC20(LINK);
    IERC20 private dai = IERC20(DAI);
    IERC20 private wbtc = IERC20(WBTC);
    uint24 private constant POOL_FEE = 3000;

    function setUp() public {}
    function test_constructor_checks() public {
        //Test address 0
        StockWallet.AssetConfig memory configx1 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000,
            riskEnabled: true,
            riskPaused: false,
            ownBot: false
        });
        StockWallet.AssetConfig memory configx2 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000,
            riskEnabled: true,
            riskPaused: false,
            ownBot: false
        });

        StockWallet.tokenAllocationConfig memory tokenConfigx1 = StockWallet
            .tokenAllocationConfig({token: WBTC, configs: configx1});
        StockWallet.tokenAllocationConfig memory tokenConfigx2 = StockWallet
            .tokenAllocationConfig({token: DAI, configs: configx2});
        // 2. Crear un array en memory con tamaño explícito (1 en este caso)
        StockWallet.tokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.tokenAllocationConfig[](2);

        // 3. Asignar por índice
        tokenAllocation[0] = tokenConfigx1;
        tokenAllocation[1] = tokenConfigx2;
        vm.prank(member2);
        wallet = new StockWallet(
            bytes32(0),
            member1,
            UNISWAP_V3_SWAP_ROUTER_03,
            USDC,
            UNISWAP_V3_FACTORY,
            tokenAllocation
        );

        deal(USDC, address(this), 10 * 1e6);
        usdc.transfer(address(wallet), 10 * 1e6);

        // --- INICIO ---
        uint256 usdcBalanceBefore = usdc.balanceOf(address(wallet));
        uint256 wbtcBalanceBefore = wbtc.balanceOf(address(wallet));
        uint256 daiBalanceBefore = dai.balanceOf(address(wallet));
        console.log("=== BALANCES ANTES ===");
        console.log("USDC Before:", usdcBalanceBefore);
        console.log("WBTC Before:", wbtcBalanceBefore);
        console.log("DAI Before: ", daiBalanceBefore);
        bytes[] memory x;
        wallet.invest(x);
        // Balances después
        uint256 usdcBalanceAfter = usdc.balanceOf(address(wallet));
        uint256 wbtcBalanceAfter = wbtc.balanceOf(address(wallet));
        uint256 daiBalanceAfter = dai.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES ===");
        console.log("USDC After: ", usdcBalanceAfter);
        console.log("WBTC After: ", wbtcBalanceAfter);
        console.log("DAI After:  ", daiBalanceAfter);

        deal(USDC, address(this), 100 * 1e6);
        usdc.transfer(address(wallet), 100 * 1e6);
        wallet.addAsset(AAVE, 2000, address(0));
        wallet.addAsset(LINK, 1000, DAI);

        // Balances de los nuevos tokens ANTES de ejecutar el segundo invest
        uint256 aaveBalanceBefore = aave.balanceOf(address(wallet));
        uint256 linkBalanceBefore = link.balanceOf(address(wallet));

        console.log("=== BALANCES NUEVOS TOKENS ANTES ===");
        console.log("AAVE Before:", aaveBalanceBefore);
        console.log("LINK Before: ", linkBalanceBefore);

        // Ejecutamos la inversión con los nuevos assets/rutas
        wallet.invest(x);

        // Balances DESPUÉS
        uint256 usdcBalanceFinal = usdc.balanceOf(address(wallet));
        uint256 wbtcBalanceFinal = wbtc.balanceOf(address(wallet));
        uint256 daiBalanceFinal = dai.balanceOf(address(wallet));
        uint256 aaveBalanceFinal = aave.balanceOf(address(wallet));
        uint256 linkBalanceFinal = link.balanceOf(address(wallet));

        console.log("=== BALANCES FINALES GENERALES ===");
        console.log("USDC Final: ", usdcBalanceFinal);
        console.log("WBTC Final: ", wbtcBalanceFinal);
        console.log("DAI Final:  ", daiBalanceFinal);
        console.log("AAVE Final: ", aaveBalanceFinal);
        console.log("LINK Final:  ", linkBalanceFinal);

        bytes memory pathWbtc = abi.encodePacked(USDC, uint24(500), WBTC);

        bytes memory pathLink = abi.encodePacked(
            USDC,
            uint24(500),
            WETH,
            uint24(3000),
            LINK
        );

        bytes memory pathAave = abi.encodePacked(
            USDC,
            uint24(500),
            WETH,
            uint24(3000),
            AAVE
        );
        bytes[] memory path = new bytes[](3);
        path[0] = pathWbtc;
        path[1] = pathLink;
        path[2] = pathAave;

        deal(USDC, address(this), 100 * 1e6);
        usdc.transfer(address(wallet), 100 * 1e6);

        wallet.invest(path);
        uint256 usdcBalanceFinal2 = usdc.balanceOf(address(wallet));
        uint256 wbtcBalanceFinal2 = wbtc.balanceOf(address(wallet));
        uint256 daiBalanceFinal2 = dai.balanceOf(address(wallet));
        uint256 aaveBalanceFinal2 = aave.balanceOf(address(wallet));
        uint256 linkBalanceFinal2 = link.balanceOf(address(wallet));

        console.log("=== BALANCES FINALES GENERALES  x2===");
        console.log("USDC Final: ", usdcBalanceFinal2);
        console.log("WBTC Final: ", wbtcBalanceFinal2);
        console.log("DAI Final:  ", daiBalanceFinal2);
        console.log("AAVE Final: ", aaveBalanceFinal2);
        console.log("LINK Final:  ", linkBalanceFinal2);
        //console.log(" PRICE:  ", wallet.getTwapPrice(WBTC, 1e18));

        /*vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_address.selector,
                address(0),
                address(0)
            )
        );
        aurContract = new aur(address(0), 10 ether, 3);

        //Test amount 0
        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract = new aur(address(usdc), 0, 3);

        //Test peridos 0
        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract = new aur(address(usdc), 20, 0);

        //Test both 0
        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract = new aur(address(usdc), 0, 0);*/
    }
    function test_constructor_checks_x2() public {
        //Test address 0
        StockWallet.AssetConfig memory configx1 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000,
            riskEnabled: true,
            riskPaused: false,
            ownBot: false
        });
        StockWallet.AssetConfig memory configx2 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000,
            riskEnabled: true,
            riskPaused: false,
            ownBot: false
        });

        StockWallet.tokenAllocationConfig memory tokenConfigx1 = StockWallet
            .tokenAllocationConfig({token: WBTC, configs: configx1});
        StockWallet.tokenAllocationConfig memory tokenConfigx2 = StockWallet
            .tokenAllocationConfig({token: DAI, configs: configx2});
        // 2. Crear un array en memory con tamaño explícito (1 en este caso)
        StockWallet.tokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.tokenAllocationConfig[](2);

        // 3. Asignar por índice
        tokenAllocation[0] = tokenConfigx1;
        tokenAllocation[1] = tokenConfigx2;
        vm.prank(member2);
        wallet = new StockWallet(
            bytes32(0),
            member1,
            UNISWAP_V3_SWAP_ROUTER_03,
            USDC,
            UNISWAP_V3_FACTORY,
            tokenAllocation
        );

        deal(USDC, address(this), 10 * 1e6);
        usdc.transfer(address(wallet), 10 * 1e6);

        // --- INICIO ---
        uint256 usdcBalanceBefore = usdc.balanceOf(address(wallet));
        uint256 wbtcBalanceBefore = wbtc.balanceOf(address(wallet));
        uint256 daiBalanceBefore = dai.balanceOf(address(wallet));
        console.log("=== BALANCES ANTES ===");
        console.log("USDC Before:", usdcBalanceBefore);
        console.log("WBTC Before:", wbtcBalanceBefore);
        console.log("DAI Before: ", daiBalanceBefore);
        bytes[] memory x;
        wallet.invest(x);
        // Balances después
        uint256 usdcBalanceAfter = usdc.balanceOf(address(wallet));
        uint256 wbtcBalanceAfter = wbtc.balanceOf(address(wallet));
        uint256 daiBalanceAfter = dai.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES ===");
        console.log("USDC After: ", usdcBalanceAfter);
        console.log("WBTC After: ", wbtcBalanceAfter);
        console.log("DAI After:  ", daiBalanceAfter);
        console.log(" PRICE DAI:  ", wallet.getTwapPrice(DAI, USDC, 1e18));

        wallet.modifyPosition(8e6, DAI);
        bytes memory x2;
        wallet.selltoken(DAI, x2);

        uint256 daiBalanceAfter2 = dai.balanceOf(address(wallet));
        uint256 usdcBalanceAfter2 = usdc.balanceOf(address(wallet));

        console.log("DAI After2:  ", daiBalanceAfter2);
        console.log("USDC After2: ", usdcBalanceAfter2);
    }
}
