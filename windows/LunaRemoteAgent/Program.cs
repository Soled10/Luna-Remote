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
        Console.WriteLine($"Luna Remote Agent 0.6.0 | {ListenPrefix(port)} | até {MaxFps()} fps | Ctrl+C para encerrar");
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
                var proto = context.Request.QueryString["protocol"];
                _ = RunSession(socket, proto is "3" or "4", regions: proto == "4");
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

    private static async Task RunSession(WebSocket socket, bool flowControl, bool regions)
    {
        using (socket)
        using (var stop = new CancellationTokenSource())
        using (var sendLock = new SemaphoreSlim(1, 1))
        using (var pad = new VirtualGamepad())
        using (var window = new FrameWindow())
        {
            var gate = new object();
            long lastPad = Environment.TickCount64, lastMouse = lastPad, lastCursorEcho = 0;
            bool padActive = false, mouseHeld = false;
            string quality = "auto";
            int ceiling = MaxFps();
            async Task Send(object value) =>
                await SendBytes(socket, sendLock, JsonSerializer.SerializeToUtf8Bytes(value), WebSocketMessageType.Text, stop.Token);

            Task frames = Task.CompletedTask, watchdog = Task.CompletedTask;
            try
            {
                await Send(new { type = "hello", version = "0.6.0", protocol = 4, gamepad = pad.Available, gamepadStatus = pad.Status, maxFps = ceiling, cursor = true, regions });
                Console.WriteLine("Cliente conectado. " + pad.Status);
                frames = Task.Run(() => StreamScreen(socket, sendLock, stop, flowControl ? window : null, () => quality, ceiling, regions));
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
                                // Eco imediato do cursor: o ponteiro parece ao vivo mesmo
                                // quando o vídeo está lento. Não espera o próximo quadro.
                                if (command.Type is "move" or "click" or "button" && lastMouse - lastCursorEcho > 16)
                                {
                                    lastCursorEcho = lastMouse;
                                    var area = Screen.PrimaryScreen?.Bounds ?? Rectangle.Empty;
                                    if (area.Width > 0)
                                    {
                                        GetCursorState(area, out double ex, out double ey, out bool evis);
                                        EchoCursor(socket, sendLock, stop, ex, ey, evis);
                                    }
                                }
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

    private static async Task StreamScreen(WebSocket socket, SemaphoreSlim mutex, CancellationTokenSource stop, FrameWindow? window, Func<string> getQuality, int ceiling, bool regions)
    {
        var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
        using var encParams = new EncoderParameters(1);
        Bitmap? frame = null;   // bitmap final, já na resolução de envio (reutilizado)
        Graphics? gfx = null;
        Bitmap? prev = null;    // último conteúdo ENVIADO (só no modo regiões)
        Graphics? prevGfx = null;
        Bitmap? raw = null;     // só alocado se o StretchBlt falhar (fallback GDI)
        Graphics? rawGfx = null;
        Size frameSize = Size.Empty;
        Rectangle lastBounds = Rectangle.Empty;
        var profile = new AutoProfile();
        ulong prevHash = 0;
        bool havePrev = false;
        double lastCurX = -1, lastCurY = -1;
        bool lastCurVis = false;
        long lastFrameSent = 0, lastCursorMeta = 0;
        bool pausedLogged = false, captureLogged = false, useFallback = false;
        long statFrames = 0, statBytes = 0, statStart = System.Diagnostics.Stopwatch.GetTimestamp();
        double statCap = 0, statEnc = 0, statSend = 0;
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

                string mode = getQuality();
                bool auto = mode == "auto";
                double latency = window?.LatencyMs ?? 50;
                if (auto) profile.Observe(latency);
                var (targetFps, width, q) = auto ? profile.Current(ceiling) : Preset(mode, ceiling, latency > 140);
                double scale = Math.Min(1, width / (double)bounds.Width);
                int outW = Math.Max(320, (int)(bounds.Width * scale));
                int outH = Math.Max(180, (int)(bounds.Height * scale));
                if (frame == null || frameSize != new Size(outW, outH) || bounds != lastBounds)
                {
                    gfx?.Dispose(); frame?.Dispose(); prevGfx?.Dispose(); prev?.Dispose();
                    frame = null; prev = null;
                    frame = new Bitmap(outW, outH, PixelFormat.Format32bppArgb);
                    gfx = Graphics.FromImage(frame);
                    gfx.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                    if (regions)
                    {
                        prev = new Bitmap(outW, outH, PixelFormat.Format32bppArgb);
                        prevGfx = Graphics.FromImage(prev);
                        prevGfx.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                        prevGfx.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                    }
                    frameSize = new Size(outW, outH); lastBounds = bounds;
                    havePrev = false; // resize/monitor novo: reenvia cheio
                }

                // Captura direto na resolução final (1 chamada). Fallback GDI se falhar.
                long capStart = System.Diagnostics.Stopwatch.GetTimestamp();
                if (!useFallback && !CaptureStretch(frame, gfx!, bounds))
                {
                    useFallback = true;
                    if (!captureLogged) { Console.WriteLine("StretchBlt indisponível; usando captura GDI."); captureLogged = true; }
                }
                if (useFallback)
                {
                    if (raw == null || raw.Size != bounds.Size)
                    {
                        rawGfx?.Dispose(); raw?.Dispose();
                        raw = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
                        rawGfx = Graphics.FromImage(raw);
                    }
                    rawGfx!.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
                    gfx!.DrawImage(raw, 0, 0, outW, outH);
                }
                double capMs = System.Diagnostics.Stopwatch.GetElapsedTime(capStart).TotalMilliseconds;

                // Tela parada? Não codifica nem envia JPEG: libera o slot e dorme.
                // O cursor continua ao vivo por mensagem própria (aqui e no eco de input).
                ulong hash = ThumbHash(frame);
                GetCursorState(bounds, out double curX, out double curY, out bool curVis);
                long now = System.Diagnostics.Stopwatch.GetTimestamp();
                bool cursorChanged = CursorMoved(lastCurX, lastCurY, lastCurVis, curX, curY, curVis);
                bool stale = System.Diagnostics.Stopwatch.GetElapsedTime(lastFrameSent).TotalMilliseconds > 1500;
                if (havePrev && hash == prevHash && !cursorChanged && !stale)
                {
                    window?.Acknowledge(id); // quadro idêntico não ocupa a rede
                    if (System.Diagnostics.Stopwatch.GetElapsedTime(lastCursorMeta).TotalMilliseconds > 200)
                    {
                        lastCursorMeta = now;
                        try { await SendBytes(socket, mutex, JsonSerializer.SerializeToUtf8Bytes(new { type = "cursor", x = Math.Round(curX, 4), y = Math.Round(curY, 4), visible = curVis }), WebSocketMessageType.Text, stop.Token); }
                        catch { break; }
                    }
                    try { await Task.Delay(33, stop.Token); } catch { break; }
                    continue;
                }

                // Diff exato por blocos: envia só o retângulo sujo (1 JPEG). Se mais de
                // 45% sujou, compensa mais o quadro cheio. Clientes antigos: quadro cheio
                // com cursor desenhado, como antes.
                bool sendFull = !havePrev || stale;
                Rectangle box = new(0, 0, outW, outH);
                if (regions && havePrev && !stale && prev != null)
                {
                    var dirty = DirtyBox(frame, prev);
                    if (dirty is { } d && d.ratio <= 0.45 && d.box.Width > 0 && d.box.Height > 0)
                    { box = d.box; sendFull = false; }
                }
                long encStart = System.Diagnostics.Stopwatch.GetTimestamp();
                byte[] jpeg;
                if (!regions) DrawRealCursor(gfx!, outW, outH, scale, curX, curY, curVis);
                encParams.Param[0]?.Dispose();
                encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, q);
                if (sendFull || !regions)
                {
                    using var ms = new MemoryStream(131072);
                    frame.Save(ms, codec, encParams);
                    jpeg = ms.ToArray();
                }
                else
                {
                    using var crop = frame.Clone(box, PixelFormat.Format32bppArgb);
                    using var ms = new MemoryStream(Math.Max(8192, box.Width * box.Height / 4));
                    crop.Save(ms, codec, encParams);
                    jpeg = ms.ToArray();
                }
                double encMs = System.Diagnostics.Stopwatch.GetElapsedTime(encStart).TotalMilliseconds;
                long sendStart = System.Diagnostics.Stopwatch.GetTimestamp();
                if (regions)
                {
                    var region = new { type = "region", frame = id, x = box.X, y = box.Y, w = box.Width, h = box.Height, full = sendFull };
                    await SendBytes(socket, mutex, JsonSerializer.SerializeToUtf8Bytes(region), WebSocketMessageType.Text, stop.Token);
                }
                await SendBytes(socket, mutex, window == null ? jpeg : FrameWindow.Packet(id, jpeg), WebSocketMessageType.Binary, stop.Token);
                double sendMs = System.Diagnostics.Stopwatch.GetElapsedTime(sendStart).TotalMilliseconds;
                if (regions)
                {
                    if (sendFull) { (prev, frame) = (frame, prev); (prevGfx, gfx) = (gfx, prevGfx); }
                    else prevGfx!.DrawImage(frame, box, box.X, box.Y, box.Width, box.Height, GraphicsUnit.Pixel);
                }
                havePrev = true; prevHash = hash;
                lastFrameSent = System.Diagnostics.Stopwatch.GetTimestamp();
                now = lastFrameSent;
                statFrames++; statBytes += jpeg.Length; statCap += capMs; statEnc += encMs; statSend += sendMs;
                if (System.Diagnostics.Stopwatch.GetElapsedTime(statStart).TotalSeconds >= 5)
                {
                    double secs = System.Diagnostics.Stopwatch.GetElapsedTime(statStart).TotalSeconds;
                    Console.WriteLine($"[vídeo] {statFrames / secs:F0} fps · {statBytes / 1024.0 / Math.Max(1, statFrames):F0} KB/f · " +
                        $"cap {statCap / statFrames:F1}ms enc {statEnc / statFrames:F1}ms snd {statSend / statFrames:F1}ms · " +
                        $"{mode}{(auto ? $" t{profile.Tier}" : "")} {outW}x{outH} q{q}");
                    statFrames = 0; statBytes = 0; statCap = statEnc = statSend = 0;
                    statStart = System.Diagnostics.Stopwatch.GetTimestamp();
                }
                if (cursorChanged || System.Diagnostics.Stopwatch.GetElapsedTime(lastCursorMeta).TotalMilliseconds > 200)
                {
                    lastCurX = curX; lastCurY = curY; lastCurVis = curVis; lastCursorMeta = now;
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
        finally { gfx?.Dispose(); frame?.Dispose(); prevGfx?.Dispose(); prev?.Dispose(); rawGfx?.Dispose(); raw?.Dispose(); }
    }

    private static (int fps, double width, long quality) Preset(string mode, int ceiling, bool constrained)
    {
        if (constrained) return (Math.Min(ceiling, 30), 960, 45);
        return mode switch
        {
            "performance" => (Math.Min(ceiling, 120), 960, 50),
            "balanced" => (Math.Min(ceiling, 90), 1280, 65),
            "quality" => (Math.Min(ceiling, 60), 1600, 78),
            _ => (ceiling, 1280, 60),
        };
    }

    // Modo automático com slow-start e histerese: começa leve (960p) para a
    // primeira imagem chegar rápido, sobe após ~2 s de rede boa e só desce
    // após congestão sustentada — sem o liga/desliga que causava engasgos.
    internal sealed class AutoProfile
    {
        public int Tier { get; private set; } = 0;
        private int goodStreak, badStreak;
        public void Observe(double latencyMs)
        {
            if (Tier == 0)
            {
                if (latencyMs < 70) { if (++goodStreak >= 240) { Tier = 1; goodStreak = badStreak = 0; } }
                else goodStreak = 0;
            }
            else
            {
                if (latencyMs > 140) { if (++badStreak >= 10) { Tier = 0; goodStreak = badStreak = 0; } }
                else badStreak = 0;
            }
        }
        public (int fps, double width, long quality) Current(int ceiling) =>
            Tier == 0 ? (Math.Min(ceiling, 60), 960, 50) : (ceiling, 1280, 68);
    }

    private static bool CursorMoved(double lx, double ly, bool lv, double x, double y, bool v) =>
        lv != v || Math.Abs(lx - x) > 0.002 || Math.Abs(ly - y) > 0.002;

    // Posição do cursor sem copiar o ícone (barato: chamado a cada input).
    private static void GetCursorState(Rectangle bounds, out double nx, out double ny, out bool visible)
    {
        nx = 0.5; ny = 0.5; visible = false;
        try
        {
            var ci = new CursorInfo { Size = Marshal.SizeOf<CursorInfo>() };
            if (!GetCursorInfo(ref ci) || ci.Handle == IntPtr.Zero) return;
            nx = (double)(ci.Pos.X - bounds.X) / Math.Max(1, bounds.Width);
            ny = (double)(ci.Pos.Y - bounds.Y) / Math.Max(1, bounds.Height);
            visible = ci.Flags == 1;
        }
        catch { }
    }

    // Envio de cursor sem esperar: observa a falha para não deixar exceção solta.
    private static void EchoCursor(WebSocket socket, SemaphoreSlim mutex, CancellationTokenSource stop, double x, double y, bool visible)
    {
        try
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new { type = "cursor", x = Math.Round(x, 4), y = Math.Round(y, 4), visible });
            _ = SendBytes(socket, mutex, bytes, WebSocketMessageType.Text, stop.Token)
                .ContinueWith(t => { if (t.IsFaulted) { try { stop.Cancel(); } catch { } } }, TaskScheduler.Default);
        }
        catch { }
    }

    // Desenha o cursor de verdade (não uma seta genérica) já na resolução de envio.
    private static void DrawRealCursor(Graphics g, int outW, int outH, double scale, double nx, double ny, bool visible)
    {
        if (!visible) return;
        try
        {
            var ci = new CursorInfo { Size = Marshal.SizeOf<CursorInfo>() };
            if (!GetCursorInfo(ref ci) || ci.Flags != 1 || ci.Handle == IntPtr.Zero) return;
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
                int icon = Math.Max(16, (int)(32 * scale));
                int dx = (int)(nx * outW - hx * scale), dy = (int)(ny * outH - hy * scale);
                IntPtr hdc = g.GetHdc();
                try { DrawIconEx(hdc, dx, dy, copy, icon, icon, 0, IntPtr.Zero, 0x0003); }
                finally { g.ReleaseHdc(hdc); }
            }
            finally { DestroyIcon(copy); }
        }
        catch { }
    }

    // Captura a tela direto na resolução de envio em 1 chamada ao driver,
    // sem bitmap full-res temporário nem resize na CPU.
    private static bool CaptureStretch(Bitmap frame, Graphics gfx, Rectangle bounds)
    {
        IntPtr screenDC = IntPtr.Zero, hdc = IntPtr.Zero;
        bool gotHdc = false;
        try
        {
            screenDC = GetDC(IntPtr.Zero);
            if (screenDC == IntPtr.Zero) return false;
            hdc = gfx.GetHdc(); gotHdc = true;
            SetStretchBltMode(hdc, 4 /*HALFTONE*/);
            SetBrushOrgEx(hdc, 0, 0, IntPtr.Zero);
            return StretchBlt(hdc, 0, 0, frame.Width, frame.Height,
                screenDC, bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x00CC0020 /*SRCCOPY*/);
        }
        catch { return false; }
        finally
        {
            if (gotHdc) { try { gfx.ReleaseHdc(hdc); } catch { } }
            if (screenDC != IntPtr.Zero) ReleaseDC(IntPtr.Zero, screenDC);
        }
    }

    // Hash rápido de miniatura amostrada: detecta qualquer mudança com <0,5 ms.
    internal static ulong ThumbHash(Bitmap bmp)
    {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int stepX = Math.Max(1, bmp.Width / 64);
            int stepY = Math.Max(1, bmp.Height / 36);
            ulong h = 1469598103934665603UL;
            for (int y = 0; y < bmp.Height; y += stepY)
            {
                int row = y * data.Stride;
                for (int x = 0; x < bmp.Width; x += stepX)
                {
                    // Pixel inteiro (BGRA): trocar R por B também muda o hash.
                    uint p = unchecked((uint)Marshal.ReadInt32(data.Scan0, row + x * 4));
                    h ^= p + (uint)x * 31 + (uint)y * 101;
                    h *= 1099511628211UL;
                }
            }
            return h;
        }
        finally { bmp.UnlockBits(data); }
    }

    // Compara dois quadros por blocos de 128px (exato, sem amostragem) e devolve
    // a caixa que cobre todos os blocos sujos + a fração suja. Null = idênticos.
    internal static (Rectangle box, double ratio)? DirtyBox(Bitmap cur, Bitmap prv)
    {
        if (cur.Size != prv.Size) return null;
        const int T = 128;
        int W = cur.Width, H = cur.Height;
        int cols = (W + T - 1) / T, rows = (H + T - 1) / T;
        var cd = cur.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var pd = prv.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int minX = cols, minY = rows, maxX = -1, maxY = -1, dirty = 0;
            byte[] a = new byte[T * 4], b = new byte[T * 4];
            for (int ty = 0; ty < rows; ty++)
                for (int tx = 0; tx < cols; tx++)
                {
                    int x0 = tx * T, y0 = ty * T, tw = Math.Min(T, W - x0), th = Math.Min(T, H - y0);
                    bool diff = false;
                    for (int y = 0; y < th && !diff; y++)
                    {
                        Marshal.Copy(IntPtr.Add(cd.Scan0, (y0 + y) * cd.Stride + x0 * 4), a, 0, tw * 4);
                        Marshal.Copy(IntPtr.Add(pd.Scan0, (y0 + y) * pd.Stride + x0 * 4), b, 0, tw * 4);
                        if (!a.AsSpan(0, tw * 4).SequenceEqual(b.AsSpan(0, tw * 4))) diff = true;
                    }
                    if (diff) { dirty++; if (tx < minX) minX = tx; if (tx > maxX) maxX = tx; if (ty < minY) minY = ty; if (ty > maxY) maxY = ty; }
                }
            if (dirty == 0) return null;
            var box = Rectangle.FromLTRB(minX * T, minY * T, Math.Min(W, (maxX + 1) * T), Math.Min(H, (maxY + 1) * T));
            return (box, (double)dirty / (cols * rows));
        }
        finally { cur.UnlockBits(cd); prv.UnlockBits(pd); }
    }

    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] private static extern bool GetCursorInfo(ref CursorInfo pci);
    [DllImport("user32.dll")] private static extern IntPtr CopyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] private static extern bool GetIconInfo(IntPtr hIcon, out IconInfo info);
    [DllImport("user32.dll")] private static extern bool DrawIconEx(IntPtr hdc, int x, int y, IntPtr hIcon, int cx, int cy, int step, IntPtr flicker, int flags);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern bool StretchBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest, IntPtr hdcSrc, int xSrc, int ySrc, int wSrc, int hSrc, int rop);
    [DllImport("gdi32.dll")] private static extern int SetStretchBltMode(IntPtr hdc, int mode);
    [DllImport("gdi32.dll")] private static extern bool SetBrushOrgEx(IntPtr hdc, int x, int y, IntPtr prev);

    [StructLayout(LayoutKind.Sequential)] private struct Point32 { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct CursorInfo { public int Size; public int Flags; public IntPtr Handle; public Point32 Pos; }
    [StructLayout(LayoutKind.Sequential)] private struct IconInfo
    {
        [MarshalAs(UnmanagedType.Bool)] public bool IsIcon;
        public int HotX, HotY;
        public IntPtr Mask, Color;
    }
}
