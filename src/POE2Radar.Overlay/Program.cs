using POE2Radar.Core;
using POE2Radar.Overlay;

// On an in-game restart, the replacement waits until the previous process has exited.
// This prevents two overlay renderers/API servers from running at the same time.
const string waitPrefix = "--restart-wait=";
var waitArg = args.FirstOrDefault(a => a.StartsWith(waitPrefix, StringComparison.Ordinal));
if (waitArg is not null && int.TryParse(waitArg[waitPrefix.Length..], out var previousPid))
{
    try
    {
        using var previous = System.Diagnostics.Process.GetProcessById(previousPid);
        if (!previous.WaitForExit(15000))
        {
            Console.Error.WriteLine("Restart cancelled: previous radar instance did not exit.");
            return 3;
        }
    }
    catch (ArgumentException) { /* The prior process already exited. */ }
    catch (InvalidOperationException) { /* The prior process already exited. */ }
}

Console.WriteLine("POE2Radar — map/radar overlay");
Console.WriteLine("=============================");

bool restartRequested = false;
using (var process = ProcessHandle.AttachToPoE())
{
    if (process is null)
    {
        Console.Error.WriteLine("PoE2 not running (no matching process found).");
        return 1;
    }
    Console.WriteLine($"Attached to {process.ProcessName} (PID {process.ProcessId})");

    var reader = new MemoryReader(process);
    var slot = Bootstrap.ResolveGameStateSlot(process, reader);
    if (slot == 0)
        return 2;

    Console.WriteLine();
    Console.WriteLine("Radar running. F5 in-game = clean restart; F9 = exit.");
    Console.WriteLine("Open the in-game map to see terrain + entities.");
    Console.WriteLine("Atlas: open it in-game; rings are auto-positioned. F10 over a tile = inspect its map/content/biome.");
    Console.WriteLine("Ctrl+C to exit.");

    // Scope ensures render resources, world/API threads and the game process handle
    // are released before starting the replacement.
    using (var app = new RadarApp(process, reader, slot))
    {
        Console.CancelKeyPress += OnCancel;
        try
        {
            app.Run();
            restartRequested = app.RestartRequested;
        }
        finally
        {
            Console.CancelKeyPress -= OnCancel;
        }

        void OnCancel(object? sender, ConsoleCancelEventArgs e)
        {
            e.Cancel = true;
            app.RequestShutdown();
        }
    }
}

if (restartRequested)
{
    var exe = Environment.ProcessPath;
    if (string.IsNullOrWhiteSpace(exe))
    {
        Console.Error.WriteLine("Restart failed: executable path unavailable.");
        return 4;
    }

    try
    {
        var start = new System.Diagnostics.ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            WorkingDirectory = AppContext.BaseDirectory,
        };
        start.ArgumentList.Add($"{waitPrefix}{Environment.ProcessId}");
        System.Diagnostics.Process.Start(start)?.Dispose();
        Console.WriteLine("Fresh radar instance starting.");
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"Restart failed: {ex.Message}");
        return 4;
    }
}

Console.WriteLine("Done.");
return 0;
