//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";

interface IFactory {
    function getPool(address a, address b, uint24 fee) external view returns (address);
}
interface IPool {
    function liquidity() external view returns (uint128);
}

contract DebugPools is Test {
    IFactory constant F = IFactory(0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7);
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant GOOGLE = 0x3F53De71c126BdaBAe20f9cD64848d317f6C3238;
    address constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function setUp() public {
        vm.createSelectFork("https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6", 133660000);
    }

    function test_pools() public {
        uint24[4] memory f = [uint24(100), 500, 3000, 10000];
        _c("USDT-GOOGLE", USDT, GOOGLE, f);
        _c("WBNB-GOOGLE", WBNB, GOOGLE, f);
        _c("USDT-ETH", USDT, ETH, f);
    }

    function _c(string memory s, address a, address b, uint24[4] memory f) internal {
        console.log(s);
        for (uint i = 0; i < 4; i++) {
            address p = F.getPool(a, b, f[i]);
            if (p == address(0)) { console.log("  fee", f[i], "NO"); }
            else { console.log("  fee", f[i], "liq", uint256(IPool(p).liquidity())); }
        }
    }
}
