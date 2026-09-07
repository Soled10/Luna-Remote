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
        XCTAssertEqual(parts.queryItems?.first { $0.name == "protocol" }?.value, "4")
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
    @MainActor
    func testRegionCompositing() throws {
        let comp = FrameCompositor()
        func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, w: Int, h: Int) -> UIImage {
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
                UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        func bytes(_ image: UIImage) throws -> Data {
            try XCTUnwrap(image.cgImage?.dataProvider?.data as Data?)
        }
        let full = try XCTUnwrap(comp.draw(tile: solid(1, 0, 0, w: 64, h: 64),
            region: .init(x: 0, y: 0, w: 64, h: 64, full: true, frame: 1), sequence: 1))
        XCTAssertEqual(full.size, CGSize(width: 64, height: 64))
        let patched = try XCTUnwrap(comp.draw(tile: solid(0, 0, 1, w: 16, h: 16),
            region: .init(x: 8, y: 8, w: 16, h: 16, full: false, frame: 2), sequence: 2))
        XCTAssertEqual(patched.size, CGSize(width: 64, height: 64))
        XCTAssertNotEqual(try bytes(full), try bytes(patched))
    }
}
