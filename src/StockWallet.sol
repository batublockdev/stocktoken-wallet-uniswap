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
 *      Designed for Celo mainnet (Chain ID 42220).
 */

pragma solidity ^0.8.20;

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

contract StockWallet is Ownable, AccessControl, ReentrancyGuard {
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

    // =================
    //   STATE VARIABLES
    // =================
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    /// @notice Uniswap V3 Factory used to find pools
    IUniswapV3Factory public immutable factory;

    /// @notice Uniswap V3 Quoter V2 used to get price quotes
    IQuoterV2 public immutable quoter;

    /// @notice Base token (USDC/USDT) used for all investments
    address public immutable usdc;

    /// @notice Address of the AI agent that executes investment decisions
    address private adgent;

    /// @notice Address of the adgent's contract that receives the agent fee
    address private adgentContract;

    /// @notice Gas fee in basis points (200 = 2%)
    uint256 private gasFee = 200;

    /// @notice Percentage of each investment sent to the adgent contract (500 = 5%)
    uint256 private adgentPercentage = 500;

    /// @notice Array of all active asset tokens
    address[] public assets;

    /// @notice Configuration for each asset (allocation, stop loss, take profit)
    mapping(address => AssetConfig) public assetConfig;

    /// @notice Current position for each asset (amount held, amount invested)
    mapping(address => Position) public assetPosition;

    /// @notice Custom swap paths for each asset
    mapping(address => bytes) public assetPath;

    /// @notice Role identifier for the AI agent
    bytes32 public constant ADGENT_ROLE = keccak256("ADGENT_ROLE");

    /// @notice Total percentage scale: 10_000 = 100%, 1 = 0.01%
    uint16 public constant TOTAL_PERCENTAGE = 10_000;

    /// @notice Uniswap V3 Universal Router address (Celo)
    address constant UNIVERSAL_ROUTER =
        0x643770E279d5D0733F21d6DC03A8efbABf3255B4;

    /// @notice Permit2 contract address
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

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

    // ============
    //   FUNCTIONS
    // ============

    // --- Constructor ---

    /**
     * @dev Initializes the StockWallet contract with the base token, Uniswap V3
     *      infrastructure, the AI agent addresses, and the initial asset allocation.
     *      The sum of all allocationBps must equal TOTAL_PERCENTAGE (10_000).
     * @param _usdc Address of the base token (USDC/USDT) used for all investments.
     * @param _factory Uniswap V3 Factory address for pool discovery.
     * @param _quoter Uniswap V3 Quoter V2 address for price quotes.
     * @param _adgent Address of the AI agent that will manage investments.
     * @param _adgentContract Address of the adgent's contract that receives fees.
     * @param _adgentPercentage Percentage of each investment sent to the adgent (in bps).
     * @param _tokenToInvest Array of tokens with their initial allocation configs.
     */
    constructor(
        address _usdc,
        address _factory,
        address _quoter,
        address _adgent,
        address _adgentContract,
        uint256 _adgentPercentage,
        TokenAllocationConfig[] memory _tokenToInvest
    ) Ownable(msg.sender) {
        if (_tokenToInvest.length == 0) {
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

        uint256 totalPercentage = 0;

        for (uint256 index = 0; index < _tokenToInvest.length; index++) {
            address addrToken = _tokenToInvest[index].token;

            if (addrToken == address(0) || addrToken == _usdc) {
                revert Address_Zero();
            }

            AssetConfig memory newConfig = _tokenToInvest[index].configs;
            assetConfig[addrToken] = newConfig;
            totalPercentage += newConfig.allocationBps;

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

            // Check for duplicate tokens
            uint256 length = assets.length;
            for (uint256 j = 0; j < length; j++) {
                if (assets[j] == addrToken) {
                    revert StockWallet_Invalid();
                }
            }

            assets.push(addrToken);
        }

        if (TOTAL_PERCENTAGE != totalPercentage) {
            revert StockWallet_PercentagesExceedTotal();
        }

        factory = IUniswapV3Factory(_factory);
        quoter = IQuoterV2(_quoter);
        usdc = _usdc;
        adgent = _adgent;
        adgentPercentage = _adgentPercentage;
        adgentContract = _adgentContract;

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
            uint256 amountOut = _swap(_token, usdc, _path, _amount);
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
     * @dev Sells a specific token if the stop loss or take profit condition is met.
     *      Stop loss: sells all tokens and removes the asset from the portfolio.
     *      Take profit: sells only the profit portion (difference between current
     *      balance and the equivalent of the original investment at current price).
     *      Only the AI agent (ADGENT_ROLE) can call this function.
     * @param _token Address of the token to sell.
     * @param _path Custom swap path (empty for auto-detection).
     */
    function selltoken(
        address _token,
        bytes calldata _path
    ) external onlyRole(ADGENT_ROLE) {
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

        (uint24 fee, uint256 tokenPriceUsdcNow) = _getBestPoolFee(
            _token,
            usdc,
            tokenBalance
        );
        if (fee == 0) {
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
            uint256 amountOut = _swap(_token, usdc, _path, tokenBalance);
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
            (, uint256 usdcToToken) = _getBestPoolFee(
                usdc,
                _token,
                position.invested
            );
            uint256 difference = tokenBalance - usdcToToken;
            uint256 amountOut = _swap(_token, usdc, _path, difference);
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
    function selltokenAll(bytes[] calldata _path) external onlyOwner {
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
            uint256 amountOut = _swap(token, usdc, tokenPath, tokenBalance);

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
     */
    function invest(
        bytes[] calldata _path
    ) external nonReentrant onlyRole(ADGENT_ROLE) {
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

        // Transfer gas and adgent fees
        IERC20(usdc).safeTransfer(adgent, gasAmount);
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
            uint256 amountOut = _swap(usdc, addrTokenOut, tokenPath, amountIn);

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

    // just for test
    /**
     * @dev Modifies the position of a token.
     * @param amount The new amount to set.
     * @param token The address of the token.
     */
    /*function modifyPosition(uint256 amount, address token) public {
        Position storage positionToken = assetPosition[token];
        positionToken.invested = amount;
    }*/

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

    /**
     * @dev Executes a token swap via Uniswap V3 Universal Router using Permit2
     *      for token approval. If no path is provided, auto-detects the best
     *      pool fee tier by querying all available fee tiers.
     * @param _tokenIn Address of the input token.
     * @param _tokenOut Address of the output token.
     * @param _path Custom swap path (empty for auto-detection).
     * @param _amountIn Amount of input tokens to swap.
     * @return amountOut Amount of output tokens received.
     */
    function _swap(
        address _tokenIn,
        address _tokenOut,
        bytes memory _path,
        uint256 _amountIn
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

        // Approve Permit2 to transfer input tokens
        inputToken.forceApprove(PERMIT2, _amountIn);

        // Authorize Universal Router within Permit2
        IPermit2Swap permit2 = IPermit2Swap(PERMIT2);
        permit2.approve(
            _tokenIn,
            UNIVERSAL_ROUTER,
            uint160(_amountIn),
            uint48(block.timestamp + 1 days)
        );

        // Prepare swap path
        bytes memory swapPath;
        if (_path.length == 0) {
            (uint24 fee, uint256 bestAmountOut) = _getBestPoolFee(
                _tokenIn,
                _tokenOut,
                _amountIn
            );
            if (fee == 0 || bestAmountOut == 0) {
                return (0);
            }
            swapPath = abi.encodePacked(_tokenIn, fee, _tokenOut);
        } else {
            swapPath = _path;
        }

        // Execute swap via Universal Router
        uint256 balanceBefore = outputToken.balanceOf(address(this));

        bytes memory commands = hex"00"; // V3_SWAP_EXACT_IN
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(this),
            _amountIn,
            uint256(1), // amountOutMinimum
            swapPath,
            true // payerIsUser
        );

        IUniversalRouterSwap(UNIVERSAL_ROUTER).execute(
            commands,
            inputs,
            block.timestamp + 60
        );

        // Calculate output amount
        uint256 balanceAfter = outputToken.balanceOf(address(this));
        if (balanceAfter <= balanceBefore) {
            revert SwapReturnedNoTokens(_tokenOut);
        }

        amountOut = balanceAfter - balanceBefore;
    }

    /**
     * @dev Finds the best Uniswap V3 pool fee tier for a given token pair by
     *      querying all available fee tiers (100, 500, 3000, 10000) and selecting
     *      the one that returns the highest output amount.
     * @param _tokenIn Address of the input token.
     * @param _tokenOut Address of the output token.
     * @param _amountIn Amount of input tokens to quote.
     * @return bestFee The best fee tier found.
     * @return bestAmountOut The best output amount found.
     */
    function _getBestPoolFee(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal returns (uint24 bestFee, uint256 bestAmountOut) {
        uint24[4] memory fees = [
            uint24(100),
            uint24(500),
            uint24(3000),
            uint24(10000)
        ];

        uint24 fallbackFee;
        bool hasValidPool = false;

        for (uint256 i = 0; i < fees.length; ++i) {
            uint24 fee = fees[i];

            address pool = factory.getPool(_tokenIn, _tokenOut, fee);
            if (pool == address(0) || pool.code.length == 0) {
                continue;
            }
            if (IUniswapV3Pool(pool).liquidity() == 0) {
                continue;
            }

            // Save first valid pool as fallback
            if (!hasValidPool) {
                fallbackFee = fee;
                hasValidPool = true;
            }

            // Try to quote
            try
                quoter.quoteExactInputSingle(
                    IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: _tokenIn,
                        tokenOut: _tokenOut,
                        amountIn: _amountIn,
                        fee: fee,
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 amountOut, uint160, uint32, uint256) {
                if (amountOut > bestAmountOut) {
                    bestAmountOut = amountOut;
                    bestFee = fee;
                }
            } catch (bytes memory reason) {
                emit QuoteFailed(_tokenIn, _tokenOut, fee, reason);
            }
        }

        // Use fallback if no quote succeeded
        if (bestAmountOut == 0) {
            if (!hasValidPool) {
                emit PoolNotFound(_tokenIn, _tokenOut);
                return (0, 0);
            }
            bestFee = fallbackFee;
        }
    }

    // --- View & Pure Functions ---

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
}
