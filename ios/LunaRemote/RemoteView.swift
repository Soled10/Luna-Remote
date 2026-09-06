import SwiftUI

struct RemoteView: View {
    @StateObject private var session = RemoteSession()
    @StateObject private var controller = GamepadRelay()
    @State private var sheet: Panel?
    @State private var fullscreen = false
    @State private var hudVisible = true
    @Environment(\.scenePhase) private var scenePhase
    enum Panel: String, Identifiable { case connection, keyboard, controller; var id: String { rawValue } }

    private let background = Color(red: 0.035, green: 0.045, blue: 0.065)
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: 18) {
                    if !fullscreen { header }
                    stage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !fullscreen {
                        if !landscape { info }
                        toolbar
                    }
                }
                .padding(fullscreen ? 0 : (landscape ? 12 : 22))
                if fullscreen {
                    VStack {
                        HStack {
                            if hudVisible {
                                Label(session.connected ? "\(session.fps) FPS · \(session.roundTripMs) ms RTT" : "Desconectado", systemImage: "waveform.path")
                                    .font(.caption.monospacedDigit())
                                    .padding(10).background(.ultraThinMaterial, in: Capsule())
                                Spacer()
                                tool("keyboard", "Teclado") { sheet = .keyboard }.disabled(!session.connected)
                                tool("gamecontroller", "Controle") { sheet = .controller }
                                tool("arrow.down.right.and.arrow.up.left", "Sair da tela cheia") { fullscreen = false }
                                    .accessibilityIdentifier("exitFullscreen")
                            } else { Spacer() }
                            tool(hudVisible ? "ellipsis" : "ellipsis.circle.fill", "Mostrar ou ocultar controles") { hudVisible.toggle() }
                                .accessibilityIdentifier("toggleHUD")
                        }.padding(.horizontal, 18).padding(.top, 8)
                        Spacer()
                    }
                }
            }
            .ignoresSafeArea(edges: fullscreen ? .all : [])
        }
        .foregroundStyle(.white)
        .tint(.mint)
        .preferredColorScheme(.dark)
        .statusBarHidden(fullscreen)
        .persistentSystemOverlays(fullscreen ? .hidden : .automatic)
        .sheet(item: $sheet) { panel in
            switch panel {
            case .connection: ConnectionSheet(session: session)
            case .keyboard: KeyboardSheet(session: session).presentationDetents([.medium, .large])
            case .controller: ControllerSheet(relay: controller, session: session)
            }
        }
        .task { controller.start(session: session) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.start(session: session) }
            else {
                controller.stop()
                session.disconnect()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "display").font(.title2.weight(.semibold)).foregroundStyle(.mint)
                .frame(width: 48, height: 48).background(.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("LUNA").font(.title2.bold()).tracking(4)
                Text("REMOTE PLAY").font(.system(size: 9, weight: .semibold)).tracking(3).foregroundStyle(.secondary)
            }
            Spacer()
            Text("0.4.1").font(.caption.monospaced()).foregroundStyle(.secondary)
            tool(session.connected ? "power" : "plus", session.connected ? "Desconectar" : "Adicionar computador") {
                if session.connected || session.connecting { controller.stop(); session.disconnect(); controller.start(session: session) }
                else { sheet = .connection }
            }.accessibilityIdentifier("connectionAction")
        }
    }

    private var stage: some View {
        ZStack {
            RemoteVideoView(frames: session.frames) { command in session.send(command) }
            if !session.connected {
                VStack(spacing: 20) {
                    Image(systemName: "desktopcomputer").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.mint)
                    Text(session.connecting ? "Conectando…" : "Seu PC, na palma da mão.")
                        .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text(session.connecting ? "Aguardando a tela do Windows" : "Abra uma sessão para trabalhar ou jogar.\nO toque vira mouse. Seu controle vai junto.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if session.connecting { ProgressView().tint(.mint) }
                    else {
                        Button { sheet = .connection } label: {
                            Label("Conectar computador", systemImage: "arrow.up.right")
                                .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(.black)
                    }
                }.padding(28)
            }
            if !fullscreen {
                VStack {
                    HStack {
                        Circle().fill(session.connected ? Color.mint : Color.gray).frame(width: 6, height: 6)
                        Text(session.connected ? "AO VIVO" : "SUA SESSÃO").font(.system(size: 9, weight: .bold)).tracking(2)
                        Spacer()
                        tool("arrow.up.left.and.arrow.down.right", "Tela cheia") { fullscreen = true; hudVisible = true }
                            .accessibilityIdentifier("enterFullscreen")
                    }.padding(14)
                    Spacer()
                }
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: fullscreen ? 0 : 24))
        .overlay {
            if !fullscreen { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.09), lineWidth: 1) }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                metric("VÍDEO", session.connected ? "\(session.fps) fps" : "—")
                Spacer()
                metric("RESOLUÇÃO", session.resolution)
                Spacer()
                metric("REDE · RTT", session.roundTripMs > 0 ? "\(session.roundTripMs) ms" : "—")
            }
            Text(session.status).font(.caption).foregroundStyle(session.connected ? Color.mint : Color.secondary)
                .accessibilityIdentifier("sessionStatus")
            if session.connected && session.protocolVersion < 2 {
                Text("Atualize o agente Windows para 0.4.0 para usar os novos comandos.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(16).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            tool("keyboard", "Teclado remoto") { sheet = .keyboard }.disabled(!session.connected)
            tool("return", "Enter no Windows") { session.send(RemoteCommand(type: "key", button: "enter")) }.disabled(!session.connected)
            tool("computermouse", "Clique direito") { session.send(RemoteCommand(type: "click", button: "right")) }.disabled(!session.connected)
            Spacer()
            tool(controller.detected ? "gamecontroller.fill" : "gamecontroller", "Configurar controle") { sheet = .controller }
                .accessibilityIdentifier("controllerAction")
            tool("arrow.up.left.and.arrow.down.right", "Tela cheia") { fullscreen = true; hudVisible = true }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(1.6).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
    private func tool(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

#Preview { RemoteView() }
