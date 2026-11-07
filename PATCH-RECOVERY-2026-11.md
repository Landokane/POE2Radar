# PoE2 November 2026 offset recovery — validation notes

These findings were supplied from live Windows PowerShell research runs on November 6, 2026.
**This is an experimental development-branch change, not a tested radar release.**

| Field | Previous | Staged | Evidence |
| --- | --- | --- | --- |
| InGameState.AreaInstanceData | 0x2A0 | unchanged | Recovered matching chain in Canal Hideout and Qimah Reservoir |
| AreaInstance.LocalPlayer | 0x5D0 | 0x5D8 | Character metadata match in both zones |
| AreaInstance.AreaInfoPtr | 0x098 | 0x0A0 | WorldAreas Code/Name validated against Canal Hideout and Qimah Reservoir |
| AreaInstance.AwakeEntities | 0x6F0 | 0x718 | StdMap with entity metadata in both zones; identity as awake map still tentative |
| AreaInstance.SleepingEntities | 0x700 | 0x728 | StdMap with entity metadata in both zones; identity as sleeping map still tentative |
| AreaInstance.TerrainMetadata | 0x8D0 | 0x8F8 | Terrain dimensions, stride and vector length self-consistent in both zones |
| AreaInstance.CurrentAreaLevel | 0x0BC | 0x0C4 | Qimah Reservoir shows 64 and +0x0C4 reads 64; check other zones |
| AreaInstance.ServerDataPtr | 0x5B0 | 0x5B8 | Live verifier: old pointer null; candidate player(+0x20) matches LocalPlayer and ServerData.League returns Forbidden Rites |
| AreaInstance.CurrentAreaHash | 0x114 | unchanged | Values 0x000002FC / 0x000002FD appear to be parts of pointers; NOT validated |
| InGameState.UiRoot | 0x300 | unchanged | Self-referencing UI object present in two zones |
| InGameState.Camera | 0x378 | unchanged | Zoom=1.0 present in two zones |

## Required before release

1. Verify level reads against at least one additional in-game zone with a known level.
2. Validate which StdMap is awake versus sleeping by comparing entity populations.
3. ServerDataPtr league and player relationship now validated; smoke-test league pricing against runtime before release.
4. Investigate the area-instance hash across multiple zone changes; do not accept pointer halves as hashes.
5. Verify the actual radar's GameState AOB resolver works; Research's relaxed root scanner is a separate path.
6. Rebuild and smoke test the complete radar and ensure F11 local visibility works after applying the offset patch.

No memory addresses from one process run should be hardcoded. If the client patches again, re-run probes instead of assuming these offsets persist.
