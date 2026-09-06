param([Parameter(Mandatory)][string]$AgentPath, [Parameter(Mandatory)][string]$TokenPath)
$ErrorActionPreference = 'Stop'
# This task MUST run in the user's interactive session, never as SYSTEM.
$taskMutex = New-Object Threading.Mutex($false, 'Local\LunaRemoteAgentSupervisor')
if (-not $taskMutex.WaitOne(0)) { exit 0 }
try {
    $secureToken = Get-Content -LiteralPath $TokenPath -Raw | ConvertTo-SecureString
    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    try { $env:LUNA_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer) }
    $env:LUNA_PORT = '8765'
    while ($true) {
        # An already running manual agent is left untouched. Wait until it exits.
        $probe = New-Object Net.Sockets.TcpClient
        $listening = $false
        try { $probe.Connect('127.0.0.1', 8765); $listening = $true } catch { } finally { $probe.Dispose() }
        if (-not $listening) { & $AgentPath }
        Start-Sleep -Seconds 5
    }
}
finally {
    Remove-Item Env:LUNA_TOKEN -ErrorAction SilentlyContinue
    $taskMutex.ReleaseMutex()
    $taskMutex.Dispose()
}
