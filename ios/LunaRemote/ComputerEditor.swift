import SwiftUI

struct ComputerEditor: View {
    @ObservedObject var store: ComputerStore
    let existing: SavedComputer?
    @State private var draft: SavedComputer
    @State private var token = ""
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss

    init(store: ComputerStore, computer: SavedComputer?) {
        self.store = store; existing = computer
        _draft = State(initialValue: computer ?? SavedComputer(name: "Meu PC", address: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Configure uma vez. Conecte com um toque.", systemImage: "bolt.circle.fill")
                        .foregroundStyle(.mint).font(.subheadline)
                }
                Section("Seu computador") {
                    TextField("Nome do computador", text: $draft.name).accessibilityIdentifier("computerName")
                    TextField("https://jogar.seudominio.com", text: $draft.address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("addressField")
                }
                Section {
                    SecureField(existing == nil ? "Token do agente Windows" : "Novo token (opcional)", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("tokenField")
                } header: { Text("Acesso protegido") } footer: {
                    Text(existing == nil ? "O token é salvo no Keychain deste iPhone." : "Deixe vazio para manter o token salvo. Se o túnel mudou, basta editar o endereço acima.")
                }
                Section("Ao conectar") {
                    Toggle("Abrir em tela cheia", isOn: $draft.fullscreen)
                    Picker("Qualidade", selection: $draft.quality) {
                        Text("Automática").tag("auto")
                        Text("Desempenho").tag("performance")
                        Text("Equilibrada").tag("balanced")
                        Text("Melhor imagem").tag("quality")
                    }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("saveError") } }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.035, green: 0.045, blue: 0.065))
            .navigationTitle(existing == nil ? "Adicionar computador" : "Editar computador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        do { try store.save(draft, newToken: token); token = ""; dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.address.isEmpty || (existing == nil && token.isEmpty))
                    .accessibilityIdentifier("saveComputer")
                }
            }
        }.tint(.mint).preferredColorScheme(.dark)
    }
}
