# Luna Remote 0.4.1

Cliente iOS SwiftUI + agente Windows 10/11. Protótipo de controle remoto; **não é equivalente ao Parsec e não promete zero latência**.

## Incluído

- Tela cheia, paisagem, trackpad, rolagem e arraste; teclado com envio Unicode + Enter em um único comando confirmado pelo host.
- Controle conectado ao iPhone encaminhado como Xbox 360 virtual no Windows. Exige ViGEmBus já instalado; o aplicativo não instala drivers. Um controle, sem vibração e sem transmissão de áudio nesta versão. ViGEm é um projeto encerrado pelo fornecedor.
- Captura da tela principal com GDI, **JPEG sobre WebSocket**, não H.264/HEVC. O perfil atual tem teto de 60 fps em 1280 pixels de largura; rede/decodificação lentas reduzem para 960 pixels e teto de 30 fps. FPS real depende do hardware, jogo e conexão.
- Protocolo 3 mantém no máximo dois quadros sem confirmação do cliente. Novos quadros são capturados somente quando há espaço; clientes antigos recebem JPEG sem cabeçalho.
- Decodificação assíncrona no iPhone; só a superfície de vídeo observa cada quadro. FPS, resolução e RTT são atualizados separadamente.
- Controle amostrado a 60 Hz, estados repetidos suprimidos com heartbeat de 250 ms; transições de botões são ordenadas. Comandos têm fila limitada e a sessão é encerrada se congestionar. Inputs mantidos são liberados pelo host após perda da conexão/heartbeat.
- RTT exibido é ida e volta de uma mensagem do app, **não** medição de latência entre apertar o botão e ver o resultado na tela.
- Serviço de túnel e notificação Discord: veja `windows/startup/README.md`.

## Executar o host

```powershell
$env:LUNA_TOKEN = "seu-token-forte-exclusivo"
dotnet run --project .\windows\LunaRemoteAgent
```

Porta 8765; reserva HTTP para `http://+:8765/remote/` deve permitir o usuário que executa o agente. No iPhone, use o domínio HTTPS do túnel ou IP/porta da rede local, junto ao mesmo token. O host escuta HTTP; HTTPS é terminado pelo túnel. Não exponha a porta HTTP diretamente à internet e não desative validação TLS. Token nunca deve entrar no Git ou em mensagens Discord.

É necessário atualizar **o agente Windows e o IPA** para usar o novo controle de fluxo. Reinicie o agente antigo após substituir o binário. Captura e entrada exigem sessão interativa desbloqueada; tela de login, desktop seguro/UAC e aplicativos elevados não são suportados por este agente comum.

## Build e testes

O workflow `Build iOS` gera os artifacts `LunaRemote-unsigned-ipa`, `LunaRemote-simulator` e `LunaRemote-Windows`. Executa testes do protocolo iOS no simulador, valida estrutura/metadados/arm64 do IPA e testa protocolo e supervisor Windows. O IPA é **sem assinatura** e precisa ser assinado para instalar; não é um build TestFlight.

```powershell
dotnet run --project .\windows\LunaRemoteAgent -- --self-test
dotnet run --project .\windows\LunaRemoteStartup -- --self-test
```

Para avaliar jogos, use o mesmo jogo/cena, compare FPS e RTT por alguns minutos, teste comandos curtos/contínuos e perda de rede. Ainda não há medição física de input-to-photon ou garantia de desempenho competitivo. JPEG consome mais banda que vídeo comprimido temporalmente; uma evolução para codificação por hardware e transporte apropriado precisa de implementação e testes próprios.

## Referências

- [Apple: preparação assíncrona de imagens](https://developer.apple.com/documentation/uikit/uiimage/preparefordisplay(completionhandler:))
- [Cloudflare: Quick Tunnels são temporários e sem SLA](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)
- [ViGEm: fim de vida](https://docs.nefarius.at/projects/ViGEm/End-of-Life/)
