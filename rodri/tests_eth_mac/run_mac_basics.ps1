param(
    [ValidateSet(32, 64)]
    [int[]]$DataWidth = @(64, 32)
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
$buildRoot = '/home/rodri/.cache/taxi/rodri-eth-mac-basics'
$wslPath = "/home/rodri/.local/bin:${verilatorBin}:/usr/bin:/bin"
$fileList = Join-Path $repositoryRoot 'src\eth\rtl\taxi_eth_mac_10g.f'

function Get-RtlSourceFiles([string]$FileListPath) {
    $fileListDirectory = Split-Path -Parent $FileListPath

    foreach ($line in Get-Content -LiteralPath $FileListPath) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) {
            continue
        }

        $resolvedPath = [IO.Path]::GetFullPath((Join-Path $fileListDirectory $entry))
        $sharedLibraryMarker = '\lib\taxi\'
        $sharedLibraryIndex = $resolvedPath.IndexOf(
            $sharedLibraryMarker,
            [StringComparison]::OrdinalIgnoreCase)
        if ($sharedLibraryIndex -ge 0) {
            $sharedLibraryRelativePath = $resolvedPath.Substring(
                $sharedLibraryIndex + $sharedLibraryMarker.Length)
            $resolvedPath = Join-Path $repositoryRoot $sharedLibraryRelativePath
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

$agentFiles = @(
    'mac_frame_pkg.sv'
    'axi_frame_driver.sv'
    'xgmii_frame_monitor.sv'
    'mac_frame_scoreboard.sv'
)
$testbenchFiles = @(
    'tb_mac_basics.sv'
)
$verificationSources = @(
    foreach ($file in $agentFiles) {
        "$linuxRepositoryRoot/rodri/agents/$file"
    }
    foreach ($file in $testbenchFiles) {
        "$linuxRepositoryRoot/rodri/tests_eth_mac/$file"
    }
)

$verilator = "$verilatorBin/verilator"
foreach ($width in $DataWidth) {
    $buildDirectory = "$buildRoot/data-w$width"
    & wsl.exe -d Ubuntu -- mkdir -p $buildDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the WSL build directory for DATA_W=$width."
    }

    $verilatorArgs = @(
        '--binary'
        '--timing'
        '-Wno-PINMISSING'
        '-Wno-WIDTHCONCAT'
        '--top-module'
        'tb_mac_basics'
        '--Mdir'
        $buildDirectory
        "-GDATA_W=$width"
    ) + $verificationSources + $rtlSources

    & wsl.exe -d Ubuntu -- env "VERILATOR_ROOT=$verilatorRoot" "PATH=$wslPath" `
        $verilator @verilatorArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Verilator failed to compile the MAC testbench for DATA_W=$width."
    }

    & wsl.exe -d Ubuntu -- env "PATH=$wslPath" "$buildDirectory/Vtb_mac_basics"
    if ($LASTEXITCODE -ne 0) {
        throw "MAC basic testbench failed for DATA_W=$width."
    }
}
