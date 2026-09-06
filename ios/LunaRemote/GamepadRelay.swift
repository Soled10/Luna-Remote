import GameController
import Combine
import Foundation

struct PadSnapshot: Encodable, Equatable {
    let type = "gamepad"
    var buttons: Int = 0
    var lx: Int = 0
    var ly: Int = 0
    var rx: Int = 0
    var ry: Int = 0
    var lt: Int = 0
    var rt: Int = 0
}

@MainActor
final class GamepadRelay: ObservableObject {
    @Published var name = "Nenhum controle conectado"
    @Published var detected = false
    @Published var enabled = true
    private var timer: Timer?
    private weak var session: RemoteSession?
    private var hadController = false
    private var lastState: PadSnapshot?
    private var lastSent: TimeInterval = 0

    func start(session: RemoteSession) {
        self.session = session
        guard timer == nil else { return }
        let poll = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
        tick()
    }
    func stop() {
        if hadController { session?.send(PadSnapshot(), coalesce: "gamepad") }
        hadController = false
        lastState = nil
        timer?.invalidate()
        timer = nil
    }
    private func tick() {
        let controller = GCController.controllers().first { $0.extendedGamepad != nil }
        let label = controller?.vendorName ?? "Nenhum controle conectado"
        if name != label { name = label }
        if detected != (controller != nil) { detected = controller != nil }
        guard enabled, let pad = controller?.extendedGamepad,
              session?.connected == true, session?.gamepadReady == true else {
            if hadController { session?.send(PadSnapshot()); hadController = false }
            lastState = nil
            return
        }
        hadController = true
        var state = PadSnapshot()
        let buttons: [(Bool, Int)] = [
            (pad.dpad.up.isPressed, 0x0001), (pad.dpad.down.isPressed, 0x0002),
            (pad.dpad.left.isPressed, 0x0004), (pad.dpad.right.isPressed, 0x0008),
            (pad.buttonMenu.isPressed, 0x0010), (pad.buttonOptions?.isPressed ?? false, 0x0020),
            (pad.leftThumbstickButton?.isPressed ?? false, 0x0040),
            (pad.rightThumbstickButton?.isPressed ?? false, 0x0080),
            (pad.leftShoulder.isPressed, 0x0100), (pad.rightShoulder.isPressed, 0x0200),
            (pad.buttonA.isPressed, 0x1000), (pad.buttonB.isPressed, 0x2000),
            (pad.buttonX.isPressed, 0x4000), (pad.buttonY.isPressed, 0x8000)
        ]
        for (pressed, bit) in buttons where pressed { state.buttons |= bit }
        func axis(_ value: Float) -> Int {
            let value = abs(value) < 0.08 ? 0 : value
            return Int((max(-1, min(1, value)) * 32767).rounded())
        }
        state.lx = axis(pad.leftThumbstick.xAxis.value)
        state.ly = axis(pad.leftThumbstick.yAxis.value)
        state.rx = axis(pad.rightThumbstick.xAxis.value)
        state.ry = axis(pad.rightThumbstick.yAxis.value)
        state.lt = Int((max(0, min(1, pad.leftTrigger.value)) * 255).rounded())
        state.rt = Int((max(0, min(1, pad.rightTrigger.value)) * 255).rounded())
        let now = ProcessInfo.processInfo.systemUptime
        guard state != lastState || now - lastSent >= 0.25 else { return }
        // Distinct button/trigger edges are ordered; only adjacent analog updates may merge.
        let key = "pad-\(state.buttons)-\(state.lt > 0)-\(state.rt > 0)"
        if session?.send(state, coalesce: key) == true { lastState = state; lastSent = now }
    }
}
