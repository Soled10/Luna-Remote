import SwiftUI
import UIKit

// Only this leaf observes per-frame changes; session chrome updates at metrics cadence.
struct RemoteVideoView: View {
    @ObservedObject var frames: RemoteFrames
    let send: (RemoteCommand) -> Void
    var body: some View { RemoteCanvas(frame: frames.image, send: send) }
}

struct RemoteCanvas: UIViewRepresentable {
    var frame: UIImage?
    var send: (RemoteCommand) -> Void

    func makeUIView(context: Context) -> TouchSurface {
        let surface = TouchSurface()
        surface.send = send
        return surface
    }
    func updateUIView(_ view: TouchSurface, context: Context) {
        view.imageView.image = frame
        view.send = send
    }

    final class TouchSurface: UIView {
        let imageView = UIImageView()
        var send: ((RemoteCommand) -> Void)?
        private var fractional = CGPoint.zero
        private var longLocation = CGPoint.zero
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            let single = UITapGestureRecognizer(target: self, action: #selector(click))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleClick))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePointerPan(_:)))
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
            scroll.minimumNumberOfTouches = 2; scroll.maximumNumberOfTouches = 2
            let right = UITapGestureRecognizer(target: self, action: #selector(rightClick))
            right.numberOfTouchesRequired = 2
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(drag(_:)))
            hold.minimumPressDuration = 0.45
            single.require(toFail: hold)
            for gesture in [single, double, pan, scroll, right, hold] { addGestureRecognizer(gesture) }
            accessibilityIdentifier = "remoteCanvas"
            accessibilityLabel = "Trackpad remoto. Um dedo move o mouse; dois dedos rolam; toque longo arrasta."
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func click() { send?(RemoteCommand(type: "click", button: "left")) }
        @objc private func doubleClick() { send?(RemoteCommand(type: "click", button: "double")) }
        @objc private func rightClick() { send?(RemoteCommand(type: "click", button: "right")) }
        private func delta(_ point: CGPoint) {
            fractional.x += point.x * 1.6; fractional.y += point.y * 1.6
            let x = Int(fractional.x), y = Int(fractional.y)
            fractional.x -= CGFloat(x); fractional.y -= CGFloat(y)
            if x != 0 || y != 0 { send?(RemoteCommand(type: "move", x: x, y: y)) }
        }
        @objc private func handlePointerPan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { fractional = .zero }
            delta(gesture.translation(in: self))
            gesture.setTranslation(.zero, in: self)
        }
        @objc private func scroll(_ gesture: UIPanGestureRecognizer) {
            let y = Int(gesture.translation(in: self).y * 5)
            if y != 0 {
                send?(RemoteCommand(type: "scroll", y: y))
                gesture.setTranslation(.zero, in: self)
            }
        }
        @objc private func drag(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: self)
            switch gesture.state {
            case .began:
                longLocation = point
                send?(RemoteCommand(type: "button", button: "left", down: true))
            case .changed:
                delta(CGPoint(x: point.x - longLocation.x, y: point.y - longLocation.y))
                longLocation = point
            case .ended, .cancelled, .failed:
                send?(RemoteCommand(type: "button", button: "left", down: false))
            default: break
            }
        }
    }
}
