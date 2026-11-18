/**
 * discover-v4-pools.ts
 * 
 * Busca pools V4 de Uniswap para cualquier par de tokens en BSC.
 * 
 * Uso:
 *   npx tsx scripts/discover-v4-pools.ts <tokenIn> <tokenOut> [amount] [chainId]
 * 
 * Ejemplos:
 *   npx tsx scripts/discover-v4-pools.ts 0x9b8E987e6fEc8Cf1380C4dcA7071e2C7853AEEA1 0x55d398326f99059fF775485246999027B3197955
 *   npx tsx scripts/discover-v4-pools.ts FXL USDT
 *   npx tsx scripts/discover-v4-pools.ts NVDAon USDT 1000000000000000000
 * 
 * Tokens soportados por simbolo (BSC):
 *   USDT, USDC, WBNB, BTCB, ETH, LINK, AAVE, DOT, UNI,
 *   NVDAon, NVDAB, AAPLon, TSLAon, MSFTon, GOOGLon, AMZNon,
 *   METAon, NFLXon, COINon, MSTRon, PLTRon, HOODon, SPYon,
 *   QQQon, IBITon, MAG7Xon, BRAINon, FXLon, USDY, USDon
 * 
 * Salida:
 *   - Lista de pools V4 encontradas (poolId, fee, tickSpacing, hooks, liquidez, sqrtPrice)
 *   - Ruta completa del quote (multi-hop si aplica)
 *   - Cantidad de output esperada
 *   - Datos listos para copiar al contrato StockWallet (V4PoolData)
 */

import { ethers } from "ethers";

// ============
// CONFIG
// ============

const API_URL = "https://trade-api.gateway.uniswap.org/v1";
const API_KEY = "Ug9mxiTaywDElSxUatzmdUXcwkkHPNI1qXM_o4KQrHE";

const AGENT_INFO = JSON.stringify({
  integration_name: "swap-integration",
  decision_origin: "human_mediated",
  version: "1.6.0",
});

const HEADERS: Record<string, string> = {
  "Content-Type": "application/json",
  "x-api-key": API_KEY,
  "x-universal-router-version": "2.0",
  "x-agent-info": AGENT_INFO,
};

// ============
// TOKENS BSC (chainId 56)
// ============

const TOKENS_BSC: Record<string, { address: string; decimals: number; name: string }> = {
  // Stablecoins
  USDT: { address: "0x55d398326f99059fF775485246999027B3197955", decimals: 18, name: "Binance-Peg USDT" },
  USDC: { address: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", decimals: 18, name: "Binance-Peg USDC" },
  DAI: { address: "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3", decimals: 18, name: "Binance-Peg DAI" },
  BUSD: { address: "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", decimals: 18, name: "Binance-Peg BUSD" },

  // Crypto majors
  WBNB: { address: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", decimals: 18, name: "Wrapped BNB" },
  BTCB: { address: "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c", decimals: 18, name: "Bitcoin BEP20" },
  ETH: { address: "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", decimals: 18, name: "Ethereum BEP20" },
  LINK: { address: "0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD", decimals: 18, name: "Chainlink BEP20" },
  AAVE: { address: "0xfb6115445Bff7b52FeB98650C87f44907E58f802", decimals: 18, name: "Aave BEP20" },
  DOT: { address: "0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402", decimals: 18, name: "Polkadot BEP20" },
  UNI: { address: "0xBf5140A22578168FD562DCcF235E5D43A02ce9B1", decimals: 18, name: "Uniswap BEP20" },
  MATIC: { address: "0xCC42724C6683B7E57334c4E856f4c9965ED682bD", decimals: 18, name: "Polygon BEP20" },

  // Ondo - Stocks
  NVDAon: { address: "0xA9eE28C80f960B889dFbd1902055218cBa016F75", decimals: 18, name: "NVIDIA (Ondo)" },
  AAPLon: { address: "0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4", decimals: 18, name: "Apple (Ondo)" },
  TSLAon: { address: "0x2494b603319d4D9F9715c9f4496d9E0364B59d93", decimals: 18, name: "Tesla (Ondo)" },
  MSFTon: { address: "0x6Bfe75D1ad432050eA973C3A3DcD88F02e2444C3", decimals: 18, name: "Microsoft (Ondo)" },
  GOOGLon: { address: "0x091FC7778e6932d4009B087B191D1EE3bac5729A", decimals: 18, name: "Alphabet (Ondo)" },
  AMZNon: { address: "0x4553cFe1C09f37f38b12dC509F676964e392F8Fc", decimals: 18, name: "Amazon (Ondo)" },
  METAon: { address: "0xD7dF5863A3e742F0c767768cDfcb63f09E0422f6", decimals: 18, name: "Meta (Ondo)" },
  NFLXon: { address: "0x7048F5227b032326cC8DBC53cF3FdDD947a2c757", decimals: 18, name: "Netflix (Ondo)" },
  COINon: { address: "0xf8589b526FdD65F7F301c605a6e04F0F1b4B3620", decimals: 18, name: "Coinbase (Ondo)" },
  MSTRon: { address: "0x7313EA16493b2f55054Df0131A3A14B043ec8992", decimals: 18, name: "MicroStrategy (Ondo)" },
  PLTRon: { address: "0x9351AbD19f42101dD36025E495B98E910b255d78", decimals: 18, name: "Palantir (Ondo)" },
  HOODon: { address: "0x19601179A60f55Ff6636F5D1A8b6671053Bd60a8", decimals: 18, name: "Robinhood (Ondo)" },
  SPYon: { address: "0x6a708EAD771238919D85930b5a0f10454E1C331a", decimals: 18, name: "SPDR S&P 500 (Ondo)" },
  QQQon: { address: "0x0cdE6936d305d5B34667fC46425E852efd73559a", decimals: 18, name: "Invesco QQQ (Ondo)" },
  IBITon: { address: "0x68B07cEf227Cea1b2b6683921C8c825cd5C69Ec7", decimals: 18, name: "iShares Bitcoin Trust (Ondo)" },
  JPMon: { address: "0x317bF42b43A394860718266Dec445DCC9FD9dA49", decimals: 18, name: "JPMorgan (Ondo)" },
  BABAon: { address: "0xd5964f3fcee8D649995AB88F04b8982539c282D2", decimals: 18, name: "Alibaba (Ondo)" },
  GMEon: { address: "0xdABb9afF4cf02f26D2014e4cA9f94aC6fe6572a3", decimals: 18, name: "GameStop (Ondo)" },
  RDDTon: { address: "0x4DA12f47578ef89c76179b760C778E70b668f80b", decimals: 18, name: "Reddit (Ondo)" },
  SPCXon: { address: "0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928", decimals: 18, name: "SpaceX (Ondo)" },

  // Ondo - Bridge
  NVDAB: { address: "0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436", decimals: 18, name: "NVIDIA Bridge (V4 pair)" },

  // Ondo - Portfolios
  MAG7Xon: { address: "0x50436eC45316A98E72b03Ead5752E8543f11ec09", decimals: 18, name: "Magnificent 7 + Crypto (Ondo)" },
  BRAINon: { address: "0x0574e53f8214d0402C8388B4402113a74354d1b0", decimals: 18, name: "AI Leaders Portfolio (Ondo)" },
  YLD5on: { address: "0x0Cfd1030E2431E0fA15D4cc3F3E43076FE93F8f9", decimals: 18, name: "5% Targeted Income (Ondo)" },
  YLD8on: { address: "0x2f20d5dfbAFfa3e6351E06B8b18059747CD7ee72", decimals: 18, name: "8% Targeted Income (Ondo)" },
  BLKGRWon: { address: "0xE4Bd77247671746CaA3119E9FEAA146F8a4EE237", decimals: 18, name: "BlackRock High Growth (Ondo)" },
  BLKDIGon: { address: "0xe658C62195f32bc53226e7E2642e3D76B4382FB8", decimals: 18, name: "BlackRock Diversified Growth (Ondo)" },
  BLKHIon: { address: "0xf78155dC15B838b7577002bc53bBe1041cA48622", decimals: 18, name: "BlackRock High Income (Ondo)" },
  SPYSHIELDon: { address: "0x5821C1EcbC33341709EF1Dd01FE1A8145BC248A8", decimals: 18, name: "S&P 500 Capital Shielded (Ondo)" },
  BIG5on: { address: "0xbA4530bf12EE2741154685D857B99FEe2B9b538B", decimals: 18, name: "Big 5 Core Allocation (Ondo)" },

  // Ondo - RWA
  USDY: { address: "0x608593d17A2decBbc4399e4185bE4922F97eD32E", decimals: 18, name: "U.S. Dollar Yield (Ondo)" },
  USDon: { address: "0x1f8955E640Cbd9abc3C3Bb408c9E2E1f5F20DfE6", decimals: 18, name: "Ondo USD stablecoin" },

  // Native
  BNB: { address: "0x0000000000000000000000000000000000000000", decimals: 18, name: "Native BNB" },
};

// ============
// TIPOS
// ============

interface V4PoolInfo {
  poolId: string;
  tokenIn: { address: string; symbol: string; decimals: string };
  tokenOut: { address: string; symbol: string; decimals: string };
  fee: number;
  tickSpacing: number;
  hooks: string;
  liquidity: string;
  sqrtPriceX96: string;
  tick: number;
  type: string;
}

interface QuoteResponse {
  routing: string;
  quote: {
    input?: { token: string; amount: string };
    output?: { token: string; amount: string };
    route?: any[];
    routeString?: string;
    gasFee?: string;
    gasFeeUSD?: string;
    gasUseEstimate?: string;
    priceImpact?: number;
    blockNumber?: string;
    orderInfo?: {
      outputs: Array<{ token: string; startAmount: string; endAmount: string }>;
      input: { token: string; startAmount: string; endAmount: string };
    };
  };
  permitData?: any;
}

// ============
// HELPERS
// ============

function resolveToken(input: string): { address: string; decimals: number; name: string } {
  // Si es un simbolo conocido
  const sym = input.toUpperCase();
  if (TOKENS_BSC[sym]) {
    return TOKENS_BSC[sym];
  }
  // Si es una address valida
  if (/^0x[a-fA-F0-9]{40}$/.test(input)) {
    return { address: input.toLowerCase(), decimals: 18, name: input.slice(0, 10) + "..." };
  }
  throw new Error(`Token no reconocido: "${input}". Usa un simbolo (USDT, NVDAon, FXLon...) o una address 0x...`);
}

function formatAmount(raw: string, decimals: number): string {
  try {
    const bi = BigInt(raw);
    const divisor = 10n ** BigInt(decimals);
    const whole = bi / divisor;
    const frac = bi % divisor;
    const fracStr = frac.toString().padStart(decimals, "0").replace(/0+$/, "");
    return fracStr ? `${whole}.${fracStr}` : whole.toString();
  } catch {
    return raw;
  }
}

// ============
// API CALLS
// ============

async function fetchQuote(
  tokenIn: string,
  tokenOut: string,
  amount: string,
  chainId: number,
  protocols: string[]
): Promise<QuoteResponse> {
  const body = {
    swapper: "0x0000000000000000000000000000000000000001",
    tokenIn,
    tokenOut,
    tokenInChainId: String(chainId),
    tokenOutChainId: String(chainId),
    amount,
    type: "EXACT_INPUT",
    slippageTolerance: 0.5,
    protocols,
  };

  const res = await fetch(`${API_URL}/quote`, {
    method: "POST",
    headers: HEADERS,
    body: JSON.stringify(body),
  });

  const data = await res.json();

  if (!res.ok) {
    const err = (data as any)?.detail || (data as any)?.errorCode || JSON.stringify(data);
    throw new Error(`API error ${res.status}: ${err}`);
  }

  return data as QuoteResponse;
}

function extractV4Pools(route: any[]): V4PoolInfo[] {
  const pools: V4PoolInfo[] = [];

  for (const hop of route) {
    const hops = Array.isArray(hop) ? hop : [hop];
    for (const h of hops) {
      if (h.type === "v4-pool" || h.protocol === "V4") {
        pools.push({
          poolId: h.address || h.poolId || "",
          tokenIn: h.tokenIn,
          tokenOut: h.tokenOut,
          fee: parseInt(h.fee || "0"),
          tickSpacing: parseInt(h.tickSpacing || "0"),
          hooks: h.hooks || "0x0000000000000000000000000000000000000000",
          liquidity: h.liquidity || "0",
          sqrtPriceX96: h.sqrtRatioX96 || h.sqrtPriceX96 || "0",
          tick: parseInt(h.tickCurrent || h.tick || "0"),
          type: h.type || "v4-pool",
        });
      }
    }
  }

  return pools;
}

// ============
// MAIN
// ============

async function main() {
  const args = process.argv.slice(2);

  if (args.length < 2) {
    console.error("Uso: npx tsx scripts/discover-v4-pools.ts <tokenIn> <tokenOut> [amount] [chainId]");
    console.error("");
    console.error("Tokens soportados (simbolo o address 0x...):");
    console.error("  Stablecoins: USDT, USDC, DAI, BUSD");
    console.error("  Crypto: WBNB, BTCB, ETH, LINK, AAVE, DOT, UNI, MATIC");
    console.error("  Ondo Stocks: NVDAon, AAPLon, TSLAon, MSFTon, GOOGLon, AMZNon, METAon, NFLXon, COINon, MSTRon, PLTRon, HOODon, SPYon, QQQon, IBITon, JPMon, BABAon, GMEon, RDDTon, SPCXon");
    console.error("  Ondo Portfolios: MAG7Xon, BRAINon, YLD5on, YLD8on, BLKGRWon, BLKDIGon, BLKHIon, SPYSHIELDon, BIG5on");
    console.error("  Ondo RWA: USDY, USDon");
    console.error("  Bridge: NVDAB");
    console.error("");
    console.error("Ejemplos:");
    console.error("  npx tsx scripts/discover-v4-pools.ts NVDAon USDT");
    console.error("  npx tsx scripts/discover-v4-pools.ts FXLon USDT 1000000000000000000");
    console.error("  npx tsx scripts/discover-v4-pools.ts 0x9b8E987e6fEc8Cf1380C4dcA7071e2C7853AEEA1 0x55d398326f99059fF775485246999027B3197955");
    process.exit(1);
  }

  const tokenInInput = args[0];
  const tokenOutInput = args[1];
  const amountArg = args[2] || (10n ** 18n).toString(); // default: 1 token
  const chainId = parseInt(args[3] || "56"); // default: BSC

  const tokenIn = resolveToken(tokenInInput);
  const tokenOut = resolveToken(tokenOutInput);

  console.log("================================================================");
  console.log("  UNISWAP V4 POOL DISCOVERY");
  console.log("================================================================");
  console.log(`  Chain:       ${chainId === 56 ? "BSC" : chainId === 1 ? "Ethereum" : `Chain ${chainId}`}`);
  console.log(`  Token In:    ${tokenIn.name} (${tokenIn.address})`);
  console.log(`  Token Out:   ${tokenOut.name} (${tokenOut.address})`);
  console.log(`  Amount:      ${formatAmount(amountArg, tokenIn.decimals)} (${amountArg} raw)`);
  console.log(`  API Key:     ${API_KEY.slice(0, 8)}...`);
  console.log("================================================================\n");

  // ============
  // 1. QUOTE SOLO V4
  // ============
  console.log("--- 1. Buscando pools V4 ---\n");

  let v4Pools: V4PoolInfo[] = [];

  try {
    const quote = await fetchQuote(tokenIn.address, tokenOut.address, amountArg, chainId, ["V4"]);

    console.log(`  Routing: ${quote.routing}`);

    if (quote.quote.output) {
      const outAmount = quote.quote.output.amount;
      console.log(`  Output: ${formatAmount(outAmount, tokenOut.decimals)} ${tokenOutInput.toUpperCase()} (${outAmount} raw)`);
    }

    if (quote.quote.gasFeeUSD) {
      console.log(`  Gas: $${quote.quote.gasFeeUSD}`);
    }

    if (quote.quote.priceImpact !== undefined) {
      console.log(`  Price impact: ${quote.quote.priceImpact}%`);
    }

    if (quote.quote.routeString) {
      console.log(`  Route: ${quote.quote.routeString}`);
    }

    if (quote.quote.route) {
      v4Pools = extractV4Pools(quote.quote.route);
    }

    if (v4Pools.length > 0) {
      console.log(`\n  === POOLS V4 ENCONTRADAS: ${v4Pools.length} ===\n`);
      v4Pools.forEach((p, i) => {
        console.log(`  Pool ${i + 1}:`);
        console.log(`    PoolId:       ${p.poolId}`);
        console.log(`    ${p.tokenIn.symbol} -> ${p.tokenOut.symbol}`);
        console.log(`    Fee:          ${p.fee} (${(p.fee / 10000).toFixed(2)}%)`);
        console.log(`    TickSpacing:  ${p.tickSpacing}`);
        console.log(`    Hooks:        ${p.hooks}`);
        console.log(`    Liquidity:    ${p.liquidity}`);
        console.log(`    SqrtPriceX96: ${p.sqrtPriceX96}`);
        console.log(`    Tick:         ${p.tick}`);
        console.log("");
      });
    } else {
      console.log("\n  No se encontraron pools V4 con liquidez para este par.\n");
    }
  } catch (e: any) {
    console.log(`  Error: ${e.message}\n`);
  }

  // ============
  // 2. QUOTE TODOS LOS PROTOCOLOS (V2 + V3 + V4)
  // ============
  console.log("--- 2. Buscando con todos los protocolos (V2 + V3 + V4) ---\n");

  try {
    const quoteAll = await fetchQuote(tokenIn.address, tokenOut.address, amountArg, chainId, ["V2", "V3", "V4"]);

    console.log(`  Routing: ${quoteAll.routing}`);
    console.log(`  Route: ${quoteAll.quote.routeString || "N/A"}`);

    if (quoteAll.quote.output) {
      console.log(`  Output: ${formatAmount(quoteAll.quote.output.amount, tokenOut.decimals)} ${tokenOutInput.toUpperCase()}`);
    }

    // Extraer pools V4 si las hay en la ruta mixta
    if (quoteAll.quote.route) {
      const mixedV4 = extractV4Pools(quoteAll.quote.route);
      if (mixedV4.length > 0 && v4Pools.length === 0) {
        console.log(`\n  === POOLS V4 EN RUTA MIXTA: ${mixedV4.length} ===\n`);
        mixedV4.forEach((p, i) => {
          console.log(`  Pool ${i + 1}: ${p.tokenIn.symbol} -> ${p.tokenOut.symbol} fee=${p.fee} ts=${p.tickSpacing}`);
          console.log(`    PoolId: ${p.poolId}`);
        });
      }
    }
  } catch (e: any) {
    console.log(`  Error: ${e.message}`);
  }

  // ============
  // 3. DIRECCION INVERSA
  // ============
  console.log("\n--- 3. Direccion inversa ---\n");

  try {
    const reverseAmount = (10n ** BigInt(tokenOut.decimals)).toString();
    const quoteRev = await fetchQuote(tokenOut.address, tokenIn.address, reverseAmount, chainId, ["V4"]);

    console.log(`  Routing: ${quoteRev.routing}`);

    if (quoteRev.quote.output) {
      console.log(`  Output: ${formatAmount(quoteRev.quote.output.amount, tokenIn.decimals)} ${tokenInInput.toUpperCase()}`);
    }

    if (quoteRev.quote.route) {
      const revPools = extractV4Pools(quoteRev.quote.route);
      if (revPools.length > 0) {
        console.log(`\n  === POOLS V4 (reverse): ${revPools.length} ===\n`);
        revPools.forEach((p, i) => {
          console.log(`  Pool ${i + 1}: ${p.tokenIn.symbol} -> ${p.tokenOut.symbol} fee=${p.fee} ts=${p.tickSpacing}`);
          console.log(`    PoolId: ${p.poolId}`);
        });
      }
    }
  } catch (e: any) {
    console.log(`  Error: ${e.message}`);
  }

  // ============
  // 4. RESUMEN PARA STOCKWALLET
  // ============
  if (v4Pools.length > 0) {
    console.log("\n================================================================");
    console.log("  DATOS LISTOS PARA StockWallet.setV4Pools()");
    console.log("================================================================\n");

    console.log("  V4PoolData[] memory pools = new V4PoolData[](" + v4Pools.length + ");");
    v4Pools.forEach((p, i) => {
      console.log(`  pools[${i}] = V4PoolData({`);
      console.log(`    tokenIn:     ${p.tokenIn.address}, // ${p.tokenIn.symbol}`);
      console.log(`    tokenOut:    ${p.tokenOut.address}, // ${p.tokenOut.symbol}`);
      console.log(`    fee:         ${p.fee},`);
      console.log(`    tickSpacing: ${p.tickSpacing},`);
      console.log(`    hooks:       ${p.hooks}`);
      console.log(`  });`);
    });
    console.log("\n  // Llamar: wallet.setV4Pools(TOKEN_ADDRESS, pools);");
    console.log("================================================================");
  } else {
    console.log("\n  No se encontraron pools V4. El par usa V3 o no tiene liquidez suficiente.");
    console.log("  Usa el scanner on-chain (ScanFXL.t.sol) para buscar pools V4 sin liquidez.");
  }

  console.log("\n=== FIN ===");
}

main().catch((e) => {
  console.error("Error fatal:", e);
  process.exit(1);
});
