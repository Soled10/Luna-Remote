#Requires -RunAsAdministrator
param(
    [string]$CloudflaredPath = "$env:USERPROFILE\bin\cloudflared.exe",
    [string]$WebhookSeed = "$env:LOCALAPPDATA\LunaRemoteStartup\webhook.dpapi"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$installRoot = Join-Path $env:ProgramFiles 'LunaRemote'
$dataRoot = Join-Path $env:ProgramData 'LunaRemote'
$userRoot = Join-Path $env:LOCALAPPDATA 'LunaRemoteStartup'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userSid = $identity.User.Value
$userAccount = $identity.Name
$serviceName = 'LunaRemoteTunnel'

function Set-PrivateDirectory([string]$Path, [string]$ExtraSid, [Security.AccessControl.FileSystemRights]$Rights) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    if ($ExtraSid) { $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($ExtraSid), $Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow')) }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Plain([Security.SecureString]$Secret) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

foreach ($required in @('service\LunaRemoteStartup.exe', 'agent\LunaRemoteAgent.exe', 'Run-Agent.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $required))) { throw "Pacote incompleto: $required" }
}
if (-not (Test-Path -LiteralPath $CloudflaredPath)) { throw 'cloudflared.exe nao encontrado. Informe -CloudflaredPath.' }
if (Test-Path -LiteralPath $WebhookSeed) { $webhook = Plain (Get-Content -LiteralPath $WebhookSeed -Raw | ConvertTo-SecureString) }
else { $webhook = Plain (Read-Host 'Cole a URL do webhook Discord (entrada oculta)' -AsSecureString) }
if ($webhook -cnotmatch '^https://discord\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$') { throw 'Webhook Discord HTTPS invalido.' }
$agentToken = Read-Host 'Digite o MESMO token configurado no app Luna Remote (entrada oculta)' -AsSecureString
if ($agentToken.Length -eq 0) { throw 'O token nao pode ficar vazio.' }

# Install under protected Program Files. Do not run privileged executables from a writable checkout.
if (Get-Service $serviceName -ErrorAction SilentlyContinue) { Stop-Service $serviceName -ErrorAction Stop }
if (Get-ScheduledTask -TaskName 'LunaRemoteAgent' -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName 'LunaRemoteAgent' }
Set-PrivateDirectory $installRoot 'S-1-5-11' 'ReadAndExecute'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'service') -Destination $installRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'agent') -Destination $installRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Run-Agent.ps1') -Destination $installRoot -Force
Copy-Item -LiteralPath $CloudflaredPath -Destination (Join-Path $installRoot 'cloudflared.exe') -Force

Set-PrivateDirectory $dataRoot 'S-1-5-19' 'ReadAndExecute'
Set-PrivateDirectory (Join-Path $dataRoot 'state') 'S-1-5-19' 'Modify'
Set-PrivateDirectory $userRoot $userSid 'FullControl'
$bytes = [Text.Encoding]::UTF8.GetBytes($webhook)
try { $protected = [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'LocalMachine')) }
finally { [Array]::Clear($bytes, 0, $bytes.Length); $webhook = $null }
@{ Cloudflared = (Join-Path $installRoot 'cloudflared.exe'); WebhookProtected = $protected; StateDirectory = (Join-Path $dataRoot 'state'); Port = 8765 } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dataRoot 'tunnel.json') -Encoding UTF8
$agentToken | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $userRoot 'agent-token.dpapi') -Encoding ASCII

$serviceExe = Join-Path $installRoot 'service\LunaRemoteStartup.exe'
if (-not (Get-Service $serviceName -ErrorAction SilentlyContinue)) {
    & sc.exe create $serviceName binPath= ('"' + $serviceExe + '"') start= delayed-auto obj= 'NT AUTHORITY\LocalService' DisplayName= 'Luna Remote - Cloudflare e Discord'
} else {
    & sc.exe config $serviceName binPath= ('"' + $serviceExe + '"') start= delayed-auto obj= 'NT AUTHORITY\LocalService'
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao registrar servico.' }
& sc.exe failure $serviceName reset= 86400 actions= restart/10000/restart/30000/restart/60000
if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar recuperacao.' }
& sc.exe failureflag $serviceName 1
if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar recuperacao de falhas.' }

$runner = Join-Path $installRoot 'Run-Agent.ps1'
$agentExe = Join-Path $installRoot 'agent\LunaRemoteAgent.exe'
$tokenFile = Join-Path $userRoot 'agent-token.dpapi'
$taskArgs = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -AgentPath "{1}" -TokenPath "{2}"' -f $runner, $agentExe, $tokenFile
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $taskArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userAccount
$principal = New-ScheduledTaskPrincipal -UserId $userAccount -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'LunaRemoteAgent' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Agente Luna Remote na sessao interativa do usuario.' -Force | Out-Null

# Keep any existing reservation intact. Add one only when absent; no public firewall rule is created.
$reservation = & netsh.exe http show urlacl url=http://+:8765/remote/ 2>&1
if ($LASTEXITCODE -ne 0) {
    & netsh.exe http add urlacl url=http://+:8765/remote/ user=$userAccount
    if ($LASTEXITCODE -ne 0) { throw 'Falha na reserva HTTP. Verifique a porta 8765.' }
}
Start-ScheduledTask -TaskName 'LunaRemoteAgent'
Start-Service $serviceName
Write-Host "Instalado. Estado: $dataRoot\state\startup.log"
Write-Host 'O Discord recebera o dominio quando a Cloudflare registrar o tunel.'
Write-Host 'O desktop exige login no Windows; ligar apos queda de energia depende da BIOS/UEFI.'
