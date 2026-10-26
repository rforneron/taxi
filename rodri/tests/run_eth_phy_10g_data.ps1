$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$drive, $repositoryRelativePath = $repositoryRoot -split ':\\', 2
if (-not $repositoryRelativePath) {
    throw "Repository path is not on a mounted Windows drive: $repositoryRoot"
}
$linuxRepositoryRoot = "/mnt/$($drive.ToLower())/$($repositoryRelativePath.Replace('\', '/'))"
$sharedLibraryLinkPrefix = Join-Path $repositoryRoot 'src\eth\lib\taxi\'
$sharedSourcePrefix = "$repositoryRoot\"

$verilatorRoot = '/home/rodri/.local/opt/taxi-verilator/usr/share/verilator'
$verilatorBin = '/home/rodri/.local/opt/taxi-verilator/usr/bin'
$buildDirectory = '/home/rodri/.cache/taxi/rodri-eth-phy-10g-data'
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
        if ($resolvedPath.StartsWith($sharedLibraryLinkPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $resolvedPath = $sharedSourcePrefix + $resolvedPath.Substring($sharedLibraryLinkPrefix.Length)
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

& wsl.exe -d Ubuntu -- mkdir -p $buildDirectory
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create the SystemVerilog build directory in WSL.'
}

$driverSources = @(
    "$linuxRepositoryRoot/rodri/agents/xgmii_tx_driver.sv"
    "$linuxRepositoryRoot/rodri/agents/serdes_rx_data_driver.sv"
    "$linuxRepositoryRoot/rodri/agents/serdes_tx_monitor.sv"
    "$linuxRepositoryRoot/rodri/agents/xgmii_rx_monitor.sv"
    "$linuxRepositoryRoot/rodri/tests/tb_eth_phy_10g_data.sv"
)

$verilator = "$verilatorBin/verilator"
$verilatorArgs = @(
    '--binary'
    '--timing'
    '--top-module'
    'tb_eth_phy_10g_data'
    '--Mdir'
    $buildDirectory
) + $rtlSources + $driverSources

& wsl.exe -d Ubuntu -- env "VERILATOR_ROOT=$verilatorRoot" "PATH=$wslPath" `
    $verilator @verilatorArgs
if ($LASTEXITCODE -ne 0) {
    throw 'Verilator failed to compile the Ethernet PHY data-path testbench.'
}

& wsl.exe -d Ubuntu -- env "PATH=$wslPath" "$buildDirectory/Vtb_eth_phy_10g_data"
if ($LASTEXITCODE -ne 0) {
    throw 'The Ethernet PHY data-path testbench failed.'
}
