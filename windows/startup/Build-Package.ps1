param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path $PSScriptRoot -Parent
$Destination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
& dotnet publish (Join-Path $windowsRoot 'LunaRemoteStartup\LunaRemoteStartup.csproj') -c Release -r win-x64 --self-contained true -o (Join-Path $Destination 'service')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar servico.' }
& dotnet publish (Join-Path $windowsRoot 'LunaRemoteAgent\LunaRemoteAgent.csproj') -c Release -r win-x64 --self-contained true -o (Join-Path $Destination 'agent')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar agente.' }
foreach ($name in @('Install-Startup.ps1', 'Uninstall-Startup.ps1', 'Run-Agent.ps1', 'Save-Webhook.ps1', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $Destination -Force
}
Write-Host "Pacote Windows x64: $Destination"
