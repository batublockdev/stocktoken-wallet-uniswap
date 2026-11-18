// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ============================================================
//   BNB Chain (BSC Mainnet) — Chain ID 56
//   Tokens Pegged de Binance + Ondo Finance + Uniswap V3
// ============================================================

// ============================================================
//   TOKENS PEGGED DE BINANCE
// ============================================================

address constant BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c; // 18 dec — Bitcoin pegged
address constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8; // 18 dec — Ethereum pegged
address constant USDT = 0x55d398326f99059fF775485246999027B3197955; // 18 dec — Binance-Peg USDT
address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // 18 dec — Binance-Peg USDC
address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // 18 dec — Binance-Peg BUSD (⚠️ DEPRECATED pero contrato activo)
address constant DAI = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3; // 18 dec — Binance-Peg DAI
address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // 18 dec — Wrapped BNB

// --- Crypto majors ---
address constant GANG = 0x0c6302401aa5325C2E36F170f52C00B1d220B405;
address constant GOOGLE = 0x3F53De71c126BdaBAe20f9cD64848d317f6C3238;

address constant LINK = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD; // 18 dec — Binance-Peg LINK
address constant MATIC = 0xCC42724C6683B7E57334c4E856f4c9965ED682bD; // 18 dec — Binance-Peg MATIC (POL)
address constant AAVE = 0xfb6115445Bff7b52FeB98650C87f44907E58f802; // 18 dec — Binance-Peg AAVE
address constant DOT = 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402; // 18 dec — Binance-Peg DOT
address constant ADA = 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47; // 18 dec — Binance-Peg ADA
address constant XRP = 0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE; // 18 dec — Binance-Peg XRP
address constant LTC = 0x4338665CBB7B2485A8855A139b75D5e34AB0DB94; // 18 dec — Binance-Peg LTC
address constant BCH = 0x8fF795a6F4D97E7887C79beA79aba5cc76444aDf; // 18 dec — Binance-Peg BCH
address constant SOL = 0x570A5D26f7765Ecb712C0924E4De545B89fD43dF; // 18 dec — Binance-Peg SOL
address constant ATOM = 0x0Eb3a705fc54725037CC9e008bDede697f62F335; // 18 dec — Binance-Peg ATOM (Cosmos)
address constant NEAR = 0x1Fa4a73a3F0133f0025378af00236f3aBDEE5D63; // 18 dec — Binance-Peg NEAR
address constant FIL = 0x0D8Ce2A99Bb6e3B7Db580eD848240e4a0F9aE153; // 18 dec — Binance-Peg FIL
address constant UNI = 0xBf5140A22578168FD562DCcF235E5D43A02ce9B1; // 18 dec — Binance-Peg UNI
address constant ZEC = 0x1Ba42e5193dfA8B03D15dd1B86a3113bbBEF8Eeb; // 18 dec — Binance-Peg ZEC
address constant COMP = 0x52CE071Bd9b1C4B00A0b92D298c512478CaD67e8; // 18 dec — Binance-Peg COMP
address constant SUSHI = 0x947950BcC74888a40Ffa2593C5798F11Fc9124C4; // 18 dec — Binance-Peg SUSHI
address constant ONEINCH = 0x111111111117dC0aa78b770fA6A738034120C302; // 18 dec — Binance-Peg 1INCH
address constant DOGE = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43; // 8 dec  — Binance-Peg DOGE
address constant SHIB = 0x2859e4544C4bB03966803b044A93563Bd2D0DD4D; // 18 dec — Binance-Peg SHIB
address constant FTM = 0xAD29AbB318791D579433D831ed122aFeAf29dcfe; // 18 dec — Binance-Peg FTM
address constant EOS = 0x56b6fB708fC5732DEC1Afc8D8556423A2EDcCbD6; // 18 dec — Binance-Peg EOS
address constant PEPE = 0x25d887Ce7a35172C62FeBFD67a1856F20FaEbB00; // 18 dec — Binance-Peg PEPE
address constant FLOKI = 0xfb5B838b6cfEEdC2873aB27866079AC55363D37E; // 9 dec  — Binance-Peg FLOKI

// --- ETH staking ---
address constant BETH = 0x250632378E573c6Be1AC2f97Fcdf00515d0Aa91B; // 18 dec — Binance Beacon ETH
address constant WBETH = 0xa2E3356610840701BDf5611a53974510Ae27E2e1; // 18 dec — Wrapped Beacon ETH

// ============================================================
//   ONDO FINANCE — RWA TOKENS
// ============================================================

address constant USDY = 0x608593d17A2decBbc4399e4185bE4922F97eD32E; // 18 dec — U.S. Dollar Yield (T-Bills)
address constant USDon = 0x1f8955E640Cbd9abc3C3Bb408c9E2E1f5F20DfE6; // 18 dec — Ondo USD stablecoin

// --- Ondo Portfolios ---
address constant BRAINon = 0x0574e53f8214d0402C8388B4402113a74354d1b0; // 18 dec — AI Leaders Portfolio
address constant YLD5on = 0x0Cfd1030E2431E0fA15D4cc3F3E43076FE93F8f9; // 18 dec — 5% Targeted Income
address constant YLD8on = 0x2f20d5dfbAFfa3e6351E06B8b18059747CD7ee72; // 18 dec — 8% Targeted Income
address constant BLKGRWon = 0xE4Bd77247671746CaA3119E9FEAA146F8a4EE237; // 18 dec — BlackRock High Growth
address constant BLKDIGon = 0xe658C62195f32bc53226e7E2642e3D76B4382FB8; // 18 dec — BlackRock Diversified Growth
address constant BLKHIon = 0xf78155dC15B838b7577002bc53bBe1041cA48622; // 18 dec — BlackRock High Income
address constant SPYSHIELDon = 0x5821C1EcbC33341709EF1Dd01FE1A8145BC248A8; // 18 dec — S&P 500 Capital Shielded
address constant BIG5on = 0xbA4530bf12EE2741154685D857B99FEe2B9b538B; // 18 dec — Big 5 Core Allocation
address constant MAG7Xon = 0x50436eC45316A98E72b03Ead5752E8543f11ec09; // 18 dec — Magnificent 7 + Crypto

// ============================================================
//   ONDO FINANCE — STOCK / ETF TOKENS
// ============================================================

address constant FXLon = 0x9b8E987e6fEc8Cf1380C4dcA7071e2C7853AEEA1; // 18 dec - iShares China Large-Cap ETF (Ondo)
address constant AAPLon = 0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4; // 18 dec — Apple
address constant TSLAon = 0x2494b603319d4D9F9715c9f4496d9E0364B59d93; // 18 dec — Tesla
address constant NVDAon = 0xA9eE28C80f960B889dFbd1902055218cBa016F75; // 18 dec — NVIDIA
address constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436; // 18 dec — NVIDIA Bridge token (V4 pair)
address constant MSFTon = 0x6Bfe75D1ad432050eA973C3A3DcD88F02e2444C3; // 18 dec — Microsoft
address constant GOOGLon = 0x091FC7778e6932d4009B087B191D1EE3bac5729A; // 18 dec — Alphabet Class A
address constant AMZNon = 0x4553cFe1C09f37f38b12dC509F676964e392F8Fc; // 18 dec — Amazon
address constant METAon = 0xD7dF5863A3e742F0c767768cDfcb63f09E0422f6; // 18 dec — Meta Platforms
address constant NFLXon = 0x7048F5227b032326cC8DBC53cF3FdDD947a2c757; // 18 dec — Netflix
address constant SPYon = 0x6a708EAD771238919D85930b5a0f10454E1C331a; // 18 dec — SPDR S&P 500 ETF
address constant QQQon = 0x0cdE6936d305d5B34667fC46425E852efd73559a; // 18 dec — Invesco QQQ
address constant IBITon = 0x68B07cEf227Cea1b2b6683921C8c825cd5C69Ec7; // 18 dec — iShares Bitcoin Trust
address constant JPMon = 0x317bF42b43A394860718266Dec445DCC9FD9dA49; // 18 dec — JPMorgan Chase
address constant BABAon = 0xd5964f3fcee8D649995AB88F04b8982539c282D2; // 18 dec — Alibaba
address constant COINon = 0xf8589b526FdD65F7F301c605a6e04F0F1b4B3620; // 18 dec — Coinbase
address constant MSTRon = 0x7313EA16493b2f55054Df0131A3A14B043ec8992; // 18 dec — MicroStrategy
address constant PLTRon = 0x9351AbD19f42101dD36025E495B98E910b255d78; // 18 dec — Palantir
address constant HOODon = 0x19601179A60f55Ff6636F5D1A8b6671053Bd60a8; // 18 dec — Robinhood Markets
address constant GMEon = 0xdABb9afF4cf02f26D2014e4cA9f94aC6fe6572a3; // 18 dec — GameStop
address constant RDDTon = 0x4DA12f47578ef89c76179b760C778E70b668f80b; // 18 dec — Reddit
address constant SPCXon = 0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928; // 18 dec — SpaceX

// ============================================================
//   UNISWAP V3 — INFRAESTRUCTURA EN BNB CHAIN
// ============================================================

// --- SIREN ---
address constant SIREN = 0x997A58129890bBdA032231A52eD1ddC845fc18e1; // 18 dec — SIREN token

// ============================================================
//   UNISWAP V3 — INFRAESTRUCTURA EN BNB CHAIN
// ============================================================

address constant UNISWAP_V3_FACTORY = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
address constant UNIVERSAL_ROUTER = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
address constant UNISWAP_V3_QUOTER = 0x78D78E420Da98ad378D7799bE8f4AF69033EB077;
address constant UNISWAP_V3_SWAP_ROUTER_02 = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;
address constant UNISWAP_V3_NONFUNGIBLE_POSITION_MANAGER = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;

// ============================================================
//   UNISWAP V4 — INFRAESTRUCTURA EN BNB CHAIN
// ============================================================

address constant UNISWAP_V4_QUOTER = 0x95C086d7fE28AdD842ee220fef225a777474d781;

// ============================================================
//   NOTAS
// ============================================================
// - OUSG NO está deployado en BNB Chain (solo Ethereum mainnet)
// - BUSD está DEPRECATED (Binance ya no minta) pero el contrato sigue activo
// - USDT y USDC en BSC usan 18 decimals (no 6 como en Ethereum)
// - Permit2 tiene la misma dirección en todas las redes soportadas
// - Todos los tokens de Ondo usan 18 decimals
