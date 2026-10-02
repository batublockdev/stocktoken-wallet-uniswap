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
pragma solidity ^0.8.25;
import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {console} from "forge-std/console.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
contract TradeWallet is AccessControl, ReentrancyGuard {
    mapping(address => AssetConfig) public assetConfig;
    mapping(address => Position) public assetPosition;

    uint256 private recerva;
    
    //funcion para cambiarla reserva; 
    address[] public assets;
    struct AssetConfig {
        uint16 allocationBps;
        uint16 stopLossBps; // 9500
        uint16 takeProfitBps; // 11000
        bool riskEnabled;
        bool riskPaused;
    }
    struct Position {
        uint256 amount;
        uint256 invested;
    }
    bytes32 public constant SECONDARY_ACCOUNT = keccak256("SECONDARY_ACCOUNT");
    // Escala de porcentaje (10_000 = 100%, 1 = 1%)
    /**
    100% ----> 10_000
    20%  ----> 2_000
    1.5% ----> 150
    0.01 ----> 1
     */
    uint256 public constant TOTAL_PERCENTAGE = 10_000;
    bytes32 private s_commitment;
    address private s_secondAddress;

    function depositAsset(address _token, uint256 _amount) public {
        if (IERC20(_token).allowance(msg.sender, address(this)) < _amount) {
            revert Wallet__NotApprovedForToken(_token);
        }
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        Position storage _assetPosition = assetPosition[_token];
        _assetPosition.amount = _amount;
    }
    //function withdraw(uint256 amount) external;
    function withdrawAsset(address _token, uint256 _amount) external {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    //we reduce one of the stocks or all of them
    function addAsset(
        address _newToken,
        uint256 _newAllocationBps,
        address _oldToken
    ) external {
        //_newAllocationBps must be in term of 10_000 = 100%
        if (_oldToken == address(0)) {
            uint256 remainingPercentage = TOTAL_PERCENTAGE - _newAllocationBps; // Ej: 100% - 20% = 80% --> 10_000 - 2_000 = 8_000
            uint256 sumAdjustedOldAssets = 0;
            uint256 length = assets.length;
            // (3,000 * 8,000) / 10,000 = 2,400
            for (uint256 index = 0; index < length; index++) {
                AssetConfig storage config = assetConfig[assets[index]];
                if (index == length - 1) {
                    uint256 lastPercentage = remainingPercentage -
                        sumAdjustedOldAssets;
                    config.allocationBps = lastPercentage;
                    sumAdjustedOldAssets += lastPercentage;
                } else {
                    //After doing the op assig new
                    uint256 itemNewAllocationBps = (config.allocationBps *
                        remainingPercentage) / TOTAL_PERCENTAGE; // Ej:  (3,000 * 8,000) / 10,000 = 2,400 --> 24%
                    config.allocationBps = itemNewAllocationBps;
                    sumAdjustedOldAssets += itemNewAllocationBps;
                }
            }
            //if total is not = to 100% we revert
            uint256 totalAllocation = sumAdjustedOldAssets + _newAllocationBps;

            if (totalAllocation != TOTAL_PERCENTAGE) {
                revert("Allocation total must equal 100%");
                //put custom error
            }
            // 3. Add new one
        } else {
            AssetConfig storage newConfig = assetConfig[_newToken];
            //After doing the op assig new
            config.allocationBps = _newAllocationBps;
            AssetConfig storage oldConfig = assetConfig[_oldToken];
            //After doing the op assig new
            //chek if the new is lower
            uint256 newAllocationBps_toReplace = config.allocationBp -
                _newAllocationBps;
            config.allocationBps = newAllocationBps_toReplace;
        }
        assetConfig[_newToken] += AssetConfig({
            allocationBps: _newAllocationBps,
            stopLossBps: 0, // 9500
            takeProfitBps: 0, // 11000
            riskEnabled: false,
            riskPaused: false
        });
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
    ) external onlyOwner;
    function invest(
        address usdc,
        bytes[] calldata path
    ) external onlyBot{
        //aprove usdc
        //add path
        uint256 tokenBalance = IERC20.balanceof(address(this));
        uint256 amount_to_invest = tokenBalance * reserva / TOTAL_PERCENTAGE;
        IERC20(usdc).approve(router, amount_to_invest);
        uint256 length = assets.length;
            for (uint256 index = 0; index < length; index++) {
                AssetConfig memory config = assetConfig[assets[index]];
                uint256 amountIn = amount_to_invest * config.allocationBps /  TOTAL_PERCENTAGE;
                uint256 amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: usdc,
                tokenOut: assets[index],
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
            
    };
    //SHOULD WE SET  USDC ADDRESS ?
    constructor(bytes32 _commitmet, address _secondAddress) {
                s_swapRouter = ISwapRouter(_swapRouter);
        s_commitment = _commitmet;
        s_secondAddress = _secondAddress;
        _grantRole(SECONDARY_ACCOUNT, msg.sender);
    }

    function getAllocation(address token) external view returns (uint256);
    function getAssets() external view returns (AssetConfig[] memory);
}
