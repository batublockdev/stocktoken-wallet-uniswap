# 🔒 Auditoría de Seguridad — StockWallet.sol

**Contrato:** `StockWallet.sol`  
**Fecha:** 2026-10-22  
**Herramienta:** Slither 0.11.6 (Static Analyzer)  
**Red objetivo:** Celo Mainnet (Chain ID: 42220)  
**Solidity:** ^0.8.20  
**Auditador:** Dev Agent

---

## 📊 Resumen Ejecutivo

Slither analizó 26 contratos con 102 detectores, encontrando **131 resultados** distribuidos entre el contrato principal y librerías de terceros. Los hallazgos del contrato `StockWallet.sol` se clasifican a continuación por severidad.

| Severidad | Cantidad | Descripción |
|-----------|----------|-------------|
| 🔴 Alta | 3 | Reentrancy, función pública sin restricciones, validación invertida |
| 🟡 Media | 5 | Falta nonReentrant, underflow, falta pausabilidad, doble evento, precio manipulable |
| 🟢 Baja | 6 | Variables no immutables, complejidad alta, naming, loops con llamadas externas |
| ℹ️ Info | 4 | Pragmas, assembly en librerías, versiones de Solidity |

---

## 🔴 Hallazgos de Severidad Alta

### H-01: Reentrancy en `_swap` (reentrancy-balance)

**Detector:** `reentrancy-balance`  
**Línea:** `src/StockWallet.sol#822-906`

**Descripción:**
La función `_swap` realiza una llamada externa a `IUniversalRouterSwap(UNIVERSAL_ROUTER).execute()` y luego compara `balanceAfter <= balanceBefore` usando el valor de `balanceBefore` leído antes de la llamada. Un atacante que controle el contrato del token de salida podría manipular el balance durante la ejecución del callback de swap.

**Código afectado:**
```solidity
uint256 balanceBefore = outputToken.balanceOf(address(this)); // L877
// ... llamada externa ...
IUniversalRouterSwap(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 60); // L892-896
uint256 balanceAfter = outputToken.balanceOf(address(this)); // L899
if (balanceAfter <= balanceBefore) { // L901 — usa balanceBefore stale
    revert SwapReturnedNoTokens(tokenOut);
}
```

**Impacto:** Un token malicioso podría falsificar el balance y causar que el swap parezca exitoso cuando no lo fue, o manipular el `amountOut` calculado.

**Recomendación:**
- Usar ReentrancyGuard en todas las funciones que llaman `_swap`
- Leer `balanceBefore` después de cualquier llamada externa, o usar un patrón checks-effects-interactions
- Considerar usar `amountOut` retornado por el router en lugar de comparar balances

---

### H-02: `modifyPosition` pública sin restricciones (Bug crítico)

**Detector:** Análisis manual  
**Línea:** `src/StockWallet.sol#922-925`

**Descripción:**
La función `modifyPosition` es `public` sin ningún modificador de acceso (`onlyOwner`, `onlyRole`). Cualquiera puede modificar el estado de las posiciones de inversión.

**Código afectado:**
```solidity
function modifyPosition(uint256 amount, address token) public {
    Position storage positionToken = assetPosition[token];
    positionToken.invested = amount;
}
```

**Impacto:** Un atacante puede:
- Setear `invested` a 0 → take profit se triggerea inmediatamente (vende todo barato)
- Setear `invested` a un valor enorme → stop loss se triggerea inmediatamente (vende todo con pérdida)
- Manipular toda la lógica de SL/TP a voluntad

**Recomendación:**
```solidity
// Opción 1: Restringir acceso
function modifyPosition(uint256 amount, address token) external onlyRole(ADGENT_ROLE) {

// Opción 2: Hacer internal (si solo se usa para testing)
function modifyPosition(uint256 amount, address token) internal {

// Opción 3: Eliminar en producción
```

---

### H-03: Validación invertida de `stopLossBps` en `updateRiskConfig`

**Detector:** Análisis manual + Slither (incorrect-equality)  
**Línea:** `src/StockWallet.sol#637-646`

**Descripción:**
La validación de `stopLossBps` en `updateRiskConfig` tiene la lógica invertida. Rechaza stop losses válidos (ej: 9000 = 5% de pérdida) y acepta valores sin sentido.

**Código afectado:**
```solidity
// Constructor (L271-274) — lógica correcta
if (newConfig.stopLossBps != 0 && newConfig.stopLossBps > TOTAL_PERCENTAGE) {
    revert ErrorStopLossBps_notCorrect(token, newConfig.stopLossBps);
}

// updateRiskConfig (L641) — lógica invertida
if (stopLossBps != 0 && stopLossBps > TOTAL_PERCENTAGE) {  // ← debería ser < TOTAL_PERCENTAGE para SL
    revert ErrorStopLossBps_notCorrect(token, stopLossBps);
}
```

**Impacto:** No se pueden configurar stop losses válidos (< 10000 bps). La función `selltoken` no funciona correctamente con valores de SL estándar.

**Recomendación:**
```solidity
// El stop loss debe ser > 0 y < TOTAL_PERCENTAGE (100%)
if (stopLossBps != 0 && stopLossBps > TOTAL_PERCENTAGE) {
    revert ErrorStopLossBps_notCorrect(token, stopLossBps);
}
```
*Nota: El constructor ya tiene esta validación correctamente. `updateRiskConfig` debe coincidir.*

---

## 🟡 Hallazgos de Severidad Media

### M-01: Reentrancy en `invest`, `selltoken`, `selltokenAll` (reentrancy-no-eth)

**Detector:** `reentrancy-no-eth`  
**Líneas:** `src/StockWallet.sol#772-820`, `#662-735`, `#736-769`

**Descripción:**
Múltiples funciones realizan llamadas externas (swaps via Universal Router) y luego escriben variables de estado (`assetPosition`, `assetPath`, `assetConfig`). `invest` tiene `nonReentrant` pero `selltoken` y `selltokenAll` **no**.

**Impacto:** Un token malicioso o un callback de reentrancy podría manipular el estado del contrato durante una venta, causando pérdida de fondos o doble venta.

**Recomendación:**
```solidity
function selltoken(address token, bytes calldata path) 
    external nonReentrant onlyRole(ADGENT_ROLE) {  // ← agregar nonReentrant

function selltokenAll(bytes[] calldata path) 
    external nonReentrant onlyOwner {  // ← agregar nonReentrant
```

---

### M-02: Underflow en `addAsset` con `_oldToken`

**Detector:** Análisis manual  
**Línea:** `src/StockWallet.sol#455-457`

**Descripción:**
Cuando `_oldToken != address(0)`, se resta `_newAllocationBps` de `oldConfig.allocationBps` sin validar que el nuevo sea menor al viejo. Si `_newAllocationBps > oldConfig.allocationBps`, ocurre un underflow.

**Código afectado:**
```solidity
uint256 newAllocationBps_toReplace = oldConfig.allocationBps - _newAllocationBps;
// Si _newAllocationBps > oldConfig.allocationBps → underflow (revert en 0.8.x)
```

**Impacto:** La transacción revierte con error de underflow, pero no hay un mensaje claro. Funcionalidad bloqueada.

**Recomendación:**
```solidity
if (_newAllocationBps > oldConfig.allocationBps) {
    revert StockWallet_PercentagesExceedTotal();
}
uint256 newAllocationBps_toReplace = oldConfig.allocationBps - _newAllocationBps;
```

---

### M-03: `depositAsset` emite doble evento

**Detector:** Análisis manual  
**Línea:** `src/StockWallet.sol#355-362`

**Descripción:**
Cuando se deposita un token != USDC, se emite `AssetDeposited` dos veces: una con el `amountOut` del swap y otra con el `_amount` original.

**Código afectado:**
```solidity
if (_token != usdc) {
    uint256 amountOut = _swap(_token, usdc, path, _amount);
    emit AssetDeposited(msg.sender, _token, _amount, amountOut); // 1er emit
}
emit AssetDeposited(msg.sender, _token, _amount, _amount); // 2do emit (siempre)
```

**Impacto:** Indexadores y listeners reciben eventos duplicados/incorrectos. Confusión en el tracking de depósitos.

**Recomendación:**
```solidity
if (_token != usdc) {
    uint256 amountOut = _swap(_token, usdc, path, _amount);
    emit AssetDeposited(msg.sender, _token, _amount, amountOut);
} else {
    emit AssetDeposited(msg.sender, _token, _amount, _amount);
}
```

---

### M-04: Precio de Stop Loss / Take Profit manipulable (sin TWAP)

**Detector:** Análisis manual  
**Línea:** `src/StockWallet.sol#679-683`

**Descripción:**
`selltoken` usa el precio spot del Quoter de Uniswap V3 para determinar si se triggerea SL/TP. El contrato importa `UniswapV3Twap` pero **nunca lo usa**. El precio spot puede ser manipulado con un swap grande justo antes de la llamada.

**Impacto:** Un atacante con suficiente capital puede:
- Manipular el precio spot para forzar un stop loss
- Evitar un take profit legítimo
- Extraer valor del contrato

**Recomendación:**
```solidity
// Usar TWAP en lugar de precio spot
address pool = factory.getPool(token, usdc, bestFee);
uint256 twapPrice = UniswapV3Twap.getTwapAmountOut(pool, token, uint128(tokenBalance), 1800);
// Usar twapPrice para comparación de SL/TP
```

---

### M-05: Falta pausabilidad (Pausable)

**Detector:** Análisis manual

**Descripción:**
El contrato no implementa `Pausable`. Si se descubre un bug o exploit, no hay forma de frenar el contrato emergentemente.

**Impacto:** En caso de vulnerabilidad, los fondos quedan expuestos sin mecanismo de mitigación.

**Recomendación:**
```solidity
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract StockWallet is Ownable, AccessControl, ReentrancyGuard, Pausable {
    // ...
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    // Agregar `whenNotPaused` a invest, selltoken, selltokenAll, depositAsset
}
```

---

## 🟢 Hallazgos de Severidad Baja

### L-01: `usdc` debería ser `immutable`

**Detector:** `immutable-states`  
**Línea:** `src/StockWallet.sol#112`

**Descripción:**
La variable `usdc` se setea en el constructor y nunca se modifica, pero no está marcada como `immutable`.

**Recomendación:**
```solidity
address public immutable usdc;  // ← agregar immutable
```

---

### L-02: Complejidad ciclomática alta en `updateAllocation`

**Detector:** `cyclomatic-complexity`  
**Línea:** `src/StockWallet.sol#531-628`

**Descripción:**
La función `updateAllocation` tiene complejidad ciclomática de 12 (recomendado < 10).

**Recomendación:** Extraer la lógica de re-escalado a una función interna separada.

---

### L-03: Variables locales no inicializadas

**Detector:** `uninitialized-local`  
**Líneas:** `src/StockWallet.sol#254`, `#939-940`

**Descripción:**
- `TotalPercentage` en el constructor nunca se inicializa explícitamente (defaults a 0, correcto pero poco explícito)
- `hasValidPool` y `fallbackFee` en `_getBestPoolFee` no se inicializan explícitamente

**Recomendación:**
```solidity
uint256 TotalPercentage = 0;
bool hasValidPool = false;
uint24 fallbackFee = 0;
```

---

### L-04: Llamadas externas dentro de loops

**Detector:** `calls-loop`  
**Líneas:** `src/StockWallet.sol#736-769`, `#772-820`, `#927-992`

**Descripción:**
`selltokenAll` e `invest` realizan llamadas externas (balanceOf, swaps, quotes) dentro de loops que iteran sobre el array `assets`. `_getBestPoolFee` itera sobre 4 fee tiers con llamadas externas a `factory.getPool()` y `quoter.quoteExactInputSingle()`.

**Impacto:** Alto gas consumption, posible DoS si el array `assets` crece demasiado.

**Recomendación:** Limitar el número máximo de assets, o batchear las operaciones.

---

### L-05: Operaciones costosas dentro de loops

**Detector:** `costly-loop`  
**Líneas:** `src/StockWallet.sol#761`, `#806`

**Descripción:**
`delete assetPath[token]` dentro de loops en `selltokenAll` e `invest`. Los deletes escriben a storage, lo cual es costoso (20,000 gas para reset a cero).

**Recomendación:** Considerar batchear los deletes fuera del loop o usar un patrón de marca/limpieza.

---

### L-06: `withdrawAsset` no remueve el token de `assets[]`

**Detector:** Análisis manual  
**Línea:** `src/StockWallet.sol#366-384`

**Descripción:**
`withdrawAsset` limpia la `Position` pero no remueve el token del array `assets` ni limpia su `assetConfig`. El token sigue contando para el `allocationBps` total.

**Recomendación:** Llamar `_removeAsset(_token)` al final de `withdrawAsset`, o al menos setear `assetConfig[_token].allocationBps = 0`.

---

## ℹ️ Hallazgos Informativos

### I-01: Múltiples versiones de pragma de Solidity

**Detector:** `pragma`, `solc-version`

**Descripción:** 7 versiones diferentes de Solidity se usan entre el contrato y las librerías. `^0.8.20` contiene bugs conocidos (VerbatimInvalidDeduplication, FullInlinerNonExpressionSplitArgumentEvaluationOrder, MissingSideEffectsOnSelectorAccess).

**Recomendación:** Fijar versión exacta: `pragma solidity 0.8.24;`

---

### I-02: Convenciones de naming

**Detector:** `naming-convention`

**Descripción:** Múltiples violaciones de convenciones:
- `gas_fee` debería ser `gasFee` (mixedCase)
- `Adgent_percentage` debería ser `adgentPercentage`
- `updateGas_Fee` debería ser `updateGasFee`
- Struct `tokenAllocationConfig` debería ser `TokenAllocationConfig` (CapWords)
- Parámetros con underscore `_token`, `_amount` no siguen mixedCase

**Recomendación:** Renombrar a convenciones estándar de Solidity.

---

### I-03: Assembly en librerías de terceros

**Detector:** `assembly`

**Descripción:** `BytesLib`, `SafeERC20`, `StorageSlot` y `console` usan assembly inline. Esto es esperado en librerías auditadas, pero se debe verificar que se usen versiones auditadas.

---

### I-04: Igualdades estrictas peligrosas

**Detector:** `incorrect-equality`

**Líneas:** `#834`, `#777`, `#676`, `#755`, `#371`

**Descripción:** Uso de `== 0` en comparaciones de balance que podrían ser problemáticas si se espera polvo (dust).

**Recomendación:** Usar `<= 0` o un threshold mínimo donde aplique.

---

## 📋 Tabla de Hallazgos Resumida

| ID | Severidad | Título | Línea | Estado |
|----|-----------|--------|-------|--------|
| H-01 | 🔴 Alta | Reentrancy en `_swap` | 822-906 | No mitigado |
| H-02 | 🔴 Alta | `modifyPosition` público sin restricciones | 922-925 | No mitigado |
| H-03 | 🔴 Alta | Validación invertida `stopLossBps` | 637-646 | No mitigado |
| M-01 | 🟡 Media | Reentrancy en `selltoken`/`selltokenAll` | 662-769 | Parcial (invest tiene nonReentrant) |
| M-02 | 🟡 Media | Underflow en `addAsset` | 455-457 | No mitigado |
| M-03 | 🟡 Media | Doble evento en `depositAsset` | 355-362 | No mitigado |
| M-04 | 🟡 Media | Precio manipulable (sin TWAP) | 679-683 | No mitigado |
| M-05 | 🟡 Media | Falta pausabilidad | Global | No mitigado |
| L-01 | 🟢 Baja | `usdc` no es immutable | 112 | No mitigado |
| L-02 | 🟢 Baja | Complejidad ciclomática alta | 531-628 | No mitigado |
| L-03 | 🟢 Baja | Variables no inicializadas | 254, 939-940 | No mitigado |
| L-04 | 🟢 Baja | Llamadas externas en loops | 736-992 | No mitigado |
| L-05 | 🟢 Baja | Deletes costosos en loops | 761, 806 | No mitigado |
| L-06 | 🟢 Baja | `withdrawAsset` no limpia `assets[]` | 366-384 | No mitigado |
| I-01 | ℹ️ Info | Múltiples pragmas | Global | No mitigado |
| I-02 | ℹ️ Info | Naming conventions | Global | No mitigado |
| I-03 | ℹ️ Info | Assembly en librerías | Libs | N/A (auditado) |
| I-04 | ℹ️ Info | Igualdades estrictas | Múltiples | No mitigado |

---

## 🏁 Conclusión

El contrato `StockWallet.sol` presenta **3 vulnerabilidades de severidad alta** que deben ser addressadas antes de cualquier deploy a mainnet:

1. **`modifyPosition` público** es el hallazgo más crítico — permite a cualquier usuario manipular las posiciones y forzar ventas a precios arbitrarios.
2. **La falta de `nonReentrant` en `selltoken` y `selltokenAll`** combinada con llamadas externas a Uniswap V3 Universal Router crea vectores de reentrancy.
3. **La validación invertida de `stopLossBps`** bloquea la configuración correcta de stop loss.

Adicionalmente, el uso de precio spot en lugar de TWAP para SL/TP es un riesgo de manipulación que debe ser addressado antes de manejar fondos reales.

**Cobertura de tests:** 95.66% lines, 95.96% statements, 86.05% branches, 100% funcs (89 tests, 0 fallos).

---

*Documento generado por Dev Agent — Auditoría de seguridad StockWallet.sol*
*2026-10-22*