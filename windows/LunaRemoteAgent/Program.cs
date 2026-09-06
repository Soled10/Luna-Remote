using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Net.WebSockets;
using System.Runtime.InteropServices;

internal static class Program
{
    private const int Port = 8765;
    private static async Task Main()
    {
        var token = Environment.GetEnvironmentVariable("LUNA_TOKEN") ?? "change-me-now";
        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://+:{Port}/remote/"); listener.Start();
        Console.WriteLine($"Luna Remote Agent ouvindo na porta {Port}");
        while (true)
        {
            var context = await listener.GetContextAsync();
            if (!context.Request.IsWebSocketRequest || context.Request.QueryString["token"] != token)
            { context.Response.StatusCode = context.Request.IsWebSocketRequest ? 401 : 400; context.Response.Close(); continue; }
            var socket = (await context.AcceptWebSocketAsync(null)).WebSocket;
            _ = Task.Run(() => HandleClient(socket));
        }
    }
    private static async Task HandleClient(WebSocket socket)
    {
        _ = Task.Run(() => StreamScreen(socket)); var buffer = new byte[8192];
        while (socket.State == WebSocketState.Open)
        { var result = await socket.ReceiveAsync(buffer, CancellationToken.None); if (result.MessageType == WebSocketMessageType.Close) break; HandleInput(System.Text.Encoding.UTF8.GetString(buffer, 0, result.Count)); }
    }
    private static async Task StreamScreen(WebSocket socket)
    {
        while (socket.State == WebSocketState.Open)
        { try { var b = Screen.PrimaryScreen?.Bounds ?? new Rectangle(0, 0, 1280, 720); using var bmp = new Bitmap(b.Width, b.Height); using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(b.Location, Point.Empty, b.Size); using var ms = new MemoryStream(); bmp.Save(ms, ImageFormat.Jpeg); await socket.SendAsync(ms.ToArray(), WebSocketMessageType.Binary, true, CancellationToken.None); await Task.Delay(100); } catch { break; } }
    }
    private static void HandleInput(string message)
    {
        var p = message.Split(':');
        if (p.Length >= 3 && p[0] == "mouse" && p[1] == "move" && int.TryParse(p[2], out var dx) && int.TryParse(p.ElementAtOrDefault(3), out var dy)) SendMouse(dx, dy, 1);
        else if (message == "mouse:left") SendMouse(0, 0, 2); else if (message == "mouse:right") SendMouse(0, 0, 8);
        else if (message == "mouse:double") { SendMouse(0, 0, 2); SendMouse(0, 0, 4); SendMouse(0, 0, 2); SendMouse(0, 0, 8); }
        else if (message.StartsWith("key:text:")) { try { SendUnicodeText(System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(message[9..]))); } catch { } }
    }
    [DllImport("user32.dll")] private static extern uint SendInput(uint n, INPUT[] a, int s);
    [DllImport("user32.dll")] private static extern uint SendInputKey(uint n, INPUT_KEY[] a, int s);
    [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint type; public MOUSEINPUT mi; }
    [StructLayout(LayoutKind.Sequential)] private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public nint dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public nint dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct INPUT_KEY { public uint type; public KEYBDINPUT ki; }
    private static void SendMouse(int x, int y, uint flags) => SendInput(1, new[] { new INPUT { type = 0, mi = new MOUSEINPUT { dx = x, dy = y, dwFlags = flags } } }, Marshal.SizeOf<INPUT>());
    private static void SendUnicodeText(string text) { var a = new List<INPUT_KEY>(); foreach (var c in text) { a.Add(new INPUT_KEY { type = 1, ki = new KEYBDINPUT { wScan = c, dwFlags = 4 } }); a.Add(new INPUT_KEY { type = 1, ki = new KEYBDINPUT { wScan = c, dwFlags = 6 } }); } if (a.Count > 0) SendInputKey((uint)a.Count, a.ToArray(), Marshal.SizeOf<INPUT_KEY>()); }
}
