using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class Program
{
    private static readonly SemaphoreSlim SessionSlot = new(1, 1);
    private static async Task Main(string[] args)
    {
        if (args.Contains("--self-test")) { SelfTest.Run(); return; }
        if (args.Contains("--gamepad-test"))
        {
            using var gamepad = new VirtualGamepad();
            Console.WriteLine(gamepad.Status);
            Environment.ExitCode = gamepad.Available ? 0 : 1;
            return;
        }
        var token = Environment.GetEnvironmentVariable("LUNA_TOKEN");
        if (string.IsNullOrWhiteSpace(token))
        {
            Console.Error.WriteLine("Defina LUNA_TOKEN antes de iniciar o agente.");
            Environment.ExitCode = 1; return;
        }
        int port = int.TryParse(Environment.GetEnvironmentVariable("LUNA_PORT"), out var p) ? p : 8765;
        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://+:{port}/remote/");
        try { listener.Start(); }
        catch (HttpListenerException e) { Console.Error.WriteLine($"Não foi possível abrir porta {port}: {e.Message}"); return; }
        Console.WriteLine($"Luna Remote Agent 0.4.1 | porta {port} | Ctrl+C para encerrar");
        while (true)
        {
            var context = await listener.GetContextAsync();
            var supplied = context.Request.QueryString["token"] ?? "";
            var valid = CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(Encoding.UTF8.GetBytes(token)), SHA256.HashData(Encoding.UTF8.GetBytes(supplied)));
            if (!valid || !context.Request.IsWebSocketRequest)
            {
                context.Response.StatusCode = !valid ? 401 : 400;
                context.Response.Close();
                Console.WriteLine(!valid ? "Conexão recusada: token incorreto." : "Requisição sem WebSocket.");
                continue;
            }
            if (!await SessionSlot.WaitAsync(0))
            {
                context.Response.StatusCode = 409; context.Response.Close(); continue;
            }
            try
            {
                var socket = (await context.AcceptWebSocketAsync(null)).WebSocket;
                _ = RunSession(socket, context.Request.QueryString["protocol"] == "3");
            }
            catch { SessionSlot.Release(); }
        }
    }

    private static async Task RunSession(WebSocket socket, bool flowControl)
    {
        using (socket)
        using (var stop = new CancellationTokenSource())
        using (var sendLock = new SemaphoreSlim(1, 1))
        using (var pad = new VirtualGamepad())
        using (var window = new FrameWindow())
        {
            var gate = new object();
            long lastPad = Environment.TickCount64, lastMouse = lastPad;
            bool padActive = false, mouseHeld = false;
            async Task Send(object value) =>
                await SendBytes(socket, sendLock, JsonSerializer.SerializeToUtf8Bytes(value), WebSocketMessageType.Text, stop.Token);

            Task frames = Task.CompletedTask, watchdog = Task.CompletedTask;
            try
            {
                await Send(new { type = "hello", version = "0.4.1", protocol = 3, gamepad = pad.Available, gamepadStatus = pad.Status });
                Console.WriteLine("Cliente conectado. " + pad.Status);
                frames = Task.Run(() => StreamScreen(socket, sendLock, stop, flowControl ? window : null));
                watchdog = Task.Run(async () =>
                {
                    while (!stop.IsCancellationRequested)
                    {
                        await Task.Delay(250, stop.Token);
                        lock (gate)
                        {
                            if (padActive && Environment.TickCount64 - lastPad > 1500) { pad.Reset(); padActive = false; }
                            if (mouseHeld && Environment.TickCount64 - lastMouse > 2000) { WindowsInput.ReleaseMouse(); mouseHeld = false; }
                        }
                    }
                });
                var buffer = new byte[8192];
                while (!stop.IsCancellationRequested && socket.State == WebSocketState.Open)
                {
                    using var message = new MemoryStream();
                    WebSocketReceiveResult part;
                    do
                    {
                        part = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), stop.Token);
                        if (part.MessageType == WebSocketMessageType.Close) return;
                        if (part.MessageType != WebSocketMessageType.Text || message.Length + part.Count > 32768)
                            throw new InvalidDataException("Mensagem inválida ou muito grande.");
                        message.Write(buffer, 0, part.Count);
                    } while (!part.EndOfMessage);
                    try
                    {
                        var command = InputProtocol.Parse(Encoding.UTF8.GetString(message.ToArray()));
                        if (command.Type == "frameAck") { if (flowControl) window.Acknowledge(command.X); continue; }
                        if (command.Type == "ping") { await Send(new { type = "pong", id = command.Id }); continue; }
                        lock (gate)
                        {
                            if (command.Type == "gamepad")
                            {
                                if (pad.Available) { pad.Apply(command.Pad!); lastPad = Environment.TickCount64; padActive = true; }
                            }
                            else if (command.Type == "release")
                            {
                                pad.Reset(); WindowsInput.ReleaseMouse(); padActive = mouseHeld = false;
                            }
                            else
                            {
                                WindowsInput.Apply(command);
                                lastMouse = Environment.TickCount64;
                                if (command.Type == "button") mouseHeld = command.Down;
                            }
                        }
                        if (command.Type == "text") await Send(new { type = "ack", id = command.Id });
                    }
                    catch (Exception e) when (e is FormatException or JsonException or InvalidOperationException or System.ComponentModel.Win32Exception or KeyNotFoundException)
                    {
                        await Send(new { type = "error", message = e is System.ComponentModel.Win32Exception ? e.Message : "Comando inválido." });
                    }
                }
            }
            catch (Exception e) { Console.WriteLine("Sessão encerrada: " + e.GetType().Name); }
            finally
            {
                stop.Cancel();
                socket.Abort();
                try { await Task.WhenAll(frames, watchdog); } catch { }
                lock (gate)
                {
                    try { pad.Reset(); if (mouseHeld) WindowsInput.ReleaseMouse(); } catch { }
                }
                SessionSlot.Release();
            }
        }
    }

    private static async Task SendBytes(WebSocket socket, SemaphoreSlim mutex, byte[] bytes, WebSocketMessageType type, CancellationToken ct)
    {
        await mutex.WaitAsync(ct);
        try { await socket.SendAsync(new ArraySegment<byte>(bytes), type, true, ct); }
        finally { mutex.Release(); }
    }

    private static async Task StreamScreen(WebSocket socket, SemaphoreSlim mutex, CancellationTokenSource stop, FrameWindow? window)
    {
        try
        {
            var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
            while (!stop.IsCancellationRequested)
            {
                // Reserve before capture so even a stalled network gets a fresh picture next.
                int id = window == null ? 0 : await window.Reserve(stop.Token);
                long started = System.Diagnostics.Stopwatch.GetTimestamp();
                var bounds = Screen.PrimaryScreen?.Bounds ?? throw new InvalidOperationException("Sem monitor.");
                using var raw = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
                using (var graphics = Graphics.FromImage(raw))
                {
                    graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
                    var cursor = Cursor.Position;
                    Cursors.Default.Draw(graphics, new Rectangle(cursor.X - bounds.X, cursor.Y - bounds.Y, 24, 24));
                }
                // A slow acknowledgement includes network + decode time; reduce load, not queue depth.
                bool constrained = window?.LatencyMs > 140;
                double scale = Math.Min(1, (constrained ? 960.0 : 1280.0) / bounds.Width);
                using var frame = new Bitmap(raw, new Size((int)(bounds.Width * scale), (int)(bounds.Height * scale)));
                using var ms = new MemoryStream();
                using var quality = new EncoderParameters(1);
                quality.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, constrained ? 45L : 60L);
                frame.Save(ms, codec, quality);
                byte[] jpeg = ms.ToArray();
                await SendBytes(socket, mutex, window == null ? jpeg : FrameWindow.Packet(id, jpeg), WebSocketMessageType.Binary, stop.Token);
                double elapsed = System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds;
                // Ceiling, not a promised frame rate: capture/encode/network can all be slower.
                double interval = window == null || constrained ? 1000.0 / 30 : 1000.0 / 60;
                if (elapsed < interval) await Task.Delay(TimeSpan.FromMilliseconds(interval - elapsed), stop.Token);
            }
        }
        catch (Exception) { stop.Cancel(); }
    }
}
