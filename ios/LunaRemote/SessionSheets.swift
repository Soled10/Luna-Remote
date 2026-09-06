import SwiftUI

struct ConnectionSheet: View {
    @ObservedObject var session: RemoteSession
    @AppStorage("remoteAddress") private var address = ""
    @State private var token = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Seu computador") {
                    TextField("https://seu-tunel.trycloudflare.com", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("addressField")
                    SecureField("Token do agente Windows", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("tokenField")
                }
                Section {
                    Text("Cole o endereço HTTPS mostrado pelo Cloudflare ou Tailscale. Se reiniciar um túnel temporário, atualize o endereço aqui.")
                    Text("O token fica apenas na memória desta tela.")
                }.font(.footnote).foregroundStyle(.secondary)
                Button {
                    session.connect(host: address, token: token)
                    dismiss()
                } label: { Label("Conectar ao PC", systemImage: "bolt.fill").frame(maxWidth: .infinity) }
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || token.isEmpty)
                .accessibilityIdentifier("connectButton")
            }
            .navigationTitle("Conectar computador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
    }
}

struct KeyboardSheet: View {
    @ObservedObject var session: RemoteSession
    @State private var text = ""
    @State private var pending: String?
    @State private var result = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Toque primeiro no campo desejado no Windows.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Mensagem ou comando", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.send)
                    .disabled(pending != nil)
                    .onSubmit { submit(enter: true) }
                    .accessibilityIdentifier("messageField")
                HStack {
                    Button("Só digitar") { submit(enter: false) }.buttonStyle(.bordered)
                    Spacer()
                    Button { submit(enter: true) } label: {
                        Label(pending == nil ? "Enviar ↵" : "Enviando…", systemImage: "paperplane.fill")
                    }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sendTextButton")
                }.disabled(!session.connected || pending != nil)
                Text(result.isEmpty ? "Enviar digita o texto e pressiona Enter no PC." : result)
                    .font(.caption).foregroundStyle(.secondary)
                if !session.inputError.isEmpty { Text(session.inputError).font(.caption).foregroundStyle(.orange) }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Teclado remoto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Concluir") { dismiss() } } }
        }
        .tint(.mint).preferredColorScheme(.dark)
        .onAppear { focused = true }
        .onChange(of: session.acknowledgedText) { _, id in
            if id == pending { pending = nil; text = ""; result = "Entregue ao Windows."; focused = true }
        }
        .onChange(of: session.inputError) { _, error in
            if !error.isEmpty { pending = nil }
        }
        .onChange(of: session.connected) { _, connected in
            if !connected { pending = nil; result = "Conexão encerrada. O texto foi preservado." }
        }
        .task(id: pending) {
            guard let id = pending else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, pending == id else { return }
            pending = nil
            result = "Sem confirmação. Confira no Windows antes de reenviar para evitar duplicação."
        }
    }
    private func submit(enter: Bool) {
        guard pending == nil else { return }
        let id = UUID().uuidString
        if session.submitText(text, enter: enter, id: id) { pending = id; result = "" }
    }
}

struct ControllerSheet: View {
    @ObservedObject var relay: GamepadRelay
    @ObservedObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("No iPhone") {
                    Label(relay.name, systemImage: "gamecontroller.fill")
                    Toggle("Encaminhar controle para o PC", isOn: $relay.enabled)
                    Text("Conecte um controle Bluetooth/USB compatível com iOS. O primeiro controle com perfil estendido será utilizado.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("No Windows") {
                    Label(session.gamepadStatus, systemImage: session.gamepadReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                    Text("Analógicos, gatilhos, direcional, ABXY, L/R, Start e Back são enviados para um Xbox 360 virtual.")
                    Text("O agente Windows 0.4.0 precisa do ViGEmBus já instalado. Vibração, áudio e múltiplos controles ainda não estão incluídos.")
                }.font(.subheadline)
            }
            .navigationTitle("Controle")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
        }.tint(.mint).preferredColorScheme(.dark)
    }
}
