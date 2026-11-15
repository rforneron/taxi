param(
    [string[]]$Only = @()
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$drive, $repositoryRelativePath = $repositoryRoot -split ':\\', 2
if (-not $repositoryRelativePath) {
    throw "Repository path is not on a mounted Windows drive: $repositoryRoot"
}
$linuxRepositoryRoot = "/mnt/$($drive.ToLower())/$($repositoryRelativePath.Replace('\', '/'))"

$verilatorRoot = '/home/rodri/.local/opt/taxi-verilator/usr/share/verilator'
$verilatorBin = '/home/rodri/.local/opt/taxi-verilator/usr/bin'
$buildRoot = '/home/rodri/.cache/taxi/rodri-eth-phy-selected'
$wslPath = "/home/rodri/.local/bin:${verilatorBin}:/usr/bin:/bin"
$fileList = Join-Path $repositoryRoot 'src\eth\rtl\taxi_eth_phy_10g.f'

function Get-RtlSourceFiles([string]$FileListPath) {
    $fileListDirectory = Split-Path -Parent $FileListPath

    foreach ($line in Get-Content -LiteralPath $FileListPath) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) {
            continue
        }

        $resolvedPath = [IO.Path]::GetFullPath((Join-Path $fileListDirectory $entry))
        if ($resolvedPath.StartsWith(
                (Join-Path $repositoryRoot 'src\eth\lib\taxi\'),
                [StringComparison]::OrdinalIgnoreCase)) {
            $sharedLibraryPrefix = Join-Path $repositoryRoot 'src\eth\lib\taxi\'
            $resolvedPath = "$repositoryRoot\" + $resolvedPath.Substring($sharedLibraryPrefix.Length)
        }
        if ([IO.Path]::GetExtension($resolvedPath) -eq '.f') {
            Get-RtlSourceFiles $resolvedPath
        } else {
            $sourceDrive, $sourceRelativePath = $resolvedPath -split ':\\', 2
            if (-not $sourceRelativePath) {
                throw "RTL source path is not on a mounted Windows drive: $resolvedPath"
            }
            "/mnt/$($sourceDrive.ToLower())/$($sourceRelativePath.Replace('\', '/'))"
        }
    }
}

$rtlSources = @(Get-RtlSourceFiles $fileList | Select-Object -Unique)
if ($rtlSources.Count -eq 0) {
    throw "No RTL source files were found in $fileList"
}

$testCases = @(
    @{
        Name = 't01-reset'
        Top = 'tb_phy_reset'
        Sources = @("$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_reset.sv")
    }
    @{
        Name = 't02-t03-r01-data'
        Top = 'tb_eth_phy_10g_data'
        Sources = @(
            "$linuxRepositoryRoot/rodri/agents/xgmii_tx_driver.sv"
            "$linuxRepositoryRoot/rodri/agents/serdes_rx_data_driver.sv"
            "$linuxRepositoryRoot/rodri/agents/serdes_tx_monitor.sv"
            "$linuxRepositoryRoot/rodri/agents/xgmii_rx_monitor.sv"
            "$linuxRepositoryRoot/rodri/tests_eth_phy/tb_eth_phy_10g_data.sv"
        )
    }
    @{
        Name = 'r02-r03-frame-sync'
        Top = 'tb_rx_frame_sync'
        Sources = @(
            "$linuxRepositoryRoot/rodri/agents/serdes_rx_header_driver.sv"
            "$linuxRepositoryRoot/rodri/agents/rx_status_monitor.sv"
            "$linuxRepositoryRoot/rodri/tests_eth_phy/tb_rx_frame_sync.sv"
        )
    }
    @{
        Name = 'm01-m02-ber'
        Top = 'tb_rx_ber_mon'
        Sources = @(
            "$linuxRepositoryRoot/rodri/agents/serdes_rx_header_driver.sv"
            "$linuxRepositoryRoot/rodri/tests_eth_phy/tb_rx_ber_mon.sv"
        )
    }
    @{
        Name = 'm03-m04-watchdog'
        Top = 'tb_rx_watchdog'
        Sources = @(
            "$linuxRepositoryRoot/rodri/agents/serdes_rx_header_driver.sv"
            "$linuxRepositoryRoot/rodri/tests_eth_phy/tb_rx_watchdog.sv"
        )
    }
    @{
        Name = 'p01-p03-prbs31'
        Top = 'tb_phy_prbs31'
        Sources = @(
            "$linuxRepositoryRoot/rodri/agents/prbs31_agent.sv"
            "$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_prbs31.sv"
        )
    }
    @{
        Name = 'm05-prbs-loopback'
        Top = 'tb_phy_prbs_loopback'
        Sources = @("$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_prbs_loopback.sv")
    }
    @{
        Name = 'p05-prbs-width'
        Top = 'tb_phy_prbs_width'
        Sources = @(
            "$linuxRepositoryRoot/rodri/agents/prbs31_agent.sv"
            "$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_prbs_width.sv"
        )
    }
    @{
        Name = 'r04-r05-rx-extended'
        Top = 'tb_phy_rx_extended'
        Sources = @("$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_rx_extended.sv")
    }
    @{
        Name = 'r06-m06-configs'
        Top = 'tb_phy_configs'
        Sources = @("$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_configs.sv")
    }
    @{
        Name = 't06-m07-tx-gbx'
        Top = 'tb_phy_tx_gbx'
        Sources = @("$linuxRepositoryRoot/rodri/tests_eth_phy/tb_phy_tx_gbx.sv")
    }
)

if ($Only.Count -gt 0) {
    $testCases = @($testCases | Where-Object {
        $Only -contains $_.Name -or $Only -contains $_.Top
    })
    if ($testCases.Count -eq 0) {
        throw "No selected test matched: $($Only -join ', ')"
    }
}

$verilator = "$verilatorBin/verilator"
foreach ($testCase in $testCases) {
    $buildDirectory = "$buildRoot/$($testCase.Name)"
    & wsl.exe -d Ubuntu -- mkdir -p $buildDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the WSL build directory for $($testCase.Name)."
    }

    $verilatorArgs = @(
        '--binary'
        '--timing'
        '--top-module'
        $testCase.Top
        '--Mdir'
        $buildDirectory
    ) + $rtlSources + $testCase.Sources

    & wsl.exe -d Ubuntu -- env "VERILATOR_ROOT=$verilatorRoot" "PATH=$wslPath" `
        $verilator @verilatorArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Verilator failed to compile $($testCase.Top)."
    }

    & wsl.exe -d Ubuntu -- env "PATH=$wslPath" "$buildDirectory/V$($testCase.Top)"
    if ($LASTEXITCODE -ne 0) {
        throw "Testbench $($testCase.Top) failed."
    }
}
