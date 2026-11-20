//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {console2} from "forge-std/console2.sol";

/// @title DeployScannerBnb - Deploy standalone del UniswapV4PoolScanner en BNB Chain
/// @notice Solo deploya el scanner, no el StockWallet
contract DeployScannerBnb is Script {
    // V4 PoolManager en BSC mainnet
    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;

    function run() external {
        address sender = msg.sender;
        console2.log("=== Deploy UniswapV4PoolScanner BNB Chain ===");
        console2.log("Sender: %s", sender);
        console2.log("PoolManager: %s", POOL_MANAGER);

        vm.startBroadcast(sender);

        UniswapV4PoolScanner scanner = new UniswapV4PoolScanner(POOL_MANAGER);

        vm.stopBroadcast();

        console2.log("=== Deploy completo ===");
        console2.log("UniswapV4PoolScanner: %s", address(scanner));
        console2.log("Owner: %s", sender);

        // Verificacion on-chain post-deploy
        console2.log("--- Verificacion ---");
        console2.log("PoolManager almacenado: %s", address(scanner.poolManager()));
        console2.log("MAX_CANDIDATES: %s", scanner.MAX_CANDIDATES());
    }
}
