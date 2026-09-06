import SwiftUI
import UIKit

struct RemoteView: View {
    @StateObject private var session = RemoteSession()
    @State private var showKeyboard = false
    private var connected: Bool { session.connected }
    @State private var showPairing = false
    @State private var host = ""
    @State private var token = ""
    @State private var lastGesture = "Toque na tela para controlar o Windows"

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.05, blue: 0.10), Color.black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Circle().fill(connected ? .green : .orange).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Luna Remote").font(.headline).foregroundStyle(.white)
                            Text(session.status)
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Button { showPairing = true } label: {
                            Image(systemName: connected ? "bolt.fill" : "plus")
                                .font(.headline)
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.12), in: Circle())
                        }
                        .foregroundStyle(.white)
                        Button { showKeyboard.toggle() } label: {
                            Image(systemName: "keyboard")
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("Mostrar teclado")
                    }
                    .padding()

                    GeometryReader { proxy in
                        RemoteCanvas(frame: session.frame) { gesture in
                            lastGesture = gesture
                            if gesture.hasPrefix("Mouse:") {
                                let values = gesture.split(separator: ":")
                                if values.count == 3 { session.send("mouse:move:\(values[1]):\(values[2])") }
                            } else if gesture == "Clique" { session.send("mouse:left") }
                            else if gesture == "Duplo clique" { session.send("mouse:double") }
                            else if gesture == "Botão direito" { session.send("mouse:right") }
                        }
                        .background(
                            ZStack {
                                Color(red: 0.08, green: 0.10, blue: 0.16)
                                Image(systemName: "display")
                                    .font(.system(size: 54))
                                    .foregroundStyle(.white.opacity(0.08))
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .overlay(alignment: .center) {
                            if !connected {
                                VStack(spacing: 10) {
                                    Image(systemName: "desktopcomputer")
                                        .font(.system(size: 38))
                                    Text("Conecte-se ao agente Windows")
                                        .font(.headline)
                                    Text("Toque no botão + para adicionar um PC")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }

                    HStack {
                        Image(systemName: "hand.tap.fill")
                        Text(lastGesture)
                        Spacer()
                        Text("⌘")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: Capsule())
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Luna Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showKeyboard) {
                RemoteKeyboardInput { text in
                    session.send("key:text:" + Data(text.utf8).base64EncodedString())
                }
                    .presentationDetents([.height(110)])
            }
            .sheet(isPresented: $showPairing) {
                VStack(spacing: 16) {
                    Text("Adicionar computador").font(.title2.bold())
                    TextField("IP do Windows (ex.: 192.168.0.10)", text: $host).textFieldStyle(.roundedBorder).keyboardType(.URL)
                    SecureField("Token do agente", text: $token).textFieldStyle(.roundedBorder)
                    Button("Conectar") {
                        session.connect(host: host, token: token); showPairing = false
                    }.buttonStyle(.borderedProminent).disabled(host.isEmpty || token.isEmpty)
                }.padding()
                    .presentationDetents([.height(250)])
            }
        }
    }
}

private struct RemoteCanvas: View {
    let frame: UIImage?
    let onGesture: (String) -> Void
    @State private var previous = CGSize.zero

    var body: some View {
        Group { if let frame { Image(uiImage: frame).resizable().scaledToFit() } else { Color.clear } }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let dx = value.translation.width - previous.width
                        let dy = value.translation.height - previous.height
                        previous = value.translation
                        onGesture("Mouse:\(Int(dx)):\(Int(dy))")
                    }
                    .onEnded { _ in
                        previous = .zero
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).exclusively(before: TapGesture(count: 1))
                    .onEnded { result in
                        switch result {
                        case .first: onGesture("Duplo clique")
                        case .second: onGesture("Clique")
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55).onEnded { _ in onGesture("Botão direito") }
            )
    }
}

private struct RemoteKeyboardInput: View {
    @State private var text = ""
    let onText: (String) -> Void
    var body: some View {
        TextField("Digite no Windows", text: $text)
            .textFieldStyle(.roundedBorder)
            .padding()
            .onSubmit {
                onText(text)
                text = ""
            }
            .submitLabel(.send)
    }
}
