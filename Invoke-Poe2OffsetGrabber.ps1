# POE2Radar independent offset candidate grabber (Windows PowerShell 5.1+).
# Read-only game probes; never rewrites offset constants or publishes artifacts.
[CmdletBinding()]
param(
    [switch]$SkipPull,
    [switch]$SkipBuild,
    [switch]$SelfTest,
    [int]$ProcessId = 0,
    [string]$GameExe = 'C:\Program Files (x86)\Steam\steamapps\common\Path of Exile 2\PathOfExileSteam.exe',
    [string]$ReportDirectory = (Join-Path $env:LOCALAPPDATA 'POE2Radar\OffsetGrabber')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$branch = 'feature/offset-grabber-cli'
$project = Join-Path $repo 'src\POE2Radar.Research\POE2Radar.Research.csproj'
$researchExe = Join-Path $repo 'src\POE2Radar.Research\bin\Debug\net10.0-windows\POE2Radar.Research.exe'

# Never assume a single regex match is verified. Capture unique hex candidates only,
# with a source and status, and explicitly exclude transient heap addresses.
function Convert-ProbesToCandidates([string]$recoverText, [string]$verifyText, [string]$vitalsText) {
    $entries = [System.Collections.Generic.List[object]]::new()
    $known = @{}
    function Add-Candidate([string]$name, [string]$hex, [string]$source, [string]$evidence) {
        $value = '0x' + $hex.ToUpperInvariant().TrimStart('0')
        if ($value -eq '0x') { $value = '0x0' }
        $key = "$name/$value/$source"
        if ($known.ContainsKey($key)) { return }
        $known[$key] = $true
        $entries.Add([pscustomobject]@{
            field = $name; offset = $value; status = 'CANDIDATE_ONLY'
            source = $source; evidence = $evidence.Trim()
        })
    }
    foreach ($line in ($recoverText -split "\r?\n")) {
        if ($line -match '(InGameState\.AreaInstanceData|AreaInstance\.LocalPlayer)\s*=\s*0x([0-9a-fA-F]+)') {
            Add-Candidate $matches[1] $matches[2] 'recover' $line
        }
        if ($line -match '^\s*(ServerDataPtr|AwakeEntities|SleepingEntities|TerrainMetadata)\s*=\s*0x([0-9a-fA-F]+)') {
            Add-Candidate ('AreaInstance.' + $matches[1]) $matches[2] 'recover-shift-guess' $line
        }
    }
    foreach ($line in ($verifyText -split "\r?\n")) {
        if ($line -match '^\s*RECOVERED chain: InGameState\.AreaInstanceData = 0x([0-9a-fA-F]+), AreaInstance\.LocalPlayer = 0x([0-9a-fA-F]+)') {
            Add-Candidate 'InGameState.AreaInstanceData' $matches[1] 'verify-chain' $line
            Add-Candidate 'AreaInstance.LocalPlayer' $matches[2] 'verify-chain' $line
        }
        if ($line -match '^\s*\+0x([0-9a-fA-F]+) -> Code=') {
            Add-Candidate 'AreaInstance.AreaInfoPtr' $matches[1] 'verify-area-code' $line
        }
        if ($line -match '^\s*\+0x([0-9a-fA-F]+)\s+tiles=.*\bCONSISTENT\b') {
            Add-Candidate 'AreaInstance.TerrainMetadata' $matches[1] 'verify-terrain' $line
        }
        if ($line -match '^\s*\+0x([0-9a-fA-F]+)\s+size=.*sample=') {
            Add-Candidate 'AreaInstance.EntityMapUnknownRole' $matches[1] 'verify-entity-map' $line
        }
        if ($line -match '^\s*\+0x([0-9a-fA-F]+) -> 0x[0-9a-fA-F]+\s+\(self-ref\)') {
            Add-Candidate 'InGameState.UiRoot' $matches[1] 'verify-ui' $line
        }
        if ($line -match '^\s*\+0x([0-9a-fA-F]+) -> 0x[0-9a-fA-F]+\s+Zoom=') {
            Add-Candidate 'InGameState.Camera' $matches[1] 'verify-camera' $line
        }
    }
    foreach ($line in ($vitalsText -split "\r?\n")) {
        if ($line -match 'configured (Health|Mana|EnergyShield)\s+@0x([0-9a-fA-F]+) -> (\d+)/(\d+)') {
            # A reported 0/0 is ambiguous; don't classify it as drift.
            $name = 'Life.' + $matches[1]
            $current = [int]$matches[3]; $max = [int]$matches[4]
            if ($max -gt 0 -and $current -le $max) {
                Add-Candidate $name $matches[2] 'configured-vitals-readback' $line
            }
        }
    }
    return @($entries.ToArray())
}

function Assert-SelfTest {
    $r = "InGameState.AreaInstanceData = 0x2A0`nAreaInstance.LocalPlayer = 0x5D8`n        AwakeEntities = 0x718"
    $v = "  +0x0A0 -> Code='P2_7' Name='Qimah Reservoir'`n  +0x8F8  tiles=121x79  walkableBytes=1000 bytesPerRow=100 CONSISTENT"
    $l = "configured EnergyShield @0x248 -> 0/0 invalid`nconfigured Health @0x1B0 -> 1601/1601 VALID"
    $c = @(Convert-ProbesToCandidates $r $v $l)
    if (-not ($c | Where-Object { $_.field -eq 'AreaInstance.LocalPlayer' -and $_.offset -eq '0x5D8' })) { throw 'Self-test failed: chain' }
    if (-not ($c | Where-Object { $_.field -eq 'AreaInstance.TerrainMetadata' -and $_.offset -eq '0x8F8' })) { throw 'Self-test failed: terrain' }
    if ($c | Where-Object { $_.field -eq 'Life.EnergyShield' }) { throw 'Self-test failed: zero-ES false candidate' }
    if (-not ($c | Where-Object { $_.field -eq 'Life.Health' })) { throw 'Self-test failed: vitals' }
    Write-Host "SELF-TEST PASS: extracted $($c.Count) candidates; 0/0 ES correctly excluded."
}

if ($SelfTest) {
    Assert-SelfTest
    return
}
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
        # Generated release ZIPs are frequently untracked; they should not block safe ff-only pulls.
        # Tracked edits remain protected. Git also refuses if an untracked file would be overwritten.
        $dirtyTracked = & git status --porcelain --untracked-files=no
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect working tree.' }
        if ($dirtyTracked) { throw 'Tracked working files changed. Commit or stash before pulling.' }
        Write-Host 'Pulling offset-grabber branch (fast-forward only)...'
        & git pull --ff-only origin $branch
        if ($LASTEXITCODE -ne 0) { throw 'Git pull failed; no reset attempted.' }
    }
    if (-not $SkipBuild) {
        Write-Host 'Building research executable...'
        & dotnet build $project -c Debug
        if ($LASTEXITCODE -ne 0) { throw 'Research build failed; probes were not run.' }
    }
    if (-not (Test-Path -LiteralPath $researchExe -PathType Leaf)) { throw "Research executable missing: $researchExe" }

    if ($ProcessId -gt 0) {
        $game = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId"
        if ($null -eq $game) { throw "No process found with PID $ProcessId" }
    } else {
        $expected = $null
        if (Test-Path -LiteralPath $GameExe -PathType Leaf) {
            $expected = (Resolve-Path -LiteralPath $GameExe).Path
        }
        $candidates = @(Get-CimInstance Win32_Process |
            Where-Object { $_.Name -match '^PathOfExile.*\.exe$' -and $_.ExecutablePath })
        if ($expected) {
            $candidates = @($candidates | Where-Object {
                [string]::Equals($_.ExecutablePath, $expected, [StringComparison]::OrdinalIgnoreCase)
            })
        } else {
            # Without a known game path, an ambiguous multi-client setup MUST be rejected.
            $candidates = @($candidates | Where-Object {
                $_.ExecutablePath -match '(?i)Path of Exile 2' -or
                $_.Name -match '^PathOfExileSteam\.exe$'
            })
        }
        if ($candidates.Count -ne 1) {
            throw "Found $($candidates.Count) matching PoE2 processes. Supply -ProcessId <PID> and -GameExe <full path> to disambiguate."
        }
        $game = $candidates[0]
    }
    if (-not $game.ExecutablePath -or -not (Test-Path -LiteralPath $game.ExecutablePath)) {
        throw 'Cannot resolve executable path for selected process; launch PowerShell with sufficient access.'
    }
    if ($game.ExecutablePath -notmatch '(?i)Path of Exile 2|PathOfExileSteam') {
        throw "Selected process does not appear to be PoE2: $($game.ExecutablePath)"
    }

    New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportPath = Join-Path $ReportDirectory "offset-grabber-$stamp.txt"
    $jsonPath = Join-Path $ReportDirectory "offset-candidates-$stamp.json"
    $gameHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $game.ExecutablePath).Hash
    $head = (& git rev-parse HEAD | Out-String).Trim()
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('POE2Radar Offset Grabber - read-only candidate report')
    $lines.Add("Time: $((Get-Date).ToString('o'))")
    $lines.Add("Commit: $head  Branch: $branch")
    $lines.Add("Game: $($game.ExecutablePath)  PID: $($game.ProcessId)")
    $lines.Add("SHA256: $gameHash")
    $lines.Add('All candidates are UNVERIFIED; do not apply automatically.')
    $results = [ordered]@{}
    $failed = $false
    $probes = @(
        @{ Key='recover'; Label='CHAIN RECOVERY'; Args=@('--recover','--deep') },
        @{ Key='verify'; Label='FIELD VERIFICATION'; Args=@('--verify-fields') },
        @{ Key='vitals'; Label='VITALS'; Args=@('--vitals') }
    )
    foreach ($probe in $probes) {
        $lines.Add('')
        $lines.Add("========= $($probe.Label) =========")
        Write-Host "Running $($probe.Label) against PID $($game.ProcessId)..."
        $output = ''
        $code = 1
        try {
            $argsForProbe = [string[]]$probe.Args + @('--pid', [string]$game.ProcessId)
            $output = (& $researchExe @argsForProbe 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } catch {
            $output = "Probe failed: $($_.Exception.Message)"
        }
        $results[$probe.Key] = [ordered]@{ exitCode=$code; text=$output }
        $lines.Add($output)
        $lines.Add("Exit code: $code")
        if ($code -ne 0) { $failed = $true }
    }
    $candidates = @(Convert-ProbesToCandidates $results.recover.text $results.verify.text $results.vitals.text)
    $lines.Add('')
    $lines.Add('CANDIDATE SUMMARY (manual validation required):')
    foreach ($c in $candidates) { $lines.Add("  $($c.field) = $($c.offset) [$($c.source)]") }
    $lines.Add('Zero-maximum Energy Shield is not considered offset drift.')
    $lines.Add('CurrentAreaHash is not auto-selected; validate in multiple instances.')
    $lines.Add('Awake/Sleeping map role cannot be inferred from one map-shaped candidate alone.')
    $lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
    $summary = [ordered]@{
        schemaVersion = 1; generatedAt = (Get-Date).ToString('o')
        gameExecutable = $game.ExecutablePath; gamePid = $game.ProcessId; gameSha256=$gameHash
        gitCommit=$head; branch=$branch
        overallStatus=$(if ($failed) { 'PROBE_FAILURE' } else { 'CANDIDATES_ONLY' })
        probes=@($probes | ForEach-Object { [ordered]@{name=$_.Key; exitCode=$results[$_.Key].exitCode} })
        candidates=$candidates
    }
    $summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Host "Full report: $reportPath"
    Write-Host "JSON candidates: $jsonPath"
    Write-Host "Candidates found: $($candidates.Count) (all unverified)"
    if ($failed) { throw 'At least one probe failed. See report; no offsets were modified.' }
    Write-Host 'Completed: no game memory or offset source files modified.'
} finally {
    Pop-Location
}
