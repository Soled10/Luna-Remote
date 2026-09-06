using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

internal record StartupConfig(string Cloudflared, string WebhookProtected, string StateDirectory, int Port = 8765)
{
    public static StartupConfig Load(string path)
    {
        var config = JsonSerializer.Deserialize<StartupConfig>(File.ReadAllText(path)) ?? throw new InvalidDataException("Configuration missing.");
        if (!Path.IsPathFullyQualified(config.Cloudflared) || !File.Exists(config.Cloudflared) ||
            !Path.IsPathFullyQualified(config.StateDirectory) || config.Port is < 1 or > 65535)
            throw new InvalidDataException("Invalid paths or port in startup configuration.");
        return config;
    }

    public Uri Webhook()
    {
        byte[] clear = ProtectedData.Unprotect(Convert.FromBase64String(WebhookProtected), null, DataProtectionScope.LocalMachine);
        try { return ValidateWebhook(Encoding.UTF8.GetString(clear)); }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }

    internal static Uri ValidateWebhook(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            uri.Host != "discord.com" || !uri.IsDefaultPort || uri.UserInfo != "" || uri.Query != "" || uri.Fragment != "" ||
            !Regex.IsMatch(uri.AbsolutePath, @"^/api/webhooks/\d+/[A-Za-z0-9_-]+$"))
            throw new InvalidDataException("Use a Discord HTTPS webhook URL without query parameters.");
        return new Uri(value + "?wait=true");
    }
}
