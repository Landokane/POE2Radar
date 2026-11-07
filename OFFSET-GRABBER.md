# Separate offset-grabber CLI (experimental)

This tool lives on **feature/offset-grabber-cli**. It does not modify the working radar's offsets, the main branch, the game files, or any release.

## One-command use on Windows

With Path of Exile 2 running in an area, open PowerShell:

```powershell
Set-Location 'C:\Users\lando\Downloads\POE2Radar-PatchRecovery'
git fetch origin
git switch --track origin/feature/offset-grabber-cli
.\Invoke-Poe2OffsetGrabber.ps1
```

The first two Git commands are one-time setup. Subsequent runs require only:

```powershell
Set-Location 'C:\Users\lando\Downloads\POE2Radar-PatchRecovery'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Invoke-Poe2OffsetGrabber.ps1'
```

The script:
1. Confirms it is on **feature/offset-grabber-cli**, with a clean tree, then runs `git pull --ff-only origin feature/offset-grabber-cli`.
2. Builds only `POE2Radar.Research` (requires .NET 10).
3. Detects the running PoE executable and records its SHA256.
4. Runs `--recover --deep`, `--verify-fields` and `--vitals`.
5. Saves full output under `%LOCALAPPDATA%\POE2Radar\OffsetGrabber`.

Options: `-SkipPull` to avoid network Git fetch; `-SkipBuild` to use the already built research executable.

## Limitations and safety

- A `git pull` fetches **source code**, not fresh game-memory offsets from GGG; live local probes are what discover possible offsets.
- This is a candidate **report**, not an automatically applied update. The program cannot guarantee that every offset is discovered or that every match is correct.
- False positives happen (e.g., the Energy Shield 0/0 case). Verify against in-game values and preferably two areas.
- It stops rather than pull over uncommitted work, and never force-resets or overwrites your offset table.
- Memory addresses change between game sessions; never hardcode a process address.
- Memory-reading overlays can conflict with game policies. Use at your own risk.
