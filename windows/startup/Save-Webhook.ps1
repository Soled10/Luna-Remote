param([Security.SecureString]$Webhook)
$ErrorActionPreference = 'Stop'
if (-not $Webhook) { $Webhook = Read-Host 'Webhook Discord (entrada oculta)' -AsSecureString }
$seedDirectory = Join-Path $env:LOCALAPPDATA 'LunaRemoteStartup'
New-Item -ItemType Directory -Force -Path $seedDirectory | Out-Null
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
foreach ($sid in @($currentSid, 'S-1-5-18', 'S-1-5-32-544')) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $seedDirectory -AclObject $acl
$Webhook | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $seedDirectory 'webhook.dpapi') -Encoding ASCII
Write-Host 'Webhook salvo com DPAPI para esta conta, fora do repositorio.'
