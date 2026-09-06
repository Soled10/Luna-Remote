# Luna Remote iOS

O diretório contém o cliente SwiftUI e a configuração de CI. O arquivo `project.yml` é usado pelo XcodeGen para gerar o projeto Xcode real no runner macOS:

- Bundle ID: `com.luna.remote`
- Deployment target: iOS 17+
- Interface: SwiftUI

O cliente usa `URLSessionWebSocketTask` para receber os frames JPEG e enviar eventos de mouse/teclado ao agente Windows. O endereço do PC e o token são informados na tela de pareamento.

O workflow em `.github/workflows/ios.yml` compila o simulador e, quando os secrets de assinatura existirem, gera o IPA como artefato.
