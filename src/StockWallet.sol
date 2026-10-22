// SPDX-License-Identifier: MIT
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
import "../lib/solidity-bytes-utils/contracts/BytesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

interface IPermit2Swap {
    function allowance(
        address user,
        address token,
        address spender
    ) external view returns (uint160 amount, uint48 expiration, uint48 nonce);

    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external;
}

interface IUniversalRouterSwap {
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;
}
interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    )
        external
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );
}
contract StockWallet is Ownable, AccessControl, ReentrancyGuard {
    error StockWallet_PercentagesExceedTotal();
    error NoViablePool(address tokenIn, address tokenOut);
    error AmountInZero();
    error InsufficientTokenBalance(
        address token,
        uint256 available,
        uint256 required
    );
    error TokenApprovalFailed(address token, address spender);
    error ErrorDeposit_NotEnoughtAllowance(address token, uint256 amount);
    error ErrortakeProfitBps_notCorrect(address token, uint256 takeProfitBps);
    error ErrorStopLossBps_notCorrect(address token, uint256 stopLossBps);
    error Address_Zero();
    error TokenNotReadytoSell(address token);
    error addressToReiveNotCorrect(address token);
    error Permit2AllowanceInsufficient(address token);
    error SwapReturnedNoTokens(address tokenOut);
    error PoolNoExiste(address tokenIn, address tokenOut);
    error StockWallet_Invalid();
    mapping(address => AssetConfig) public assetConfig;
    mapping(address => Position) public assetPosition;
    mapping(address => bytes path) public assetPath;
    IUniswapV3Factory public immutable factory;
    IQuoterV2 public immutable quoter;

    address public usdc;
    address private adgent;
    address private adgentContract;

    // seteamos de cero pero hay que hacerlo dinamica
    uint256 private gas_fee = 200;
    uint256 private Adgent_percentage = 500;

    using SafeERC20 for IERC20;
    using BytesLib for bytes;
    //funcion para cambiarla reserva;
    address[] public assets;
    struct AssetConfig {
        uint256 allocationBps;
        uint16 stopLossBps; // 9500
        uint16 takeProfitBps; // 11000
    }
    struct Position {
        uint256 amount;
        uint256 invested; // in usdc
    }
    struct tokenAllocationConfig {
        address token;
        AssetConfig configs;
    }
    bytes32 public constant ADGENT_ROLE = keccak256("ADGENT_ROLE");
    // Escala de porcentaje (10_000 = 100%, 1 = 1%)
    /**
    100% ----> 10_000
    20%  ----> 2_000
    1.5% ----> 150
    0.01 ----> 1
     */
    uint16 public constant TOTAL_PERCENTAGE = 10_000;
    address constant UNIVERSAL_ROUTER =
        0x643770E279d5D0733F21d6DC03A8efbABf3255B4;

    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    event AssetDeposited(
        address indexed user,
        address indexed token,
        uint256 amountDeposited,
        uint256 usdcReceived
    );

    event AssetWithdrawn(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    event UsdcWithdrawn(address indexed recipient, uint256 amount);
    event AssetPurchased(
        address indexed token,
        uint256 usdcSpent,
        uint256 tokensReceived
    );

    event AssetSold(
        address indexed token,
        uint256 tokensSold,
        uint256 usdcReceived
    );

    event InvestmentExecuted(
        uint256 totalUsdc,
        uint256 gasFee,
        uint256 agentFee,
        uint256 totalInvested
    );
    event StopLossTriggered(
        address indexed token,
        uint256 tokensSold,
        uint256 usdcReceived,
        uint256 referenceInvested
    );

    event TakeProfitTriggered(
        address indexed token,
        uint256 tokensSold,
        uint256 usdcReceived,
        uint256 referenceInvested
    );
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);

    event AgentContractUpdated(
        address indexed oldAgentContract,
        address indexed newAgentContract
    );

    event GasFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    event AgentPercentageUpdated(
        uint256 oldPercentageBps,
        uint256 newPercentageBps
    );

    event AssetAdded(address indexed token, uint256 allocationBps);

    event AssetRemoved(address indexed token);

    event AssetAllocationUpdated(
        address indexed token,
        uint256 oldAllocationBps,
        uint256 newAllocationBps
    );

    event AssetRiskConfigUpdated(
        address indexed token,
        uint16 oldStopLossBps,
        uint16 newStopLossBps,
        uint16 oldTakeProfitBps,
        uint16 newTakeProfitBps
    );
    constructor(
        address _usdc,
        address _factory,
        address _quoter,
        address _adgent,
        address _adgentContract,
        uint256 _Adgent_percentage,
        tokenAllocationConfig[] memory tokenToInvest
    ) Ownable(msg.sender) {
        if (tokenToInvest.length == 0) {
            revert StockWallet_Invalid();
        }
        if (
            _usdc == address(0) ||
            _factory == address(0) ||
            _quoter == address(0) ||
            _adgent == address(0) ||
            _adgentContract == address(0)
        ) {
            revert Address_Zero();
        }
        uint256 TotalPercentage;
        for (uint256 index = 0; index < tokenToInvest.length; index++) {
            address addrToken = tokenToInvest[index].token;
            if (addrToken == address(0) || addrToken == _usdc) {
                revert Address_Zero();
            }
            AssetConfig memory newConfig = tokenToInvest[index].configs;
            assetConfig[addrToken] = newConfig;
            TotalPercentage += newConfig.allocationBps;
            if (
                newConfig.takeProfitBps != 0 &&
                newConfig.takeProfitBps < TOTAL_PERCENTAGE
            ) {
                revert ErrortakeProfitBps_notCorrect(
                    addrToken,
                    newConfig.takeProfitBps
                );
            }
            if (
                newConfig.stopLossBps != 0 &&
                newConfig.stopLossBps > TOTAL_PERCENTAGE
            ) {
                revert ErrorStopLossBps_notCorrect(
                    addrToken,
                    newConfig.stopLossBps
                );
            }
            uint256 length = assets.length;
            for (uint256 index = 0; index < length; index++) {
                address token = assets[index];
                if (token == addrToken) {
                    revert StockWallet_Invalid();
                }
            }

            assets.push(addrToken);
        }
        if (TOTAL_PERCENTAGE != TotalPercentage) {
            revert StockWallet_PercentagesExceedTotal();
        }

        factory = IUniswapV3Factory(_factory);
        quoter = IQuoterV2(_quoter);
        usdc = _usdc;
        adgent = _adgent;
        Adgent_percentage = _Adgent_percentage;
        adgentContract = _adgentContract;
        _grantRole(ADGENT_ROLE, _adgent);
        _grantRole(ADGENT_ROLE, msg.sender);
    }
    function updateAdgent(address newAdgent) external onlyOwner {
        address oldAdgent = adgent;
        if (newAdgent == address(0)) {
            revert Address_Zero();
        }
        _revokeRole(ADGENT_ROLE, adgent);

        _grantRole(ADGENT_ROLE, newAdgent);
        adgent = newAdgent;
        emit AgentUpdated(oldAdgent, newAdgent);
    }
    function updateAdgentContract(
        address newAdgentContract
    ) external onlyOwner {
        address oldAdgentContract = adgentContract;
        if (newAdgentContract == address(0)) {
            revert Address_Zero();
        }
        adgentContract = newAdgentContract;
        emit AgentContractUpdated(oldAdgentContract, newAdgentContract);
    }
    function updateGas_Fee(uint256 newGasFee) external onlyOwner {
        uint256 oldGas_fee = gas_fee;
        if (newGasFee == 0) {
            revert AmountInZero();
        }
        gas_fee = newGasFee;
        emit GasFeeUpdated(oldGas_fee, newGasFee);
    }
    function updateAdgentPercentage(uint256 newPercentage) external onlyOwner {
        uint256 oldPercentage = Adgent_percentage;
        if (newPercentage == 0) {
            revert AmountInZero();
        }
        Adgent_percentage = newPercentage;
        emit AgentPercentageUpdated(oldPercentage, newPercentage);
    }

    function depositAsset(
        address _token,
        uint256 _amount,
        bytes calldata path
    ) external {
        if (_amount == 0) {
            revert AmountInZero();
        }
        if (_token == address(0)) {
            revert Address_Zero();
        }
        if (IERC20(_token).allowance(msg.sender, address(this)) < _amount) {
            revert ErrorDeposit_NotEnoughtAllowance(_token, _amount);
        }
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        if (_token != usdc) {
            uint256 amountOut = _swap(_token, usdc, path, _amount);
            emit AssetDeposited(msg.sender, _token, _amount, amountOut);
        }
        emit AssetDeposited(msg.sender, _token, _amount, _amount);
    }
    //function withdraw(uint256 amount) external;
    function withdrawAsset(address _token) external onlyOwner {
        if (_token == address(0)) {
            revert Address_Zero();
        }
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert InsufficientTokenBalance(_token, balance, 1);
        }

        IERC20(_token).safeTransfer(
            msg.sender,
            IERC20(_token).balanceOf(address(this))
        );

        Position storage positionToken = assetPosition[_token];
        positionToken.amount = 0;
        positionToken.invested = 0; //emit
        emit AssetWithdrawn(_token, msg.sender, balance);
    }
    function withdrawAssetUsdt(uint256 _ammount) external onlyOwner {
        if (_ammount == 0) {
            revert AmountInZero();
        }
        IERC20(usdc).safeTransfer(msg.sender, _ammount);

        emit UsdcWithdrawn(msg.sender, _ammount);
    }
    //we reduce one of the stocks or all of them
    function addAsset(
        address _newToken,
        uint256 _newAllocationBps,
        address _oldToken
    ) external onlyOwner {
        if (_newToken == address(0)) {
            revert Address_Zero();
        }
        if (_newAllocationBps == 0 || _newAllocationBps > TOTAL_PERCENTAGE) {
            revert StockWallet_PercentagesExceedTotal();
        }
        uint256 length = assets.length;
        for (uint256 index = 0; index < length; index++) {
            address token = assets[index];
            if (token == _newToken) {
                revert StockWallet_Invalid();
            }
        }

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
                revert StockWallet_PercentagesExceedTotal();
            }
        } else {
            AssetConfig storage newConfig = assetConfig[_newToken];
            //After doing the op assig new
            newConfig.allocationBps = _newAllocationBps;
            AssetConfig storage oldConfig = assetConfig[_oldToken];

            //After doing the op assig new
            //chek if the new is lower
            uint256 newAllocationBps_toReplace = oldConfig.allocationBps -
                _newAllocationBps;

            oldConfig.allocationBps = newAllocationBps_toReplace;
        }
        // add new
        assetConfig[_newToken] = AssetConfig({
            allocationBps: _newAllocationBps,
            stopLossBps: 0, // 9500
            takeProfitBps: 0 // 11000
        });
        assets.push(_newToken);
        emit AssetAdded(_newToken, _newAllocationBps);
    }
    function removeAsset(address _removedToken) external onlyOwner {
        _removeAsset(_removedToken);
    }
    function _removeAsset(address _removedToken) internal {
        uint256 length = assets.length;
        bool isThere = false;
        for (uint256 index = 0; index < length; index++) {
            address token = assets[index];
            if (token == _removedToken) {
                isThere = true;
                break;
            }
        }
        if (!isThere) {
            revert StockWallet_Invalid();
        }
        uint256 removedBps = assetConfig[_removedToken].allocationBps;
        //require(removedBps > 0, "Token not active or already 0%");

        // 1. Eliminar el token del mapping
        delete assetConfig[_removedToken];

        // 2. Remover el token del array 'assets' (swap & pop)
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
            revert StockWallet_PercentagesExceedTotal();
        }
        emit AssetRemoved(_removedToken);
    }

    function updateAllocation(
        address token,
        uint256 newAllocationBps
    ) external onlyOwner {
        uint256 length = assets.length;

        if (token == address(0)) {
            revert Address_Zero();
        }

        if (newAllocationBps == 0 || newAllocationBps > TOTAL_PERCENTAGE) {
            revert StockWallet_PercentagesExceedTotal();
        }

        // 1. Verificar que el token exista en assets.
        uint256 tokenIndex = type(uint256).max;

        for (uint256 i = 0; i < length; i++) {
            if (assets[i] == token) {
                tokenIndex = i;
                break;
            }
        }

        if (tokenIndex == type(uint256).max) {
            revert StockWallet_Invalid();
        }

        AssetConfig storage config = assetConfig[token];
        uint256 oldAllocationBps = config.allocationBps;

        // No hay nada que actualizar.
        if (oldAllocationBps == newAllocationBps) {
            return;
        }

        // 2. Calcular el porcentaje restante para los otros activos.
        uint256 remainingPercentage = TOTAL_PERCENTAGE - newAllocationBps;

        uint256 oldOthersTotal = TOTAL_PERCENTAGE - oldAllocationBps;

        // No podemos asignar el porcentaje restante si no hay
        // otros activos que puedan recibirlo.
        if (length == 1) {
            if (newAllocationBps != TOTAL_PERCENTAGE) {
                revert StockWallet_PercentagesExceedTotal();
            }

            emit AssetAllocationUpdated(
                token,
                oldAllocationBps,
                newAllocationBps
            );

            return;
        }

        if (oldOthersTotal == 0 && remainingPercentage > 0) {
            revert StockWallet_PercentagesExceedTotal();
        }

        // 3. Actualizar proporcionalmente las asignaciones de los
        // demás activos. El último absorbe el residuo del redondeo.
        uint256 sumAdjusted = 0;
        uint256 lastOtherIndex = length - 1;

        if (tokenIndex == lastOtherIndex) {
            lastOtherIndex = length - 2;
        }

        for (uint256 i = 0; i < length; i++) {
            if (i == tokenIndex) {
                continue;
            }

            AssetConfig storage otherConfig = assetConfig[assets[i]];

            uint256 adjustedAllocation;

            if (i == lastOtherIndex) {
                adjustedAllocation = remainingPercentage - sumAdjusted;
            } else {
                adjustedAllocation =
                    (otherConfig.allocationBps * remainingPercentage) /
                    oldOthersTotal;

                sumAdjusted += adjustedAllocation;
            }

            otherConfig.allocationBps = adjustedAllocation;
        }

        // 4. Actualizar el activo solicitado.
        config.allocationBps = newAllocationBps;

        // 5. Emitir el evento.
        emit AssetAllocationUpdated(token, oldAllocationBps, newAllocationBps);
    }

    function updateRiskConfig(
        address token,
        uint256 stopLossBps,
        uint256 takeProfitBps
    ) external onlyOwner {
        AssetConfig storage config = assetConfig[token];
        if (config.allocationBps == 0) {
            revert StockWallet_Invalid();
        }
        if (takeProfitBps != 0 && takeProfitBps < TOTAL_PERCENTAGE) {
            revert ErrortakeProfitBps_notCorrect(token, takeProfitBps);
        }
        if (stopLossBps != 0 && stopLossBps < TOTAL_PERCENTAGE) {
            revert ErrorStopLossBps_notCorrect(token, stopLossBps);
        }
        uint16 oldStopLossBps = config.stopLossBps;
        uint16 oldTakeProfitBps = config.takeProfitBps;

        config.stopLossBps = uint16(stopLossBps);
        config.takeProfitBps = uint16(takeProfitBps);

        emit AssetRiskConfigUpdated(
            token,
            oldStopLossBps,
            uint16(stopLossBps),
            oldTakeProfitBps,
            uint16(takeProfitBps)
        );
    }
    function selltoken(
        address token,
        bytes calldata path
    ) external onlyRole(ADGENT_ROLE) {
        //chek path
        if (path.length > 0) {
            address TokentoReceive = getLastAddress(path);
            if (TokentoReceive != usdc) {
                revert addressToReiveNotCorrect(TokentoReceive);
            }
        }
        //check price

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance == 0) {
            revert InsufficientTokenBalance(token, tokenBalance, 0);
        }
        (, uint256 tokenPriceUsdcNow) = _getBestPoolFee(
            token,
            usdc,
            tokenBalance
        );

        //chek if the stoppfit or the startprofit meet with the price
        Position storage position = assetPosition[token];
        AssetConfig memory config = assetConfig[token];

        //get the price stop which is the maximun price to sell
        uint256 minimunToLose = (position.invested * config.stopLossBps) /
            TOTAL_PERCENTAGE;
        uint256 minimunTowin = (position.invested * config.takeProfitBps) /
            TOTAL_PERCENTAGE;

        if (tokenPriceUsdcNow <= minimunToLose) {
            uint256 amountOut = _swap(token, usdc, path, tokenBalance);
            _removeAsset(token);
            emit StopLossTriggered(
                token,
                tokenBalance,
                amountOut,
                position.invested
            );
            return;
        }
        if (tokenPriceUsdcNow >= minimunTowin) {
            //we get the price invested in the token with the current price then substract and sell de diference
            // in 2020 buy 10 DOG --- > 10 USDC
            // in 2021 10 DOG ----- > 20 USDC
            // in 2021 sell (10 DOG)
            // in 2021 how many DOG i get for the same price I invested in 2020 (10 USDC) --- > 5 DOG
            // so 5 DOG now substract the 10 DOG I have and sell the diference 5 DOG
            // and since 5 DOG == 10 USDC I get the profit
            (, uint256 usdcToToken) = _getBestPoolFee(
                usdc,
                token,
                position.invested
            );
            uint256 diference = tokenBalance - usdcToToken;
            uint256 amountOut = _swap(token, usdc, path, diference);
            position.amount -= diference;
            emit TakeProfitTriggered(
                token,
                diference,
                amountOut,
                position.invested
            );
            return;
        } else {
            revert TokenNotReadytoSell(token);
        }
    }
    function selltokenAll(bytes[] calldata path) external onlyOwner {
        if (path.length > 0) {
            for (uint256 index = 0; index < path.length; index++) {
                address TokentoSend = getFirstAddress(path[index]);
                address TokentoReceive = getLastAddress(path[index]);
                assetPath[TokentoSend] = path[index];
                if (TokentoReceive != usdc) {
                    revert addressToReiveNotCorrect(TokentoReceive);
                }
            }
        }
        uint256 length = assets.length;
        if (length == 0) {
            revert TokenNotReadytoSell(address(0));
        }
        for (uint256 index = 0; index < length; index++) {
            address token = assets[index];

            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) {
                continue; // Skip tokens with zero balance
            }
            bytes memory tokenPath = assetPath[token];
            uint256 amountOut = _swap(token, usdc, tokenPath, tokenBalance);
            delete assetPath[token];
            Position storage positionToken = assetPosition[token];
            positionToken.amount = 0;
            positionToken.invested = 0;
            emit AssetSold(token, tokenBalance, amountOut);
        }
        //emit
    }

    //send some money to the adgent and to the paymaste to pay the gas fee
    function invest(
        bytes[] calldata path
    ) external nonReentrant onlyRole(ADGENT_ROLE) {
        uint256 tokenBalance = IERC20(usdc).balanceOf(address(this));
        if (tokenBalance == 0) {
            revert InsufficientTokenBalance(usdc, tokenBalance, 0);
        }
        uint256 gasAmount = (tokenBalance * gas_fee) / TOTAL_PERCENTAGE;
        uint256 adgentAmount = (tokenBalance * Adgent_percentage) /
            TOTAL_PERCENTAGE;
        uint256 amountToInvest = tokenBalance - gasAmount - adgentAmount;
        //Transfer gas and adgent
        IERC20(usdc).safeTransfer(adgent, gasAmount);
        IERC20(usdc).safeTransfer(adgentContract, adgentAmount);
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
            uint256 amountIn = (amountToInvest * config.allocationBps) /
                TOTAL_PERCENTAGE;
            uint256 amountOut = _swap(usdc, addrTokenOut, tokenPath, amountIn);
            delete assetPath[addrTokenOut];
            positionToken.amount += amountOut;
            positionToken.invested += amountIn;
            emit AssetPurchased(addrTokenOut, amountIn, amountOut);
        }
        emit InvestmentExecuted(
            tokenBalance,
            gasAmount,
            adgentAmount,
            amountToInvest
        );
    }

    function _swap(
        address tokenIn,
        address tokenOut,
        bytes memory path,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (tokenIn == tokenOut) {
            revert NoViablePool(tokenIn, tokenOut);
        }
        if (tokenIn == address(0) || tokenOut == address(0)) {
            revert Address_Zero();
        }
        if (amountIn == 0) revert AmountInZero();

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        // 1. Verificar saldo de entrada.
        uint256 balanceIn = inputToken.balanceOf(address(this));

        if (balanceIn < amountIn) {
            revert InsufficientTokenBalance(tokenIn, balanceIn, amountIn);
        }

        // 2. Aprobar Permit2 para transferir tokenIn.

        inputToken.forceApprove(PERMIT2, amountIn);

        // 3. Autorizar Universal Router dentro de Permit2.

        IPermit2Swap permit2 = IPermit2Swap(PERMIT2);

        permit2.approve(
            tokenIn,
            UNIVERSAL_ROUTER,
            uint160(amountIn),
            uint48(block.timestamp + 1 days)
        );

        // 4. Preparar ruta V3.
        bytes memory swapPath;
        if (path.length == 0) {
            (uint24 FEE, uint256 bestAmountOut) = _getBestPoolFee(
                tokenIn,
                tokenOut,
                amountIn
            );
            swapPath = abi.encodePacked(tokenIn, FEE, tokenOut);
        } else {
            swapPath = path;
        }

        uint256 balanceBefore = outputToken.balanceOf(address(this));

        // 5. Codificar V3_SWAP_EXACT_IN.
        bytes memory commands = hex"00";
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(
            address(this),
            amountIn,
            uint256(1),
            swapPath,
            true
        );

        // 6. Ejecutar swap.
        IUniversalRouterSwap(UNIVERSAL_ROUTER).execute(
            commands,
            inputs,
            block.timestamp + 60
        );

        // 7. Calcular salida.
        uint256 balanceAfter = outputToken.balanceOf(address(this));

        if (balanceAfter <= balanceBefore) {
            revert SwapReturnedNoTokens(tokenOut);
        }

        amountOut = balanceAfter - balanceBefore;
    }

    function getLastAddress(bytes memory path) public pure returns (address) {
        require(path.length >= 20, "Path invalido");

        // Lee exactamente 20 bytes iniciando en la posición (longitud total - 20)
        return path.toAddress(path.length - 20);
    }
    function getFirstAddress(bytes memory path) public pure returns (address) {
        require(path.length >= 20, "Path invalido");

        // Lee exactamente 20 bytes iniciando en la posición 0 (el comienzo del path)
        return path.toAddress(0);
    }

    //just for test
    function modifyPosition(uint256 amount, address token) public {
        Position storage positionToken = assetPosition[token];
        positionToken.invested = amount;
    }

    function _getBestPoolFee(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint24 bestFee, uint256 bestAmountOut) {
        uint24[4] memory fees = [
            uint24(100),
            uint24(500),
            uint24(3000),
            uint24(10000)
        ];

        for (uint256 i; i < fees.length; ++i) {
            uint24 fee = fees[i];

            address pool = factory.getPool(tokenIn, tokenOut, fee);

            if (pool == address(0)) continue;

            try
                quoter.quoteExactInputSingle(
                    IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountIn: amountIn,
                        fee: fee,
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 amountOut, uint160, uint32, uint256) {
                if (amountOut > bestAmountOut) {
                    bestAmountOut = amountOut;
                    bestFee = fee;
                }
            } catch {
                continue;
            }
        }

        if (bestAmountOut == 0) {
            revert NoViablePool(tokenIn, tokenOut);
        }
    }
    function getTokenCofig(
        address token
    ) external view returns (AssetConfig memory) {
        return assetConfig[token];
    }

    /*function getAllocation(address token) external view returns (uint256);
    function getAssets() external view returns (AssetConfig[] memory);*/
}
