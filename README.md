# Luna Remote 0.6.0

Cliente iOS SwiftUI + agente Windows 10/11. Protótipo de controle remoto; **não é equivalente ao Parsec e não promete zero latência**.

## Incluído

- Tela cheia, paisagem, trackpad, rolagem e arraste; teclado com envio Unicode + Enter em um único comando confirmado pelo host.
- Controle conectado ao iPhone encaminhado como Xbox 360 virtual no Windows. Exige ViGEmBus já instalado; o aplicativo não instala drivers. Um controle, sem vibração e sem transmissão de áudio nesta versão. ViGEm é um projeto encerrado pelo fornecedor.
- **Cursor real do Windows**: forma verdadeira (seta, I-beam, mão…) e posição enviadas ao iPhone, que mostra uma seta nítida sobre o vídeo em qualquer resolução. Clientes de protocolo 4 não recebem o cursor desenhado no quadro — o overlay é a única fonte, sem cursor duplo.
- Captura da tela principal, **JPEG diferencial sobre WebSocket**, não H.264/HEVC. Teto de **120 fps** (telas ProMotion) com espera de precisão sub-milissegundo; `LUNA_MAX_FPS` ajusta o teto (30–144). Modos pedidos pelo iPhone: Performance (120 fps/960px), Equilibrado (90 fps/1280px/q65), Qualidade (60 fps/1600px/q78) e Automático adaptativo (960p/q50 → 1280p/q68); rede lenta reduz para 960 pixels e 30 fps. FPS real depende do hardware, jogo e conexão.
- **Anti-travamento**: a tela é capturada direto na resolução de envio em 1 chamada ao driver; quadros idênticos ao anterior **não são recodificados nem enviados**; quando algo muda, viaja **só o retângulo sujo** (diff exato por blocos de 128px, 1 JPEG por quadro; >45% sujo vira quadro cheio), com reenvio cheio de segurança a cada 1,5 s; o cursor é ecoado ao iPhone imediatamente após cada movimento/clique, então o ponteiro parece ao vivo mesmo com vídeo lento; o modo automático começa leve (960p) e só sobe após ~2 s de rede boa, descendo só sob congestão sustentada — sem oscilação. O agente imprime `[vídeo] fps · KB/f · cap/enc/snd ms · modo` a cada 5 s no console. Com a tela parada, o contador de FPS do iPhone cai de propósito (não há nada novo para enviar); o cursor continua ao vivo.
- **A sessão sobrevive ao minimizar o app**: sem acks, o agente pausa o vídeo e mantém a conexão; ao voltar, o iPhone reconecta sozinho. Quedas de rede também reconectam com backoff.
- Protocolo 4 mantém no máximo dois quadros sem confirmação do cliente e envia só regiões sujas (clientes de protocolo 3 continuam recebendo quadros cheios). O iPhone confirma cada quadro na chegada (mede só a rede), decodifica em paralelo descartando quadros velhos e compõe as regiões num quadro retido; arrastos do trackpad e rolagem são coalescidos antes do envio.
- Decodificação assíncrona no iPhone; só a superfície de vídeo observa cada quadro. FPS, resolução e RTT são atualizados separadamente.
- Controle amostrado a 60 Hz, estados repetidos suprimidos com heartbeat de 250 ms; transições de botões são ordenadas. Comandos têm fila limitada; congestionamento agora tenta reconectar em vez de encerrar. Inputs mantidos são liberados pelo host após perda da conexão/heartbeat.
- RTT exibido é ida e volta de uma mensagem do app, **não** medição de latência entre apertar o botão e ver o resultado na tela.
- Serviço de túnel e notificação Discord: veja `windows/startup/README.md`.
- Gateway por domínio próprio, DNS-only e certificado automático: veja `windows/direct-gateway/README.md`. Ele está pronto, mas não é ativado até você definir o domínio e configurar o roteador.

## Executar o host

```powershell
$env:LUNA_TOKEN = "seu-token-forte-exclusivo"
$env:LUNA_MAX_FPS = "120"   # opcional: teto de fps, 30–144 (padrão 120)
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
