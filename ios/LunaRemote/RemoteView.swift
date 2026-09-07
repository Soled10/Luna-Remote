import SwiftUI

struct RemoteView: View {
    @StateObject private var session = RemoteSession()
    @StateObject private var controller = GamepadRelay()
    @StateObject private var computers = ComputerStore()
    @State private var showingSession = false
    @State private var activeComputer: SavedComputer?
    @State private var connectionError = ""
    @State private var sheet: Panel?
    @State private var fullscreen = false
    @State private var hudVisible = true
    @AppStorage("lunaQuality") private var quality = "auto"
    @Environment(\.scenePhase) private var scenePhase
    enum Panel: Identifiable {
        case editor(SavedComputer?), keyboard, controller
        var id: String {
            switch self {
            case .editor(let computer): return computer?.id.uuidString ?? "new-computer"
            case .keyboard: return "keyboard"
            case .controller: return "controller"
            }
        }
    }

    private let background = Color(red: 0.035, green: 0.045, blue: 0.065)
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                background.ignoresSafeArea()
                if !showingSession {
                    ComputerLibrary(store: computers, add: { sheet = .editor(nil) }, edit: { sheet = .editor($0) }, connect: connect)
                } else {
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
                }
                if fullscreen {
                    VStack {
                        HStack {
                            if hudVisible {
                                Label(session.connected ? "\(session.fps) FPS · \(bitrateText) · \(session.roundTripMs) ms" : "Desconectado", systemImage: "waveform.path")
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
            case .editor(let computer): ComputerEditor(store: computers, computer: computer)
            case .keyboard: KeyboardSheet(session: session).presentationDetents([.medium, .large])
            case .controller: ControllerSheet(relay: controller, session: session)
            }
        }
        .alert("Não foi possível conectar", isPresented: Binding(get: { !connectionError.isEmpty }, set: { if !$0 { connectionError = "" } })) {
            Button("OK", role: .cancel) { connectionError = "" }
        } message: { Text(connectionError) }
        .onChange(of: session.connected) { _, connected in
            if connected { fullscreen = activeComputer?.fullscreen ?? false }
        }
        .task { controller.start(session: session); session.preferredQuality = quality }
        .onChange(of: quality) { _, mode in session.sendQuality(mode) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                controller.start(session: session)
                session.didBecomeActive() // reconecta sozinho se o sistema derrubou o socket
            } else {
                controller.stop()
                session.didEnterBackground() // minimizou? a sessão continua viva
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
            Text("0.6.0").font(.caption.monospaced()).foregroundStyle(.secondary)
            tool("chevron.left", "Voltar aos computadores e desconectar") {
                leaveSession()
            }.accessibilityIdentifier("connectionAction")
        }
    }

    private var stage: some View {
        ZStack {
            RemoteVideoView(frames: session.frames) { command, key in _ = session.send(command, coalesce: key) }
            if !session.connected {
                VStack(spacing: 20) {
                    Image(systemName: "desktopcomputer").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.mint)
                    Text(activeComputer?.name ?? "Seu computador")
                        .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text(session.status)
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if session.connecting { ProgressView().tint(.mint) }
                    else {
                        Button { if let computer = activeComputer { connect(computer) } } label: {
                            Label("Tentar novamente", systemImage: "arrow.clockwise")
                                .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(.black)
                    }
                    Button("Voltar aos computadores") { leaveSession() }
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(28)
            }
            if !fullscreen {
                VStack {
                    HStack {
                        Circle().fill(linkColor).frame(width: 6, height: 6)
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
        .shadow(color: session.connected && !fullscreen ? .mint.opacity(0.25) : .clear, radius: 24)
        .overlay {
            if !fullscreen {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(session.connected ? .mint.opacity(0.35) : .white.opacity(0.09), lineWidth: 1)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                metric("VÍDEO", session.connected ? "\(session.fps) fps" : "—")
                Spacer()
                metric("RESOLUÇÃO", session.resolution)
                Spacer()
                metric("RTT", session.roundTripMs > 0 ? "\(session.roundTripMs) ms" : "—")
                Spacer()
                metric("DADOS", session.connected ? bitrateText : "—")
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
            Menu {
                ForEach(["auto", "performance", "balanced", "quality"], id: \.self) { mode in
                    Button(qualityTitle(mode)) { quality = mode }
                }
            } label: {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Qualidade do vídeo: \(qualityTitle(quality))")
            .disabled(!session.connected)
            Spacer()
            tool(controller.detected ? "gamecontroller.fill" : "gamecontroller", "Configurar controle") { sheet = .controller }
                .accessibilityIdentifier("controllerAction")
            tool("arrow.up.left.and.arrow.down.right", "Tela cheia") { fullscreen = true; hudVisible = true }
        }
    }

    private var bitrateText: String {
        let kbps = session.bitrateKbps
        if kbps >= 1000 { return String(format: "%.1f Mb/s", kbps / 1000) }
        return "\(Int(kbps)) Kb/s"
    }
    private var linkColor: Color {
        guard session.connected else { return .gray }
        if session.roundTripMs <= 0 || session.roundTripMs < 50 { return .mint }
        if session.roundTripMs < 120 { return .orange }
        return .red
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(1.6).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
    private func connect(_ computer: SavedComputer) {
        do {
            let token = try computers.token(for: computer)
            activeComputer = computer
            quality = computer.quality
            session.preferredQuality = computer.quality
            showingSession = true; fullscreen = false; hudVisible = true
            session.connect(host: computer.address, token: token)
        } catch {
            connectionError = error.localizedDescription + " Abra Editar no cartão para atualizar o token."
        }
    }
    private func leaveSession() {
        controller.stop(); session.disconnect(); controller.start(session: session)
        fullscreen = false; showingSession = false; activeComputer = nil
    }
    private func qualityTitle(_ mode: String) -> String {
        let check = (mode == quality) ? " ✓" : ""
        switch mode {
        case "performance": return "Performance (120 fps)" + check
        case "balanced": return "Equilibrado (90 fps)" + check
        case "quality": return "Qualidade (60 fps)" + check
        default: return "Automático" + check
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
