import Foundation
import Combine
import Security

struct SavedComputer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var address: String
    var quality = "auto"
    var fullscreen = true
}

protocol ComputerSecrets {
    func read(_ id: UUID) throws -> String?
    func write(_ token: String, id: UUID) throws
    func delete(_ id: UUID) throws
}

struct KeychainComputerSecrets: ComputerSecrets {
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.luna.remote.computers",
         kSecAttrAccount as String: id.uuidString]
    }
    func read(_ id: UUID) throws -> String? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data,
              let token = String(data: data, encoding: .utf8) else { throw ComputerError.keychain(status) }
        return token
    }
    func write(_ token: String, id: UUID) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(id).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ComputerError.keychain(status) }
    }
    func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ComputerError.keychain(status) }
    }
}

enum ComputerError: LocalizedError {
    case missingToken, missingName, corruptStorage, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .missingToken: return "Salve o token deste computador para conectar com um toque."
        case .missingName: return "Dê um nome ao computador."
        case .corruptStorage: return "Não foi possível ler os computadores salvos. Seus dados foram preservados."
        case .keychain: return "Não foi possível acessar o token protegido. Desbloqueie o iPhone e tente novamente."
        }
    }
}

@MainActor
final class ComputerStore: ObservableObject {
    @Published private(set) var computers: [SavedComputer] = []
    @Published private(set) var loadError: String?
    private let defaults: UserDefaults
    private let secrets: ComputerSecrets
    private let storageKey = "luna.savedComputers.v1"

    init(defaults: UserDefaults = .standard, secrets: ComputerSecrets = KeychainComputerSecrets()) {
        self.defaults = defaults; self.secrets = secrets
        if let data = defaults.data(forKey: storageKey) {
            do { computers = try JSONDecoder().decode([SavedComputer].self, from: data) }
            catch { loadError = ComputerError.corruptStorage.localizedDescription }
        } else if let previous = defaults.string(forKey: "remoteAddress"),
                  let address = try? Self.normalizedAddress(previous) {
            computers = [SavedComputer(name: "Meu PC", address: address)]
            defaults.set(try? JSONEncoder().encode(computers), forKey: storageKey)
            defaults.removeObject(forKey: "remoteAddress")
        }
    }

    static func normalizedAddress(_ value: String) throws -> String {
        let endpoint = try RemoteEndpoint.url(host: value, token: "")
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw RemoteEndpoint.EndpointError.invalid }
        parts.query = nil; parts.fragment = nil; parts.path = ""
        parts.scheme = parts.scheme == "wss" ? "https" : "http"
        guard let result = parts.url?.absoluteString else { throw RemoteEndpoint.EndpointError.invalid }
        return result
    }

    func token(for computer: SavedComputer) throws -> String {
        guard let token = try secrets.read(computer.id), !token.isEmpty else { throw ComputerError.missingToken }
        return token
    }

    func save(_ computer: SavedComputer, newToken: String) throws {
        guard loadError == nil else { throw ComputerError.corruptStorage }
        var validated = computer
        validated.name = computer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validated.name.isEmpty else { throw ComputerError.missingName }
        validated.address = try Self.normalizedAddress(computer.address)
        var updated = computers
        if let index = updated.firstIndex(where: { $0.id == validated.id }) { updated[index] = validated }
        else { updated.append(validated) }
        let encoded = try JSONEncoder().encode(updated)
        if newToken.isEmpty { _ = try token(for: validated) }
        else { try secrets.write(newToken, id: validated.id) }
        defaults.set(encoded, forKey: storageKey)
        computers = updated
    }

    func remove(_ computer: SavedComputer) throws {
        guard loadError == nil else { throw ComputerError.corruptStorage }
        let updated = computers.filter { $0.id != computer.id }
        let encoded = try JSONEncoder().encode(updated)
        try secrets.delete(computer.id)
        defaults.set(encoded, forKey: storageKey)
        computers = updated
    }
}
