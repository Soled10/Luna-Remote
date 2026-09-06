# Gateway direto por domínio próprio

Este pacote prepara o caminho de menor latência disponível para o protocolo atual: iPhone → IP público do roteador → Caddy HTTPS/WSS → agente em `127.0.0.1:8765`. O app usa `https://jogar.seudominio.com`; a conversão para `wss://` é automática.

## Pré-requisitos que ficam pendentes até você escolher o domínio

1. Ter IP público e definir um subdomínio, por exemplo `jogar.seudominio.com`.
2. No Cloudflare, criar `A jogar` apontando ao IP público do roteador, marcado **DNS only** (nuvem cinza). Isso revela o IP público; é o preço de não rotear o jogo pela Cloudflare.
3. No roteador, encaminhar exclusivamente **TCP 80 e TCP 443** para este PC. Não encaminhe 8765. Se usar IPv6, configure firewall IPv6 equivalente.
4. Instalar `caddy.exe` de uma fonte oficial e fornecer o caminho local ao script. Caddy pede e renova certificado ACME público; certificado Origin CA da Cloudflare não funciona quando o iPhone se conecta diretamente.

Quando esses quatro itens estiverem prontos, em PowerShell como administrador:

```powershell
.\Configure-DirectGateway.ps1 -Domain jogar.seudominio.com -CaddyPath C:\caminho\caddy.exe -Start
```

O script valida o Caddyfile, cria o serviço `LunaRemoteGateway`, permite somente TCP 80/443 no firewall e inicia o serviço. Não cria DNS nem mexe no roteador. Caso o desafio de certificado falhe, pare o serviço, confirme DNS/port-forward e consulte o Event Viewer/log do Caddy antes de tentar novamente.

## Limite atual

O gateway fornece TLS válido e remove o percurso do Quick Tunnel, mas vídeo ainda é JPEG/WebSocket sobre TCP. Para um modo de jogo comparável a Parsec, o próximo projeto será Desktop Duplication + H.264 por hardware + WebRTC/UDP. Não abra UDP aleatoriamente até esse transporte existir.

- [Caddy: HTTPS automático](https://caddyserver.com/docs/automatic-https)
- [Caddy: reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Cloudflare: DNS-only expõe a origem](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/exposed-ip-address/)
