# Luna Remote 0.6.0

Nova biblioteca de computadores: adicione nome, endereço e token uma vez; salve e conecte pelo cartão. Editar preserva o token quando o campo fica vazio. Remover apaga o cartão e sua credencial do Keychain após confirmação.

Cada computador possui qualidade e preferência de tela cheia. O endereço anterior é migrado para um cartão chamado Meu PC; como o app antigo não guardava o token, é necessário informá-lo uma vez em Editar. O domínio próprio permanece opcional: endereços de túneis existentes continuam aceitos e podem ser editados.

Metadados ficam em UserDefaults; tokens ficam no Keychain com `WhenUnlockedThisDeviceOnly`. Não há sincronização do token com outros aparelhos. Ao assinar com outra identidade/equipe ou trocar bundle ID, o acesso ao Keychain anterior pode mudar e será necessário salvar o token novamente. O endereço persistido descarta query strings, evitando salvar um token colado na URL.

Testes incluem persistência entre instâncias, migração, edição sem substituir token, remoção, falha de armazenamento protegido, operações reais de Keychain e fluxo de interface salvar → reabrir → conectar sem novo formulário. Nenhum domínio ou certificado é configurado por esta atualização.

## Motor de vídeo diferencial (protocolo 4)

O agente passa a enviar só o retângulo sujo de cada quadro (diff exato por blocos de 128px, no máximo 1 JPEG por quadro; acima de 45% de mudança, quadro cheio), com reenvio cheio de segurança a cada 1,5 s. O iPhone compõe as regiões num quadro retido. O cursor não é mais desenhado no quadro: o overlay é a única fonte, sem cursor duplo. Qualidade JPEG maior nas faixas altas (até q78) sem gastar mais banda, telemetria de bitrate no app e linha de estatísticas `[vídeo]` a cada 5 s no console do agente. Clientes antigos (protocolo 3) continuam recebendo quadros cheios com cursor desenhado.
