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
