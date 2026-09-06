import UIKit
import Combine

@MainActor
final class RemoteSession: ObservableObject {
    let frames = RemoteFrames()
    @Published var status = "Pronto para conectar"
    @Published var connected = false
    @Published var connecting = false
    @Published var gamepadReady = false
    @Published var gamepadStatus = "Conecte ao PC para verificar"
    @Published var protocolVersion = 0
    @Published var fps = 0
    @Published var resolution = "—"
    @Published var acknowledgedText = ""
    @Published var inputError = ""
    @Published var roundTripMs = 0
    /// Qualidade pedida ao agente ("auto", "performance", "balanced", "quality").
    var preferredQuality = "auto"
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var inbox: Task<Void, Never>?
    private var outbox: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay = 1.0
    private var wantsConnection = false
    private var lastHost = ""
    private var lastToken = ""
    private var pendingPing: (id: String, started: TimeInterval)?
    private var queue: [(data: Data, key: String?)] = []
    private var counter = 0
    private var measuredAt = Date()
    private var lastShownSequence = 0
    private var generation = UUID()
    private var bgTask = UIBackgroundTaskIdentifier.invalid

    func connect(host: String, token: String) {
        wantsConnection = true
        lastHost = host
        lastToken = token
        reconnectDelay = 1.0
        reconnectTask?.cancel(); reconnectTask = nil
        startConnection()
    }

    private func startConnection() {
        tearDown()
        do {
            guard !lastToken.isEmpty else { throw SessionError.missingToken }
            let url = try RemoteEndpoint.url(host: lastHost, token: lastToken)
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            let sess = URLSession(configuration: config)
            session = sess
            let ws = sess.webSocketTask(with: url)
            ws.maximumMessageSize = 16 * 1024 * 1024
            socket = ws
            let id = generation
            status = "Conectando ao PC…"
            connecting = true
            measuredAt = Date(); counter = 0
            ws.resume()
            enqueue(RemoteCommand(type: "quality", mode: preferredQuality))
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard let self, self.generation == id else { return }
                    if let ping = self.pendingPing {
                        if ProcessInfo.processInfo.systemUptime - ping.started > 8 {
                            self.handleDrop("Conexão sem resposta. Reconectando…"); return
                        }
                    } else if self.connected && self.protocolVersion >= 3 {
                        let pingID = UUID().uuidString
                        self.pendingPing = (pingID, ProcessInfo.processInfo.systemUptime)
                        self.send(RemoteCommand(type: "ping", id: pingID))
                    }
                }
            }
            inbox = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        let message = try await ws.receive()
                        guard let self, self.generation == id else { return }
                        switch message {
                        case .data(let data):
                            self.receivedFrame(data, id: id)
                        case .string(let text): self.handle(text)
                        @unknown default: break
                        }
                    }
                } catch {
                    guard let self, self.generation == id, !Task.isCancelled else { return }
                    self.handleDrop("Falha na conexão: \(error.localizedDescription)")
                }
            }
        } catch { status = error.localizedDescription }
    }

    // O ack sai assim que o pacote chega (mede a rede, não o decode), e o decode
    // roda em paralelo: quadros lentos nunca seguram a chegada do próximo.
    private func receivedFrame(_ data: Data, id: UUID) {
        let packet = VideoPacket(data)
        // Ack direto na fila (sem exigir `connected`): o 1º quadro também libera
        // crédito no servidor, senão a janela de fluxo encolheria para sempre.
        if let sequence = packet.sequence { enqueue(RemoteCommand(type: "frameAck", x: sequence)) }
        let jpeg = packet.jpeg
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let encoded = UIImage(data: jpeg),
                  let image = await encoded.byPreparingForDisplay() else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == id else { return }
                if let sequence = packet.sequence {
                    guard sequence >= self.lastShownSequence else { return } // descarta decode velho
                    self.lastShownSequence = sequence
                }
                self.frames.image = image
                if !self.connected {
                    self.connected = true; self.connecting = false
                    self.status = "Sessão ativa"
                    self.reconnectDelay = 1.0
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                self.counter += 1
                let elapsed = Date().timeIntervalSince(self.measuredAt)
                if elapsed >= 1 {
                    self.fps = Int((Double(self.counter) / elapsed).rounded())
                    self.resolution = "\(Int(image.size.width)) × \(Int(image.size.height))"
                    self.counter = 0; self.measuredAt = Date()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let reply = try? JSONDecoder().decode(ServerReply.self, from: data) else { return }
        switch reply.type {
        case "hello":
            protocolVersion = reply.protocol ?? 0
            gamepadReady = reply.gamepad ?? false
            gamepadStatus = reply.gamepadStatus ?? "Controle indisponível"
        case "ack": acknowledgedText = reply.id ?? ""
        case "pong":
            if let ping = pendingPing, ping.id == reply.id {
                roundTripMs = Int(((ProcessInfo.processInfo.systemUptime - ping.started) * 1000).rounded())
                pendingPing = nil
            }
        case "cursor":
            frames.cursorX = reply.x ?? frames.cursorX
            frames.cursorY = reply.y ?? frames.cursorY
            frames.cursorVisible = reply.visible ?? true
        case "error": inputError = reply.message ?? "O Windows recusou o comando."
        default: break
        }
    }

    @discardableResult
    func send<T: Encodable>(_ command: T, coalesce: String? = nil) -> Bool {
        guard connected else { return false }
        return enqueue(command, coalesce: coalesce)
    }

    @discardableResult
    private func enqueue<T: Encodable>(_ command: T, coalesce: String? = nil) -> Bool {
        guard socket != nil, let data = try? JSONEncoder().encode(command) else { return false }
        // Only replace adjacent analog states: never reorder a button transition.
        if let key = coalesce, queue.last?.key == key {
            queue[queue.count - 1] = (data, key)
        } else {
            guard queue.count < 64 else {
                handleDrop("Rede congestionada: reconectando sem acumular comandos.")
                inputError = status
                return false
            }
            queue.append((data, coalesce))
        }
        drain()
        return true
    }

    func sendQuality(_ mode: String) {
        preferredQuality = mode
        enqueue(RemoteCommand(type: "quality", mode: mode))
    }

    func submitText(_ text: String, enter: Bool, id: String) -> Bool {
        inputError = ""
        guard protocolVersion >= 2 else { inputError = "Atualize e reinicie o agente Windows 0.4.0."; return false }
        return send(RemoteCommand(type: "text", text: text, submit: enter, id: id))
    }

    private func drain() {
        guard outbox == nil, let ws = socket else { return }
        let id = generation
        outbox = Task { [weak self] in
            guard let self else { return }
            do {
                while self.generation == id, !self.queue.isEmpty, !Task.isCancelled {
                    let next = self.queue.removeFirst()
                    try await ws.send(.string(String(decoding: next.data, as: UTF8.self)))
                }
                if self.generation == id { self.outbox = nil }
            } catch {
                if self.generation == id {
                    self.handleDrop("Envio interrompido: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Quedas e reconexão

    private func handleDrop(_ message: String) {
        let retry = wantsConnection
        tearDown()
        status = message
        if retry { scheduleReconnect() }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = reconnectDelay
        reconnectDelay = min(15, reconnectDelay * 2)
        status += " Tentando de novo em \(Int(delay))s…"
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                if self.wantsConnection && !self.connected { self.startConnection() }
            }
        }
    }

    // MARK: - Segundo plano: a sessão sobrevive ao minimizar

    func didEnterBackground() {
        endBgTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "LunaRemote") { [weak self] in
            Task { @MainActor [weak self] in self?.endBgTask() }
        }
        // O agente pausa o vídeo sozinho quando os acks param; o socket fica aberto.
    }

    func didBecomeActive() {
        endBgTask()
        pendingPing = nil // evita "sem resposta" fantasma de antes de minimizar
        if wantsConnection && !connected && !connecting {
            reconnectTask?.cancel(); reconnectTask = nil
            reconnectDelay = 1.0
            startConnection()
        }
    }

    private func endBgTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel(); reconnectTask = nil
        endBgTask()
        tearDown()
        status = "Desconectado"
    }

    private func tearDown() {
        generation = UUID()
        inbox?.cancel(); inbox = nil
        outbox?.cancel(); outbox = nil
        heartbeat?.cancel(); heartbeat = nil; pendingPing = nil; roundTripMs = 0
        queue.removeAll()
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        connected = false; connecting = false; gamepadReady = false
        protocolVersion = 0; frames.image = nil; frames.cursorVisible = false
        fps = 0; resolution = "—"; lastShownSequence = 0
        gamepadStatus = "Conecte ao PC para verificar"
        UIApplication.shared.isIdleTimerDisabled = false
    }

    enum SessionError: LocalizedError {
        case missingToken, invalidFrame
        var errorDescription: String? {
            switch self {
            case .missingToken: return "Informe o token do agente Windows."
            case .invalidFrame: return "Quadro de vídeo inválido. Reconecte ao agente atualizado."
            }
        }
    }
    private struct ServerReply: Decodable {
        let type: String
        let version: String?
        let `protocol`: Int?
        let gamepad: Bool?
        let gamepadStatus: String?
        let id: String?
        let message: String?
        let x: Double?
        let y: Double?
        let visible: Bool?
    }
}

@MainActor
final class RemoteFrames: ObservableObject {
    @Published var image: UIImage?
    @Published var cursorX = 0.5
    @Published var cursorY = 0.5
    @Published var cursorVisible = false
}

struct VideoPacket {
    let jpeg: Data
    let sequence: Int?
    init(_ data: Data) {
        let header = Array(data.prefix(8))
        if header.count == 8 && Array(header.prefix(4)) == [76, 82, 48, 51] {
            sequence = Int(UInt32(header[4]) | UInt32(header[5]) << 8 | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
            jpeg = Data(data.dropFirst(8))
        } else { jpeg = data; sequence = nil }
    }
}

struct RemoteCommand: Encodable {
    var type: String
    var text: String? = nil
    var submit: Bool? = nil
    var id: String? = nil
    var x: Int? = nil
    var y: Int? = nil
    var button: String? = nil
    var down: Bool? = nil
    var mode: String? = nil
}
