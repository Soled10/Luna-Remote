using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

if (args.Contains("--self-test")) { await StartupTests.Run(); return; }
var configPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "LunaRemote", "tunnel.json");
var configIndex = Array.IndexOf(args, "--config");
if (configIndex >= 0 && configIndex + 1 < args.Length) configPath = Path.GetFullPath(args[configIndex + 1]);
var builder = Host.CreateApplicationBuilder(args);
builder.Logging.ClearProviders(); // Never let HTTP diagnostics print the webhook credential.
builder.Services.AddWindowsService(options => options.ServiceName = "LunaRemoteTunnel");
builder.Services.AddSingleton(StartupConfig.Load(configPath));
builder.Services.AddHostedService<TunnelWorker>();
await builder.Build().RunAsync();
