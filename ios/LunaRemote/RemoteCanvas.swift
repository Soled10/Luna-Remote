import SwiftUI
import UIKit

// Only this leaf observes per-frame changes; session chrome updates at metrics cadence.
struct RemoteVideoView: View {
    @ObservedObject var frames: RemoteFrames
    let send: (RemoteCommand, String?) -> Void
    var body: some View {
        RemoteCanvas(
            frame: frames.image,
            cursor: (frames.cursorX, frames.cursorY, frames.cursorVisible),
            send: send
        )
    }
}

struct RemoteCanvas: UIViewRepresentable {
    var frame: UIImage?
    var cursor: (x: Double, y: Double, visible: Bool)
    var send: (RemoteCommand, String?) -> Void

    func makeUIView(context: Context) -> TouchSurface {
        let surface = TouchSurface()
        surface.send = send
        return surface
    }
    func updateUIView(_ view: TouchSurface, context: Context) {
        view.imageView.image = frame
        view.cursor = cursor
        view.send = send
    }

    final class TouchSurface: UIView {
        let imageView = UIImageView()
        private let cursorLayer = CAShapeLayer()
        var send: ((RemoteCommand, String?) -> Void)?
        var cursor: (x: Double, y: Double, visible: Bool) = (0.5, 0.5, false) {
            didSet { updateCursor() }
        }
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
            // Seta do cursor remoto: nítida em qualquer resolução, posicionada sem animação.
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: 1, y: 0))
            arrow.addLine(to: CGPoint(x: 1, y: 16))
            arrow.addLine(to: CGPoint(x: 5.5, y: 12))
            arrow.addLine(to: CGPoint(x: 8, y: 17.5))
            arrow.addLine(to: CGPoint(x: 10, y: 16.5))
            arrow.addLine(to: CGPoint(x: 7.5, y: 11.5))
            arrow.addLine(to: CGPoint(x: 12, y: 11.5))
            arrow.closeSubpath()
            cursorLayer.path = arrow
            cursorLayer.fillColor = UIColor.white.cgColor
            cursorLayer.strokeColor = UIColor.black.withAlphaComponent(0.85).cgColor
            cursorLayer.lineWidth = 1
            cursorLayer.shadowColor = UIColor.black.cgColor
            cursorLayer.shadowOpacity = 0.6
            cursorLayer.shadowRadius = 2
            cursorLayer.shadowOffset = CGSize(width: 1, height: 1)
            cursorLayer.isHidden = true
            layer.addSublayer(cursorLayer)
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
        override func layoutSubviews() {
            super.layoutSubviews()
            updateCursor()
        }
        private func updateCursor() {
            guard cursor.visible, let size = imageView.image?.size, size.width > 0, size.height > 0 else {
                cursorLayer.isHidden = true
                return
            }
            let bounds = imageView.bounds
            let s = min(bounds.width / size.width, bounds.height / size.height)
            let w = size.width * s, h = size.height * s
            let ox = bounds.minX + (bounds.width - w) / 2
            let oy = bounds.minY + (bounds.height - h) / 2
            cursorLayer.isHidden = false
            // Sem animação implícita: a posição acompanha o vídeo quadro a quadro.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.position = CGPoint(x: ox + CGFloat(cursor.x) * w, y: oy + CGFloat(cursor.y) * h)
            CATransaction.commit()
        }
        @objc private func click() { send?(RemoteCommand(type: "click", button: "left"), nil) }
        @objc private func doubleClick() { send?(RemoteCommand(type: "click", button: "double"), nil) }
        @objc private func rightClick() { send?(RemoteCommand(type: "click", button: "right"), nil) }
        private func delta(_ point: CGPoint) {
            fractional.x += point.x * 1.6; fractional.y += point.y * 1.6
            let x = Int(fractional.x), y = Int(fractional.y)
            fractional.x -= CGFloat(x); fractional.y -= CGFloat(y)
            // "move" coalesce: arrastos a 120 Hz viram um comando só na fila.
            if x != 0 || y != 0 { send?(RemoteCommand(type: "move", x: x, y: y), "move") }
        }
        @objc private func handlePointerPan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { fractional = .zero }
            delta(gesture.translation(in: self))
            gesture.setTranslation(.zero, in: self)
        }
        @objc private func scroll(_ gesture: UIPanGestureRecognizer) {
            let y = Int(gesture.translation(in: self).y * 5)
            if y != 0 {
                send?(RemoteCommand(type: "scroll", y: y), "scroll")
                gesture.setTranslation(.zero, in: self)
            }
        }
        @objc private func drag(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: self)
            switch gesture.state {
            case .began:
                longLocation = point
                send?(RemoteCommand(type: "button", button: "left", down: true), nil)
            case .changed:
                delta(CGPoint(x: point.x - longLocation.x, y: point.y - longLocation.y))
                longLocation = point
            case .ended, .cancelled, .failed:
                send?(RemoteCommand(type: "button", button: "left", down: false), nil)
            default: break
            }
        }
    }
}
