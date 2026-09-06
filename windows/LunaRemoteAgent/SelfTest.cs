using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

internal static class SelfTest
{
    public static void Run()
    {
        void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("PASS " + label); }
        var c = InputProtocol.Parse("""{"type":"text","text":"Olá 🎮","submit":true,"id":"one"}""");
        var inputs = WindowsInput.TextInputs(c.Text, c.Submit);
        Check(inputs.Length == c.Text.Length * 2 + 2, "Unicode text followed by exactly one Enter");
        Check(inputs[^2].Data.Key.VK == 13 && inputs[^2].Data.Key.Flags == 0 && inputs[^1].Data.Key.Flags == 2, "Enter down then up");
        Check(WindowsInput.TextInputs("", true).Length == 2, "Empty submit still sends Enter");
        Check(WindowsInput.TextInputs("abc", false).Length == 6, "Type-only has no Enter");
        Check(Marshal.SizeOf<WindowsInput.Input>() == (IntPtr.Size == 8 ? 40 : 28), "Win32 INPUT ABI");
        var p = InputProtocol.Parse("""{"type":"gamepad","lx":99999,"ly":-99999,"lt":300,"buttons":4096}""").Pad!;
        Check(p.LX == 32767 && p.LY == -32768 && p.LT == 255 && p.Buttons == 4096, "Gamepad bounds and buttons");
        Check(InputProtocol.Parse("mouse:double").Button == "double", "Legacy compatibility");
        try { InputProtocol.Parse("""{"type":"key","button":"arbitrary"}"""); throw new Exception("Unknown key accepted"); }
        catch (FormatException) { Console.WriteLine("PASS reject unknown key"); }
        Check(InputProtocol.Parse("""{"type":"frameAck","x":42}""").X == 42, "Frame acknowledgement protocol");
        Check(InputProtocol.Parse("""{"type":"ping","id":"rtt"}""").Id == "rtt", "RTT protocol");
        Check(InputProtocol.Parse("""{"type":"quality","mode":"performance"}""").Mode == "performance", "Quality protocol");
        try { InputProtocol.Parse("""{"type":"quality","mode":"ultra"}"""); throw new Exception("Unknown quality accepted"); }
        catch (FormatException) { Console.WriteLine("PASS reject unknown quality"); }
        var previousFps = Environment.GetEnvironmentVariable("LUNA_MAX_FPS");
        try
        {
            Environment.SetEnvironmentVariable("LUNA_MAX_FPS", "90");
            Check(Program.MaxFps() == 90, "Configurable frame ceiling");
            Environment.SetEnvironmentVariable("LUNA_MAX_FPS", "999");
            Check(Program.MaxFps() == 144, "Frame ceiling clamped");
            Environment.SetEnvironmentVariable("LUNA_MAX_FPS", "bogus");
            Check(Program.MaxFps() == 120, "Frame ceiling defaults to 120");
        }
        finally { Environment.SetEnvironmentVariable("LUNA_MAX_FPS", previousFps); }
        var previousBind = Environment.GetEnvironmentVariable("LUNA_BIND_HOST");
        try
        {
            Environment.SetEnvironmentVariable("LUNA_BIND_HOST", "127.0.0.1");
            Check(Program.ListenPrefix(8765) == "http://127.0.0.1:8765/remote/", "Loopback host binding");
            Environment.SetEnvironmentVariable("LUNA_BIND_HOST", "invalid.example");
            try { Program.ListenPrefix(8765); throw new Exception("Unsafe host accepted"); }
            catch (InvalidOperationException) { Console.WriteLine("PASS reject unsafe bind host"); }
        }
        finally { Environment.SetEnvironmentVariable("LUNA_BIND_HOST", previousBind); }
        Check(FrameWindow.Packet(42, [255, 216]).SequenceEqual(new byte[] { 76, 82, 48, 51, 42, 0, 0, 0, 255, 216 }), "Video header little endian");
        using var window = new FrameWindow();
        int first = window.Reserve(CancellationToken.None).GetAwaiter().GetResult();
        int second = window.Reserve(CancellationToken.None).GetAwaiter().GetResult();
        var third = window.Reserve(CancellationToken.None);
        Check(!third.IsCompleted, "At most two unacknowledged frames");
        window.Acknowledge(first);
        Check(third.GetAwaiter().GetResult() > second, "Acknowledgement grants next frame");
        window.Acknowledge(first); // Duplicate acknowledgements cannot grant extra credit.
        using var cancel = new CancellationTokenSource();
        var fourth = window.Reserve(cancel.Token);
        Check(!fourth.IsCompleted, "Duplicate acknowledgement ignored");
        cancel.Cancel();
        try { fourth.GetAwaiter().GetResult(); throw new Exception("Cancellation ignored"); }
        catch (OperationCanceledException) { Console.WriteLine("PASS video credit cancellation"); }
        using var paused = new FrameWindow();
        paused.Reserve(CancellationToken.None).GetAwaiter().GetResult();
        paused.Reserve(CancellationToken.None).GetAwaiter().GetResult();
        Check(paused.TryReserve(TimeSpan.FromMilliseconds(50), CancellationToken.None) == null, "Stalled client pauses instead of killing session");
        using var cancelPause = new CancellationTokenSource();
        cancelPause.Cancel();
        try { paused.TryReserve(TimeSpan.FromSeconds(5), cancelPause.Token); throw new Exception("Pause ignores cancellation"); }
        catch (OperationCanceledException) { Console.WriteLine("PASS paused video honours cancellation"); }
        var profile = new Program.AutoProfile();
        Check(profile.Tier == 0 && profile.Current(120) == (60, 960, 50), "Auto slow-starts light");
        for (int i = 0; i < 240; i++) profile.Observe(20);
        Check(profile.Tier == 1 && profile.Current(120) == (120, 1280, 60), "Sustained good network upgrades");
        for (int i = 0; i < 9; i++) profile.Observe(500);
        Check(profile.Tier == 1, "Single spikes do not downgrade");
        profile.Observe(500);
        Check(profile.Tier == 0 && profile.Current(120) == (60, 960, 50), "Sustained congestion downgrades");
        using var tiny = new Bitmap(16, 16, PixelFormat.Format32bppArgb);
        using (var tg = Graphics.FromImage(tiny)) tg.Clear(Color.Red);
        ulong hash1 = Program.ThumbHash(tiny), hash2 = Program.ThumbHash(tiny);
        Check(hash1 == hash2, "Identical frames hash equal");
        tiny.SetPixel(3, 4, Color.Blue);
        Check(Program.ThumbHash(tiny) != hash1, "Changed pixel detected");
    }
}
