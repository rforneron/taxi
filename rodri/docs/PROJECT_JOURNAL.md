# Project Journal

## 2026-11-14 - Initial PHY test implementation

Implemented and ran the first selected tests for `taxi_eth_phy_10g`:

- Added the reusable PRBS31 agent in `../agents/prbs31_agent.sv`.
- Added T01 reset independence and recovery coverage in `../tests/tb_phy_reset.sv`.
- Extended existing testbenches for T02, T03, R01, R02, R03, M01, and M02.
- Added P01-P03 PRBS31 TX, clean RX, and injected-error tests in `../tests/tb_phy_prbs31.sv`.
- Added `../tests/run_selected_phy_tests.ps1` to compile and run the selected PHY testbenches.

Validation command:

```powershell
.\rodri\tests\run_selected_phy_tests.ps1
```

Result: all 11 selected IDs passed with Verilator 5.032: T01-T03, R01-R03, M01-M02, and P01-P03. P03 detected the injected error (reported count: 3).

The test plan remains partially complete. Unimplemented IDs, broader parameter/configuration coverage, and functional coverage instrumentation remain open.

## 2026-11-14 - Remaining planned PHY tests

Implemented the remaining test-plan IDs:

- T04-T05: payload pattern loopback and illegal XGMII control-symbol reporting, added to `../tests/tb_eth_phy_10g_data.sv`.
- T06 and M07: gearbox valid-data gating, sync marker alignment, request/stall propagation, in `../tests/tb_phy_tx_gbx.sv`.
- R04-R05: RX pipeline alignment and decoder rejection of illegal block types/control codes, in `../tests/tb_phy_rx_extended.sv`.
- R06 and M06: end-to-end loopback at DATA_W=32/64 and scrambled loopback with bit reversal enabled, in `../tests/tb_phy_configs.sv`.
- M03-M04: watchdog healthy status, lock-loss clearing, and reset-request behavior, in `../tests/tb_rx_watchdog.sv`.
- M05: integrated TX-to-RX PRBS31 loopback, in `../tests/tb_phy_prbs_loopback.sv`.
- P04: PRBS enable/disable and disabled-reset phase retention, added to `../tests/tb_phy_prbs31.sv`.
- P05: PRBS valid gating and phase continuity with bubbles at DATA_W=32/64, in `../tests/tb_phy_prbs_width.sv`.
- Extended `../tests/run_selected_phy_tests.ps1` to include all of these benches.
- Updated the execution states, coverage summaries, and IEEE traceability rows in `TEST_PLAN.xlsx`.

Validation command:

```powershell
.\rodri\tests\run_selected_phy_tests.ps1
```

Result: all planned IDs T01-T06, R01-R06, M01-M07, and P01-P05 passed with Verilator 5.032. This is simulation evidence for the scenarios above, not a claim of exhaustive IEEE 802.3 compliance. Functional coverage instrumentation, more exhaustive negative-case enumeration, and additional parameter combinations remain future work.

## 2026-11-14 - Unified testbench output

Standardized the console output for all 11 selected PHY testbenches:

- Added a test banner with the covered test IDs at the start of each testbench.
- Added concise scenario metrics and a common `RESULT : PASS` footer.
- Removed intermediate per-test PASS messages so each bench has one unambiguous final result.
- Preserved `$fatal` failures and the existing runner behavior.

Validation:

```powershell
.\rodri\tests\run_selected_phy_tests.ps1
```

Result: all 11 testbenches compiled and passed; each emitted one test banner and one `RESULT : PASS` footer.

## 2026-11-14 - MAC 10G DUT architecture

Added `../DUT TAXI_ETH_MAC_10G.md` as an architectural baseline for `taxi_eth_mac_10g`, covering its interfaces, clocks/resets, hierarchy, TX/RX datapaths, optional features, FSMs, and verification risks. No Test Plan or verification components were created.

## 2026-11-14 - MAC 10G DUT source-backed corrections

Updated `../DUT TAXI_ETH_MAC_10G.md` against the MAC RTL to clarify that:

- Timestamp metadata (`PTP_TS_EN`) is independently selectable from the PTP time-distribution leaf (`PTP_TS_EN && PTP_TD_EN`); timestamp outputs are passthrough when the leaf is absent.
- RX AXI-Stream backpressure is unsupported (`tready` is not consumed, including by the top-level MAC-control RX configuration).
- `stat_rx_err_bad_block` remains zero in both 32-bit and 64-bit RX variants.
- Gearbox control is TX request/stall/sync plus RX `xgmii_rx_valid` gating when its respective enable is set; RX has no separate request/sync interface.
- 31B and 31D are referred to as annexes per RTL comments, PFC is noted alongside IEEE 802.1Qbb, and standard-edition/PTP Clause 90 caveats are explicit.

## 2026-11-14 - MAC 10G verification plan baseline

Created `../docs/TEST_PLAN_MAC_10G.xlsx` with the DUT Overview, Test Plan, Coverage Matrix, IEEE Traceability Matrix, and Verification Status worksheets. The Test Plan contains 49 source-scoped MAC cases using the requested nine columns and five test categories. All cases are marked planned/not implemented; no MAC tests were implemented or executed.

The plan explicitly excludes PHY PRBS31/PCS/PMD/SERDES, general VLAN tag manipulation, PTP event-message processing, and RX `tready` backpressure as unsupported/out of scope. IEEE mappings are conservative and edition-dependent where noted. Updated the DUT document with the workbook reference. The existing PHY workbook was not modified; no testbench, driver, or RTL code was added.

## 2026-11-14 - MAC 10G basic verification environment

Added a minimal MAC-only SystemVerilog verification environment for
`MAC-BAS-01` through `MAC-BAS-03`. Reusable components are stored under
`../agents/`; `../tests_eth_mac/` contains only the testbench and runner:

- `../agents/mac_frame_pkg.sv`: Ethernet CRC-32 reference implementation.
- `../agents/axi_frame_driver.sv`: configurable AXI-Stream frame and tag driver.
- `../agents/xgmii_frame_monitor.sv`: TX frame capture and preamble/SFD reconstruction.
- `../agents/mac_frame_scoreboard.sv`: TX/RX payload, FCS, status, and completion-tag checks.
- `../tests_eth_mac/tb_mac_basics.sv`: independent reset, TX, and RX directed scenarios.
- `../tests_eth_mac/run_mac_basics.ps1`: Verilator runner for DATA_W=32 and 64.

No files under `../tests_eth_phy/` were modified or reused directly; the
existing PHY components operate at a different verification boundary. The
MAC Cocotb testbench was used only as an interface reference. The component
reuse audit, final data flow, execution scope, and configuration caveat are
documented in [VERIFICATION_ARCHITECTURE_MAC.md](./VERIFICATION_ARCHITECTURE_MAC.md).

Validation command:

```powershell
.\rodri\tests_eth_mac\run_mac_basics.ps1
```

Result: MAC-BAS-01, MAC-BAS-02, and MAC-BAS-03 passed at DATA_W=32 and 64 with
Verilator 5.032. The workbook records these executions; broader test-plan
coverage and functional coverage instrumentation remain open.

The baseline uncovered a TX completion configuration risk: with PTP disabled
and default `PTP_TS_FMT_TOD=1`, the RTL does not assert completion valid. The
testbench explicitly selects `PTP_TS_FMT_TOD=0` and `PTP_TS_W=96` to exercise
non-PTP packet completion. The default combination remains unverified and
requires RTL triage.
