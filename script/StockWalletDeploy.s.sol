//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {console2} from "forge-std/console2.sol";
import {
    WETH,
    WBTC,
    USDT,
    XAUt0,
    PLAST,
    WBRL,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER
} from "../test/ConstantsCelo.sol";
contract deployStockWalletScript is Script {
    function run() external {
        deployStockWallet();
    }

    function setConfig(
        uint256 allocationBps,
        uint16 stopLossBps,
        uint16 takeProfitBps,
        address token
    )
        public
        returns (StockWallet.TokenAllocationConfig memory tokenAllocation)
    {
        StockWallet.AssetConfig memory configx1 = StockWallet.AssetConfig({
            allocationBps: allocationBps,
            stopLossBps: stopLossBps,
            takeProfitBps: takeProfitBps
        });

        StockWallet.TokenAllocationConfig memory tokenConfigx1 = StockWallet
            .TokenAllocationConfig({token: token, configs: configx1});

        return tokenConfigx1;
    }

    function deployStockWallet() public returns (StockWallet) {
        //OWNER: 0x5CE3bA750E63Bd990876Ed504cE2B2A6f21DA06f
        address sender = 0x5CE3bA750E63Bd990876Ed504cE2B2A6f21DA06f;
        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](2);

        tokenAllocation[0] = setConfig(5000, 8000, 11000, WBTC);
        tokenAllocation[1] = setConfig(5000, 9500, 11000, WETH);
        console2.log("Sender: %s", sender);
        vm.startBroadcast(sender);
        StockWallet stockWallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNISWAP_V3_QUOTER,
            address(0xf43ea1700E117e9c456690514Db9C5b1405EC5E5),
            address(0x74E16132B76Af0B03730F5c4BF540D777b085DDc),
            2000,
            tokenAllocation
        );
        vm.stopBroadcast();
        return (stockWallet);
    }
}
