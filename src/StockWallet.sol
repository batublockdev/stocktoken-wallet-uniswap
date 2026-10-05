// SPDX-License-Identifier: MIT

/**
=========================================================
  SENTINEL - Smart Contract Wallet (Single User)
  Especificación de Funciones
=========================================================

ROLES:
  - Owner:    Control total (deposit implícito via transfer, withdraw, trading, config, recovery)
  - Bot:      Solo trading (buy/sell)
  - Guardian: Solo recovery (initiate + execute)

=========================================================
  💰 GESTIÓN DE FONDOS
=========================================================

1. withdrawUSDC(uint256 amount)
   Input:  amount (cantidad de USDC a retirar, en decimals 6)
   Acceso: Owner
   Descripción: Retira USDC del contrato a la wallet del owner.
                Requiere que el contrato tenga saldo suficiente.
                Requiere !paused.

2. withdrawToken(address token, uint256 amount)
   Input:  token (dirección del token ERC-20)
           amount (cantidad a retirar)
   Acceso: Owner
   Descripción: Retira cualquier token ERC-20 del contrato al owner.
                Útil para retirar stocks que no se quieren vender por Uniswap.
                Requiere !paused.

=========================================================
  📈 TRADING
=========================================================

3. buyMultiple(address[] tokens, uint256[] amounts)
   Input:  tokens (array de direcciones de tokens a comprar)
           amounts (array de montos en USDC para cada token)
   Acceso: Owner, Bot
   Descripción: Compra múltiples stocks en una sola transacción.
                Aprueba al router de Uniswap automáticamente.
                Ejecuta swap exactInputSingle por cada token.
                Registra cada posición (token, amount, buyPrice, timestamp).
                Requiere tokens.length == amounts.length.
                Requiere !paused.

4. sellMultiple(address[] tokens, uint256[] amounts)
   Input:  tokens (array de direcciones de tokens a vender)
           amounts (array de cantidades de cada token a vender)
   Acceso: Owner, Bot
   Descripción: Vende múltiples stocks en una sola transacción.
                Swap de token → USDC via Uniswap.
                Actualiza posiciones y calcula P&L realizado.
                Requiere tokens.length == amounts.length.
                Requiere !paused.

5. sellAll()
   Input:  (sin parámetros)
   Acceso: Owner, Bot
   Descripción: Liquida todas las posiciones abiertas.
                Vende todos los tokens del contrato por USDC.
                Calcula P&L total realizado.
                Requiere !paused.

=========================================================
  📊 CONSULTA (view functions)
=========================================================

6. getUSDCBalance()
   Input:  (sin parámetros)
   Acceso: Público
   Descripción: Devuelve el balance de USDC disponible en el contrato.
                Return: uint256

7. getPosition(address token)
   Input:  token (dirección del token)
   Acceso: Público
   Descripción: Devuelve los datos de una posición específica:
                amount, buyPrice, buyTimestamp.
                Return: Position struct

8. getActivePositions()
   Input:  (sin parámetros)
   Acceso: Público
   Descripción: Devuelve todas las posiciones abiertas en el contrato.
                Return: Position[] array

9. getTotalValue()
   Input:  (sin parámetros)
   Acceso: Público
   Descripción: Estima el valor total del portfolio en USDC.
                Suma USDC balance + valor de todas las posiciones
                (precio actual on-chain via Uniswap quoter).
                Return: uint256

10. getPnL()
    Input:  (sin parámetros)
    Acceso: Público
    Descripción: Devuelve el profit & loss total:
                 totalRealizedPnL + unrealizedPnL de posiciones abiertas.
                 Return: int256 (puede ser negativo)

=========================================================
  🔐 RECOVERY DE CUENTA
=========================================================

11. initiateRecovery(address newOwner)
    Input:  newOwner (nueva dirección que será el owner)
    Acceso: Guardian
    Descripción: Inicia el proceso de recuperación de cuenta.
                 Setea pendingOwner y activa un timelock (24h).
                 El owner actual puede cancelar durante el timelock.
                 Requiere !recoveryInProgress.

12. cancelRecovery()
    Input:  (sin parámetros)
    Acceso: Owner
    Descripción: Cancela un proceso de recuperación en curso.
                Limpia pendingOwner y el timelock.
                Solo funciona durante el periodo de timelock.

13. executeRecovery()
    Input:  (sin parámetros)
    Acceso: Owner, Guardian
    Descripción: Ejecuta la recuperación después del timelock.
                 Cambia owner = pendingOwner.
                 Limpia pendingOwner y timelock.
                 Requiere block.timestamp >= recoveryTimelock.

14. recoverWithZK(bytes calldata proof, address newOwner)
    Input:  proof (ZK proof generado off-chain)
            newOwner (nueva dirección que será owner)
    Acceso: Público (cualquiera con un proof válido)
    Descripción: Recupera la cuenta usando ZK proof.
                 Verifica que hash(passwordHash, backendSecret) == recoveryHash.
                 Si el proof es válido, cambia owner = newOwner.
                 No requiere timelock — el proof mismo es la autorización.
                 Llama al ZKVerifier para validar el proof.

15. rotateRecoverySecret(bytes calldata proof, bytes32 newRecoveryHash)
    Input:  proof (ZK proof del secret actual)
            newRecoveryHash (nuevo hash a guardar on-chain)
    Acceso: Owner (con proof válido del secret actual)
    Descripción: Rota el secret de recovery.
                 Verifica que conocés el secret actual mediante ZK proof.
                 Si es válido, actualiza recoveryHash = newRecoveryHash.
                 El backend debe rotar su backendSecret al mismo tiempo.
                 Permite rotación periódica por seguridad.

16. setGuardian(address _guardian)
    Input:  _guardian (dirección de la cuenta secundaria)
    Acceso: Owner
    Descripción: Setea o cambia la dirección del guardian.
                 El guardian puede iniciar y ejecutar recovery.

17. setZKVerifier(address _zkVerifier)
    Input:  _zkVerifier (dirección del contrato verificador ZK)
    Acceso: Owner
    Descripción: Setea el contrato verificador de ZK proofs.
                 Generado por circom/noir al compilar el circuito.

=========================================================
  ⚙️ CONFIGURACIÓN
=========================================================

18. setBot(address _bot)
    Input:  _bot (dirección del bot que ejecuta trades)
    Acceso: Owner
    Descripción: Setea o rota la dirección del bot autorizado
                 para comprar y vender.

19. setRouter(address _router)
    Input:  _router (dirección del router de Uniswap)
    Acceso: Owner
    Descripción: Cambia el router de Uniswap usado para los swaps.
                 Útil si hay que migrar a una nueva versión del router.

20. pause()
    Input:  (sin parámetros)
    Acceso: Owner, Guardian
    Descripción: Congela todas las operaciones de trading y withdraw.
                Las funciones de recovery siguen operando.
                Útil en caso de sospecha de compromiso.

21. unpause()
    Input:  (sin parámetros)
    Acceso: Owner
    Descripción: Descongela las operaciones. Reanuda trading y withdraw.

=========================================================
  📦 ESTRUCTURAS DE DATOS
=========================================================

struct Position {
    address token;        // dirección del token
    uint256 amount;       // cantidad持有
    uint256 buyPrice;     // precio de compra en USDC
    uint256 buyTimestamp; // timestamp de la compra
}

VARIABLES DE ESTADO:
- address public owner
- address public guardian
- address public bot
- address public pendingOwner
- uint256 public recoveryTimelock
- bool public paused
- bool public recoveryInProgress
- bytes32 public recoveryHash           // hash(passwordHash, backendSecret)
- address public zkVerifier
- IERC20 public usdcToken
- ISwapRouter public uniswapRouter
- Position[] public positions
- mapping(address => Position) public tokenPositions
- uint256 public totalInvested
- uint256 public totalRealizedPnL

=========================================================
  📋 EVENTOS
=========================================================

event USDCWithdrawn(address indexed to, uint256 amount)
event TokenWithdrawn(address indexed token, address indexed to, uint256 amount)
event Bought(address indexed token, uint256 usdcAmount, uint256 tokenAmount)
event Sold(address indexed token, uint256 tokenAmount, uint256 usdcReceived)
event PositionClosed(address indexed token, int256 pnl)
event RecoveryInitiated(address indexed newOwner, uint256 timelockEnd)
event RecoveryCancelled(address indexed by)
event RecoveryExecuted(address indexed oldOwner, address indexed newOwner)
event RecoverySecretRotated(address indexed by)
event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian)
event BotUpdated(address indexed oldBot, address indexed newBot)
event RouterUpdated(address indexed oldRouter, address indexed newRouter)
event ZKVerifierUpdated(address indexed oldVerifier, address indexed newVerifier)
event Paused(address indexed by)
event Unpaused(address indexed by)

=========================================================
  FIN DEL DOCUMENTO
=========================================================
**/

/**
STOCK PORTFOLIO VAULT
│
├── FUND MANAGEMENT
│   ├── deposit()
│   ├── withdraw()
│   └── withdrawAsset()
│
├── ASSET CONFIGURATION
│   ├── addAsset()
│   ├── removeAsset()
│   ├── updateAllocation()
│   ├── getAllocation()
│   └── getAssets()
│
├── RISK CONFIGURATION
│   ├── enableRisk()
│   ├── disableRisk()
│   ├── updateRiskConfig()
│   └── resetRisk()
│
├── INVESTMENT
│   ├── invest()
│   └── executeSwap()
│
├── POSITIONS
│   ├── getPosition()
│   └── internal position accounting
│
├── BOT
│   └── setBot()
│
├── EMERGENCY
│   ├── pauseTrading()
│   └── unpauseTrading()
│
└── VIEW
    ├── getAssets()
    ├── getPosition()
    ├── getAllocation()
    └── getRiskConfig() */

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public0
// internal
// private
// view & pure functions
pragma solidity ^0.8.20;
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../lib/solidity-bytes-utils/contracts/BytesLib.sol";
import {console} from "forge-std/console.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV3Twap} from "./libraries/UniswapV3Twap.sol";
contract StockWallet is AccessControl, ReentrancyGuard {
    error StockWallet_PercentagesExceedTotal();
    mapping(address => AssetConfig) public assetConfig;
    mapping(address => Position) public assetPosition;
    mapping(address => bytes path) public assetPath;
    IUniswapV3Factory public immutable factory;
    address public usdc;
    uint24 public constant POOL_FEE = 500;
    ISwapRouter public immutable s_swapRouter;
    // seteamos de cero pero hay que hacerlo dinamica
    uint256 private gas_fee = 200;
    using SafeERC20 for IERC20;
    using BytesLib for bytes;
    //funcion para cambiarla reserva;
    address[] public assets;
    struct AssetConfig {
        uint256 allocationBps;
        uint16 stopLossBps; // 9500
        uint16 takeProfitBps; // 11000
        bool riskEnabled;
        bool riskPaused;
        bool ownBot;
    }
    struct Position {
        uint256 amount;
        uint256 invested; // in usdc
    }
    struct tokenAllocationConfig {
        address token;
        AssetConfig configs;
    }
    bytes32 public constant SECONDARY_ACCOUNT = keccak256("SECONDARY_ACCOUNT");
    // Escala de porcentaje (10_000 = 100%, 1 = 1%)
    /**
    100% ----> 10_000
    20%  ----> 2_000
    1.5% ----> 150
    0.01 ----> 1
     */
    uint16 public constant TOTAL_PERCENTAGE = 10_000;
    bytes32 private s_commitment;
    address private s_secondAddress;

    function depositAsset(address _token, uint256 _amount) public {
        if (IERC20(_token).allowance(msg.sender, address(this)) < _amount) {
            revert("Allocation total must equal 100%");
        }
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        Position storage _assetPosition = assetPosition[_token];
        _assetPosition.amount = _amount;
    }
    //function withdraw(uint256 amount) external;
    function withdrawAsset(address _token, uint256 _amount) external {
        IERC20(_token).transfer(msg.sender, _amount);
    }
    //we reduce one of the stocks or all of them
    function addAsset(
        address _newToken,
        uint256 _newAllocationBps,
        address _oldToken
    ) external {
        //_newAllocationBps must be in term of 10_000 = 100%
        console.log("=== addAsset START ===");
        console.log("_newToken:", _newToken);
        console.log("_newAllocationBps:", _newAllocationBps);
        console.log("_oldToken:", _oldToken);
        if (_oldToken == address(0)) {
            console.log("Branch: _oldToken == address(0)");
            uint256 remainingPercentage = TOTAL_PERCENTAGE - _newAllocationBps; // Ej: 100% - 20% = 80% --> 10_000 - 2_000 = 8_000
            console.log("remainingPercentage:", remainingPercentage);
            uint256 sumAdjustedOldAssets = 0;
            uint256 length = assets.length;
            console.log("assets.length:", length);
            // (3,000 * 8,000) / 10,000 = 2,400
            for (uint256 index = 0; index < length; index++) {
                AssetConfig storage config = assetConfig[assets[index]];
                console.log("  index:", index);
                console.log("  token:", assets[index]);
                console.log(
                    "  config.allocationBps (before):",
                    config.allocationBps
                );
                if (index == length - 1) {
                    console.log("  is last element");
                    console.log("  remainingPercentage:", remainingPercentage);
                    console.log(
                        "  sumAdjustedOldAssets:",
                        sumAdjustedOldAssets
                    );
                    uint256 lastPercentage = remainingPercentage -
                        sumAdjustedOldAssets;
                    console.log("  lastPercentage:", lastPercentage);
                    config.allocationBps = lastPercentage;
                    sumAdjustedOldAssets += lastPercentage;
                    console.log(
                        "  sumAdjustedOldAssets (after last):",
                        sumAdjustedOldAssets
                    );
                } else {
                    //After doing the op assig new
                    uint256 itemNewAllocationBps = (config.allocationBps *
                        remainingPercentage) / TOTAL_PERCENTAGE; // Ej:  (3,000 * 8,000) / 10,000 = 2,400 --> 24%
                    console.log(
                        "  itemNewAllocationBps:",
                        itemNewAllocationBps
                    );
                    config.allocationBps = itemNewAllocationBps;
                    sumAdjustedOldAssets += itemNewAllocationBps;
                    console.log(
                        "  sumAdjustedOldAssets (after):",
                        sumAdjustedOldAssets
                    );
                }
            }
            //if total is not = to 100% we revert
            uint256 totalAllocation = sumAdjustedOldAssets + _newAllocationBps;
            console.log("totalAllocation:", totalAllocation);
            console.log("_newAllocationBps:", _newAllocationBps);
            console.log("sumAdjustedOldAssets:", sumAdjustedOldAssets);

            if (totalAllocation != TOTAL_PERCENTAGE) {
                revert("Allocation total must equal 100%");
                //put custom error
            }
            // 3. Add new one
        } else {
            console.log("Branch: _oldToken != address(0)");
            AssetConfig storage newConfig = assetConfig[_newToken];
            //After doing the op assig new
            newConfig.allocationBps = _newAllocationBps;
            AssetConfig storage oldConfig = assetConfig[_oldToken];
            console.log("oldConfig.allocationBps:", oldConfig.allocationBps);
            console.log("_newAllocationBps:", _newAllocationBps);
            //After doing the op assig new
            //chek if the new is lower
            uint256 newAllocationBps_toReplace = oldConfig.allocationBps -
                _newAllocationBps;
            console.log(
                "newAllocationBps_toReplace:",
                newAllocationBps_toReplace
            );
            oldConfig.allocationBps = newAllocationBps_toReplace;
        }
        console.log("=== addAsset END ===");
        assetConfig[_newToken] = AssetConfig({
            allocationBps: _newAllocationBps,
            stopLossBps: 0, // 9500
            takeProfitBps: 0, // 11000
            riskEnabled: false,
            riskPaused: false,
            ownBot: false
        });
        assets.push(_newToken);
    }

    function removeAsset(address _removedToken) external {
        uint256 removedBps = assetConfig[_removedToken].allocationBps;
        //require(removedBps > 0, "Token not active or already 0%");

        // 1. Eliminar el token del mapping
        delete assetConfig[_removedToken];

        // 2. Remover el token del array 'assets' (swap & pop)
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; i++) {
            if (assets[i] == _removedToken) {
                assets[i] = assets[length - 1];
                assets.pop();
                break;
            }
        }

        uint256 newLength = assets.length;

        // Si no quedan tokens, terminamos
        if (newLength == 0) return;

        // 3. La suma BPS que representaban los activos restantes antes del reajuste
        uint256 remainingAssetsOldSumBps = TOTAL_PERCENTAGE - removedBps; // Ej: 10_000 - 3_000 = 7_000

        uint256 sumAdjustedOldAssets = 0;

        // 4. Reescalar hacia arriba los porcentajes de los activos restantes
        for (uint256 index = 0; index < newLength; index++) {
            AssetConfig storage config = assetConfig[assets[index]];

            if (index == newLength - 1) {
                // Último elemento: Absorbe residuos por redondeo (dust)
                uint256 lastPercentage = TOTAL_PERCENTAGE -
                    sumAdjustedOldAssets;
                config.allocationBps = lastPercentage;
                sumAdjustedOldAssets += lastPercentage;
            } else {
                // Fórmula de escalado hacia arriba: (BPS_actual * 10_000) / Suma_Viejos_Restantes
                uint256 itemNewAllocationBps = (config.allocationBps *
                    TOTAL_PERCENTAGE) / remainingAssetsOldSumBps;
                config.allocationBps = itemNewAllocationBps;
                sumAdjustedOldAssets += itemNewAllocationBps;
            }
        }

        // 5. Validación final de integridad
        if (sumAdjustedOldAssets != TOTAL_PERCENTAGE) {
            revert("Allocation total must equal 100%");
        }
    }
    /*
    function updateAllocation(
        address token,
        uint256 newAllocationBps
    ) external onlyOwner;
    function enableRisk(
        address token,
        uint256 stopLossBps,
        uint256 stopLossSellBps,
        uint256 takeProfitBps
    ) external onlyOwner;
    function updateRiskConfig(
        address token,
        uint256 stopLossBps,
        uint256 stopLossSellBps,
        uint256 takeProfitBps
    ) external onlyOwner;*/
    //
    function selltoken(address token, bytes calldata path) public {
        console.log("=== selltoken START ===");
        console.log("token:", token);
        console.log("path.length:", path.length);
        //chek path
        if (path.length > 0) {
            address TokentoReceive = getLastAddress(path);
            console.log("TokentoReceive:", TokentoReceive);
            console.log("usdc:", usdc);
            if (TokentoReceive != usdc) {
                console.log("REVERT: path does not end in usdc");
                revert();
            }
        }
        //check price

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        console.log("tokenBalance:", tokenBalance);
        uint256 tokenPriceUsdcNow = getTwapPrice(
            token,
            usdc,
            uint128(tokenBalance)
        );
        console.log("tokenPriceUsdcNow:", tokenPriceUsdcNow);
        //chek if the stoppfit or the startprofit meet with the price
        Position storage position = assetPosition[token];
        AssetConfig memory config = assetConfig[token];
        console.log("position.invested:", position.invested);
        console.log("config.stopLossBps:", config.stopLossBps);
        console.log("config.takeProfitBps:", config.takeProfitBps);
        //get the price stop which is the maximun price to sell
        uint256 minimunToLose = (position.invested * config.stopLossBps) /
            TOTAL_PERCENTAGE;
        uint256 minimunTowin = (position.invested * config.takeProfitBps) /
            TOTAL_PERCENTAGE;
        console.log("minimunToLose:", minimunToLose);
        console.log("minimunTowin:", minimunTowin);
        if (tokenPriceUsdcNow <= minimunToLose) {
            console.log("BRANCH: stopLoss triggered (price <= minimunToLose)");
            IERC20(token).approve(address(s_swapRouter), tokenBalance);
            console.log("approved swapRouter for tokenBalance");
            uint256 amountOut = _swap(token, usdc, path, tokenBalance);
            console.log("swap amountOut:", amountOut);

            //ban token so can not be investe no more
            console.log("=== selltoken END (stopLoss) ===");
            return;
        }
        if (tokenPriceUsdcNow >= minimunTowin) {
            console.log("BRANCH: takeProfit triggered (price >= minimunTowin)");
            //we get the price invested in the token with the current price then substract and sell de diference
            uint256 usdcToToken = getTwapPrice(
                usdc,
                token,
                uint128(position.invested)
            );
            console.log("usdcToToken:", usdcToToken);
            uint256 diference = tokenBalance - usdcToToken;
            console.log("diference:", diference);
            IERC20(token).approve(address(s_swapRouter), diference);
            console.log("approved swapRouter for diference");
            uint256 amountOut = _swap(token, usdc, path, diference);
            console.log("swap amountOut:", amountOut);
            console.log("=== selltoken END (takeProfit) ===");
            return;
        } else {
            console.log(
                "REVERT: price between stopLoss and takeProfit, no action"
            );
            revert();
        }
        // if now price is lower or equal to maximun to lose we can sell
        /// faltan los effects
        //sell --- > swap
    } /*
    function selltokenAll() {
        //check price
        //chek if the stoppfit or the startprofit meet with the price
        //sell --- > swap
    }*/

    //send some money to the adgent and to the paymaste to pay the gas fee
    function invest(bytes[] calldata path) external {
        //aprove usdc
        //add path

        uint256 tokenBalance = IERC20(usdc).balanceOf(address(this));
        uint256 amount_to_invest = (tokenBalance *
            (TOTAL_PERCENTAGE - gas_fee)) / TOTAL_PERCENTAGE;
        IERC20(usdc).approve(address(s_swapRouter), amount_to_invest);
        uint256 length = assets.length;
        if (path.length > 0) {
            for (uint256 index = 0; index < path.length; index++) {
                address TokentoReceive = getLastAddress(path[index]);
                assetPath[TokentoReceive] = path[index];
            }
        }

        for (uint256 index = 0; index < length; index++) {
            address addrTokenOut = assets[index];
            Position storage positionToken = assetPosition[addrTokenOut];
            bytes memory tokenPath = assetPath[addrTokenOut];
            AssetConfig memory config = assetConfig[addrTokenOut];
            uint256 amountIn = (amount_to_invest * config.allocationBps) /
                TOTAL_PERCENTAGE;
            uint256 amountOut = _swap(usdc, addrTokenOut, tokenPath, amountIn);
            delete assetPath[addrTokenOut];
            positionToken.amount = amountOut;
            positionToken.invested = amountIn;
        }
    }

    //SHOULD WE SET  USDC ADDRESS ?
    constructor(
        bytes32 _commitmet,
        address _secondAddress,
        address _swapRouter,
        address _usdc,
        address _factory,
        tokenAllocationConfig[] memory tokenToInvest
    ) {
        uint256 TotalPercentage;
        for (uint256 index = 0; index < tokenToInvest.length; index++) {
            address addrToken = tokenToInvest[index].token;
            AssetConfig memory newConfig = tokenToInvest[index].configs;
            assetConfig[addrToken] = newConfig;
            TotalPercentage += newConfig.allocationBps;
            if (
                newConfig.stopLossBps != 0 &&
                newConfig.takeProfitBps < TOTAL_PERCENTAGE
            ) {
                revert();
            }
            if (
                newConfig.stopLossBps != 0 &&
                newConfig.stopLossBps > TOTAL_PERCENTAGE
            ) {
                revert();
            }
            assets.push(addrToken);
        }
        if (TOTAL_PERCENTAGE != TotalPercentage) {
            revert StockWallet_PercentagesExceedTotal();
        }

        s_swapRouter = ISwapRouter(_swapRouter);
        factory = IUniswapV3Factory(_factory);
        s_commitment = _commitmet;
        s_secondAddress = _secondAddress;
        _grantRole(SECONDARY_ACCOUNT, msg.sender);
        usdc = _usdc;
    }
    function _swap(
        address tokenIn,
        address tokenOut,
        bytes memory path,
        uint256 amountIn
    ) internal returns (uint256) {
        if (path.length == 0) {
            uint256 amountOut = s_swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: POOL_FEE,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: amountIn,
                    amountOutMinimum: 1,
                    sqrtPriceLimitX96: 0
                })
            );
            return amountOut;
        } else {
            uint256 amountOut = s_swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: amountIn,
                    amountOutMinimum: 1
                })
            );
            return amountOut;
        }
    }
    function getLastAddress(bytes memory path) public pure returns (address) {
        require(path.length >= 20, "Path invalido");

        // Lee exactamente 20 bytes iniciando en la posición (longitud total - 20)
        return path.toAddress(path.length - 20);
    }
    function getTwapPrice(
        address tokenin,
        address tokenout,
        uint128 amount
    ) public view returns (uint256) {
        address pool = factory.getPool(tokenin, tokenout, POOL_FEE);
        return UniswapV3Twap.getTwapAmountOut(pool, tokenin, amount, 1800);
    }
    //just for test
    function modifyPosition(uint256 amount, address token) public {
        Position storage positionToken = assetPosition[token];
        positionToken.invested = amount;
    }

    /*function getAllocation(address token) external view returns (uint256);
    function getAssets() external view returns (AssetConfig[] memory);*/
}
