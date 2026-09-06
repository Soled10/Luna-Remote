import XCTest
@testable import LunaRemote

final class LunaRemoteTests: XCTestCase {
    func testSecureTunnelPortAndToken() throws {
        let url = try RemoteEndpoint.url(host: "  https://sample.trycloudflare.com  ", token: "a&b #")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "wss")
        XCTAssertNil(parts.port)
        XCTAssertEqual(parts.path, "/remote/")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "token" }?.value, "a&b #")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "protocol" }?.value, "3")
    }
    func testLocalEndpointAndLoopback() throws {
        let local = try RemoteEndpoint.url(host: "192.168.100.7", token: "test")
        XCTAssertEqual(local.scheme, "ws")
        XCTAssertEqual(local.port, 8765)
        XCTAssertThrowsError(try RemoteEndpoint.url(host: "127.0.0.1", token: "test"))
        XCTAssertThrowsError(try RemoteEndpoint.url(host: "https://user:password@example.com", token: "test"))
        XCTAssertThrowsError(try RemoteEndpoint.url(host: "", token: "test"))
    }
    func testFrameHeaderAndLegacy() {
        let jpeg = Data([255, 216, 255, 217])
        let packet = VideoPacket(Data([76, 82, 48, 51, 42, 0, 0, 0]) + jpeg)
        XCTAssertEqual(packet.sequence, 42)
        XCTAssertEqual(packet.jpeg, jpeg)
        XCTAssertNil(VideoPacket(jpeg).sequence)
        XCTAssertEqual(VideoPacket(jpeg).jpeg, jpeg)
    }
    func testTextSubmitIsOneAtomicCommand() throws {
        let data = try JSONEncoder().encode(RemoteCommand(type: "text", text: "Olá 🎮", submit: true, id: "once"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "text")
        XCTAssertEqual(json["submit"] as? Bool, true)
        XCTAssertEqual(json["text"] as? String, "Olá 🎮")
    }
    func testQualityCommandEncoding() throws {
        let data = try JSONEncoder().encode(RemoteCommand(type: "quality", mode: "performance"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "quality")
        XCTAssertEqual(json["mode"] as? String, "performance")
    }
}
