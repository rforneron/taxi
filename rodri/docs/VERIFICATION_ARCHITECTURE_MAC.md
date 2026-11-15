# MAC 10G Verification Architecture

## Scope and baseline

This document describes the initial SystemVerilog verification environment for
`taxi_eth_mac_10g`. Reusable MAC verification agents are kept in `../agents/`;
`../tests_eth_mac/` contains only the testbench and its runner. The PHY test
environment is left unchanged.

The initial implementation targets `MAC-BAS-01`, `MAC-BAS-02`, and
`MAC-BAS-03` from [TEST_PLAN_MAC_10G.xlsx](./TEST_PLAN_MAC_10G.xlsx), at
`DATA_W=32` and `DATA_W=64`. PTP, statistics, PAUSE/PFC, and gearbox features
are disabled.

## Reuse audit

| Existing asset | Use in MAC environment |
|---|---|
| `../tests_eth_phy/` XGMII/SERDES drivers, monitors, and PRBS31 agent | Audited, but no PHY component is instantiated or copied. Their transaction and PCS/PHY assumptions do not match the MAC AXI-Stream-to-XGMII packet boundary. |
| `src/eth/tb/taxi_eth_mac_10g/test_taxi_eth_mac_10g.py` | Reference for existing DUT integration and interface conventions; it is not part of this Verilator run. |
| Shared `taxi_axis_if` and the MAC RTL/file list | Reused directly as the DUT's AXI-Stream interfaces and elaboration sources. |
| Existing project test conventions | Reused the concise banner/result style and a PowerShell runner; reusable MAC components follow the existing `agents/` organization. |

No existing PHY driver, monitor, scoreboard, packet model, or coverage collector
was found suitable for direct reuse at this MAC boundary.

## DUT boundary

The testbench instantiates `taxi_eth_mac_10g` directly:

- TX input: `s_axis_tx` AXI-Stream packet interface, clocked by `tx_clk`.
- TX completion: `m_axis_tx_cpl`; the test keeps `tready` asserted and checks
  the completion tag.
- XGMII TX: `xgmii_txd`, `xgmii_txc`, and `xgmii_tx_valid`, observed passively
  by the monitor.
- XGMII RX: `xgmii_rxd`, `xgmii_rxc`, and `xgmii_rx_valid`, driven by the
  testbench.
- RX output: `m_axis_rx` AXI-Stream packet interface, with `tready` held high.
- TX and RX use separate clocks and resets so reset isolation can be tested.

## Testbench architecture

```text
AXI frame driver
      |
      v
 taxi_eth_mac_10g --------------------> XGMII TX
      ^                                      |
      |                                      v
 XGMII RX stimulus                    XGMII frame monitor
      |                                      |
      v                                      v
 m_axis_rx capture <------------------- Frame scoreboard
                                             |
                                             v
                               Functional coverage (planned)
```

### Components

| File | Responsibility | Current completeness |
|---|---|---|
| `../agents/mac_frame_pkg.sv` | Defines frame capacity and an independent reflected Ethernet CRC-32 reference function. | Implemented for frame/FCS checking. |
| `../agents/axi_frame_driver.sv` | Sends a configurable byte array and length over `s_axis_tx`, drives `tkeep`, `tlast`, and tag, and waits for AXI handshakes. | Implemented for contiguous, gap-free frames; randomized source stalls are not included. |
| `../agents/xgmii_frame_monitor.sv` | Passively detects XGMII START/TERM and reconstructs preamble, SFD, frame, and FCS bytes. | Implemented for TX packet capture; IFG measurement and broader malformed-control checking are not covered. |
| `../agents/mac_frame_scoreboard.sv` | Checks TX bytes, preamble/SFD and FCS, RX payload/status, and the TX completion tag. | Implemented for the three basic cases. |
| `../tests_eth_mac/tb_mac_basics.sv` | Instantiates the DUT and agents, drives valid RX XGMII frames, captures RX AXI output, and executes BAS-01/02/03. | Implemented as a directed smoke testbench. |
| `../tests_eth_mac/run_mac_basics.ps1` | Resolves the MAC RTL file list, builds with Verilator in WSL, and runs both data widths. | Implemented. |

### Flow

For TX tests, the AXI frame driver in `../agents/` presents an Ethernet frame
on AXI-Stream. The DUT
generates the XGMII packet, which the monitor reconstructs; the scoreboard
compares the bytes and FCS against the source frame and checks the completion
tag. Completion handshakes are captured concurrently so a one-cycle valid
pulse cannot be missed while waiting for the XGMII frame.

For RX tests, the testbench constructs a valid XGMII frame with START,
preamble, SFD, payload, reference FCS, TERM, and idle. It captures the AXI
output and checks payload, length, and error status.

## Execution status

| Test ID | Scenario | Result |
|---|---|---|
| MAC-BAS-01 | Independent TX/RX reset and traffic recovery | PASS at DATA_W=32 and 64 |
| MAC-BAS-02 | TX frame, preamble/SFD, FCS, and completion tag | PASS at DATA_W=32 and 64 |
| MAC-BAS-03 | Valid RX frame, payload, and status | PASS at DATA_W=32 and 64 |

Run the regression from the repository root:

```powershell
.\rodri\tests_eth_mac\run_mac_basics.ps1
```

This is directed simulation evidence for the listed scenarios, not exhaustive
MAC or IEEE 802.3 compliance. There is not yet a functional coverage collector
or coverage report; the workbook's remaining tests and feature bins remain
open. The coverage stage in the diagram is a target extension, not an
implemented component in this baseline.

## Configuration risk discovered

With PTP disabled and `PTP_TS_FMT_TOD` left at its default value of 1, the
current TX RTL path does not assert `m_axis_tx_cpl.tvalid`. The testbench sets
`PTP_TS_FMT_TOD=0` and `PTP_TS_W=96` to test ordinary TX packet completion
without enabling PTP. This is recorded as an RTL configuration risk, not
silently treated as covered by the passing regression. The default-parameter
combination should be triaged separately before relying on it in integration.
