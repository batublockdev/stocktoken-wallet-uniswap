// SPDX-License-Identifier: MIT

/**
 * @title StockWallet — AI-Managed Investment Wallet
 * @author Batu Block Dev
 * @notice This contract allows an AI agent (adgent) to manage a portfolio of tokens
 *         on behalf of the owner. The adgent invests USDC into predefined assets following
 *         allocation rules set by the owner, with automatic stop-loss and take-profit triggers.
 *         A percentage of each investment goes to the adgent contract so it can operate
 *         independently, and another portion covers gas fees.
 * @dev Uses Uniswap V3 for swaps via Universal Router + Permit2, OpenZeppelin AccessControl
 *      for role-based permissions, and ReentrancyGuard on investment functions.
 *      V4 swaps use PoolManager directly (unlock/callback pattern) with official V4Quoter.
 *      Designed for Celo mainnet (Chain ID 42220).
 */

pragma solidity 0.8.24;

// ============
//   IMPORTS
// ============

import "../lib/solidity-bytes-utils/contracts/BytesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {
    TransientStateLibrary
} from "v4-core/libraries/TransientStateLibrary.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PathKey} from "v4-periphery/libraries/PathKey.sol";
import {IV4Quoter} from "v4-periphery/interfaces/IV4Quoter.sol";

// ==============================
//   INTERFACES, LIBRARIES, CONTRACTS
// ==============================

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

contract StockWallet is
    Ownable,
    AccessControl,
    ReentrancyGuard,
    IUnlockCallback
{
    // ===========
    //   ERRORS
    // ===========

    error StockWallet_PercentagesExceedTotal();
    error NoViablePool(address tokenIn, address tokenOut);
    error TokensEqual(address tokenIn, address tokenOut);
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
    error AddressToReceiveNotCorrect(address token);
    error Permit2AllowanceInsufficient(address token);
    error SwapReturnedNoTokens(address tokenOut);
    error PoolNoExiste(address tokenIn, address tokenOut);
    error StockWallet_Invalid();
    error BadRoute(uint256 customOut, uint256 minAcceptable);
    error NoQuoteAvailable(address tokenIn, address tokenOut);
    error EnforcedPause();
    error EnforcedTradingPause();

    // ====================
    //   TYPE DECLARATIONS
    // ====================

    struct AssetConfig {
        uint256 allocationBps;
        uint16 stopLossBps;
        uint16 takeProfitBps;
    }

    struct Position {
        uint256 amount;
        uint256 invested;
    }

    struct TokenAllocationConfig {
        address token;
        AssetConfig configs;
    }

    /// @notice Parámetros de una pool V4 para un token específico
    struct V4PoolData {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    // =================
    //   STATE VARIABLES
    // =================
    using SafeERC20 for IERC20;
    using BytesLib for bytes;
    using TransientStateLibrary for IPoolManager;

    /// @notice Uniswap V3 Factory used to find pools
    IUniswapV3Factory public immutable factory;

    /// @notice Uniswap V3 Quoter V2 used to get price quotes
    IQuoterV2 public immutable quoter;

    /// @notice Uniswap V4 Quoter for on-chain quotes (replaces manual tick iteration)
    IV4Quoter public immutable quoterV4;

    /// @notice Base token (USDC/USDT) used for all investments
    address public immutable usdc;

    /// @notice Address of the AI agent that executes investment decisions
    address private adgent;

    /// @notice Address of the adgent's contract that receives the agent fee
    address private adgentContract;

    /// @notice Gas fee in basis points (200 = 2%)
    uint256 private gasFee = 200;
    uint256 private slippageBps = 100;

    /// @notice Token used to pay gas fees. address(0) = USDC (default),
    ///         any other address = swap USDC → gasToken before sending to adgent
    address public gasToken;

    /// @notice Percentage of each investment sent to the adgent contract (500 = 5%)
    uint256 private adgentPercentage = 500;

    /// @notice Pause total — bloquea todo excepto withdrawals
    bool public paused;

    /// @notice Pause de trading — bloquea solo invest y selltoken del agente
    bool public tradingPaused;

    /// @notice Array of all active asset tokens
    address[] public assets;

    /// @notice Configuration for each asset (allocation, stop loss, take profit)
    mapping(address => AssetConfig) public assetConfig;

    /// @notice Current position for each asset (amount held, amount invested)
    mapping(address => Position) public assetPosition;

    /// @notice Custom swap paths for each asset
    mapping(address => bytes) public assetPath;

    /// @notice Pools V4 para compra (USDC -> token). Indexadas por token destino.
    mapping(address => V4PoolData[]) public v4BuyPoolsByToken;

    /// @notice Pools V4 para venta (token -> USDC). Indexadas por token origen.
    mapping(address => V4PoolData[]) public v4SellPoolsByToken;

    /// @notice Role identifier for the AI agent
    bytes32 public constant ADGENT_ROLE = keccak256("ADGENT_ROLE");

    /// @notice Total percentage scale: 10_000 = 100%, 1 = 0.01%
    uint16 public constant TOTAL_PERCENTAGE = 10_000;

    /// @notice Uniswap V3 Universal Router address (Celo)
    address public immutable UNIVERSAL_ROUTER;

    /// @notice Permit2 contract address
    address public immutable PERMIT2;

    /// @notice Uniswap V4 PoolManager address (BSC)
    IPoolManager public immutable poolManager;

    /// @notice Uniswap V4 PoolScanner address
    address public immutable v4Scanner;

    // Universal Router commands
    bytes1 constant CMD_V3_SWAP_EXACT_IN = bytes1(0x00);

    // --- V4 Direct Swap State (for unlockCallback) ---
    V4PoolData[] private _v4SwapPools;
    address private _v4SwapTokenIn;
    address private _v4SwapTokenOut;
    uint256 private _v4SwapAmountIn;
    uint256 private _v4SwapMinimumOut;

    // ==========
    //   EVENTS
    // ==========

    event QuoteFailed(
        address indexed tokenIn,
        address indexed tokenOut,
        uint24 fee,
        bytes reason
    );

    event PoolNotFound(address indexed tokenIn, address indexed tokenOut);

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
    event SellTokenByOwner(
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
    event slippageBpsUpdated(
        uint256 indexed oldslippageBps,
        uint256 newslippageBps
    );

    event V4PoolsUpdated(address indexed token, uint256 poolCount);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event TradingPaused(address indexed account);
    event TradingUnpaused(address indexed account);
    event GasTokenUpdated(address indexed oldToken, address indexed newToken);
    event GasSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    // ============
    //   FUNCTIONS
    // ============

    // --- Pause Modifiers ---

    modifier whenNotPaused() {
        if (paused) revert EnforcedPause();
        _;
    }

    modifier whenTradingNotPaused() {
        if (tradingPaused) revert EnforcedTradingPause();
        _;
    }

    // --- Pause Functions ---

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function pauseTrading() external onlyOwner {
        tradingPaused = true;
        emit TradingPaused(msg.sender);
    }

    function unpauseTrading() external onlyOwner {
        tradingPaused = false;
        emit TradingUnpaused(msg.sender);
    }

    // --- Constructor ---

    /**
     * @dev Initializes the StockWallet contract with the base token, Uniswap V3
     *      infrastructure, the AI agent addresses, and the initial asset allocation.
     *      The sum of all allocationBps must equal TOTAL_PERCENTAGE (10_000).
     * @param _usdc Address of the base token (USDC/USDT) used for all investments.
     * @param _factory Uniswap V3 Factory address for pool discovery.
     * @param _universal_router Universal Router address.
     * @param _permit2 Permit2 contract address.
     * @param _quoter Uniswap V3 Quoter V2 address for price quotes.
     * @param _quoterV4 Uniswap V4 Quoter address for V4 quotes.
     * @param _poolManager Uniswap V4 PoolManager address.
     * @param _v4Scanner V4 PoolScanner address.
     * @param _adgent Address of the AI agent that will manage investments.
     * @param _adgentContract Address of the adgent's contract that receives fees.
     * @param _adgentPercentage Percentage of each investment sent to the adgent (in bps).
     * @param _tokenToInvest Array of tokens with their initial allocation configs.
     */
    constructor(
        address _usdc,
        address _factory,
        address _universal_router,
        address _permit2,
        address _quoter,
        address _quoterV4,
        address _poolManager,
        address _v4Scanner,
        address _adgent,
        address _adgentContract,
        uint256 _adgentPercentage,
        TokenAllocationConfig[] memory _tokenToInvest
    ) Ownable(msg.sender) {
        // Set immutables directly in constructor
        factory = IUniswapV3Factory(_factory);
        quoter = IQuoterV2(_quoter);
        quoterV4 = IV4Quoter(_quoterV4);
        UNIVERSAL_ROUTER = _universal_router;
        PERMIT2 = _permit2;
        usdc = _usdc;
        poolManager = IPoolManager(_poolManager);
        v4Scanner = _v4Scanner;
        adgent = _adgent;
        adgentPercentage = _adgentPercentage;
        adgentContract = _adgentContract;

        // Validation + token setup
        if (_tokenToInvest.length == 0) revert StockWallet_Invalid();
        if (
            _usdc == address(0) ||
            _factory == address(0) ||
            _quoter == address(0) ||
            _adgent == address(0) ||
            _adgentContract == address(0)
        ) revert Address_Zero();

        uint256 totalPercentage = 0;
        for (uint256 index = 0; index < _tokenToInvest.length; index++) {
            address addrToken = _tokenToInvest[index].token;
            if (addrToken == address(0) || addrToken == _usdc)
                revert Address_Zero();
            AssetConfig memory newConfig = _tokenToInvest[index].configs;
            assetConfig[addrToken] = newConfig;
            totalPercentage += newConfig.allocationBps;
            if (
                newConfig.takeProfitBps != 0 &&
                newConfig.takeProfitBps < TOTAL_PERCENTAGE
            )
                revert ErrortakeProfitBps_notCorrect(
                    addrToken,
                    newConfig.takeProfitBps
                );
            if (
                newConfig.stopLossBps != 0 &&
                newConfig.stopLossBps > TOTAL_PERCENTAGE
            )
                revert ErrorStopLossBps_notCorrect(
                    addrToken,
                    newConfig.stopLossBps
                );
            uint256 length = assets.length;
            for (uint256 j = 0; j < length; j++) {
                if (assets[j] == addrToken) revert StockWallet_Invalid();
            }
            assets.push(addrToken);
        }
        if (TOTAL_PERCENTAGE != totalPercentage)
            revert StockWallet_PercentagesExceedTotal();

        _grantRole(ADGENT_ROLE, _adgent);
        _grantRole(ADGENT_ROLE, msg.sender);
    }

    // --- External Functions ---

    /**
     * @dev Updates the AI agent address. Revokes the old agent's role and grants
     *      it to the new one. Only the owner can call this function.
     * @param _newAdgent Address of the new AI agent.
     */
    function updateAdgent(address _newAdgent) external onlyOwner {
        if (_newAdgent == address(0)) {
            revert Address_Zero();
        }

        address oldAdgent = adgent;
        _revokeRole(ADGENT_ROLE, adgent);
        _grantRole(ADGENT_ROLE, _newAdgent);
        adgent = _newAdgent;

        emit AgentUpdated(oldAdgent, _newAdgent);
    }

    /**
     * @dev Updates the adgent contract address that receives the agent fee.
     *      Only the owner can call this function.
     * @param _newAdgentContract Address of the new adgent contract.
     */
    function updateAdgentContract(
        address _newAdgentContract
    ) external onlyOwner {
        if (_newAdgentContract == address(0)) {
            revert Address_Zero();
        }

        address oldAdgentContract = adgentContract;
        adgentContract = _newAdgentContract;

        emit AgentContractUpdated(oldAdgentContract, _newAdgentContract);
    }

    function updateslippageBps(uint256 _newslippageBps) external onlyOwner {
        if (_newslippageBps == 0) {
            revert AmountInZero();
        }

        uint256 oldslippageBps = slippageBps;
        slippageBps = _newslippageBps;

        emit slippageBpsUpdated(oldslippageBps, _newslippageBps);
    }

    /**
     * @dev Updates the gas fee percentage charged on each investment.
     *      Only the owner can call this function.
     * @param _newGasFee New gas fee in basis points (e.g. 500 = 5%).
     */
    function updateGasFee(uint256 _newGasFee) external onlyOwner {
        if (_newGasFee == 0) {
            revert AmountInZero();
        }

        uint256 oldGasFee = gasFee;
        gasFee = _newGasFee;

        emit GasFeeUpdated(oldGasFee, _newGasFee);
    }

    /**
     * @dev Sets the token used to pay gas fees to the adgent.
     *      address(0) or usdc = pay in USDC (default, no swap needed).
     *      Any other address = swap USDC → gasToken before sending to adgent.
     *      Only the owner can call this function.
     * @param _gasToken Address of the gas token (e.g. WBNB, WETH, CELO).
     */
    function setGasToken(address _gasToken) external onlyOwner {
        address old = gasToken;
        gasToken = _gasToken;
        emit GasTokenUpdated(old, _gasToken);
    }

    /**
     * @dev Updates the percentage of each investment sent to the adgent contract.
     *      Only the owner can call this function.
     * @param _newPercentage New adgent percentage in basis points (e.g. 100 = 1%).
     */
    function updateAdgentPercentage(uint256 _newPercentage) external onlyOwner {
        if (_newPercentage == 0) {
            revert AmountInZero();
        }

        uint256 oldPercentage = adgentPercentage;
        adgentPercentage = _newPercentage;

        emit AgentPercentageUpdated(oldPercentage, _newPercentage);
    }

    /**
     * @dev Deposits a token into the contract. If the token is not the base
     *      token (USDC), it gets swapped to USDC via Uniswap V3.
     *      The caller must approve the contract to spend the token first.
     * @param _token Address of the token to deposit.
     * @param _amount Amount of tokens to deposit.
     * @param _path Custom Uniswap V3 swap path (empty for auto-detection).
     */
    function depositAsset(
        address _token,
        uint256 _amount,
        bytes calldata _path
    ) external whenNotPaused {
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
            uint256 amountOut = _swap(_token, usdc, _path, _amount, 0, 0);
            emit AssetDeposited(msg.sender, _token, _amount, amountOut);
        } else {
            emit AssetDeposited(msg.sender, _token, _amount, _amount);
        }
    }

    /**
     * @dev Withdraws all balance of a specific token from the contract.
     *      Resets the position for that token. Only the owner can call this.
     * @param _token Address of the token to withdraw.
     */
    function withdrawAsset(address _token) external onlyOwner {
        if (_token == address(0)) {
            revert Address_Zero();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert InsufficientTokenBalance(_token, balance, 1);
        }

        IERC20(_token).safeTransfer(msg.sender, balance);

        Position storage positionToken = assetPosition[_token];
        positionToken.amount = 0;
        positionToken.invested = 0;

        emit AssetWithdrawn(_token, msg.sender, balance);
    }

    function SellAssetOwner(address _token) external onlyOwner {
        if (_token == address(0)) {
            revert Address_Zero();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert InsufficientTokenBalance(_token, balance, 1);
        }

        (uint8 protocol, uint24 fee, uint256 tokenPriceUsdcNow) = _getBestRoute(
            _token,
            usdc,
            balance
        );
        if (fee == 0 && protocol == 0) {
            revert PoolNoExiste(_token, usdc);
        }

        uint256 amountOut = _swap(
            _token,
            usdc,
            bytes(""),
            balance,
            tokenPriceUsdcNow,
            protocol
        );

        Position storage positionToken = assetPosition[_token];
        positionToken.amount = 0;
        positionToken.invested = 0;

        emit SellTokenByOwner(_token, msg.sender, balance);
    }

    /**
     * @dev Withdraws a specific amount of the base token (USDC) from the contract.
     *      Only the owner can call this function.
     * @param _amount Amount of USDC to withdraw.
     */
    function withdrawAssetUsdt(uint256 _amount) external onlyOwner {
        if (_amount == 0) {
            revert AmountInZero();
        }

        IERC20(usdc).safeTransfer(msg.sender, _amount);

        emit UsdcWithdrawn(msg.sender, _amount);
    }

    /**
     * @dev Adds a new asset to the portfolio. If _oldToken is address(0), all
     *      existing assets are re-scaled proportionally to make room for the new one.
     *      If _oldToken is specified, the new token takes allocation from the old one.
     *      Only the owner can call this function.
     * @param _tokenToAdd Configuration of the new token to add.
     * @param _oldToken Address of an existing token to take allocation from (address(0) for re-scale all).
     */
    function addAsset(
        TokenAllocationConfig memory _tokenToAdd,
        address _oldToken
    ) external onlyOwner {
        address _newToken = _tokenToAdd.token;
        uint256 _newAllocationBps = _tokenToAdd.configs.allocationBps;

        if (_newToken == address(0)) {
            revert Address_Zero();
        }
        if (_newAllocationBps == 0 || _newAllocationBps > TOTAL_PERCENTAGE) {
            revert StockWallet_PercentagesExceedTotal();
        }

        // Check for duplicates
        uint256 length = assets.length;
        for (uint256 index = 0; index < length; index++) {
            if (assets[index] == _newToken) {
                revert StockWallet_Invalid();
            }
        }

        if (_oldToken == address(0)) {
            // Re-scale all existing assets proportionally
            uint256 remainingPercentage = TOTAL_PERCENTAGE - _newAllocationBps;
            uint256 sumAdjustedOldAssets = 0;

            for (uint256 index = 0; index < length; index++) {
                AssetConfig storage config = assetConfig[assets[index]];

                if (index == length - 1) {
                    // Last element absorbs rounding dust
                    uint256 lastPercentage = remainingPercentage -
                        sumAdjustedOldAssets;
                    config.allocationBps = lastPercentage;
                    sumAdjustedOldAssets += lastPercentage;
                } else {
                    uint256 itemNewAllocationBps = (config.allocationBps *
                        remainingPercentage) / TOTAL_PERCENTAGE;
                    config.allocationBps = itemNewAllocationBps;
                    sumAdjustedOldAssets += itemNewAllocationBps;
                }
            }

            uint256 totalAllocation = sumAdjustedOldAssets + _newAllocationBps;
            if (totalAllocation != TOTAL_PERCENTAGE) {
                revert StockWallet_PercentagesExceedTotal();
            }
        } else {
            // Take allocation from the old token
            AssetConfig storage oldConfig = assetConfig[_oldToken];
            AssetConfig storage newConfig = assetConfig[_newToken];
            newConfig.allocationBps = _newAllocationBps;

            uint256 newAllocationBpsToReplace = oldConfig.allocationBps -
                _newAllocationBps;
            oldConfig.allocationBps = newAllocationBpsToReplace;
        }

        assetConfig[_newToken] = AssetConfig({
            allocationBps: _newAllocationBps,
            stopLossBps: 0,
            takeProfitBps: 0
        });
        assets.push(_newToken);

        emit AssetAdded(_newToken, _newAllocationBps);
    }

    /**
     * @dev Removes an asset from the portfolio. The remaining assets are
     *      re-scaled to maintain the total allocation at 100%.
     *      Only the owner can call this function.
     * @param _removedToken Address of the token to remove.
     */
    function removeAsset(address _removedToken) external onlyOwner {
        _removeAsset(_removedToken);
    }

    /**
     * @dev Updates the allocation percentage of a specific asset. The remaining
     *      assets are re-scaled proportionally to maintain 100% total allocation.
     *      Only the owner can call this function.
     * @param _token Address of the token to update.
     * @param _newAllocationBps New allocation in basis points.
     */
    function updateAllocation(
        address _token,
        uint256 _newAllocationBps
    ) external onlyOwner {
        uint256 length = assets.length;

        if (_token == address(0)) {
            revert Address_Zero();
        }
        if (_newAllocationBps == 0 || _newAllocationBps > TOTAL_PERCENTAGE) {
            revert StockWallet_PercentagesExceedTotal();
        }

        // Find the token in the assets array
        uint256 tokenIndex = type(uint256).max;
        for (uint256 i = 0; i < length; i++) {
            if (assets[i] == _token) {
                tokenIndex = i;
                break;
            }
        }
        if (tokenIndex == type(uint256).max) {
            revert StockWallet_Invalid();
        }

        AssetConfig storage config = assetConfig[_token];
        uint256 oldAllocationBps = config.allocationBps;

        if (oldAllocationBps == _newAllocationBps) {
            return;
        }

        uint256 remainingPercentage = TOTAL_PERCENTAGE - _newAllocationBps;
        uint256 oldOthersTotal = TOTAL_PERCENTAGE - oldAllocationBps;

        // Single asset case
        if (length == 1) {
            if (_newAllocationBps != TOTAL_PERCENTAGE) {
                revert StockWallet_PercentagesExceedTotal();
            }
            emit AssetAllocationUpdated(
                _token,
                oldAllocationBps,
                _newAllocationBps
            );
            return;
        }

        if (oldOthersTotal == 0 && remainingPercentage > 0) {
            revert StockWallet_PercentagesExceedTotal();
        }

        // Re-scale other assets proportionally
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

        config.allocationBps = _newAllocationBps;

        emit AssetAllocationUpdated(
            _token,
            oldAllocationBps,
            _newAllocationBps
        );
    }

    /**
     * @dev Updates the risk configuration (stop loss and take profit) for a
     *      specific asset. Stop loss must be less than take profit, and both
     *      must be valid (0 or >= TOTAL_PERCENTAGE for TP, 0 or <= TOTAL_PERCENTAGE for SL).
     *      Only the owner can call this function.
     * @param _token Address of the token to update.
     * @param _stopLossBps New stop loss in basis points (e.g. 9500 = 5% loss).
     * @param _takeProfitBps New take profit in basis points (e.g. 11000 = 10% gain).
     */
    function updateRiskConfig(
        address _token,
        uint256 _stopLossBps,
        uint256 _takeProfitBps
    ) external onlyOwner {
        AssetConfig storage config = assetConfig[_token];

        if (config.allocationBps == 0) {
            revert StockWallet_Invalid();
        }
        if (_takeProfitBps != 0 && _takeProfitBps < TOTAL_PERCENTAGE) {
            revert ErrortakeProfitBps_notCorrect(_token, _takeProfitBps);
        }
        if (_stopLossBps != 0 && _stopLossBps > TOTAL_PERCENTAGE) {
            revert ErrorStopLossBps_notCorrect(_token, _stopLossBps);
        }
        if (_stopLossBps >= _takeProfitBps) {
            revert ErrorStopLossBps_notCorrect(_token, _stopLossBps);
        }

        uint16 oldStopLossBps = config.stopLossBps;
        uint16 oldTakeProfitBps = config.takeProfitBps;

        config.stopLossBps = uint16(_stopLossBps);
        config.takeProfitBps = uint16(_takeProfitBps);

        emit AssetRiskConfigUpdated(
            _token,
            oldStopLossBps,
            uint16(_stopLossBps),
            oldTakeProfitBps,
            uint16(_takeProfitBps)
        );
    }

    /**
     * @dev Guarda o actualiza los parámetros de pools V4 para un token específico.
     *      Guarda las pools de compra (USDC -> token) en v4BuyPoolsByToken
     *      y las pools de venta (token -> USDC) en v4SellPoolsByToken (con la ruta invertida).
     *      Solo el owner o el AI agent pueden actualizar.
     * @param _token Address del token destino (ej: NVDAon).
     * @param _pools Array de pools V4 que conforman la ruta USDC -> _token (compra).
     */
    function setV4Pools(
        address _token,
        V4PoolData[] calldata _pools
    ) external onlyRole(ADGENT_ROLE) {
        if (_token == address(0)) revert Address_Zero();
        if (_pools.length == 0) revert StockWallet_Invalid();

        _setV4PoolsInternal(_token, _pools);

        emit V4PoolsUpdated(_token, _pools.length);
    }

    /**
     * @dev Devuelve las pools V4 de compra guardadas para un token.
     * @param _token Address del token destino.
     * @return Array de V4PoolData (ruta de compra: USDC -> token).
     */
    function getV4Pools(
        address _token
    ) external view returns (V4PoolData[] memory) {
        return v4BuyPoolsByToken[_token];
    }

    /**
     * @dev Devuelve las pools V4 de venta guardadas para un token.
     * @param _token Address del token origen.
     * @return Array de V4PoolData (ruta de venta: token -> USDC).
     */
    function getV4SellPools(
        address _token
    ) external view returns (V4PoolData[] memory) {
        return v4SellPoolsByToken[_token];
    }

    /**
     * @dev Sells a specific token if the stop loss or take profit condition is met.
     *      Stop loss: sells all tokens and removes the asset from the portfolio.
     *      Take profit: sells only the profit portion (difference between current
     *      balance and the equivalent of the original investment at current price).
     *      Only the AI agent (ADGENT_ROLE) can call this function.
     * @param _token Address of the token to sell.
     * @param _path Custom swap path (empty for auto-detection).
     * @param _v4Pools V4 pools for the swap route (empty array = use V3 or stored V4 pools).
     */
    function selltoken(
        address _token,
        bytes calldata _path,
        V4PoolData[] calldata _v4Pools
    ) external onlyRole(ADGENT_ROLE) whenNotPaused whenTradingNotPaused {
        // Save V4 pools if provided
        if (_v4Pools.length > 0) {
            _setV4PoolsInternal(_token, _v4Pools);
        }

        // Validate path if provided
        if (_path.length > 0) {
            address tokenToReceive = getLastAddress(_path);
            if (tokenToReceive != usdc) {
                revert AddressToReceiveNotCorrect(tokenToReceive);
            }
        }

        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        if (tokenBalance == 0) {
            revert InsufficientTokenBalance(_token, tokenBalance, 0);
        }

        (uint8 protocol, uint24 fee, uint256 tokenPriceUsdcNow) = _getBestRoute(
            _token,
            usdc,
            tokenBalance
        );
        if (fee == 0 && protocol == 0) {
            revert PoolNoExiste(_token, usdc);
        }

        Position storage position = assetPosition[_token];
        AssetConfig memory config = assetConfig[_token];

        uint256 minimumToLose = (position.invested * config.stopLossBps) /
            TOTAL_PERCENTAGE;
        uint256 minimumToWin = (position.invested * config.takeProfitBps) /
            TOTAL_PERCENTAGE;

        // Stop Loss: sell everything and remove asset
        if (tokenPriceUsdcNow <= minimumToLose) {
            uint256 amountOut = _swap(
                _token,
                usdc,
                _path,
                tokenBalance,
                tokenPriceUsdcNow,
                protocol
            );
            _removeAsset(_token);
            emit StopLossTriggered(
                _token,
                tokenBalance,
                amountOut,
                position.invested
            );
            return;
        }

        // Take Profit: sell only the profit portion
        if (tokenPriceUsdcNow >= minimumToWin) {
            (, , uint256 usdcToToken) = _getBestRoute(
                usdc,
                _token,
                position.invested
            );
            uint256 difference = tokenBalance - usdcToToken;
            uint256 amountOut = _swap(
                _token,
                usdc,
                _path,
                difference,
                0,
                protocol
            );
            position.amount -= difference;
            emit TakeProfitTriggered(
                _token,
                difference,
                amountOut,
                position.invested
            );
            return;
        }

        revert TokenNotReadytoSell(_token);
    }

    /**
     * @dev Sells all assets in the portfolio, converting everything back to USDC.
     *      Resets all positions. Only the owner can call this function.
     * @param _path Array of custom swap paths (empty for auto-detection).
     */
    function selltokenAll(
        bytes[] calldata _path
    ) external onlyOwner whenNotPaused {
        // Store custom paths if provided
        if (_path.length > 0) {
            for (uint256 index = 0; index < _path.length; index++) {
                address tokenToSend = getFirstAddress(_path[index]);
                address tokenToReceive = getLastAddress(_path[index]);
                assetPath[tokenToSend] = _path[index];
                if (tokenToReceive != usdc) {
                    revert AddressToReceiveNotCorrect(tokenToReceive);
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
                continue;
            }

            bytes memory tokenPath = assetPath[token];
            uint256 amountOut = _swap(
                token,
                usdc,
                tokenPath,
                tokenBalance,
                0,
                0
            );

            if (amountOut != 0) {
                delete assetPath[token];
                Position storage positionToken = assetPosition[token];
                positionToken.amount = 0;
                positionToken.invested = 0;
                emit AssetSold(token, tokenBalance, amountOut);
            }
        }
    }

    /**
     * @dev Executes the investment strategy: distributes the available USDC balance
     *      across all configured assets according to their allocation percentages.
     *      A gas fee and an adgent fee are deducted from the total before investing.
     *      Only the AI agent (ADGENT_ROLE) can call this function.
     * @param _path Array of custom swap paths (empty for auto-detection).
     * @param _v4Pools V4 pools for each asset (empty array = use V3 or stored V4 pools).
     */
    function invest(
        bytes[] calldata _path,
        V4PoolData[][] calldata _v4Pools
    )
        external
        nonReentrant
        onlyRole(ADGENT_ROLE)
        whenNotPaused
        whenTradingNotPaused
    {
        // Save V4 pools if provided
        if (_v4Pools.length > 0) {
            for (uint256 i = 0; i < _v4Pools.length && i < assets.length; i++) {
                if (_v4Pools[i].length > 0) {
                    _setV4PoolsInternal(assets[i], _v4Pools[i]);
                }
            }
        }

        uint256 tokenBalance = IERC20(usdc).balanceOf(address(this));
        uint256 amountNotInvested = 0;

        if (tokenBalance == 0) {
            revert InsufficientTokenBalance(usdc, tokenBalance, 0);
        }

        // Calculate fees
        uint256 gasAmount = (tokenBalance * gasFee) / TOTAL_PERCENTAGE;
        uint256 adgentAmount = (tokenBalance * adgentPercentage) /
            TOTAL_PERCENTAGE;
        uint256 amountToInvest = tokenBalance - gasAmount - adgentAmount;

        // Transfer gas fee (via _swapForGas if gasToken is set) and adgent fee
        _swapForGas(gasAmount);
        IERC20(usdc).safeTransfer(adgentContract, adgentAmount);

        // Store custom paths if provided
        uint256 length = assets.length;
        if (_path.length > 0) {
            for (uint256 index = 0; index < _path.length; index++) {
                address tokenToReceive = getLastAddress(_path[index]);
                assetPath[tokenToReceive] = _path[index];
            }
        }

        // Invest in each asset according to its allocation
        for (uint256 index = 0; index < length; index++) {
            address addrTokenOut = assets[index];
            Position storage positionToken = assetPosition[addrTokenOut];
            bytes memory tokenPath = assetPath[addrTokenOut];
            AssetConfig memory config = assetConfig[addrTokenOut];

            uint256 amountIn = (amountToInvest * config.allocationBps) /
                TOTAL_PERCENTAGE;
            uint256 amountOut = _swap(
                usdc,
                addrTokenOut,
                tokenPath,
                amountIn,
                0,
                0 // auto-detect best protocol
            );

            if (amountOut != 0) {
                delete assetPath[addrTokenOut];
                positionToken.amount += amountOut;
                positionToken.invested += amountIn;
                emit AssetPurchased(addrTokenOut, amountIn, amountOut);
            } else {
                amountNotInvested += amountIn;
            }
        }

        emit InvestmentExecuted(
            tokenBalance,
            gasAmount,
            adgentAmount,
            amountToInvest - amountNotInvested
        );
    }

    // --- Internal: Gas Token Swap ---

    /**
     * @dev Swaps USDC → gasToken and sends to adgent.
     *      If gasToken == address(0) or gasToken == usdc → transfer USDC directly (default behavior).
     *      Otherwise → swap USDC → gasToken via best route, then transfer gasToken to adgent.
     * @param _gasAmountUsdc Amount of USDC allocated for gas fees.
     * @return gasTokenAmount Amount of gas token sent to adgent.
     */
    function _swapForGas(
        uint256 _gasAmountUsdc
    ) internal returns (uint256 gasTokenAmount) {
        if (_gasAmountUsdc == 0) return 0;

        // Caso 1: gasToken no seteado o == usdc → transfer directo (comportamiento actual)
        if (gasToken == address(0) || gasToken == usdc) {
            IERC20(usdc).safeTransfer(adgent, _gasAmountUsdc);
            return _gasAmountUsdc;
        }

        // Caso 2: swap USDC → gasToken via best route
        (uint8 protocol, uint24 fee, uint256 expectedOut) = _getBestRoute(
            usdc,
            gasToken,
            _gasAmountUsdc
        );

        if (fee == 0 && protocol == 0) {
            // No hay pool USDC/gasToken → fallback: enviar USDC directo
            IERC20(usdc).safeTransfer(adgent, _gasAmountUsdc);
            emit GasSwapped(usdc, usdc, _gasAmountUsdc, _gasAmountUsdc);
            return _gasAmountUsdc;
        }

        gasTokenAmount = _swap(
            usdc,
            gasToken,
            bytes(""),
            _gasAmountUsdc,
            expectedOut,
            protocol
        );

        // Transfer gasToken al adgent
        IERC20(gasToken).safeTransfer(adgent, gasTokenAmount);

        emit GasSwapped(usdc, gasToken, _gasAmountUsdc, gasTokenAmount);
    }

    // --- Public Functions ---

    /**
     * @dev Extracts the last address from a Uniswap V3 encoded path.
     *      A path is encoded as: address + fee + address + fee + ... + address
     * @param _path The encoded Uniswap V3 path.
     * @return The last address in the path.
     */
    function getLastAddress(bytes memory _path) public pure returns (address) {
        require(_path.length >= 20, "Path invalido");
        return _path.toAddress(_path.length - 20);
    }

    /**
     * @dev Extracts the first address from a Uniswap V3 encoded path.
     * @param _path The encoded Uniswap V3 path.
     * @return The first address in the path.
     */
    function getFirstAddress(bytes memory _path) public pure returns (address) {
        require(_path.length >= 20, "Path invalido");
        return _path.toAddress(0);
    }

    /**
     * @dev Extracts the first fee from a Uniswap V3 encoded path.
     *      Path format: address(20) + fee(3) + address(20) + fee(3) + ...
     * @param _path The encoded Uniswap V3 path.
     * @return The first fee tier in the path.
     */
    function _getFirstFeeFromPath(
        bytes memory _path
    ) internal pure returns (uint24) {
        require(_path.length >= 23, "Path too short for fee");
        return uint24(uint32(_path.toUint32(20)) >> 8);
    }

    // --- Internal Functions ---

    /**
     * @dev Removes an asset from the portfolio: deletes its config, removes it
     *      from the assets array (swap & pop), and re-scales remaining assets
     *      to maintain 100% total allocation.
     * @param _removedToken Address of the token to remove.
     */
    function _removeAsset(address _removedToken) internal {
        uint256 length = assets.length;
        bool isThere = false;

        for (uint256 index = 0; index < length; index++) {
            if (assets[index] == _removedToken) {
                isThere = true;
                break;
            }
        }
        if (!isThere) {
            revert StockWallet_Invalid();
        }

        uint256 removedBps = assetConfig[_removedToken].allocationBps;
        delete assetConfig[_removedToken];

        // Remove from array (swap & pop)
        for (uint256 i = 0; i < length; i++) {
            if (assets[i] == _removedToken) {
                assets[i] = assets[length - 1];
                assets.pop();
                break;
            }
        }

        uint256 newLength = assets.length;
        if (newLength == 0) return;

        // Re-scale remaining assets
        uint256 remainingAssetsOldSumBps = TOTAL_PERCENTAGE - removedBps;
        uint256 sumAdjustedOldAssets = 0;

        for (uint256 index = 0; index < newLength; index++) {
            AssetConfig storage config = assetConfig[assets[index]];

            if (index == newLength - 1) {
                // Last element absorbs rounding dust
                uint256 lastPercentage = TOTAL_PERCENTAGE -
                    sumAdjustedOldAssets;
                config.allocationBps = lastPercentage;
                sumAdjustedOldAssets += lastPercentage;
            } else {
                uint256 itemNewAllocationBps = (config.allocationBps *
                    TOTAL_PERCENTAGE) / remainingAssetsOldSumBps;
                config.allocationBps = itemNewAllocationBps;
                sumAdjustedOldAssets += itemNewAllocationBps;
            }
        }

        if (sumAdjustedOldAssets != TOTAL_PERCENTAGE) {
            revert StockWallet_PercentagesExceedTotal();
        }

        emit AssetRemoved(_removedToken);
    }

    /// @dev Internal helper to save V4 pools without access control (for internal calls).
    ///      Saves buy pools (USDC -> token) as-is in v4BuyPoolsByToken.
    ///      Saves sell pools (token -> USDC) reversed in v4SellPoolsByToken.
    function _setV4PoolsInternal(
        address _token,
        V4PoolData[] calldata _pools
    ) internal {
        if (_token == address(0) || _pools.length == 0) return;

        // Save buy pools (USDC -> token) as-is
        delete v4BuyPoolsByToken[_token];
        for (uint256 i = 0; i < _pools.length; i++) {
            v4BuyPoolsByToken[_token].push(_pools[i]);
        }

        // Save sell pools (token -> USDC) reversed
        delete v4SellPoolsByToken[_token];
        for (uint256 i = _pools.length; i > 0; i--) {
            V4PoolData memory buyPool = _pools[i - 1];
            v4SellPoolsByToken[_token].push(
                V4PoolData({
                    tokenIn: buyPool.tokenOut,
                    tokenOut: buyPool.tokenIn,
                    fee: buyPool.fee,
                    tickSpacing: buyPool.tickSpacing,
                    hooks: buyPool.hooks
                })
            );
        }
    }

    /**
     * @dev Builds a PoolKey from V4PoolData.
     */
    function _buildPoolKey(
        V4PoolData memory data
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

    /**
     * @dev Builds PathKey array from V4PoolData for multi-hop V4 quotes.
     */
    function _buildPathKeys(
        V4PoolData[] storage pools
    ) internal view returns (PathKey[] memory pathKeys, Currency currencyIn) {
        uint256 n = pools.length;
        pathKeys = new PathKey[](n);
        currencyIn = Currency.wrap(pools[0].tokenIn);
        for (uint256 i = 0; i < n; i++) {
            pathKeys[i] = PathKey({
                intermediateCurrency: Currency.wrap(pools[i].tokenOut),
                fee: pools[i].fee,
                tickSpacing: pools[i].tickSpacing,
                hooks: IHooks(pools[i].hooks),
                hookData: bytes("")
            });
        }
    }

    /**
     * @dev Quotes a V4 route using the official V4Quoter contract.
     *      Single-hop: quoteExactInputSingle. Multi-hop: quoteExactInput.
     *      Note: This function is non-view because the V4Quoter performs unlock internally.
     */
    function _quoteV4Route(
        V4PoolData[] storage pools,
        uint256 amountIn
    ) internal returns (uint256 totalAmountOut) {
        if (pools.length == 0) return 0;
        if (address(quoterV4) == address(0)) return 0;
        if (address(poolManager) == address(0)) return 0;

        if (pools.length == 1) {
            PoolKey memory key = _buildPoolKey(pools[0]);
            bool zeroForOne = pools[0].tokenIn < pools[0].tokenOut;
            try
                quoterV4.quoteExactInputSingle(
                    IV4Quoter.QuoteExactSingleParams({
                        poolKey: key,
                        zeroForOne: zeroForOne,
                        exactAmount: uint128(amountIn),
                        hookData: bytes("")
                    })
                )
            returns (uint256 amountOut, uint256) {
                totalAmountOut = amountOut;
            } catch {
                return 0;
            }
        } else {
            (PathKey[] memory pathKeys, Currency currencyIn) = _buildPathKeys(
                pools
            );
            try
                quoterV4.quoteExactInput(
                    IV4Quoter.QuoteExactParams({
                        exactCurrency: currencyIn,
                        path: pathKeys,
                        exactAmount: uint128(amountIn)
                    })
                )
            returns (uint256 amountOut, uint256) {
                totalAmountOut = amountOut;
            } catch {
                return 0;
            }
        }
    }

    /**
     * @dev Compares V3 and V4 routes and returns the best one.
     *      V3: iterates fee tiers [100, 500, 3000, 10000] via factory + quoter.
     *      V4: if _tokenIn == usdc, reads buy pools (v4BuyPoolsByToken[_tokenOut]);
     *          otherwise reads sell pools (v4SellPoolsByToken[_tokenIn]).
     * @return protocol 0=V3, 1=V4.
     * @return fee V3 fee tier (if V3 wins) or 0 (if V4 wins).
     * @return amountOut Best output amount.
     */
    function _getBestRoute(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal returns (uint8 protocol, uint24 fee, uint256 amountOut) {
        // --- V3 Quote ---
        uint24 v3BestFee;
        uint256 v3BestAmountOut;

        uint24[4] memory v3Fees = [
            uint24(100),
            uint24(500),
            uint24(3000),
            uint24(10000)
        ];
        uint24 fallbackFee;
        bool hasValidPool = false;

        for (uint256 i = 0; i < v3Fees.length; ++i) {
            uint24 f = v3Fees[i];
            address pool = factory.getPool(_tokenIn, _tokenOut, f);
            if (pool == address(0) || pool.code.length == 0) continue;
            if (IUniswapV3Pool(pool).liquidity() == 0) continue;

            if (!hasValidPool) {
                fallbackFee = f;
                hasValidPool = true;
            }

            try
                quoter.quoteExactInputSingle(
                    IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: _tokenIn,
                        tokenOut: _tokenOut,
                        amountIn: _amountIn,
                        fee: f,
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 amountOut_, uint160, uint32, uint256) {
                if (amountOut_ > v3BestAmountOut) {
                    v3BestAmountOut = amountOut_;
                    v3BestFee = f;
                }
            } catch (bytes memory reason) {
                emit QuoteFailed(_tokenIn, _tokenOut, f, reason);
            }
        }

        if (v3BestAmountOut == 0 && hasValidPool) {
            v3BestFee = fallbackFee;
        }

        // --- V4 Quote ---
        // If buying (USDC -> token), use buy pools indexed by tokenOut
        // If selling (token -> USDC), use sell pools indexed by tokenIn
        V4PoolData[] storage v4Pools;
        if (_tokenIn == usdc) {
            v4Pools = v4BuyPoolsByToken[_tokenOut];
        } else {
            v4Pools = v4SellPoolsByToken[_tokenIn];
        }

        uint256 v4AmountOut;
        if (v4Pools.length > 0 && address(poolManager) != address(0)) {
            v4AmountOut = _quoteV4Route(v4Pools, _amountIn);
        }

        // --- Compare ---
        if (v3BestAmountOut >= v4AmountOut && v3BestAmountOut > 0) {
            return (0, v3BestFee, v3BestAmountOut); // V3 wins
        } else if (v4AmountOut > 0) {
            return (1, 0, v4AmountOut); // V4 wins
        } else if (v3BestAmountOut > 0) {
            return (0, v3BestFee, v3BestAmountOut); // V3 fallback
        }

        emit PoolNotFound(_tokenIn, _tokenOut);
        return (0, 0, 0); // No pool found
    }

    /**
     * @dev Executes a token swap via Uniswap V3 (Universal Router) or V4 (PoolManager direct).
     *      If _protocol is 0 and _path is empty, auto-detects best route (V3 vs V4).
     *      If _protocol is 1, uses V4 with stored V4 pools.
     * @param _tokenIn Input token address.
     * @param _tokenOut Output token address.
     * @param _path Custom V3 swap path (empty for auto-detection).
     * @param _amountIn Input amount.
     * @param _amountOut Expected output (for slippage). 0 = auto-detect.
     * @param _protocol 0=V3, 1=V4, use 0 for auto-detect when path is empty.
     * @return amountOut Output amount received.
     */
    function _swap(
        address _tokenIn,
        address _tokenOut,
        bytes memory _path,
        uint256 _amountIn,
        uint256 _amountOut,
        uint8 _protocol
    ) internal returns (uint256 amountOut) {
        if (_tokenIn == _tokenOut) {
            revert TokensEqual(_tokenIn, _tokenOut);
        }
        if (_tokenIn == address(0) || _tokenOut == address(0)) {
            revert Address_Zero();
        }
        if (_amountIn == 0) revert AmountInZero();

        IERC20 inputToken = IERC20(_tokenIn);
        IERC20 outputToken = IERC20(_tokenOut);

        // Verify input balance
        uint256 balanceIn = inputToken.balanceOf(address(this));
        if (balanceIn < _amountIn) {
            revert InsufficientTokenBalance(_tokenIn, balanceIn, _amountIn);
        }

        // Determine route: auto-detect or use provided path/protocol
        uint8 useProtocol = _protocol;
        uint24 bestFee;
        uint256 bestAmountOut;

        // Always quote the best route to know the expected output (security: prevents bad/sandwich routes)
        (
            uint8 bestRouteProtocol,
            uint24 bestRouteFee,
            uint256 bestRouteAmountOut
        ) = _getBestRoute(_tokenIn, _tokenOut, _amountIn);
        bestAmountOut = bestRouteAmountOut;

        if (_path.length == 0) {
            // Auto-detect: use the best route found
            useProtocol = bestRouteProtocol;
            bestFee = bestRouteFee;
            if (bestFee == 0 && useProtocol == 0) {
                return 0;
            }
        } else if (_protocol == 0) {
            // V3 path provided by agent — validate it's not worse than 90% of best route
            useProtocol = 0;
            if (bestAmountOut > 0) {
                // Quote the custom path via V3 quoter to compare
                try
                    quoter.quoteExactInputSingle(
                        IQuoterV2.QuoteExactInputSingleParams({
                            tokenIn: _tokenIn,
                            tokenOut: _tokenOut,
                            amountIn: _amountIn,
                            fee: _getFirstFeeFromPath(_path),
                            sqrtPriceLimitX96: 0
                        })
                    )
                returns (uint256 customAmountOut, uint160, uint32, uint256) {
                    uint256 minAcceptable = (bestAmountOut * 9000) / 10000;
                    if (customAmountOut < minAcceptable) {
                        revert BadRoute(customAmountOut, minAcceptable);
                    }
                } catch {}
            }
        }

        // Prepare V3 swap path if needed
        bytes memory swapPath;
        if (useProtocol == 0) {
            if (_path.length == 0) {
                swapPath = abi.encodePacked(_tokenIn, bestFee, _tokenOut);
            } else {
                swapPath = _path;
            }
        }

        // Calculate minimum output for slippage protection (never hardcode to 1)
        uint256 balanceBefore = outputToken.balanceOf(address(this));

        uint256 minimumOut;
        if (_amountOut != 0) {
            minimumOut = calculateMinimumOut(_amountOut);
        } else if (bestAmountOut != 0) {
            minimumOut = calculateMinimumOut(bestAmountOut);
        } else {
            // No quote available — refuse to swap with no protection
            revert NoQuoteAvailable(_tokenIn, _tokenOut);
        }

        if (useProtocol == 0) {
            // --- V3 Swap via Universal Router ---
            inputToken.forceApprove(PERMIT2, _amountIn);

            IPermit2Swap permit2 = IPermit2Swap(PERMIT2);
            permit2.approve(
                _tokenIn,
                UNIVERSAL_ROUTER,
                uint160(_amountIn),
                uint48(block.timestamp + 1 days)
            );

            bytes memory commands = abi.encodePacked(CMD_V3_SWAP_EXACT_IN);
            bytes[] memory inputs = new bytes[](1);

            inputs[0] = abi.encode(
                address(this),
                _amountIn,
                minimumOut,
                swapPath,
                true // payerIsUser
            );

            IUniversalRouterSwap(UNIVERSAL_ROUTER).execute(
                commands,
                inputs,
                block.timestamp + 60
            );
        } else if (useProtocol == 1) {
            // --- V4 Swap via PoolManager direct ---
            // Select pools: if buying (USDC -> token), use buy pools; if selling, use sell pools
            V4PoolData[] storage v4Pools;
            if (_tokenIn == usdc) {
                v4Pools = v4BuyPoolsByToken[_tokenOut];
            } else {
                v4Pools = v4SellPoolsByToken[_tokenIn];
            }
            if (v4Pools.length == 0) {
                return 0;
            }

            _executeV4Swap(_tokenIn, _tokenOut, _amountIn, minimumOut, v4Pools);
        } else {
            return 0;
        }

        // Calculate output amount
        uint256 balanceAfter = outputToken.balanceOf(address(this));
        if (balanceAfter <= balanceBefore) {
            revert SwapReturnedNoTokens(_tokenOut);
        }

        amountOut = balanceAfter - balanceBefore;
    }

    /**
     * @dev Executes a V4 swap via PoolManager directly (no Universal Router).
     *      Sets state vars, calls poolManager.unlock(), unlockCallback does swap+settle+take.
     */
    function _executeV4Swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minimumOut,
        V4PoolData[] storage v4Pools
    ) internal {
        uint256 n = v4Pools.length;
        V4PoolData[] memory poolsMem = new V4PoolData[](n);
        for (uint256 i = 0; i < n; i++) {
            poolsMem[i] = v4Pools[i];
        }

        _v4SwapPools = poolsMem;
        _v4SwapTokenIn = _tokenIn;
        _v4SwapTokenOut = _tokenOut;
        _v4SwapAmountIn = _amountIn;
        _v4SwapMinimumOut = _minimumOut;

        IERC20(_tokenIn).forceApprove(address(poolManager), _amountIn);

        poolManager.unlock("");

        // Cleanup state
        delete _v4SwapPools;
        _v4SwapTokenIn = address(0);
        _v4SwapTokenOut = address(0);
        _v4SwapAmountIn = 0;
        _v4SwapMinimumOut = 0;
    }

    /**
     * @dev Called by PoolManager during unlock. Executes swap sequence:
     *      1. For each hop: poolManager.swap()
     *      2. Settle input token (sync + transfer + settle)
     *      3. Take output token (currencyDelta + take)
     */
    function unlockCallback(
        bytes calldata
    ) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Not PoolManager");

        V4PoolData[] memory pools = _v4SwapPools;
        uint256 n = pools.length;
        uint256 currentAmount = _v4SwapAmountIn;

        for (uint256 i = 0; i < n; i++) {
            PoolKey memory key = _buildPoolKey(pools[i]);
            bool zeroForOne = pools[i].tokenIn < pools[i].tokenOut;

            BalanceDelta delta = poolManager.swap(
                key,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(currentAmount),
                    sqrtPriceLimitX96: zeroForOne
                        ? TickMath.MIN_SQRT_PRICE + 1
                        : TickMath.MAX_SQRT_PRICE - 1
                }),
                bytes("")
            );

            if (zeroForOne) {
                currentAmount = uint128(delta.amount1());
            } else {
                currentAmount = uint128(delta.amount0());
            }
        }

        require(currentAmount >= _v4SwapMinimumOut, "V4: too little received");

        // Settle: sync input, transfer to PoolManager, settle
        Currency inputCurrency = Currency.wrap(_v4SwapTokenIn);
        poolManager.sync(inputCurrency);
        IERC20(_v4SwapTokenIn).safeTransfer(
            address(poolManager),
            _v4SwapAmountIn
        );
        poolManager.settle();

        // Take: read actual credit from PoolManager
        Currency outputCurrency = Currency.wrap(_v4SwapTokenOut);
        int256 credit = poolManager.currencyDelta(
            address(this),
            outputCurrency
        );
        require(credit > 0, "V4: no credit");
        poolManager.take(outputCurrency, address(this), uint256(credit));

        return "";
    }

    // --- View & Pure Functions ---
    function calculateMinimumOut(
        uint256 expectedOut
    ) public view returns (uint256) {
        return
            (expectedOut * (TOTAL_PERCENTAGE - slippageBps)) / TOTAL_PERCENTAGE;
    }

    /**
     * @dev Returns the full configuration for a given asset.
     * @param _token Address of the token to query.
     * @return AssetConfig struct containing allocation, stop loss, and take profit.
     */
    function getTokenConfig(
        address _token
    ) external view returns (AssetConfig memory) {
        return assetConfig[_token];
    }

    // ============================================================
    // === TEST ONLY FUNCTIONS — ELIMINAR ANTES DE PRODUCCIÓN ===
    // ============================================================
    // Las siguientes funciones existen únicamente para facilitar testing
    // de selltoken() (stop-loss y take-profit) sin depender de movimientos
    // reales del mercado. Permiten setear manualmente el position.invested
    // y position.amount para simular escenarios de precio.
    //
    // ⚠️ ADVERTENCIA: Estas funciones NO deben ir a mainnet.
    // Cualquiera puede llamarlas y manipular las posiciones.
    // En producción, eliminar o envolver en un modifier que verifique
    // que el caller es el owner y el contrato está en modo test.
    // ============================================================

    /**
     * @dev TEST ONLY — Setea manualmente la posición de un token.
     *      Permite simular que el precio subió o bajó para testear
     *      selltoken() con triggers de stop-loss y take-profit.
     *
     *      Casos de uso en testing:
     *      - Stop-loss: setear _invested alto relativo al _amount
     *        para que tokenPriceUsdcNow <= minimumToLose
     *      - Take-profit: setear _invested bajo relativo al _amount
     *        para que tokenPriceUsdcNow >= minimumToWin
     *
     * @param _token Address del token cuya posición se quiere modificar.
     * @param _amount Cantidad de tokens que la wallet "tiene".
     * @param _invested Cantidad de USDC que se "invirtió" originalmente.
     *
     * ⚠️ ELIMINAR EN PRODUCCIÓN
     */
    function __testSetPosition(
        address _token,
        uint256 _amount,
        uint256 _invested
    ) external {
        assetPosition[_token] = Position({
            amount: _amount,
            invested: _invested
        });
    }

    /**
     * @dev TEST ONLY — Setea manualmente el balance de un token en la wallet.
     *      Útil cuando se quiere testear selltoken() sin haber hecho invest()
     *      previamente. Usa deal() de forge para mintear tokens reales.
     *
     *      En tests de fork de BSC, usar vm.deal o deal() de forge-std
     *      para mintear tokens reales on-chain, y luego usar esta función
     *      para setear la posición contable.
     *
     * @param _token Address del token.
     * @param _amount Cantidad de tokens a setear como balance.
     * @param _invested Cantidad de USDC "invertida".
     *
     * ⚠️ ELIMINAR EN PRODUCCIÓN
     */
    function __testFundAndSetPosition(
        address _token,
        uint256 _amount,
        uint256 _invested
    ) external {
        // Setear la posición contable
        assetPosition[_token] = Position({
            amount: _amount,
            invested: _invested
        });
    }
}
