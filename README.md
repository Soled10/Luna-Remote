# Luna Remote

MVP de controle remoto Windows 10/11 a partir do iPhone.

## Arquitetura

- `ios/LunaRemote`: cliente SwiftUI.
- `windows/LunaRemoteAgent`: agente Windows.
- Transporte inicial: WebSocket sobre TLS.
- Vídeo: frames H.264/HEVC (implementação de produção prevista no próximo passo).
- Entrada: eventos de toque convertidos em mouse e teclado via `SendInput`.

## Teste local

1. Defina um token forte antes de executar: `$env:LUNA_TOKEN = "um-token-longo-e-aleatorio"`.
2. Execute o agente Windows somente na rede local confiável.
3. Descubra o IPv4 do PC com `ipconfig`.
4. No app, informe o IPv4 e o mesmo token.
5. Libere a porta TCP 8765 apenas na rede privada do Windows Firewall.

O transporte atual é um protótipo sem autenticação e sem TLS. Não faça port-forward dessa porta nem exponha o agente na internet.

## Distribuição

O build iOS precisa ser assinado com a conta Apple Developer e enviado ao App Store Connect por um runner macOS em nuvem. O TestFlight distribui o build depois do processamento da Apple.
