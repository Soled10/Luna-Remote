#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
if (Get-Service LunaRemoteTunnel -ErrorAction SilentlyContinue) {
    Stop-Service LunaRemoteTunnel
    & sc.exe delete LunaRemoteTunnel
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel remover o servico.' }
}
if (Get-ScheduledTask -TaskName LunaRemoteAgent -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName LunaRemoteAgent
    Unregister-ScheduledTask -TaskName LunaRemoteAgent -Confirm:$false
}
Write-Host 'Inicializacao automatica removida. Arquivos, segredos protegidos e reservas HTTP foram preservados.'
Write-Host 'Se o agente continuar aberto, encerre a sessao do Windows ou feche apenas esse agente.'
