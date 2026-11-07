# Patch-check workflow (experimental)

This branch adds a **read-only patch fingerprint** and a **manually invoked** recovery report. It does not automatically change offsets, generate a release, or run continuously.

## Run on Windows

From the repository folder in PowerShell, supply the **full path** to your locally installed PoE2 executable:

```powershell
Set-Location 'C:\path\to\POE2Radar'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Check-Poe2Patch.ps1' -GameExe 'C:\path\to\PathOfExileSteam.exe'
```

Replace both example paths with your actual installation paths. For Steam, locate the game executable via Steam > Path of Exile 2 > Properties > Installed Files > Browse. Do not assume the executable name.

The first run records a baseline. Subsequent runs compare the SHA-256 of that executable. Reports are saved to:

```text
%LOCALAPPDATA%\POE2Radar\PatchReports
```

To run the existing project recovery tools **on demand**, while PoE2 is running and your character is in a zone:

```powershell
dotnet build .\POE2Radar.slnx
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Check-Poe2Patch.ps1' -GameExe 'C:\path\to\PathOfExileSteam.exe' -RunProbes
```

The probes run `--recover --deep` and `--verify-fields` sequentially, recording their output and exit codes. The script does not promote probe guesses into code or change `Poe2Offsets.cs`.

## Important limitations

- Detection happens only **when you run the script**; this is not a background watcher or an alert service.
- A changed executable signals that validation may be necessary, **not** that offsets are broken.
- The initial baseline cannot tell whether the current installation already differs from an earlier build.
- Data-only updates can occur without changing the selected executable.
- Automatic memory-layout recovery is **not guaranteed**. Proposed offset changes require live testing and review.
- The game client and researcher should only be run in compliance with the game's terms and applicable rules.
- This branch is based on `feature/local-overlay-visibility` to preserve overlay customization. Do not merge or release before reviewing the diff and testing on Windows.
