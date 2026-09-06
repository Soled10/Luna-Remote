using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
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
        listener.Prefixes.Add(ListenPrefix(port));
        try { listener.Start(); }
        catch (HttpListenerException e) { Console.Error.WriteLine($"Não foi possível abrir porta {port}: {e.Message}"); return; }
        // Coordenadas de captura e do cursor em pixels reais, mesmo com escala de 125%/150% no Windows.
        try { SetProcessDPIAware(); } catch { }
        Console.WriteLine($"Luna Remote Agent 0.5.0 | {ListenPrefix(port)} | até {MaxFps()} fps | Ctrl+C para encerrar");
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

    internal static string ListenPrefix(int port)
    {
        // Default preserves manual LAN testing. The installed supervisor sets loopback,
        // so Caddy/cloudflared are the only public-facing processes.
        string host = Environment.GetEnvironmentVariable("LUNA_BIND_HOST") ?? "+";
        if (host is not ("+" or "127.0.0.1" or "localhost"))
            throw new InvalidOperationException("LUNA_BIND_HOST deve ser +, 127.0.0.1 ou localhost.");
        return $"http://{host}:{port}/remote/";
    }

    // Teto de quadros por segundo. Padrão 120 (telas ProMotion); 30..144.
    // O ritmo real é adaptativo: rede ou CPU lentas reduzem sozinhas, sem acumular atraso.
    internal static int MaxFps()
    {
        if (int.TryParse(Environment.GetEnvironmentVariable("LUNA_MAX_FPS"), out var v))
            return Math.Clamp(v, 30, 144);
        return 120;
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
            string quality = "auto";
            int ceiling = MaxFps();
            async Task Send(object value) =>
                await SendBytes(socket, sendLock, JsonSerializer.SerializeToUtf8Bytes(value), WebSocketMessageType.Text, stop.Token);

            Task frames = Task.CompletedTask, watchdog = Task.CompletedTask;
            try
            {
                await Send(new { type = "hello", version = "0.5.0", protocol = 3, gamepad = pad.Available, gamepadStatus = pad.Status, maxFps = ceiling, cursor = true });
                Console.WriteLine("Cliente conectado. " + pad.Status);
                frames = Task.Run(() => StreamScreen(socket, sendLock, stop, flowControl ? window : null, () => quality, ceiling));
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
                        if (command.Type == "quality") { lock (gate) { quality = command.Mode; } Console.WriteLine($"Qualidade pedida: {command.Mode}"); continue; }
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

    private static async Task StreamScreen(WebSocket socket, SemaphoreSlim mutex, CancellationTokenSource stop, FrameWindow? window, Func<string> getQuality, int ceiling)
    {
        var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
        using var encParams = new EncoderParameters(1);
        Bitmap? raw = null;
        Graphics? gfx = null;
        Bitmap? scaled = null;
        Size scaledSize = Size.Empty;
        Rectangle lastBounds = Rectangle.Empty;
        double lastCurX = -1, lastCurY = -1;
        bool lastCurVis = false;
        long lastCursorSend = 0;
        bool pausedLogged = false;
        try
        {
            while (!stop.IsCancellationRequested)
            {
                // Sem crédito de ack, o cliente pode estar em segundo plano: PAUSA sem
                // capturar e sem encerrar a sessão. O receive continua respondendo ping.
                int id;
                while (true)
                {
                    int? got = window == null ? 0 : window.TryReserve(TimeSpan.FromSeconds(2), stop.Token);
                    if (got.HasValue) { id = got.Value; break; }
                    if (!pausedLogged) { Console.WriteLine("Vídeo pausado: cliente sem confirmar (app em 2º plano?). Sessão mantida."); pausedLogged = true; }
                    await Task.Delay(250, stop.Token);
                }
                if (pausedLogged) { Console.WriteLine("Vídeo retomado."); pausedLogged = false; }
                long started = System.Diagnostics.Stopwatch.GetTimestamp();
                var bounds = Screen.PrimaryScreen?.Bounds ?? throw new InvalidOperationException("Sem monitor.");
                if (raw == null || bounds != lastBounds)
                {
                    gfx?.Dispose(); raw?.Dispose(); scaled?.Dispose(); scaled = null; scaledSize = Size.Empty;
                    raw = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
                    gfx = Graphics.FromImage(raw);
                    lastBounds = bounds;
                }
                gfx!.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
                // Cursor REAL (seta, I-beam, mão…) com hotspot correto + posição p/ overlay do iOS.
                DrawRealCursor(gfx, bounds, out double curX, out double curY, out bool curVis);

                string mode = getQuality();
                // A slow acknowledgement includes network time; reduce load, not queue depth.
                bool constrained = window?.LatencyMs > 140;
                var (targetFps, width, q) = Preset(mode, ceiling, constrained);
                double scale = Math.Min(1, width / (double)bounds.Width);
                int outW = Math.Max(320, (int)(bounds.Width * scale));
                int outH = Math.Max(180, (int)(bounds.Height * scale));
                Bitmap frame = raw;
                if (scale < 0.995)
                {
                    if (scaled == null || scaledSize != new Size(outW, outH))
                    {
                        scaled?.Dispose();
                        scaled = new Bitmap(outW, outH, PixelFormat.Format24bppRgb);
                        scaledSize = new Size(outW, outH);
                    }
                    using (var sg = Graphics.FromImage(scaled))
                    {
                        sg.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                        sg.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighSpeed;
                        sg.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                        sg.DrawImage(raw, 0, 0, outW, outH);
                    }
                    frame = scaled;
                }
                encParams.Param[0]?.Dispose();
                encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, q);
                byte[] jpeg;
                using (var ms = new MemoryStream(131072)) { frame.Save(ms, codec, encParams); jpeg = ms.ToArray(); }
                await SendBytes(socket, mutex, window == null ? jpeg : FrameWindow.Packet(id, jpeg), WebSocketMessageType.Binary, stop.Token);
                long now = System.Diagnostics.Stopwatch.GetTimestamp();
                if (CursorMoved(lastCurX, lastCurY, lastCurVis, curX, curY, curVis)
                    || System.Diagnostics.Stopwatch.GetElapsedTime(lastCursorSend).TotalMilliseconds > 200)
                {
                    lastCurX = curX; lastCurY = curY; lastCurVis = curVis; lastCursorSend = now;
                    try { await SendBytes(socket, mutex, JsonSerializer.SerializeToUtf8Bytes(new { type = "cursor", x = Math.Round(curX, 4), y = Math.Round(curY, 4), visible = curVis }), WebSocketMessageType.Text, stop.Token); }
                    catch (OperationCanceledException) { break; }
                    catch { break; }
                }
                double interval = 1000.0 / Math.Max(15, targetFps);
                // Espera precisa: Task.Delay tem granulação de ~15 ms no Windows, então
                // dorme até ~3 ms antes e completa o resto em spin (sub-milissegundo).
                double elapsed = System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds;
                double remain = interval - elapsed;
                if (remain > 4) await Task.Delay(TimeSpan.FromMilliseconds(remain - 3), stop.Token);
                long spinStart = System.Diagnostics.Stopwatch.GetTimestamp();
                while (System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds < interval)
                {
                    if (System.Diagnostics.Stopwatch.GetElapsedTime(spinStart).TotalMilliseconds > 6) break;
                    Thread.SpinWait(200);
                    if (stop.IsCancellationRequested) break;
                }
            }
        }
        catch (Exception) { stop.Cancel(); }
        finally { gfx?.Dispose(); raw?.Dispose(); scaled?.Dispose(); }
    }

    private static (int fps, double width, long quality) Preset(string mode, int ceiling, bool constrained)
    {
        if (constrained) return (Math.Min(ceiling, 30), 960, 45);
        return mode switch
        {
            "performance" => (Math.Min(ceiling, 120), 960, 50),
            "balanced" => (Math.Min(ceiling, 90), 1280, 60),
            "quality" => (Math.Min(ceiling, 60), 1600, 72),
            _ => (ceiling, 1280, 60),
        };
    }

    private static bool CursorMoved(double lx, double ly, bool lv, double x, double y, bool v) =>
        lv != v || Math.Abs(lx - x) > 0.002 || Math.Abs(ly - y) > 0.002;

    // Desenha o cursor de verdade (não uma seta genérica) e devolve a posição
    // normalizada para o overlay nítido do iPhone.
    private static void DrawRealCursor(Graphics g, Rectangle bounds, out double nx, out double ny, out bool visible)
    {
        nx = 0.5; ny = 0.5; visible = false;
        try
        {
            var ci = new CursorInfo { Size = Marshal.SizeOf<CursorInfo>() };
            if (!GetCursorInfo(ref ci) || ci.Flags != 1 || ci.Handle == IntPtr.Zero) return;
            int sx = ci.Pos.X - bounds.X, sy = ci.Pos.Y - bounds.Y;
            nx = (double)sx / Math.Max(1, bounds.Width);
            ny = (double)sy / Math.Max(1, bounds.Height);
            visible = true;
            IntPtr copy = CopyIcon(ci.Handle);
            if (copy == IntPtr.Zero) return;
            try
            {
                int hx = 0, hy = 0;
                try
                {
                    if (GetIconInfo(copy, out var ii))
                    {
                        hx = ii.HotX; hy = ii.HotY;
                        if (ii.Mask != IntPtr.Zero) DeleteObject(ii.Mask);
                        if (ii.Color != IntPtr.Zero) DeleteObject(ii.Color);
                    }
                }
                catch { }
                IntPtr hdc = g.GetHdc();
                try { DrawIconEx(hdc, sx - hx, sy - hy, copy, 0, 0, 0, IntPtr.Zero, 0x0003); }
                finally { g.ReleaseHdc(hdc); }
            }
            finally { DestroyIcon(copy); }
        }
        catch { }
    }

    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] private static extern bool GetCursorInfo(ref CursorInfo pci);
    [DllImport("user32.dll")] private static extern IntPtr CopyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] private static extern bool GetIconInfo(IntPtr hIcon, out IconInfo info);
    [DllImport("user32.dll")] private static extern bool DrawIconEx(IntPtr hdc, int x, int y, IntPtr hIcon, int cx, int cy, int step, IntPtr flicker, int flags);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)] private struct Point32 { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct CursorInfo { public int Size; public int Flags; public IntPtr Handle; public Point32 Pos; }
    [StructLayout(LayoutKind.Sequential)] private struct IconInfo
    {
        [MarshalAs(UnmanagedType.Bool)] public bool IsIcon;
        public int HotX, HotY;
        public IntPtr Mask, Color;
    }
}
