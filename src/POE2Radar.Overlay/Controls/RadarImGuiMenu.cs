using System.Numerics;
using System.Runtime.InteropServices;
using ClickableTransparentOverlay;
using ImGuiNET;
using POE2Radar.Overlay.Config;

namespace POE2Radar.Overlay.Controls;

/// <summary>
/// Small native ImGui control surface. This is a SEPARATE top-level Windows window from the
/// Direct2D game radar, so capture exclusion applies only to controls, never to radar graphics.
/// </summary>
internal sealed record MenuDisplayOptions(
    bool OverlayVisible,
    bool ShowMonsters,
    bool ShowTerrain,
    bool ShowPlayerBlip,
    bool ShowPath,
    bool HpBarMagic,
    bool HpBarRare,
    bool HpBarUnique,
    int FpsCap)
{
    public static MenuDisplayOptions From(RadarSettings settings) => new(
        settings.OverlayVisible,
        settings.ShowMonsters,
        settings.ShowTerrain,
        settings.ShowPlayerBlip,
        settings.ShowPath,
        settings.HpBarMagic,
        settings.HpBarRare,
        settings.HpBarUnique,
        settings.FpsCap);
}

internal sealed class RadarImGuiMenu : Overlay
{
    // Windows 10 2004+ removes this top-level window from supported OS captures.
    // This is NOT a guarantee for every third-party recording or streaming implementation.
    private const uint WdaExcludeFromCapture = 0x00000011;

    private readonly Func<MenuDisplayOptions> _readSettings;
    private readonly Action<MenuDisplayOptions> _applySettings;
    private readonly Action _openDashboard;
    private readonly Action _requestExit;

    private volatile bool _visible;
    private volatile bool _captureExcluded;
    private volatile MenuDisplayOptions _draft;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowDisplayAffinity(nint hWnd, uint dwAffinity);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowDisplayAffinity(nint hWnd, out uint dwAffinity);

    public RadarImGuiMenu(
        Func<MenuDisplayOptions> readSettings,
        Action<MenuDisplayOptions> applySettings,
        Action openDashboard,
        Action requestExit)
        : base("POE2Radar - Private Controls", 560, 600)
    {
        _readSettings = readSettings;
        _applySettings = applySettings;
        _openDashboard = openDashboard;
        _requestExit = requestExit;
        _draft = readSettings();
        FPSLimit = 30; // This window doesn't need to repaint at the game's FPS.
    }

    /// <summary>Fail closed: never show the private menu unless Windows accepted capture exclusion.</summary>
    public bool Visible => _visible && _captureExcluded;

    public bool TryToggleVisible()
    {
        if (!_captureExcluded) return false;
        if (!_visible) _draft = _readSettings(); // Pick up F11 / dashboard changes since last opening.
        _visible = !_visible;
        return true;
    }

    protected override Task PostInitialized()
    {
        // This executes on the ImGui window's own render thread, AFTER its HWND is created.
        var set = SetWindowDisplayAffinity(window.Handle, WdaExcludeFromCapture);
        var verified = set && GetWindowDisplayAffinity(window.Handle, out var actual)
            && actual == WdaExcludeFromCapture;
        _captureExcluded = verified;
        if (verified)
            Console.WriteLine("ImGui menu: Windows capture exclusion accepted. Verify with an actual Discord stream.");
        else
            Console.Error.WriteLine(
                $"ImGui menu DISABLED: Windows capture exclusion unavailable (Win32 error {Marshal.GetLastWin32Error()}). " +
                "The menu will stay hidden rather than risk appearing in capture.");

        ImGui.StyleColorsDark();
        var style = ImGui.GetStyle();
        style.WindowRounding = 8f;
        style.FrameRounding = 4f;
        style.Colors[(int)ImGuiCol.TitleBgActive] = new Vector4(0.32f, 0.23f, 0.11f, 1f);
        style.Colors[(int)ImGuiCol.Header] = new Vector4(0.34f, 0.25f, 0.11f, 0.70f);
        style.Colors[(int)ImGuiCol.HeaderHovered] = new Vector4(0.46f, 0.33f, 0.13f, 0.90f);
        style.Colors[(int)ImGuiCol.Button] = new Vector4(0.38f, 0.27f, 0.12f, 1f);
        style.Colors[(int)ImGuiCol.ButtonHovered] = new Vector4(0.51f, 0.36f, 0.15f, 1f);

        return Task.CompletedTask;
    }

    protected override void Render()
    {
        if (!_visible || !_captureExcluded) return;

        ImGui.SetNextWindowPos(new Vector2(12, 12), ImGuiCond.FirstUseEver);
        ImGui.SetNextWindowSize(new Vector2(510, 545), ImGuiCond.FirstUseEver);

        var open = true;
        var expanded = ImGui.Begin(
            "POE2Radar - Main Application Control",
            ref open,
            ImGuiWindowFlags.MenuBar | ImGuiWindowFlags.NoCollapse);

        if (expanded)
        {
            if (ImGui.BeginMenuBar())
            {
                if (ImGui.BeginMenu("File"))
                {
                    if (ImGui.MenuItem("Open web dashboard")) _openDashboard();
                    if (ImGui.MenuItem("Reload current settings")) _draft = _readSettings();
                    ImGui.Separator();
                    if (ImGui.MenuItem("Exit POE2Radar")) _requestExit();
                    ImGui.EndMenu();
                }

                if (ImGui.BeginMenu("View"))
                {
                    if (ImGui.MenuItem("Hide menu (Insert)")) _visible = false;
                    ImGui.EndMenu();
                }

                ImGui.EndMenuBar();
            }

            ImGui.TextColored(new Vector4(0.91f, 0.72f, 0.33f, 1f), "THE EXILE'S RADAR");
            ImGui.TextWrapped("Private local control panel. Changes apply when you press Apply Changes.");
            ImGui.Separator();

            var current = _draft;
            var visible = current.OverlayVisible;
            if (ImGui.Checkbox("Show radar overlay (also F11)", ref visible))
                _draft = current with { OverlayVisible = visible };

            current = _draft;
            var monsters = current.ShowMonsters;
            if (ImGui.Checkbox("Show monsters", ref monsters))
                _draft = current with { ShowMonsters = monsters };

            current = _draft;
            var terrain = current.ShowTerrain;
            if (ImGui.Checkbox("Show walkable terrain", ref terrain))
                _draft = current with { ShowTerrain = terrain };

            current = _draft;
            var blip = current.ShowPlayerBlip;
            if (ImGui.Checkbox("Show player blip", ref blip))
                _draft = current with { ShowPlayerBlip = blip };

            current = _draft;
            var path = current.ShowPath;
            if (ImGui.Checkbox("Show navigation guidance", ref path))
                _draft = current with { ShowPath = path };

            ImGui.SeparatorText("Monster health bars");

            current = _draft;
            var magic = current.HpBarMagic;
            if (ImGui.Checkbox("Magic", ref magic))
                _draft = current with { HpBarMagic = magic };

            current = _draft;
            var rare = current.HpBarRare;
            if (ImGui.Checkbox("Rare", ref rare))
                _draft = current with { HpBarRare = rare };

            current = _draft;
            var unique = current.HpBarUnique;
            if (ImGui.Checkbox("Unique", ref unique))
                _draft = current with { HpBarUnique = unique };

            ImGui.SeparatorText("Performance");

            current = _draft;
            var fps = current.FpsCap;
            if (ImGui.SliderInt("FPS cap (0 = auto)", ref fps, 0, 240))
                _draft = current with { FpsCap = fps };

            ImGui.Spacing();
            if (ImGui.Button("Apply Changes", new Vector2(205f, 32f)))
                _applySettings(_draft); // Queued: the radar render thread owns the actual save.

            ImGui.SameLine();
            if (ImGui.Button("Reload Settings", new Vector2(170f, 32f)))
                _draft = _readSettings();

            ImGui.Spacing();
            ImGui.TextColored(new Vector4(0.48f, 0.86f, 0.61f, 1f),
                "Windows capture exclusion: enabled");
            ImGui.TextWrapped("Capture protection is best-effort. Verify in Discord's actual stream preview.");
            ImGui.TextDisabled("Insert: menu | F11: radar | F8: auto-flask | F12: dashboard");
        }

        ImGui.End();
        if (!open) _visible = false;
    }
}
