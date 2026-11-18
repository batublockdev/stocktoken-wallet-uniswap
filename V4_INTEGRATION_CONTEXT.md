# StockWallet V4 Integration — Context & Plan

**Fecha:** 2026-11-15
**Proyecto:** StockWallet — AI-Managed Investment Wallet
**Ubicación:** `/home/openclaw-project/Documentos/stockwallet`

---

## CONTEXTO GENERAL

StockWallet es un contrato que permite a un AI agent gestionar un portfolio de tokens. Hoy usa **Uniswap V3** para swaps via Universal Router + Permit2. El objetivo es **integrar Uniswap V4** para que pueda comparar V3 vs V4 y elegir la mejor pool para cada swap.

### Tokens relevantes en BSC
- **NVDAon:** `0xA9eE28C80f960B889dFbd1902055218cBa016F75`
- **NVDAB (token puente):** `0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436`
- **USDT:** `0x55d398326f99059fF775485246999027B3197955`

### Direcciones clave en BSC
- **V4 PoolManager:** `0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF`
- **Universal Router:** `0x1906c1d672b88cD1B9aC7593301cA990F94Eae07`
- **Permit2:** `0x000000000022D473030F116dDEE9F6B43aC78BA3`

---

## LO QUE YA ESTÁ HECHO ✅

### 1. UniswapV4PoolScanner.sol
- Contrato scanner que lee storage del PoolManager via `extsload`
- Funciones: `checkPool(PoolKey)`, `scanPair(tokenA, tokenB, fees, tickSpacings, hooks)`, `getPoolDiagnostic(PoolKey)`
- Usa `StateLibrary` de v4-core

### 2. Skill swap-integration de Uniswap instalado
- Ubicación: `~/.openclaw/workspace/agents/dev/skills/swap-integration/`
- Referencia completa del Trading API y Universal Router
- API Key: `KryK4xkC4xrde-b8zvIz9l4aGAL4193jMmeBMkN1Ezw`

### 3. Script TS discover-v4-pools.ts
- Ubicación: `scripts/discover-v4-pools.ts`
- Usa Trading API `/quote` con `protocols: ["V4"]` para descubrir pools
- Confirmó que el route V4 para NVDAon→USDT es multi-hop: NVDAon → NVDAB → USDT

### 4. Test DiscoverV4Pools.t.sol — 6/6 PASAN ✅
- Ubicación: `test/DiscoverV4Pools.t.sol`
- Fork de BSC en bloque específico con `vm.createSelectFork(rpc, 133660000)`
- **6 tests pasan:**
  1. `test_verify_v4_pools_from_api` — scanner verifica 2 pools on-chain
  2. `test_quote_v4_multihop` — quote V4 con SwapMath iterando ticks
  3. `test_execute_swap_v4_single_hop` — swap NVDAon→NVDAB via Universal Router
  4. `test_execute_swap_v4_multihop` — swap NVDAon→NVDAB→USDT via Universal Router
  5. `test_compare_v3_vs_v4` — estructura de comparación
  6. `test_nonexistent_pool` — pool inexistente retorna false

### Resultados del test:
- Quote V4: 153.59 USDT vs 153.40 del Trading API (match casi exacto)
- Swap single-hop: 1 NVDAon → 1,001,243,263,428,330,209 NVDAB ✅
- Swap multi-hop: 1 NVDAon → 153,434,067,133,462,852,045 USDT ✅

---

## FLUJO DEL TEST (lo que ya funciona)

1. **Datos off-chain del Trading API** → hardcoded en el test como `V4PoolAPIData`
   - Pool 1: NVDAon↔NVDAB, fee=200, tickSpacing=4, hooks=0x0
   - Pool 2: NVDAB↔USDT, fee=20000, tickSpacing=400, hooks=0x0

2. **Scanner verifica pools on-chain** → `UniswapV4PoolScanner.checkPool(PoolKey)`
   - Lee sqrtPriceX96, tick, liquidity via extsload
   - Verifica initialized=true, liquidity > 0

3. **Quote V4 on-chain** → `_quoteV4()` usando `SwapMath.computeSwapStep` de v4-core
   - Itera múltiples tick steps hasta consumir todo el amountIn
   - Multi-hop: quote hop 1 → output como input del hop 2

4. **Swap V4 via Universal Router** → command `V4_SWAP` (0x10)
   - Actions: `SWAP_EXACT_IN_SINGLE(6)` + `SETTLE_ALL(12)` + `TAKE_ALL(15)`
   - Encoding: `abi.encode(actions, params)` — produce offset 0x40 correcto
   - V4 action codes: SWAP_EXACT_IN_SINGLE=6, SETTLE_ALL=12, TAKE_ALL=15
   - struct V2.1.1: (PoolKey, bool, uint128, uint128, uint256 minHopPriceX36, bytes hookData)

---

## DETALLES TÉCNICOS IMPORTANTES

### Encoding del V4_SWAP
- El input de V4_SWAP es `abi.encode(bytes actions, bytes[] params)`
- `abi.encode(actions, params)` produce offset 0x40 (correcto)
- `abi.encode(["bytes","bytes[]"], ...)` produce offset 0x60 (INCORRECTO — causa SliceOutOfBounds)
- SWAP_EXACT_IN_SINGLE param: `abi.encode(currency0, currency1, fee, tickSpacing, hooks, zeroForOne, amountIn, amountOutMin, minHopPriceX36, hookData)`
- SETTLE_ALL param: `abi.encode(currency, maxAmount)`
- TAKE_ALL param: `abi.encode(currency, minAmount)`

### Fork de Foundry
- `vm.createFork(rpc)` sin bloque → NO carga el PoolManager (extcodesize=0)
- `vm.createSelectFork(rpc, blockNumber)` con bloque específico → SÍ funciona
- Usar bloque 133660000 o superior

### Pool IDs V4 confirmados
- Pool NVDAon↔NVDAB: `0xcccfc65c871b005e61de77265cdb2f98be547f9c75ec5476f8b4c160db3836c4`
- Pool NVDAB↔USDT: `0x184410b44a52eca69a0bcebabe4fb9dde38e5d3eb10a50b719e88a7d57f56497`
- Pool WBNB↔USDT: `0xa77d89e40ddd6a57b72ad4a8c55554b2fd6171026c903462a9f9c7be133811a6`

### 3 pools con liquidez real (encontrados por Batu)
- `0x3e3490699f36dddb3cf0252db1b8c7fd3c2d3a3a4ad5e0c3203668d7a90b9968` — liquidity: 10.3e18
- `0x892a3c850767bbc48ec229ef8b68eb3859b43cde635f7f7df405a47f693cf6ad` — liquidity: 43.7e18
- `0x532fe9101dcab124a66c6f4f3e7880b77e87e7f6625889b1ca8e5e7e5f82d598` — liquidity: 6.4e18
- Estas pools tienen fees custom (80%, 4.99%, 77%) — no son estándar

---

## PLAN DE INTEGRACIÓN EN STOCKWALLET

### Paso 1: Sistema de storage on-chain para parámetros V4 ✅ COMPLETADO
- ✅ Struct `V4PoolData` agregada: `{tokenIn, tokenOut, fee, tickSpacing, hooks}`
- ✅ Mapping `v4PoolsByToken` agregado: `mapping(address => V4PoolData[])` guardado por token
- ✅ Función `setV4Pools(address token, V4PoolData[] pools)` — solo ADGENT_ROLE
- ✅ Función `getV4Pools(address token)` — getter view
- ✅ Event `V4PoolsUpdated(address token, uint256 poolCount)`
- ✅ Compila correctamente (solo warnings, ningún error)
- Nota: El script `StockWalletDeploy.s.sol` tiene un error preexistente (orden de parámetros del constructor), no relacionado con este paso

### Paso 2: Modificar `_getBestPoolFee` → `_getBestRoute` ⏳ PENDIENTE
- Mantener lógica V3 actual (factory.getPool + quoter)
- Agregar lógica V4: leer pools guardadas o del parámetro, scanner verifica, `_quoteV4` calcula
- Devolver `(uint8 protocol, uint24 fee, uint256 amountOut)` — el mejor entre V3 y V4

### Paso 3: Modificar `_swap` ⏳ PENDIENTE
- Si gana V3 → `V3_SWAP_EXACT_IN` (0x00) como hoy
- Si gana V4 → `V4_SWAP` (0x10) con los actions `SWAP_EXACT_IN_SINGLE + SETTLE_ALL + TAKE_ALL`

### Paso 4: Modificar `invest` y `selltoken` ⏳ PENDIENTE
- Agregar parámetro `V4PoolData[]` para recibir las pools V4 del backend
- Si viene vacío usa los guardados on-chain

### Paso 5: Test del flujo completo ⏳ PENDIENTE
- Test invest con V3 vs V4, guardando parámetros on-chain

---

## CONTRATO STOCKWALLET ACTUAL

- **Ubicación:** `src/StockWallet.sol`
- **Chain:** Diseñado para Celo (42220) pero las pools V4 están en BSC (56)
- **V3 swap actual:**
  - `_getBestPoolFee(tokenIn, tokenOut, amountIn)` → itera fees [100, 500, 3000, 10000], usa `quoter.quoteExactInputSingle()`
  - `_swap()` → usa `UniversalRouter.execute(V3_SWAP_EXACT_IN, ...)` con Permit2
- **Funciones principales:** `invest()`, `selltoken()`, `selltokenAll()`, `depositAsset()`

---

*Actualizado: 2026-11-15 00:19 GMT-5*
