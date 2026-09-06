import UIKit
import Combine

@MainActor
final class RemoteSession: ObservableObject {
    @Published var frame: UIImage?
    @Published var status = "Desconectado"
    private var socket: URLSessionWebSocketTask?

    func connect(host: String, token: String, port: Int = 8765) {
        guard var components = URLComponents(string: "ws://\(host):\(port)/remote/") else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }
        socket = URLSession.shared.webSocketTask(with: url)
        socket?.resume(); status = "Conectando…"; receive()
    }
    func send(_ message: String) { socket?.send(.string(message)) { _ in } }
    private func receive() {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case .success(.data(let data)) = result { self.frame = UIImage(data: data); self.status = "Conectado" }
                if self.socket?.state == .running { self.receive() }
            }
        }
    }
}
