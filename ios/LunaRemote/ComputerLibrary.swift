import SwiftUI

struct ComputerLibrary: View {
    @ObservedObject var store: ComputerStore
    var add: () -> Void
    var edit: (SavedComputer) -> Void
    var connect: (SavedComputer) -> Void
    @State private var removal: SavedComputer?
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("LUNA", systemImage: "display").font(.headline).tracking(3).foregroundStyle(.mint)
                    Spacer()
                    Button(action: add) { Image(systemName: "plus").font(.title3).frame(width: 44, height: 44) }
                        .background(.white.opacity(0.07), in: Circle()).accessibilityLabel("Adicionar computador")
                        .accessibilityIdentifier("addComputer")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Seu PC.\nOnde você estiver.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("Escolha um computador e entre na sua sessão.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)

                if let message = store.loadError { Text(message).foregroundStyle(.orange) }
                if !error.isEmpty { Text(error).foregroundStyle(.orange).accessibilityIdentifier("libraryError") }

                if store.computers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "desktopcomputer").font(.system(size: 58, weight: .light)).foregroundStyle(.mint)
                        Text("Seu primeiro computador").font(.title3.bold())
                        Text("Salve o endereço e o token uma vez.\nNa próxima, basta tocar em Conectar.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button(action: add) {
                            Label("Adicionar computador", systemImage: "plus").fontWeight(.semibold)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                    }.padding(28).frame(maxWidth: .infinity)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 28))
                } else {
                    HStack {
                        Text("SEUS COMPUTADORES").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(store.computers.count)").font(.caption.monospacedDigit()).foregroundStyle(.mint)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(store.computers) { computer in card(computer) }
                    }
                }
                Label("Acesso salvo com segurança neste iPhone", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [Color.mint.opacity(0.08), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .confirmationDialog("Remover este computador e seu token salvo?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            Button("Remover computador", role: .destructive) {
                guard let computer = removal else { return }
                do { try store.remove(computer) } catch { self.error = error.localizedDescription }
                removal = nil
            }
            Button("Cancelar", role: .cancel) { removal = nil }
        }
    }

    private func card(_ computer: SavedComputer) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.mint)
                    .frame(width: 54, height: 54).background(Color.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                Spacer()
                Menu {
                    Button("Editar", systemImage: "pencil") { edit(computer) }
                    Button("Remover", systemImage: "trash", role: .destructive) { removal = computer }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Opções de \(computer.name)")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(computer.name).font(.title3.bold()).lineLimit(2)
                Text(computer.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(computer.fullscreen ? "Tela cheia ao conectar" : "Janela de sessão")
                    .font(.caption2).foregroundStyle(.mint)
            }
            Button { connect(computer) } label: {
                HStack { Text("Conectar").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.up.right") }
                    .padding(14).foregroundStyle(.black)
                    .background(Color.mint, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityLabel("Conectar a \(computer.name)")
        }.padding(20)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
    }
}
