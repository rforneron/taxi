$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$drive, $repositoryRelativePath = $repositoryRoot -split ':\\', 2
if (-not $repositoryRelativePath) {
    throw "Repository path is not on a mounted Windows drive: $repositoryRoot"
}
$linuxRepositoryRoot = "/mnt/$($drive.ToLower())/$($repositoryRelativePath.Replace('\', '/'))"

$verilatorRoot = '/home/rodri/.local/opt/taxi-verilator/usr/share/verilator'
$verilatorBin = '/home/rodri/.local/opt/taxi-verilator/usr/bin'
$buildDirectory = '/home/rodri/.cache/taxi/rodri-rx-frame-sync'
$wslPath = "/home/rodri/.local/bin:${verilatorBin}:/usr/bin:/bin"

& wsl.exe -d Ubuntu -- mkdir -p $buildDirectory
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create the SystemVerilog build directory in WSL.'
}

$verilator = "$verilatorBin/verilator"
$rtl = "$linuxRepositoryRoot/src/eth/rtl/taxi_eth_phy_10g_rx_frame_sync.sv"
$driver = "$linuxRepositoryRoot/rodri/agents/serdes_rx_header_driver.sv"
$monitor = "$linuxRepositoryRoot/rodri/agents/rx_status_monitor.sv"
$testbench = "$linuxRepositoryRoot/rodri/tests/tb_rx_frame_sync.sv"

& wsl.exe -d Ubuntu -- env "VERILATOR_ROOT=$verilatorRoot" "PATH=$wslPath" $verilator `
    --binary --timing --top-module tb_rx_frame_sync --Mdir $buildDirectory `
    $rtl $driver $monitor $testbench
if ($LASTEXITCODE -ne 0) {
    throw 'Verilator failed to compile the RX frame-sync testbench.'
}

& wsl.exe -d Ubuntu -- env "PATH=$wslPath" "$buildDirectory/Vtb_rx_frame_sync"
if ($LASTEXITCODE -ne 0) {
    throw 'The RX frame-sync testbench failed.'
}
