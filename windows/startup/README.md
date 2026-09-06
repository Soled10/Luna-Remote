# Inicialização automática Luna Remote

## O que faz

- `LunaRemoteTunnel`: serviço Windows com início automático atrasado, executado como **LocalService**, cria um Quick Tunnel HTTPS para `http://127.0.0.1:8765`.
- Aguarda o registro do túnel e envia seu domínio ao Discord (`wait=true`, sem menções e sem token). Falhas de rede/429 têm novas tentativas; webhook revogado/403/404 exige reconfiguração e reinício do serviço.
- Se cloudflared encerrar ou não registrar em dois minutos, o supervisor tenta novamente com espera progressiva até 60 segundos. O Windows também reinicia o supervisor em caso de falha. Um job object encerra o processo filho ao encerrar o supervisor.
- `LunaRemoteAgent`: tarefa na entrada **desta conta de usuário**, supervisiona o agente de captura e o reinicia. Se já houver algo escutando na porta 8765, aguarda sem encerrar o processo existente.
- Webhook protegido com DPAPI de máquina + ACL para administradores/SYSTEM/LocalService; token protegido com DPAPI do usuário. Nada disso integra Git, IPA ou mensagem Discord.

## Instalar

No pacote pronto, abra PowerShell **como administrador, usando sua própria conta Windows**, e execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Install-Startup.ps1"
```

O instalador solicita o mesmo token que você usa no app (entrada oculta). Usa o webhook protegido por `Save-Webhook.ps1`, se existir; caso contrário solicita o webhook. A senha da conta Windows não é necessária. Se elevar com uma conta diferente, o agente será configurado para essa outra conta.

Requisito: cloudflared já instalado em `%USERPROFILE%\bin\cloudflared.exe`; outro caminho pode ser informado com `-CloudflaredPath`. O pacote inclui o runtime .NET para Windows x64. Reinstalar substitui os arquivos desta instalação e reconfigura sua tarefa/serviço; feche antes o agente instalado para evitar arquivos em uso.

O instalador não cria regra de entrada no firewall nem redireciona portas no roteador. Mantém reservas HTTP existentes. Não altera BIOS, suspensão, bloqueio de tela, login automático ou certificados TLS. Um túnel HTTPS expõe o endpoint à internet: mantenha um token forte, exclusivo e privado.

## Após queda de energia

1. A BIOS/UEFI precisa estar configurada com **Restore on AC Power Loss / AC Back = Power On**; o nome varia por placa. O serviço não consegue ligar um PC desligado.
2. Quando o Windows iniciar e a internet voltar, o serviço gera o domínio e o envia ao Discord.
3. **A captura exige uma sessão de usuário aberta e desktop desbloqueado.** Sem login, você pode receber um domínio válido, mas ainda não controlar a tela. Não há suporte à tela de login, UAC/desktop seguro ou desbloqueio remoto nesta versão. Login automático não é habilitado por razões de segurança.
4. Cole o domínio HTTPS recebido no campo de endereço do app. O token permanece igual. O app não consulta o Discord automaticamente.

## Verificar / parar / remover

```powershell
Get-Service LunaRemoteTunnel
Get-ScheduledTask -TaskName LunaRemoteAgent
Get-Content "$env:ProgramData\LunaRemote\state\startup.log" -Tail 30
Get-Content "$env:ProgramData\LunaRemote\state\current-url.txt"
Stop-Service LunaRemoteTunnel
# Remover somente a inicialização (preserva arquivos e segredos):
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Uninstall-Startup.ps1"
```

Logs e URL são acessíveis como administrador. O log rotaciona em ~1 MB, mantendo uma cópia. O arquivo `current-url.txt` existe apenas durante uma execução registrada (após desligamento abrupto pode permanecer obsoleto até o próximo início). Falha de entrega pode gerar duplicata se o Discord recebeu a mensagem mas a confirmação se perdeu. Quedas breves da internet são reconectadas pelo cloudflared; o domínio só muda quando o processo cria outro túnel.

## Desenvolvimento

```powershell
dotnet run --project .\windows\LunaRemoteStartup -- --self-test
.\windows\startup\Build-Package.ps1 -Destination C:\caminho\LunaRemote-Startup
```

Os testes locais usam um HTTP handler simulado: verificam domínio, rejeição de URLs falsas, DPAPI, payload sem menções, rate limiting, webhook revogado e cancelamento, sem enviar mensagens reais.

## Limites e documentação

Quick Tunnels são temporários, destinados a testes e sem SLA; não equivalem a um serviço de acesso remoto garantido. Um túnel nomeado é preferível para domínio estável/uso contínuo. O serviço não resolve falhas de energia, ausência de rede, atualização travada do Windows ou suspensão.

- [Cloudflare: Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)
- [Microsoft: serviços e sessões interativas](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services)
- [Microsoft: Worker como Windows Service](https://learn.microsoft.com/en-us/dotnet/core/extensions/windows-service)
- [Discord: executar webhook](https://docs.discord.com/developers/resources/webhook#execute-webhook)
