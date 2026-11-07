# Separate experimental offset-grabber command for POE2Radar.
# Never edits Poe2Offsets.cs, never writes into game memory, never publishes a release.
[CmdletBinding()]
param(
    [switch]$SkipPull,
    [switch]$SkipBuild,
    [string]$ReportDirectory = (Join-Path $env:LOCALAPPDATA 'POE2Radar\OffsetGrabber')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$branch = 'feature/offset-grabber-cli'
$project = Join-Path $repo 'src\POE2Radar.Research\POE2Radar.Research.csproj'
$exe = Join-Path $repo 'src\POE2Radar.Research\bin\Debug\net10.0-windows\POE2Radar.Research.exe'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is missing from PATH.' }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw '.NET SDK/runtime is missing from PATH.' }
Push-Location $repo
try {
    $currentBranch = (& git branch --show-current 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Not a working Git repository.' }
    if ($currentBranch -ne $branch) {
        throw "Expected branch '$branch', found '$currentBranch'. Switch branches explicitly before running."
    }
    if (-not $SkipPull) {
        $dirty = & git status --porcelain
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect working tree.' }
        if ($dirty) { throw 'Working tree has changes. Commit or stash them before pulling; no files were overwritten.' }
        Write-Host 'Pulling offset-grabber branch (fast-forward only)...'
        & git pull --ff-only origin $branch
        if ($LASTEXITCODE -ne 0) { throw 'Git pull failed. Local code unchanged by this script.' }
    }
    if (-not $SkipBuild) {
        Write-Host 'Building research probes...'
        & dotnet build $project --configuration Debug
        if ($LASTEXITCODE -ne 0) { throw 'Research build failed; no probes run.' }
    }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Research executable missing: $exe" }

    $game = Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object { $_.Name -match '^PathOfExile.*\.exe$' -and $_.ExecutablePath } |
        Select-Object -First 1
    if ($null -eq $game) { throw 'PoE executable not detected. Start PoE2 and enter a zone before running.' }
    if ($game.ExecutablePath -notmatch '(?i)Path of Exile 2|PathOfExileSteam') {
        Write-Warning "Detected process $($game.Name); confirm this is Path of Exile 2."
    }

    New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportPath = Join-Path $ReportDirectory "offset-grabber-$stamp.txt"
    $gameHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $game.ExecutablePath).Hash
    $head = (& git rev-parse --short HEAD | Out-String).Trim()
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('POE2Radar Offset Grabber - read-only candidate report')
    $lines.Add("Timestamp: $((Get-Date).ToString('o'))")
    $lines.Add("Branch: $branch  Commit: $head")
    $lines.Add("Game: $($game.ExecutablePath)")
    $lines.Add("Game SHA256: $gameHash")
    $lines.Add('IMPORTANT: candidates are not validated offsets or automatic source updates.')
    $failed = $false
    foreach ($probe in @(
        @{ Label = 'CHAIN RECOVERY'; Args = @('--recover', '--deep') },
        @{ Label = 'FIELD VERIFICATION'; Args = @('--verify-fields') },
        @{ Label = 'VITALS'; Args = @('--vitals') }
    )) {
        $lines.Add('')
        $lines.Add("========= $($probe.Label) =========")
        Write-Host "Running $($probe.Label)..."
        $argsForProbe = [string[]]$probe.Args
        try {
            $output = & $exe @argsForProbe 2>&1 | Out-String
            $code = $LASTEXITCODE
            $lines.Add($output)
            $lines.Add("Exit code: $code")
            if ($code -ne 0) { $failed = $true }
        } catch {
            $failed = $true
            $lines.Add("Probe error: $($_.Exception.Message)")
        }
    }
    $lines.Add('')
    $lines.Add('NEXT: Compare candidate values with in-game facts across two zones.')
    $lines.Add('Do not change Poe2Offsets.cs until manually validated.')
    $lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Report: $reportPath"
    if ($failed) {
        Write-Warning 'At least one probe failed. Check the report before using any candidate values.'
        exit 1
    }
    Write-Host 'Probes completed. No offset files modified.'
} finally {
    Pop-Location
}
