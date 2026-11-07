using POE2Radar.Core;
using POE2Radar.Core.Game;

namespace POE2Radar.Research;

/// <summary>Read-only post-patch chain discovery for the field verifier.</summary>
internal static class RecoveryChain
{
    private static readonly byte?[] RootPattern = [0x48, 0x39, 0x2D, null, null, null, null];
    private static bool Plausible(nint p) => p >= 0x10000 && p < 0x7FFFFFFFFFFF;
    private static nint Ptr(MemoryReader reader, nint addr)
        => reader.TryReadStruct<nint>(addr, out var p) && Plausible(p) ? p : 0;

    internal static bool TryFind(ProcessHandle process, MemoryReader reader,
        out nint igsResult, out nint aiResult, out nint lpResult,
        out int aiOffset, out int lpOffset)
    {
        igsResult = aiResult = lpResult = 0;
        aiOffset = lpOffset = 0;
        var slots = new HashSet<nint>();
        foreach (var (baseAddress, bytes) in AobScanner.ReadExecutableSections(process, reader))
            foreach (var off in AobScanner.FindPattern(bytes, RootPattern))
            {
                var slot = AobScanner.ResolveRipRelative(baseAddress, off, 3, 7, bytes);
                if (Plausible(slot)) slots.Add(slot);
            }

        foreach (var slot in slots)
        {
            var gs = Ptr(reader, slot);
            if (gs == 0) continue;
            var candidates = new HashSet<nint>();
            for (var i = 0; i < Poe2.GameState.StateSlotCount; i++)
            {
                var ptr = Ptr(reader, gs + Poe2.GameState.States + i * Poe2.GameState.StateSlotStride);
                if (ptr != 0) candidates.Add(ptr);
            }
            if (candidates.Count < 6) continue; // Same structural root guard as --recover.
            var vec = Ptr(reader, gs + Poe2.GameState.CurrentStatePtr);
            if (vec != 0)
            {
                var active = Ptr(reader, vec);
                if (active != 0) candidates.Add(active);
            }

            foreach (var igs in candidates)
            {
                var igsBytes = new byte[0x800];
                if (reader.TryReadBytes(igs, igsBytes) <= 0) continue;
                for (var i = 0; i + 8 <= igsBytes.Length; i += 8)
                {
                    var ai = (nint)BitConverter.ToInt64(igsBytes, i);
                    if (!Plausible(ai)) continue;
                    var aiBytes = new byte[0xA00];
                    if (reader.TryReadBytes(ai, aiBytes) <= 0) continue;
                    for (var j = 0; j + 8 <= aiBytes.Length; j += 8)
                    {
                        var lp = (nint)BitConverter.ToInt64(aiBytes, j);
                        if (!Plausible(lp)) continue;
                        var details = Ptr(reader, lp + Poe2.Entity.EntityDetailsPtr);
                        if (details == 0 || Ptr(reader, lp + Poe2.Entity.ComponentList) == 0) continue;
                        var name = ReadName(reader, details + Poe2.EntityDetails.Name);
                        if (!name.StartsWith("Metadata/Characters/", StringComparison.Ordinal)) continue;
                        igsResult = igs;
                        aiResult = ai;
                        lpResult = lp;
                        aiOffset = i;
                        lpOffset = j;
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private static string ReadName(MemoryReader reader, nint address)
    {
        if (!reader.TryReadStruct<int>(address + 0x10, out var length) ||
            length <= 0 || length > 1024) return string.Empty;
        if (length < 8) return reader.ReadStringUtf16(address, length);
        var ptr = Ptr(reader, address);
        return ptr == 0 ? string.Empty : reader.ReadStringUtf16(ptr, length);
    }
}
