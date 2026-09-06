import UIKit
import Combine

@MainActor
final class RemoteSession: ObservableObject {
    @Published var frame: UIImage?
    @Published var status = "Desconectado"
    @Published var connected = false
    private var socket: URLSessionWebSocketTask?

    func connect(host: String, token: String, port: Int = 8765) {
        disconnect()
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.hasPrefix("127."), host != "localhost", host != "::1" else {
            status = "Use o IP do Windows. 127.0.0.1 aponta para o próprio iPhone."
            return
        }
        let scheme = host.hasPrefix("https://") ? "wss" : "ws"
        host = host.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let portPart = scheme == "wss" || host.contains(":") ? "" : ":\(port)"
        guard var components = URLComponents(string: "\(scheme)://\(host)\(portPart)/remote/") else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }
        socket = URLSession.shared.webSocketTask(with: url)
        socket?.resume(); status = "Conectando…"; receive()
    }
    func send(_ message: String) { socket?.send(.string(message)) { _ in } }
    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        frame = nil
        status = "Desconectado"
    }
    private func receive() {
        guard let current = socket else { return }
        current.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                guard self.socket === current else { return }
                switch result {
                case .success(.data(let data)):
                    self.frame = UIImage(data: data)
                    self.connected = self.frame != nil
                    self.status = "Conectado ao Windows"
                case .failure(let error):
                    self.disconnect()
                    self.status = "Falha: \(error.localizedDescription) Verifique IP, token, agente e Wi-Fi."
                    return
                default: break
                }
                self.receive()
            }
        }
    }
}
