# Auditoría de taxi_eth_phy_10g

## Objetivo

El objetivo de este trabajo es analizar, comprender y validar el funcionamiento interno del módulo `taxi_eth_phy_10g` del proyecto Taxi.

La auditoría se centra en:

- Comprender la arquitectura interna del PHY.
- Identificar los bloques funcionales que participan en la transmisión y recepción.
- Relevar las señales utilizadas entre bloques.
- Construir agentes de validación reutilizables.
- Diseñar y ejecutar pruebas funcionales.
- Verificar cumplimiento con IEEE 802.3 Clause 49 (10GBASE-R).
- Registrar hallazgos y posibles desviaciones del estándar.

---

## Estado Actual

### Entorno

- ✅ Repositorio clonado
- ✅ Entorno virtual configurado
- ✅ Cocotb configurado
- ✅ cocotbext-eth instalado
- ✅ Verilator 5.x funcionando

### Validación Inicial

Los testbench originales del proyecto fueron ejecutados exitosamente:

```text
TESTS = 3
PASS  = 3
FAIL  = 0
```

Esto confirma el correcto funcionamiento del entorno de simulación antes de comenzar la auditoría.

---

## Arquitectura General

### Camino TX

```text
XGMII
  ↓
taxi_xgmii_baser_enc
  ↓
taxi_eth_phy_10g_tx
  ↓
SERDES
```

### Camino RX

```text
SERDES
  ↓
taxi_eth_phy_10g_rx
  ↓
taxi_xgmii_baser_dec
  ↓
XGMII
```

---

## Bloques Analizados

### taxi_xgmii_baser_enc

Responsable de la codificación:

```text
XGMII → 64b/66b
```

Funciones principales:

- Generación de bloques 64b/66b.
- Conversión de caracteres de control.
- Generación de Sync Headers.

---

### taxi_eth_phy_10g_tx

Responsable del procesamiento de transmisión.

Funciones principales:

- Scrambling.
- Adaptación hacia la interfaz SERDES.
- Generación del flujo transmitido.

---

### taxi_eth_phy_10g_rx

Responsable del procesamiento de recepción.

Funciones principales:

- Frame Sync.
- Block Lock.
- Monitoreo BER.
- Descrambling.
- Recuperación de bloques 64b/66b.

---

### taxi_xgmii_baser_dec

Responsable de la decodificación:

```text
64b/66b → XGMII
```

Funciones principales:

- Reconstrucción de tramas XGMII.
- Decodificación de bloques de control.
- Recuperación de START, TERM e IDLE.


## Objetivos de la Auditoría

### Arquitectura

- Identificar todos los bloques internos.
- Documentar interfaces.
- Documentar flujo de datos.


### Señales

- Construir matriz de señales.
- Identificar origen y destino de cada señal.
- Identificar señales de estado del receptor.


### Validación Funcional

- Integridad de datos TX/RX.
- Block Lock.
- Loss of Lock.
- Lock Recovery.
- BER Monitoring.


### Cumplimiento de Estándar

- Validación de Sync Headers.
- Validación de bloques Start.
- Validación de bloques Terminate.
- Validación de Ordered Sets.
- Verificación de algoritmos de Block Lock.
- Verificación de detección de High BER.

---

## Próximos Pasos

### Fase 1

- Identificar señales internas reales.
- Construir matriz de señales.
- Confirmar conexiones entre módulos.

### Fase 2

- Diseñar agentes reutilizables.
- Diseñar monitores.
- Diseñar scoreboard.

### Fase 3

- Implementar pruebas funcionales.
- Implementar pruebas de sincronización.
- Implementar pruebas de cumplimiento IEEE.

### Fase 4

- Ejecutar auditoría.
- Registrar hallazgos.
- Documentar conclusiones.
