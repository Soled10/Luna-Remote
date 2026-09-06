#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][string]$CaddyPath,
    [switch]$Start
)
$ErrorActionPreference = 'Stop'

# Caddy's HTTP challenge only works after this hostname resolves to the router's
# public IP and TCP 80/443 are forwarded to this PC. DNS must be Cloudflare DNS-only.
if ($Domain -notmatch '^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$') {
    throw 'Informe um hostname público válido, por exemplo jogar.exemplo.com.'
}
if (-not (Test-Path -LiteralPath $CaddyPath)) { throw 'caddy.exe não encontrado. Informe -CaddyPath.' }
$candidate = Get-Item -LiteralPath $CaddyPath
if ($candidate.Extension -ne '.exe') { throw 'O gateway precisa apontar para caddy.exe.' }

$root = Join-Path $env:ProgramData 'LunaRemote\gateway'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @('S-1-5-18', 'S-1-5-19', 'S-1-5-32-544')) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $root -AclObject $acl

$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Caddyfile.template') -Raw
$config = $template.Replace('{{DOMAIN}}', $Domain.ToLowerInvariant())
$configPath = Join-Path $root 'Caddyfile'
Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8

# Validate before exposing ports or registering a service.
& $candidate.FullName validate --config $configPath --adapter caddyfile
if ($LASTEXITCODE -ne 0) { throw 'Caddy recusou a configuração.' }

$serviceName = 'LunaRemoteGateway'
if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
    Stop-Service $serviceName -ErrorAction SilentlyContinue
    & sc.exe config $serviceName binPath= ('"' + $candidate.FullName + '" run --config "' + $configPath + '" --adapter caddyfile') start= auto obj= 'NT AUTHORITY\LocalService'
} else {
    & sc.exe create $serviceName binPath= ('"' + $candidate.FullName + '" run --config "' + $configPath + '" --adapter caddyfile') start= auto obj= 'NT AUTHORITY\LocalService' DisplayName= 'Luna Remote - HTTPS direto'
}
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível registrar o gateway HTTPS.' }
& sc.exe failure $serviceName reset= 86400 actions= restart/10000/restart/30000/restart/60000
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível configurar recuperação do gateway.' }

# Rules are narrow: TCP only, no direct exposure of the internal agent port 8765.
foreach ($port in 80,443) {
    $rule = "Luna Remote HTTPS TCP $port"
    if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow -Protocol TCP -LocalPort $port -Profile Private,Public | Out-Null
    }
}
Write-Host "Gateway preparado para https://$Domain"
Write-Host 'Antes de iniciar: crie um registro A DNS-only para seu IP público e encaminhe TCP 80/443 do roteador para este PC.'
if ($Start) {
    Start-Service $serviceName
    Write-Host 'Serviço iniciado. A emissão do certificado aparecerá no log do Windows/Caddy.'
} else {
    Write-Host 'Serviço ainda parado. Após concluir DNS e redirecionamento, execute: Start-Service LunaRemoteGateway'
}
