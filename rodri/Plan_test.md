# Plan de pruebas: `taxi_eth_phy_10g`

## Objetivo

Definir una estrategia de verificación en SystemVerilog para el PHY digital
`taxi_eth_phy_10g`, sus caminos de transmisión y recepción, y los bloques
principales que integran la codificación 10GBASE-R.

Este archivo describe pruebas propuestas; no significa que ya estén
implementadas ni que se haya demostrado conformidad formal con IEEE 802.3.

## Alcance y límites

El top recibe y entrega palabras XGMII y bloques 64b/66b en la interfaz
SERDES digital. Internamente integra:

- Transmisión: `taxi_xgmii_baser_enc` y `taxi_eth_phy_10g_tx_if`.
- Recepción: `taxi_eth_phy_10g_rx_if` y `taxi_xgmii_baser_dec`.
- Monitoreo RX: `taxi_eth_phy_10g_rx_frame_sync`,
  `taxi_eth_phy_10g_rx_ber_mon` y `taxi_eth_phy_10g_rx_watchdog`.

La referencia normativa principal para 10GBASE-R PCS es IEEE 802.3, cláusula
49; XGMII se define en la cláusula 46. Se deben confirmar los requisitos y
vectores de referencia contra la edición del estándar aplicable al proyecto.
Una simulación RTL puede verificar comportamiento digital observable, pero
por sí sola no certifica conformidad completa ni cubre la capa eléctrica,
PMA/PMD, transceptores, placa o tolerancias analógicas.

La PHY no sustituye las funciones de MAC. Las pruebas deben generar secuencias
XGMII legales y no atribuir a este top la generación o comprobación de FCS, ni
el filtrado por tamaños Ethernet de trama.

## Interfaz y señales de interés

Los nombres son los puertos del top
[`taxi_eth_phy_10g`](../src/eth/rtl/taxi_eth_phy_10g.sv). El reloj y reset
TX son independientes de los de RX.

| Camino | Señales | Uso en la verificación |
|---|---|---|
| Relojes y reset | `tx_clk`, `tx_rst`, `rx_clk`, `rx_rst` | Probar resets independientes y actividad con dominios TX/RX desacoplados. |
| XGMII TX | `xgmii_txd`, `xgmii_txc`, `xgmii_tx_valid` | Inyectar palabras XGMII, caracteres de control y ciclos sin datos válidos cuando corresponda. |
| SERDES TX | `serdes_tx_data`, `serdes_tx_hdr`, `serdes_tx_data_valid`, `serdes_tx_hdr_valid` | Comprobar datos, sync header y validez del bloque emitido. |
| XGMII RX | `xgmii_rxd`, `xgmii_rxc`, `xgmii_rx_valid` | Comparar palabras reconstruidas, control por byte y validez con la referencia. |
| SERDES RX | `serdes_rx_data`, `serdes_rx_hdr`, `serdes_rx_data_valid`, `serdes_rx_hdr_valid` | Inyectar bloques válidos, huecos de validez y errores de header. |
| Estado del bloque RX | `rx_block_lock`, `serdes_rx_bitslip` | Observar adquisición/pérdida de alineación y los pulsos de bitslip. |
| Errores RX | `rx_bad_block`, `rx_sequence_error`, `rx_high_ber` | Distinguir bloques de control inválidos, errores de secuencia y headers 64b/66b inválidos en una ventana. |
| Estado y recuperación RX | `rx_status`, `serdes_rx_reset_req` | Verificar los criterios temporizados del watchdog y las solicitudes de reset. |
| Contador PRBS RX | `rx_error_count` | Contar errores de PRBS31 cuando el modo está habilitado; **no** es un contador general de errores de trama/bloque. |
| Estado TX | `tx_bad_block` | Detectar una palabra/bloque XGMII de entrada no codificable según el encoder. |
| Gearbox TX | `tx_gbx_req_sync`, `tx_gbx_req_stall`, `tx_gbx_sync`, `serdes_tx_gbx_req_sync`, `serdes_tx_gbx_req_stall`, `serdes_tx_gbx_sync` | Verificar las señales de coordinación cuando `TX_GBX_IF_EN` está habilitado y sus valores inactivos cuando no lo está. |
| Gearbox RX | `serdes_rx_gbx_sync`, `rx_gbx_sync` | Verificar el paso y la alineación del sync cuando `RX_GBX_IF_EN` está habilitado. |
| Configuración PRBS31 | `cfg_tx_prbs31_enable`, `cfg_rx_prbs31_enable` | Activar/verificar el generador y checker PRBS solo cuando `PRBS31_EN` está configurado. |

Los buses codificados `encoded_tx_*` y `encoded_rx_*` son señales internas de
las instancias TX/RX, no puertos del top. Las pruebas de integración deben
priorizar las interfaces públicas. Se pueden observar señales internas en
pruebas unitarias específicas del submódulo, evitando depender de rutas
jerárquicas privadas en el scoreboard del top.

### Interpretación de estado RX

- `rx_block_lock` proviene del detector de sync headers del receptor.
- `rx_high_ber` se calcula a partir de sync headers inválidos, no de una medida
  analógica ni de errores arbitrarios en los bits de payload.
- `rx_bad_block` y `rx_sequence_error` los produce el decoder 64b/66b a partir
  de bloques/control y secuencias XGMII.
- `rx_error_count` mide discrepancias PRBS31 en el checker, con anchura de 7
  bits. Para probarlo hay que habilitar `PRBS31_EN` y `cfg_rx_prbs31_enable`;
  en el modo normal no debe usarse como sustituto de `rx_bad_block`.
- `rx_status` y `serdes_rx_reset_req` dependen del watchdog y de ventanas de
  tiempo; no son señales de respuesta inmediata a un único bloque.

## Estrategia de testbench SystemVerilog

Usar un testbench autochecking organizado en tareas de estímulo, monitores,
modelo de referencia/scoreboard y checks con `$fatal` ante errores. Separar:

1. Pruebas de integración del top con loopback digital SERDES TX a RX usando
   un reloj común o un modelo de enlace que respete los dominios de reloj.
2. Pruebas unitarias para encoder/decoder y para los monitores RX temporizados.
3. Pruebas de parámetros: `DATA_W` 32 y 64; opciones de pipeline, bit reverse,
   scrambler, PRBS31 y gearbox según las configuraciones que usa el diseño.

Mantener una referencia de bloques XGMII/64b/66b independiente de la lógica RTL
que se prueba. No comprobar solo que dos instancias con el mismo defecto se
cancelan en loopback: agregar vectores de referencia para codificación,
headers, bloques de control y secuencias.

Para no gastar cientos de miles de ciclos, configurar un `COUNT_125US` pequeño
en las pruebas del BER monitor/watchdog. Comprobar las transiciones en los
límites de ventana de acuerdo con el parámetro y con los ciclos de latencia del
testbench.

### Primera prueba SystemVerilog implementada

Las pruebas SystemVerilog cubren el sincronizador RX y los caminos de datos TX,
RX y loopback del top. Los agentes reutilizables son:

- [`serdes_rx_header_driver.sv`](./agents/serdes_rx_header_driver.sv) aplica
  sync headers válidos o inválidos y permite dejar ciclos sin header válido.
- [`xgmii_tx_driver.sv`](./agents/xgmii_tx_driver.sv) presenta palabras y
  caracteres de control por la interfaz XGMII de transmisión.
- [`serdes_rx_data_driver.sv`](./agents/serdes_rx_data_driver.sv) presenta
  bloques SERDES completos con sus indicadores de validez.
- [`serdes_tx_monitor.sv`](./agents/serdes_tx_monitor.sv) registra los bloques
  y headers emitidos por SERDES TX para comprobarlos o reproducirlos.
- [`xgmii_rx_monitor.sv`](./agents/xgmii_rx_monitor.sv) registra las palabras
  reconstruidas por XGMII RX junto con sus indicadores de error.
- [`rx_status_monitor.sv`](./agents/rx_status_monitor.sv) registra transiciones
  de lock, bitslip y status, además de pulsos de error y cambios del contador
  PRBS. Los contadores se reinician con `rst`.

El testbench
[`tb_eth_phy_10g_data.sv`](./tests/tb_eth_phy_10g_data.sv) ejecuta tres etapas:
comprueba headers TX, reproduce en RX los bloques SERDES capturados y verifica
la salida XGMII, y conecta la salida SERDES TX a la entrada SERDES RX para
verificar el loopback del top. Usa un reloj común, `DATA_W=64`, scrambler activo
y pipeline SERDES de dos etapas. Estos son casos básicos; aún no cubren todos
los parámetros, errores de protocolo ni una certificación de IEEE 802.3.

- [`tb_rx_frame_sync.sv`](./tests/tb_rx_frame_sync.sv) comprueba reset,
  adquisición tras 64 headers válidos, rechazo de un header inválido no válido,
  pérdida tras 16 headers inválidos consecutivos, bitslip y readquisición.

El driver cambia sus salidas en el flanco descendente y deja que el DUT las
muestree en el flanco ascendente, evitando carreras. Los monitores solo capturan
señales; las comparaciones de datos y los `$fatal` pertenecen a los testbenches.

Desde PowerShell, ejecutar las dos pruebas:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rodri\tests\run_rx_frame_sync.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rodri\tests\run_eth_phy_10g_data.ps1
```

El cambio de política solo se aplica a cada proceso lanzado. Los scripts
compilan con Verilator en WSL (distribución `Ubuntu`) y dejan los artefactos de
compilación fuera del repositorio. Usan la instalación local de Verilator
creada para este entorno.

## Casos de prueba propuestos

### A. Top y transmisión

| ID | Prueba | Estímulo y resultado esperado |
|---|---|---|
| PHY-T01 | Reset e inactividad | Aplicar y liberar `tx_rst` y `rx_rst` por separado. Verificar el estado de los bloques que sí implementan reset, drenar la latencia de pipeline antes de comprobar tráfico y no asumir que un reset de un camino reinicia el otro o todos los registros del top. |
| PHY-T02 | Bloques de datos 64b/66b | Enviar palabras de datos XGMII. Comprobar sync header `10`, secuencia de datos codificada y scrambler contra vectores de referencia. `tx_bad_block` debe permanecer inactivo para entradas válidas. |
| PHY-T03 | Bloques de control | Enviar IDLE, START, TERM y caracteres de control XGMII válidos. Verificar sync header `01`, block type/payload, ubicación de START y terminación en cada posición legal admitida por el encoder. |
| PHY-T04 | Tramas y patrones | Enviar varias tramas XGMII legales con patrones todo cero, todo uno, alternante, contador y pseudoaleatorio; comprobar orden, contenido, START/TERM e IFG en la referencia TX/RX. No esperar que la PHY agregue FCS. |
| PHY-T05 | Entrada no válida | Probar combinaciones/caracteres de control XGMII no codificables y verificar el comportamiento de error documentado por el encoder y `tx_bad_block`. |
| PHY-T06 | `xgmii_tx_valid` | En configuración con gearbox, introducir ciclos no válidos y comprobar que los datos de entrada y el avance del encoder respetan `xgmii_tx_valid`; no tratar el puerto como backpressure general fuera del modo que lo habilita. |

### B. Recepción y alineación

| ID | Prueba | Estímulo y resultado esperado |
|---|---|---|
| PHY-R01 | Decoder y loopback limpio | Inyectar bloques codificados conocidos por SERDES y verificar reconstrucción de `xgmii_rxd/xgmii_rxc`. Después probar loopback TX→RX con ambos caminos inicializados y esperar la adquisición de lock antes de comparar tráfico. |
| PHY-R02 | Adquisición de block lock | Después del reset, enviar 64 sync headers válidos `01`/`10`; comprobar que `rx_block_lock` se adquiere. Confirmar que headers con `serdes_rx_hdr_valid=0` no se cuentan. |
| PHY-R03 | Pérdida y readquisición | Con lock adquirido, inyectar 16 headers inválidos consecutivos `00`/`11` para provocar la pérdida de lock; luego restaurar una secuencia válida. Verificar `serdes_rx_bitslip` conforme a `BITSLIP_HIGH_CYCLES`/`BITSLIP_LOW_CYCLES` y readquisición tras 64 headers válidos. |
| PHY-R04 | Validez y pipeline | Variar `serdes_rx_data_valid`/`serdes_rx_hdr_valid` en la configuración gearbox pertinente. Verificar que data, header, validez y sync conservan alineación con `SERDES_PIPELINE` configurado. |
| PHY-R05 | Errores de bloque y secuencia | Inyectar block type/control codes ilegales y secuencias START/TERM mal ubicadas en bloques recibidos. Comprobar los pulsos `rx_bad_block`/`rx_sequence_error` y el XGMII de error reconstruido según el decoder. |
| PHY-R06 | Ancho de datos | Ejecutar los vectores esenciales para `DATA_W=64` y `DATA_W=32`, verificando repacking, validez, orden de palabras y reconstrucción sin pérdidas. |

### C. Monitores, recuperación y configuraciones

| ID | Prueba | Estímulo y resultado esperado |
|---|---|---|
| PHY-M01 | High BER debajo/encima del umbral | En ventanas acortadas, inyectar menos de 16 headers de sync inválidos y luego alcanzar 16. Verificar el instante de aserción de `rx_high_ber` y que headers con `serdes_rx_hdr_valid=0` no se contabilicen; confirmar el umbral normativo aplicable antes de afirmar conformidad. |
| PHY-M02 | Recuperación de BER | Tras activar High BER, enviar una ventana limpia y verificar la desaserción según el temporizador/contador implementado. |
| PHY-M03 | Watchdog RX saludable | Mantener lock y enviar el sync header de control requerido en cada ventana. En la lógica actual, verificar que `rx_status` se afirma después de 16 ventanas buenas consecutivas. |
| PHY-M04 | Watchdog RX degradado | Retirar lock o dejar de enviar el sync header de control; por separado, acumular errores de bloque/secuencia hasta el límite. Comprobar la caída de `rx_status` y el pulso de `serdes_rx_reset_req` tras 16 ventanas de error consecutivas en la lógica actual. |
| PHY-M05 | PRBS31 TX/RX | Con `PRBS31_EN=1`, habilitar ambos modos. Comparar la secuencia PRBS conocida y comprobar conteo cero sin errores; inyectar flips de bits y verificar que `rx_error_count` cuenta discrepancias. Deshabilitar el checker y comprobar el comportamiento inactivo documentado. |
| PHY-M06 | Scrambler y bit reverse | Comparar vectores conocidos con scrambler activo/deshabilitado y `BIT_REVERSE` habilitado/deshabilitado. Aplicar la reversión coherentemente al modelo SERDES y comprobar los sync headers. |
| PHY-M07 | Gearbox | Con `TX_GBX_IF_EN`/`RX_GBX_IF_EN` habilitados, aplicar solicitudes, stall y sync en límites de bloque y comprobar propagación/alineación; repetir configuración deshabilitada y verificar señales inactivas. |

Los conteos exactos de lock, BER, watchdog y la duración de bitslip deben
derivarse de los parámetros y contadores RTL y contrastarse con los requisitos
normativos aplicables. Evitar asumir que un error de bit en `serdes_rx_data`
debe activar `rx_high_ber`: ese monitor observa headers inválidos.

## Cobertura y prioridad

- **P0:** reset, vector de referencia TX, recepción de bloque válido, loopback,
  adquisición/pérdida/readquisición de lock, errores básicos del decoder y
  checks de status sin tráfico erróneo.
- **P1:** umbrales BER/watchdog con ventanas reducidas, PRBS31 con error
  inyectado, configuraciones de 32/64 bits y pipeline.
- **P2:** combinaciones de gearbox, bit reverse, patrones aleatorios con semilla
  reproducible y regresiones de límites de block type.

Registrar en cada corrida la configuración de parámetros, semilla, ciclos de
lock/errores/status y el vector que provocó un fallo. Ejecutar cada check sobre
la muestra temporal correcta para evitar carreras entre testbench y `always_ff`.

## Cobertura ya existente

El test actual
[`test_taxi_eth_phy_10g.py`](../src/eth/tb/taxi_eth_phy_10g/test_taxi_eth_phy_10g.py)
está escrito en cocotb, no en SystemVerilog. Parametriza anchos 32/64 y contiene
pruebas de tráfico RX, tráfico TX y reacquisición de frame sync tras cambiar el
offset de bits. Usa scrambler activo, pipeline SERDES de 2, bit reverse
deshabilitado y gearbox deshabilitado. Aunque habilita la capacidad PRBS31 por
parámetro, deja `cfg_tx_prbs31_enable` y `cfg_rx_prbs31_enable` inactivos en el
testbench; no verifica el modo PRBS ni el contador PRBS.

En `rodri/agents` existe
[`rx_status_monitor.sv`](./agents/rx_status_monitor.sv), marcado en el propio
archivo como no probado. No se encontró un testbench autochecking en
SystemVerilog dentro de `rodri`. Por lo tanto, el plan de este README
complementa la regresión existente; no describe las pruebas cocotb ni el
monitor como pruebas SystemVerilog ya implementadas.
