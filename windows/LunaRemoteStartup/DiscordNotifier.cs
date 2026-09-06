using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;

internal static class DiscordNotifier
{
    internal static string? ExtractDomain(string line)
    {
        var match = Regex.Match(line, @"https://[a-z0-9]+(?:-[a-z0-9]+)*\.trycloudflare\.com(?=[\s/|]|$)");
        return match.Success ? match.Value : null;
    }

    internal static object Payload(string domain) => new
    {
        content = $"Luna Remote — novo endereço de conexão:\n{domain}\n\nUse esse endereço no app. O controle da tela depende de uma sessão de usuário aberta no Windows. O token continua o mesmo e não é enviado aqui.",
        allowed_mentions = new { parse = Array.Empty<string>() }
    };

    internal static async Task<bool> Send(HttpClient client, Uri webhook, string domain, Action<string> log, CancellationToken stop)
    {
        int seconds = 2;
        while (!stop.IsCancellationRequested)
        {
            TimeSpan delay = TimeSpan.FromSeconds(seconds);
            try
            {
                using var response = await client.PostAsJsonAsync(webhook, Payload(domain), stop);
                if (response.IsSuccessStatusCode) { log("Discord: endereço enviado."); return true; }
                log($"Discord: HTTP {(int)response.StatusCode} (sem registrar URL ou resposta).");
                if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden or HttpStatusCode.NotFound)
                    return false;
                if (response.StatusCode == HttpStatusCode.TooManyRequests)
                {
                    using var json = System.Text.Json.JsonDocument.Parse(await response.Content.ReadAsStringAsync(stop));
                    if (json.RootElement.TryGetProperty("retry_after", out var retry) && retry.TryGetDouble(out var wait) && double.IsFinite(wait))
                        delay = TimeSpan.FromSeconds(Math.Clamp(wait, 1, 3600));
                }
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { throw; }
            catch (Exception) { log("Discord indisponível; nova tentativa automática."); }
            await Task.Delay(delay, stop);
            seconds = Math.Min(seconds * 2, 60);
        }
        return false;
    }
}
