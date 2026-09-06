using System.Diagnostics;
using Microsoft.Extensions.Hosting;

internal sealed class TunnelWorker(StartupConfig config) : BackgroundService
{
    private readonly object logGate = new();
    private void Log(string message)
    {
        lock (logGate)
        {
            Directory.CreateDirectory(config.StateDirectory);
            string path = Path.Combine(config.StateDirectory, "startup.log");
            if (File.Exists(path) && new FileInfo(path).Length > 1_000_000) File.Move(path, path + ".previous", true);
            File.AppendAllText(path, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try { await Run(stoppingToken); }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
        catch (Exception)
        {
            // A nonzero exit lets Service Control Manager apply its recovery policy.
            Environment.Exit(1);
        }
    }

    private async Task Run(CancellationToken stoppingToken)
    {
        // HTTP redirects must not forward the webhook credential to another host.
        using var http = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(20) };
        var webhook = config.Webhook();
        int backoff = 5;
        while (!stoppingToken.IsCancellationRequested)
        {
            var started = Stopwatch.StartNew();
            using var session = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
            using var process = new Process { StartInfo = new ProcessStartInfo(config.Cloudflared)
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                WorkingDirectory = config.StateDirectory
            }};
            foreach (string argument in new[] { "tunnel", "--no-autoupdate", "--url", $"http://127.0.0.1:{config.Port}", "--protocol", "http2" })
                process.StartInfo.ArgumentList.Add(argument);
            Task stdout = Task.CompletedTask, stderr = Task.CompletedTask, notify = Task.CompletedTask;
            ChildProcessJob? childJob = null;
            var domainFound = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            async Task Read(StreamReader reader)
            {
                while (await reader.ReadLineAsync(session.Token) is { } line)
                {
                    if (DiscordNotifier.ExtractDomain(line) is { } domain) domainFound.TrySetResult(domain);
                    if (line.Contains("Registered tunnel connection", StringComparison.Ordinal)) ready.TrySetResult();
                    // Raw cloudflared output is deliberately not persisted.
                }
            }
            try
            {
                process.Start();
                childJob = new ChildProcessJob(process);
                Log("Túnel iniciado; aguardando internet e registro na Cloudflare.");
                stdout = Read(process.StandardOutput); stderr = Read(process.StandardError);
                var exited = process.WaitForExitAsync(session.Token);
                var registered = Task.WhenAll(domainFound.Task, ready.Task);
                var deadline = Task.Delay(TimeSpan.FromMinutes(2), session.Token);
                if (await Task.WhenAny(registered, exited, deadline) == registered)
                {
                    string domain = await domainFound.Task;
                    File.WriteAllText(Path.Combine(config.StateDirectory, "current-url.txt"), domain);
                    Log("Túnel registrado; enviando endereço ao Discord.");
                    notify = DiscordNotifier.Send(http, webhook, domain, Log, session.Token);
                    await exited;
                }
                else Log("Túnel saiu ou não registrou em 2 minutos; será reiniciado.");
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
            catch (Exception) { Log("Falha no supervisor; nova tentativa automática."); }
            finally
            {
                session.Cancel();
                try { if (!process.HasExited) { process.Kill(entireProcessTree: true); await process.WaitForExitAsync(); } }
                catch (InvalidOperationException) { }
                childJob?.Dispose();
                try { await Task.WhenAll(stdout, stderr, notify); }
                catch (OperationCanceledException) { }
                catch (Exception) { Log("Leitura do processo encerrada."); }
                // A stopped tunnel's address must not be presented as current.
                string current = Path.Combine(config.StateDirectory, "current-url.txt");
                if (File.Exists(current)) File.Delete(current);
            }
            if (stoppingToken.IsCancellationRequested) break;
            if (started.Elapsed > TimeSpan.FromMinutes(5)) backoff = 5;
            await Task.Delay(TimeSpan.FromSeconds(backoff), stoppingToken);
            backoff = Math.Min(backoff * 2, 60);
        }
    }
}
