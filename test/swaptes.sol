// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

interface IERC20Universal {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPermit2Universal {
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

contract SwapUniversalRouterTest is Test {
    address constant USDC = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;

    address constant WBTC = 0x8aC2901Dd8A1F17a1A4768A6bA4C3751e3995B2D;

    address constant UNIVERSAL_ROUTER =
        0x643770E279d5D0733F21d6DC03A8efbABf3255B4;

    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint24 constant FEE = 3000;
    uint256 constant AMOUNT_IN = 4_900_000; // 4.9 USDC

    function setUp() public {
        // Fork de Celo mainnet
        vm.createSelectFork("https://forno.celo.org");
    }

    function testSwapUniversalRouter() public {
        // Confirmar que estamos en el fork de Celo.
        assertEq(block.chainid, 42220, "No estas en Celo");

        // Verificar que los contratos existen en el fork.
        assertGt(USDC.code.length, 0, "USDC sin codigo");
        assertGt(WBTC.code.length, 0, "WBTC sin codigo");
        assertGt(
            UNIVERSAL_ROUTER.code.length,
            0,
            "Universal Router sin codigo"
        );
        assertGt(PERMIT2.code.length, 0, "Permit2 sin codigo");

        IERC20Universal usdc = IERC20Universal(USDC);
        IERC20Universal wbtc = IERC20Universal(WBTC);
        IPermit2Universal permit2 = IPermit2Universal(PERMIT2);
        IUniversalRouter router = IUniversalRouter(UNIVERSAL_ROUTER);

        // Fondos simulados para este test en el fork.
        deal(USDC, address(this), AMOUNT_IN);

        uint256 wbtcAntes = wbtc.balanceOf(address(this));

        // 1. Autorizar a Permit2 para transferir nuestros USDC.
        require(
            usdc.approve(PERMIT2, type(uint256).max),
            "Approve USDC a Permit2 fallo"
        );

        // 2. Autorizar al Universal Router dentro de Permit2.
        permit2.approve(
            USDC,
            UNIVERSAL_ROUTER,
            uint160(AMOUNT_IN),
            uint48(block.timestamp + 1 days)
        );

        // 3. Construir la ruta V3: USDC -> WBTC.
        bytes memory path = abi.encodePacked(USDC, FEE, WBTC);

        // 4. Comando V3_SWAP_EXACT_IN = 0x00.
        bytes memory commands = hex"00";

        // Estructura de entrada V3_SWAP_EXACT_IN.
        bytes memory swapInput = abi.encode(
            address(this), // recipient
            AMOUNT_IN, // amountIn
            uint256(1), // amountOutMinimum: solo para la prueba
            path, // ruta V3
            true // payerIsUser
        );

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = swapInput;

        // 5. Ejecutar el swap.
        router.execute(commands, inputs, block.timestamp + 60);

        // 6. Verificar el resultado.
        uint256 wbtcDespues = wbtc.balanceOf(address(this));

        assertGt(wbtcDespues, wbtcAntes, "El swap no entrego WBTC");

        emit log_named_uint("USDC gastados", AMOUNT_IN);

        emit log_named_uint("WBTC recibidos", wbtcDespues - wbtcAntes);
    }
}
