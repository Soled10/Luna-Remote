import Foundation

enum RemoteEndpoint {
    static func url(host: String, token: String) throws -> URL {
        let input = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw EndpointError.invalid }
        var value = input
        if !input.contains("://") {
            let first = input.split(separator: ":").first ?? ""
            let isIP = first.split(separator: ".").count == 4 && first.allSatisfy { $0.isNumber || $0 == "." }
            value = (isIP ? "ws://" : "https://") + input
        }
        guard var c = URLComponents(string: value),
              let hostname = c.host, !hostname.isEmpty,
              c.user == nil, c.password == nil,
              let scheme = c.scheme?.lowercased(),
              ["https", "http", "ws", "wss"].contains(scheme) else { throw EndpointError.invalid }
        guard hostname.lowercased() != "localhost", !hostname.hasPrefix("127."), hostname != "::1" else {
            throw EndpointError.loopback
        }
        c.scheme = ["https", "wss"].contains(scheme) ? "wss" : "ws"
        if c.scheme == "ws", c.port == nil { c.port = 8765 }
        c.path = "/remote/"
        c.fragment = nil
        c.queryItems = [URLQueryItem(name: "token", value: token), URLQueryItem(name: "protocol", value: "4")]
        guard let url = c.url else { throw EndpointError.invalid }
        return url
    }
    enum EndpointError: LocalizedError {
        case invalid, loopback
        var errorDescription: String? {
            switch self {
            case .invalid: return "Informe o domínio HTTPS do túnel ou o IP do PC."
            case .loopback: return "Este endereço aponta para o próprio iPhone. Use o endereço do PC."
            }
        }
    }
}
