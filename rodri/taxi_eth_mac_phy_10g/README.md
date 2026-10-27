# Auditoría y plan de pruebas: `taxi_eth_mac_phy_10g`

## 1. Objetivo y alcance

Este documento analiza el módulo integrado `taxi_eth_mac_phy_10g` y propone un plan para verificarlo con testbenches SystemVerilog y agentes de prueba.

El alcance es el top MAC/PHY, no el wrapper con FIFOs `taxi_eth_mac_phy_10g_fifo`. El top combina el MAC Ethernet, el PHY 10GBASE-R y funciones opcionales como PTP, autonegociación USXGMII, control de flujo y estadísticas. Por ello, conviene probarlo tanto por sus interfaces externas como mediante escenarios de integración TX→SERDES→RX.

Una simulación RTL permite verificar el comportamiento implementado y los casos cubiertos por el testbench; por sí sola no certifica conformidad completa con IEEE 802.3 ni sustituye la validación de interoperabilidad en hardware.

## 2. RTL y regresión existente

- Top: [`taxi_eth_mac_phy_10g.sv`](../../src/eth/rtl/taxi_eth_mac_phy_10g.sv)
- Camino TX: [`taxi_eth_mac_phy_10g_tx.sv`](../../src/eth/rtl/taxi_eth_mac_phy_10g_tx.sv)
- Camino RX: [`taxi_eth_mac_phy_10g_rx.sv`](../../src/eth/rtl/taxi_eth_mac_phy_10g_rx.sv)
- Wrapper de test Cocotb: [`test_taxi_eth_mac_phy_10g.sv`](../../src/eth/tb/taxi_eth_mac_phy_10g/test_taxi_eth_mac_phy_10g.sv)
- Regresión Cocotb: [`test_taxi_eth_mac_phy_10g.py`](../../src/eth/tb/taxi_eth_mac_phy_10g/test_taxi_eth_mac_phy_10g.py)
- Filelist del RTL: [`taxi_eth_mac_phy_10g.f`](../../src/eth/rtl/taxi_eth_mac_phy_10g.f)

La regresión existente está implementada en Python/Cocotb. El archivo SystemVerilog declara el top de simulación, interfaces y señales; los estímulos, monitores y aserciones de los tests existentes están principalmente en el archivo Python. Por tanto, los casos de abajo marcados como existentes no son una suite SystemVerilog de agentes.

## 3. Arquitectura funcional

```text
s_axis_tx
   │
   ├── MAC control TX opcional (LFC/PFC)
   ├── padding y adaptación AXI-Stream → Ethernet/BASE-R
   ├── PHY 10GBASE-R TX
   ▼
SERDES TX

SERDES RX
   │
   ├── PHY 10GBASE-R RX y recuperación de bloque
   ├── adaptación BASE-R → Ethernet/AXI-Stream
   ├── MAC control RX opcional (LFC/PFC)
   ▼
m_axis_rx

Funciones transversales/opcionales: completions TX, PTP, autonegociación
USXGMII y estadísticas transmitidas por m_axis_stat.
```

Los caminos TX y RX tienen dominios de reloj y reset separados (`tx_clk/tx_rst` y `rx_clk/rx_rst`). PTP y estadísticas también tienen interfaces de reloj/reset propias. Las pruebas deben respetar esos dominios y no asumir que las señales de control se observan sin latencia de sincronización.

## 4. Señales de interés

| Grupo | Interfaces/señales | Qué observar |
|---|---|---|
| Transmisión MAC | `s_axis_tx` | AXI-Stream de entrada: `tdata`, `tkeep`, `tvalid`, `tready`, `tlast`, `tuser` e `tid` cuando estén habilitados. En esta configuración, `tuser` indica error del usuario y `tid` identifica el paquete/completion. |
| Completion TX | `m_axis_tx_cpl` | Respuesta del transmisor asociada al paquete, incluido el tag. Con PTP habilitado puede transportar timestamp; verificar tag, orden y validez según el modo configurado. |
| Recepción MAC | `m_axis_rx` | AXI-Stream recibido: datos, `tkeep`, fin de paquete y `tuser`. El top reserva un bit de usuario para estado de error y, con PTP, bits adicionales para timestamp. |
| SERDES TX/RX | `serdes_{tx,rx}_data`, `*_hdr`, `*_data_valid`, `*_hdr_valid` | Datos y headers codificados, validez, alineación y recuperación de bloques. Para GBX también observar `serdes_tx_gbx_req_sync`, `serdes_tx_gbx_req_stall`, `serdes_tx_gbx_sync` y `serdes_rx_gbx_sync`. |
| Estado del PHY RX | `rx_block_lock`, `rx_high_ber`, `rx_error_count`, `rx_status`, `serdes_rx_bitslip`, `serdes_rx_reset_req` | Adquisición/pérdida de lock, BER alto, errores de bloque/alineación y solicitudes de bitslip/reset. `rx_error_count` no es un contador genérico de errores Ethernet; se relaciona con la comprobación PRBS31 del PHY. |
| Autonegociación | `an_*` | `an_running`, `an_complete`, `an_timeout`, `an_intr`, `an_usxgmii_mode` y las capacidades/resultados del partner. |
| PTP | `tx_ptp_ts_*`, `rx_ptp_ts_*`, `*_ptp_locked`, correcciones y `*_ts_cor_sync` | Timestamp transmitido/recibido, lock, pasos y sincronización de corrección cuando el modo PTP correspondiente está habilitado. |
| LFC/PFC y pausa | `tx_lfc_req/resend`, `rx_lfc_en/req/ack`; `tx_pfc_req/resend`, `rx_pfc_en/req/ack`; `tx_pause_req/ack` | Solicitudes, reconocimiento, generación/consumo de MAC Control Frames y pausas por prioridad. PFC depende de `PFC_EN`; el control MAC se integra cuando `PAUSE_EN || PFC_EN`. |
| Estadísticas | `stat_tx_*`, `stat_rx_*`, `stat_*_lfc/pfc/mcf`; `m_axis_stat` | Eventos de paquetes, bytes, tipos de error/control y su exportación por AXI-Stream. |
| Configuración MAC/PHY | `cfg_tx_*`, `cfg_rx_*`, `cfg_mcf_*` | Habilitación TX/RX, longitudes máximas, padding, IFG, PRBS31 y filtros/configuración de MAC Control Frames. |

El significado de los campos AXI-Stream debe tomarse de la interfaz y del módulo correspondiente. Para las pruebas de paquete, comparar el payload y los bytes válidos; no incluir preámbulo, delimitador de inicio ni FCS en la comparación de `m_axis_rx` salvo que el contrato de la interfaz indique lo contrario.

## 5. Cobertura ya presente en Cocotb

La regresión existente define los siguientes escenarios:

- TX y RX de tramas con diferentes longitudes y patrones.
- Alineación de transmisión (test condicionado a `DATA_W == 64`).
- Underrun TX y error de usuario TX.
- Adquisición, pérdida y recuperación de block lock RX mediante cambio de offset.
- LFC: recepción/terminación de frames de control y generación/resend de frames.
- PFC: frames de control, máscaras de prioridades y generación de solicitudes.
- Autonegociación USXGMII y comprobación de capacidad, link, velocidad y dúplex.

La matriz de compilación parametriza `DATA_W` en 32/64, GBX activado/desactivado, timestamp distribution PTP activado/desactivado, DIC activado/desactivado y PFC activado/desactivado. Los tests LFC/PFC y USXGMII se omiten cuando la función necesaria no está habilitada.

La suite es una buena referencia funcional, pero todavía deben revisarse o añadirse casos de cobertura dirigidos a errores de FCS/bloque, backpressure, contadores y mensajes de estadística, límites de longitud, reset en actividad, PTP/completions y casos negativos de filtros de control. La parametrización de compilación, por sí sola, no demuestra que cada comportamiento quede ejercitado en todas las variantes.

## 6. Agentes SystemVerilog propuestos

Para empezar no es necesario construir un framework UVM completo. Se pueden implementar módulos SV pequeños, con interfaces claras y tareas de envío/recepción, y añadir assertions/scoreboard en el testbench:

1. **`axis_tx_source`**: conduce `s_axis_tx`, genera tramas con `tkeep/tlast/tuser/tid` y aplica pausas aleatorias para probar handshakes y backpressure.
2. **`axis_tx_cpl_monitor`**: registra y valida las completions, correlacionando `tid` con los paquetes aceptados y comprobando el orden/latencia permitidos.
3. **`serdes_rx_source`**: inyecta en la entrada SERDES secuencias BASE-R válidas e inválidas, controlando headers, validez, offsets y, cuando corresponda, sincronización GBX.
4. **`serdes_tx_monitor`**: observa el flujo SERDES TX, reconstruye bloques/tramas y valida datos, FCS, IFG, control blocks y señales de sincronización.
5. **`axis_rx_monitor`**: recoge los paquetes recibidos y verifica payload, `tkeep`, fin de paquete, bit de error y timestamp si está habilitado.
6. **`mac_ctrl_agent`**: crea/decodifica LFC/PFC MAC Control Frames y modela solicitudes/acknowledgments de pausa.
7. **`ptp_agent`**: proporciona reloj/timestamp de referencia y permite variar los valores de corrección, distribución y reset.
8. **`scoreboard`**: mantiene colas esperadas para TX/RX y correlaciona tramas, completions, errores y estadística sin asumir una latencia fija innecesaria.

Una opción práctica es poner cada agente sobre una `interface` SV con `clocking block` y tareas como `send_frame`, `recv_frame` o `wait_for_lock`. La interfaz debe definir quién conduce cada señal y en qué flanco se muestrea; así se evitan carreras entre testbench y DUT. Para estímulos aleatorios, guardar la semilla permite reproducir fallos.

## 7. Plan de pruebas recomendado

### Prioridad 0 — smoke e integración de paquete

| Caso | Estímulo | Comprobaciones |
|---|---|---|
| Reset y estado inicial | Resetear RX/TX y luego liberar ambos dominios. | Sin transacciones espurias; señales de estado coherentes; TX/RX no emiten paquetes hasta habilitarse y recibir datos. |
| TX de trama normal | Enviar una trama AXI válida y recibir el bloque transmitido por SERDES. | Payload, delimitación, FCS correcto, completion/tag correspondiente y ausencia de errores. |
| RX de trama normal | Inyectar una trama válida por SERDES. | Payload/`tkeep`/`tlast` correctos en AXI RX; error desactivado; estadísticas RX coherentes. |
| Loopback integrado | Capturar el stream SERDES TX, adaptarlo al formato de entrada SERDES y devolverlo al RX tras la latencia/configuración de alineación necesaria. | Correspondencia TX→RX y ausencia de errores. Evitar conectar señales ciegamente si el escenario no satisface alineación, clocks o configuración del PHY. |

### Prioridad 1 — MAC y condiciones de protocolo

| Caso | Estímulo | Comprobaciones |
|---|---|---|
| Longitudes límite | Mínimo, alrededor del mínimo, máximo y máximo+1; con padding activado/desactivado. | Padding, rechazo/indicación de oversize, longitud y bytes válidos correctos. |
| IFG y DIC | Variar `cfg_tx_ifg`, habilitar/deshabilitar `DIC_EN` y probar secuencias de paquetes. | Separación/interpacket gap conforme a la configuración; sin pérdida, duplicación ni corrupción. |
| Backpressure AXI TX | Pausar al source antes y durante paquetes, alternar `tready` en el agente si se modela. | El DUT respeta `valid/ready`; no pierde ni duplica beats y no altera datos/campos. |
| Underflow y error TX | Interrumpir el suministro a mitad de trama o marcar error con `tuser`. | Código/señal de error en el stream SERDES; completion y estadísticas esperadas. |
| Errores RX | FCS incorrecto, bloque inválido, secuencia/trama malformada y longitud excesiva. | Política de forwarding/drop y `tuser` conforme a configuración; contadores de error específicos. |
| Filtros de MAC Control | Variar dirección destino/origen, EtherType, opcode y `cfg_mcf_rx_forward`. | Aceptar/consumir/reenviar solamente los frames que corresponden; no generar requests por frames no coincidentes. |

### Prioridad 2 — Control de flujo, PTP y gestión

| Caso | Estímulo | Comprobaciones |
|---|---|---|
| LFC XON/XOFF | Generar pausa, renovar y cancelar pausa con diferentes quanta; probar `resend` y acknowledge. | Estado de pausa, frames de control, requests/acks y estadísticas coherentes. |
| PFC por prioridad | Probar las ocho prioridades con máscaras individuales, combinadas y cero; probar quanta distintos. | Solo se afectan las prioridades solicitadas; contenido del frame y estado de pausa por prioridad correctos. |
| PTP TX/RX | Variar timestamps alrededor de inicio de paquete, con y sin corrección GBX. | Timestamp/completion asociado al paquete correcto; precisión dentro del modelo de ciclo/resolución configurado. |
| PTP enable/disable y reset | Compilar con timestamp/distribution habilitados y deshabilitados; resetear durante la inicialización. | Campos de timestamp presentes solo según configuración; lock/step y reset sin valores espurios. |
| Estadísticas AXI | Provocar eventos conocidos y consumir `m_axis_stat` con pausas. | ID, datos, framing y contadores exportados correctos; no perder eventos por backpressure. |

### Prioridad 3 — PHY, negociación y robustez

| Caso | Estímulo | Comprobaciones |
|---|---|---|
| Block lock RX | Secuencia BASE-R válida, offset incorrecto y recuperación. | `rx_block_lock`, bitslip/reset request y `rx_high_ber` evolucionan como se espera. |
| Validez/errores SERDES | Pausar `data_valid`/`hdr_valid`, inyectar headers inválidos o errores de bloque. | El RX no crea paquetes falsos y expone las indicaciones/contadores correctos. |
| PRBS31 | Habilitar/deshabilitar PRBS31 en cada dirección y suministrar secuencia buena/mala. | Estado/contador PRBS coherente; no confundirlo con los contadores de error de trama MAC. |
| GBX | Habilitar el gearbox e introducir sync/stall/request en secuencias relevantes. | Recuperación y temporización correctas; timestamps de corrección sincronizados si aplican. |
| USXGMII autonegotiation | Completar negociación, reiniciarla, variar abilities y simular timeout/link partner ausente. | Estados de negociación y resultado (link, speed, duplex) correctos; sin completar falsamente en timeout. |
| Reset bajo tráfico | Afirmar reset TX, RX, PTP o estadísticas durante una transferencia. | Recuperación limpia por dominio, sin transacciones fantasma ni estado colgado. |

## 8. Referencias de conformidad

Usar la edición de IEEE 802.3 definida por el proyecto como referencia normativa para las funciones Ethernet MAC/BASE-R. Las áreas más directamente relacionadas son el manejo MAC de tramas, BASE-R (Clause 49) y los anexos de control de flujo LFC (31B) y PFC (31D), tal como también se indican en el RTL. PTP debe contrastarse con el perfil IEEE 1588 aplicable.

USXGMII es una interfaz/función de negociación que debe verificarse contra la especificación USXGMII empleada por el diseño; no debe presentarse como una cláusula IEEE 802.3 sin comprobar la referencia exacta del proyecto. Antes de declarar conformidad, fijar explícitamente edición de norma, velocidad, parámetros de configuración, límites de trama, temporizaciones y criterios de aceptación.

## 9. Orden sugerido de implementación

1. Definir la interfaz de testbench, clocks/resets y los formatos de transacción comunes.
2. Implementar los agentes AXI TX, SERDES RX y SERDES TX; comenzar con TX/RX de una trama válida.
3. Añadir AXI RX monitor y scoreboard; completar el smoke y el loopback.
4. Añadir pruebas de errores y límites MAC, incluyendo las estadísticas que los reflejan.
5. Añadir agentes/casos de LFC/PFC, PTP y autonegociación como bloques separados y opcionales por parámetro.
6. Mantener una matriz que registre parámetros compilados, test ejecutado y cobertura funcional alcanzada; usar assertions para invariantes de handshaking y estabilidad de señales.

La configuración base del top tiene varias funciones opcionales deshabilitadas por defecto. El testbench debe habilitarlas explícitamente en sus parámetros y configurar las señales relacionadas; un test que no llega a esa configuración no demuestra cobertura de la función.
