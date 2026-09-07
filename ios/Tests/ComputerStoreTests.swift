import XCTest
@testable import LunaRemote

@MainActor
final class ComputerStoreTests: XCTestCase {
    private final class Secrets: ComputerSecrets {
        var values: [UUID: String] = [:]
        var fail = false
        func read(_ id: UUID) throws -> String? { values[id] }
        func write(_ token: String, id: UUID) throws {
            if fail { throw ComputerError.keychain(-1) }
            values[id] = token
        }
        func delete(_ id: UUID) throws { values.removeValue(forKey: id) }
    }

    func testSaveReloadEditAndRemove() throws {
        let suite = "luna.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = Secrets()
        let store = ComputerStore(defaults: defaults, secrets: secrets)
        var pc = SavedComputer(name: "Gaming PC", address: "https://gaming.example.com?token=must-not-persist")
        try store.save(pc, newToken: "private-test-token")
        let restored = ComputerStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(restored.computers.count, 1)
        XCTAssertEqual(try restored.token(for: pc), "private-test-token")
        let saved = try XCTUnwrap(defaults.data(forKey: "luna.savedComputers.v1"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("token"))
        pc.address = "https://new-tunnel.example.com"; pc.name = "Meu PC"
        try restored.save(pc, newToken: "")
        XCTAssertEqual(try restored.token(for: pc), "private-test-token")
        XCTAssertEqual(restored.computers.first?.name, "Meu PC")
        try restored.remove(pc)
        XCTAssertTrue(restored.computers.isEmpty)
        XCTAssertNil(secrets.values[pc.id])
    }
    func testKeychainFailureDoesNotCreateProfile() throws {
        let suite = "luna.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = Secrets(); secrets.fail = true
        let store = ComputerStore(defaults: defaults, secrets: secrets)
        XCTAssertThrowsError(try store.save(SavedComputer(name: "PC", address: "https://test.example.com"), newToken: "test"))
        XCTAssertTrue(store.computers.isEmpty)
        XCTAssertNil(defaults.data(forKey: "luna.savedComputers.v1"))
    }
    func testPreviousAddressMigratesOnceWithoutPretendingToHaveToken() throws {
        let suite = "luna.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://previous.example.com", forKey: "remoteAddress")
        let secrets = Secrets()
        let store = ComputerStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(store.computers.count, 1)
        XCTAssertThrowsError(try store.token(for: XCTUnwrap(store.computers.first)))
        XCTAssertEqual(ComputerStore(defaults: defaults, secrets: secrets).computers, store.computers)
    }
    func testRealKeychainRoundTrip() throws {
        let keychain = KeychainComputerSecrets()
        let id = UUID()
        defer { try? keychain.delete(id) }
        try keychain.write("roundtrip-test", id: id)
        XCTAssertEqual(try keychain.read(id), "roundtrip-test")
        try keychain.write("updated-test", id: id)
        XCTAssertEqual(try keychain.read(id), "updated-test")
        try keychain.delete(id)
        XCTAssertNil(try keychain.read(id))
    }
}
