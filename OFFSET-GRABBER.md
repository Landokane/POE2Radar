# POE2Radar standalone offset grabber

**Branch:** `feature/offset-grabber-cli` (experimental, separate from `main`)

This script can **pull the latest grabber source**, build the existing research executable, run live PoE2 memory probes, and produce both a full text report and structured JSON candidate summary.

It **does not** push or automatically apply offset changes to the working radar. Genuine offset recovery after a patch requires comparing evidence across multiple zones and in-game values. Zero-ES readings, area hash, and entity-map identity are deliberately not guessed.

## First-time setup (Windows PowerShell)

```powershell
Set-Location 'C:\Users\lando\Downloads\POE2Radar-PatchRecovery'
git fetch origin
git switch --track origin/feature/offset-grabber-cli
```

If that branch already exists locally, use `git switch feature/offset-grabber-cli` instead.

## Built-in self-test (no game required)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Invoke-Poe2OffsetGrabber.ps1' -SelfTest
```

Expected: `SELF-TEST PASS` with no game attachment. This checks sample chain, terrain and vitals extraction including the zero-ES false positive.

## Scan the current game

Start Path of Exile 2 and enter an area, then:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Invoke-Poe2OffsetGrabber.ps1'
```

Default PoE2 path:
`C:\Program Files (x86)\Steam\steamapps\common\Path of Exile 2\PathOfExileSteam.exe`

Use `-GameExe 'C:\full\other\PathOfExileSteam.exe'` if installed elsewhere. If multiple matching processes exist, select the exact one with `-ProcessId 12345`. The script passes the selected PID to all three research probes.

Optional: `-SkipPull` (offline), `-SkipBuild` (reuse a previously built research EXE).

Output is written to `%LOCALAPPDATA%\POE2Radar\OffsetGrabber`:

- `offset-grabber-YYYYMMDD-HHMMSS.txt`: full probe output, errors and candidate summary.
- `offset-candidates-YYYYMMDD-HHMMSS.json`: machine-readable candidates with source and `CANDIDATE_ONLY` status, plus SHA256 of the game executable and probe exit codes.

The pipeline executes `--recover --deep`, `--verify-fields`, and `--vitals` using the `POE2Radar.Research` executable.

## Safety and limitations

- `git pull --ff-only` never force-resets. Tracked work-in-progress blocks pulling; untracked release ZIPs do not.
- Self-test validates parser logic from saved examples. It is **not** a Windows or live-game validation.
- The script is independent of the Release radar and does not change `Poe2Offsets.cs`.
- The game and memory-reader executable must run on Windows with sufficient permission to read game process memory.
- No static scan can guarantee all offsets after an arbitrary patch; candidate matching may give false positives.
- Never use a numeric candidate from a single pass as an automatic production change.
- The script never writes to game memory. Ensure use complies with game rules and applicable terms.
