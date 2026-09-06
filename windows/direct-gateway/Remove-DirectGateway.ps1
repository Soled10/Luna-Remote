#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
if (Get-Service LunaRemoteGateway -ErrorAction SilentlyContinue) {
    Stop-Service LunaRemoteGateway -ErrorAction SilentlyContinue
    & sc.exe delete LunaRemoteGateway
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível remover o gateway.' }
}
foreach ($port in 80,443) {
    Get-NetFirewallRule -DisplayName "Luna Remote HTTPS TCP $port" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}
Write-Host 'Gateway e regras TCP 80/443 removidos. DNS e redirecionamento do roteador não foram alterados.'
