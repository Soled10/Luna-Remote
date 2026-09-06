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
    }
}
