# POE2Radar patch check: read-only, opt-in recovery probes.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$GameExe,
    [string]$ReportDirectory = (Join-Path $env:LOCALAPPDATA 'POE2Radar\PatchReports'),
    [switch]$RunProbes,
    [string]$ResearchDll = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $GameExe).Path
New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$reportDir = (Resolve-Path -LiteralPath $ReportDirectory).Path
$statePath = Join-Path $reportDir 'last-game-build.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $reportDir "patch-check-$stamp.txt"
$info = Get-Item -LiteralPath $exe
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$current = [ordered]@{
    executable = $exe
    product_version = $info.VersionInfo.ProductVersion
    file_version = $info.VersionInfo.FileVersion
    size_bytes = $info.Length
    sha256 = $hash
    checked_at = (Get-Date).ToString('o')
}
$old = $null
if (Test-Path -LiteralPath $statePath) {
    try { $old = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    catch { Write-Warning "Previous fingerprint is unreadable: $($_.Exception.Message)" }
}
$changed = ($null -ne $old -and $old.sha256 -ne $current.sha256)
$first = ($null -eq $old)
$status = if ($first) { 'BASELINE CREATED' } elseif ($changed) { 'GAME EXECUTABLE CHANGED' } else { 'UNCHANGED' }
$lines = @(
    'POE2Radar local game-build check'
    "Time: $($current.checked_at)"
    "Executable: $exe"
    "Product version: $($current.product_version)"
    "File version: $($current.file_version)"
    "Bytes: $($current.size_bytes)"
    "SHA256: $hash"
    "Status: $status"
    'Build changes do not prove offset changes; an unchanged build does not prove offsets valid.'
)
$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
if ($RunProbes) {
    if ([string]::IsNullOrWhiteSpace($ResearchDll)) {
        $ResearchDll = Join-Path $PSScriptRoot 'src\POE2Radar.Research\bin\Debug\net10.0-windows\POE2Radar.Research.dll'
    }
    if (-not (Test-Path -LiteralPath $ResearchDll -PathType Leaf)) {
        throw "Research DLL missing: $ResearchDll. Build first with: dotnet build POE2Radar.slnx"
    }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw 'dotnet SDK/runtime not found on PATH.'
    }
    Add-Content -LiteralPath $reportPath -Value ([Environment]::NewLine + 'Live probes explicitly requested; PoE2 must be running in a zone.')
    foreach ($flags in @(@('--recover','--deep'), @('--verify-fields'))) {
        $label = $flags -join ' '
        Add-Content -LiteralPath $reportPath -Value ([Environment]::NewLine + "===== $label =====")
        $probeOutput = & dotnet $ResearchDll @flags 2>&1 | Out-String
        Add-Content -LiteralPath $reportPath -Value $probeOutput
        Add-Content -LiteralPath $reportPath -Value "Exit code: $LASTEXITCODE"
    }
}
$current | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Host "Patch report: $reportPath"
Write-Host "Status: $status"
if ($changed) { Write-Warning 'Game executable changed. Validate offsets before using the overlay.' }
