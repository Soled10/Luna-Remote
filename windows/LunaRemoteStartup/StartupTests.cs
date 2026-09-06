using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class StartupTests
{
    public static async Task Run()
    {
        void Check(bool result, string name) { if (!result) throw new Exception(name); Console.WriteLine("PASS " + name); }
        const string domain = "https://quiet-green-river.trycloudflare.com";
        Check(DiscordNotifier.ExtractDomain("INF | " + domain + " |") == domain, "parse cloudflared domain");
        Check(DiscordNotifier.ExtractDomain(domain + ".evil.org") == null, "reject domain suffix spoof");
        Check(DiscordNotifier.ExtractDomain("https://api.trycloudflare.com.evil/") == null, "reject foreign URL");
        Check(StartupConfig.ValidateWebhook("https://discord.com/api/webhooks/123/test-token").Query == "?wait=true", "Discord delivery confirmation");
        foreach (var bad in new[] { "http://discord.com/api/webhooks/123/token", "https://evil.org/api/webhooks/123/token", "https://discord.com/api/webhooks/123/token?x=1" })
        {
            bool rejected = false;
            try { StartupConfig.ValidateWebhook(bad); } catch (InvalidDataException) { rejected = true; }
            Check(rejected, "reject invalid webhook");
        }
        using var payload = JsonDocument.Parse(JsonSerializer.Serialize(DiscordNotifier.Payload(domain)));
        Check(payload.RootElement.GetProperty("content").GetString()!.Contains(domain), "payload includes domain");
        Check(payload.RootElement.GetProperty("allowed_mentions").GetProperty("parse").GetArrayLength() == 0, "disable Discord mentions");
        byte[] sample = Encoding.UTF8.GetBytes("test-only");
        byte[] cipher = ProtectedData.Protect(sample, null, DataProtectionScope.LocalMachine);
        Check(ProtectedData.Unprotect(cipher, null, DataProtectionScope.LocalMachine).SequenceEqual(sample), "DPAPI round trip");
        var handler = new FakeHandler(HttpStatusCode.TooManyRequests, HttpStatusCode.OK);
        using var client = new HttpClient(handler);
        var uri = new Uri("https://discord.com/api/webhooks/123/test-token?wait=true");
        Check(await DiscordNotifier.Send(client, uri, domain, _ => { }, CancellationToken.None) && handler.Count == 2, "retry rate limit then success");
        using var denied = new HttpClient(new FakeHandler(HttpStatusCode.NotFound));
        Check(!await DiscordNotifier.Send(denied, uri, domain, _ => { }, CancellationToken.None), "revoked webhook does not spin");
        using var canceled = new CancellationTokenSource(); canceled.Cancel();
        Check(!await DiscordNotifier.Send(client, uri, domain, _ => { }, canceled.Token), "canceled tunnel does not notify");
        using var child = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ping.exe", "-t 127.0.0.1")
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!;
        try
        {
            using (var job = new ChildProcessJob(child)) { Check(!child.HasExited, "child attached to Windows job"); }
            Check(child.WaitForExit(5000), "job disposal terminates child");
        }
        finally { if (!child.HasExited) child.Kill(); }
        Console.WriteLine("All startup tests passed. No external requests were made.");
    }

    private sealed class FakeHandler(params HttpStatusCode[] statuses) : HttpMessageHandler
    {
        public int Count { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var status = statuses[Math.Min(Count++, statuses.Length - 1)];
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent("{\"retry_after\":1}") });
        }
    }
}
