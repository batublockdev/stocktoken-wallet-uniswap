// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from "../lib/forge-std/src/Script.sol";
import {StockWallet} from "../src/StockWallet.sol";
contract DeployContract is Script {
    address public sender;
    /**
        @dev This funtion is setup in the script to deploy the contract
        @param "currencyAddress" this is the token address like "usdc, usdt"
        @param "amount" this is the amount per mounth to be provided by users
        @param "periods_claim" this var define the amount of periods for a user to claim the turn
     */
    /**function run(
        address currencyAddress,
        uint256 amount,
        uint16 periods_claim
    ) external returns (StockWallet, address) {
        vm.startBroadcast();
        sender = msg.sender;
        StockWallet ContactStockWallet = new StockWallet(
            currencyAddress,
            amount,
            periods_claim
        );
        vm.stopBroadcast();
        return (ContactStockWallet, sender);
    }*/
}
