import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var coordinator: LumeCoordinator
    @ObservedObject var model: StatusModel
    @ObservedObject var hud: HUDManager
    @ObservedObject var corners: OverlayManager
    @ObservedObject var player: MediaRemoteWrapper
    @ObservedObject private var keys = MediaKeyManager.shared
    @ObservedObject private var native = NativeHUDController.shared
    @State private var selected: Page = .capsule
    @State private var search = ""
    enum Page: String, CaseIterable, Identifiable {
        case capsule = "Capsule", indicators = "Indicadores", hud = "Volume e brilho", music = "Música", appearance = "Tela", permissions = "Permissões"
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .capsule: return .blue
            case .indicators: return .purple
            case .hud: return .pink
            case .music: return .red
            case .appearance: return .cyan
            case .permissions: return .blue
            }
        }
        var symbol: String {
            switch self {
            case .capsule: return "capsule"
            case .indicators: return "slider.horizontal.3"
            case .hud: return "speaker.wave.2"
            case .music: return "music.note"
            case .appearance: return "macwindow"
            case .permissions: return "hand.raised"
            }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar", text: $search).textFieldStyle(.plain)
                }
                .padding(9)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.12)))
                .padding(.top, 16)
                HStack(spacing: 10) {
                    Image(nsImage: NSImage(named: "EkoAppIcon") ?? NSImage(size: NSSize(width: 43, height: 43)))
                        .resizable().scaledToFit().frame(width: 43, height: 43)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Eko").font(.system(size: 19, weight: .semibold))
                        Text("Ajustes do aplicativo").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 19).padding(.horizontal, 7)
                ForEach(Page.allCases.filter { search.isEmpty || $0.rawValue.localizedStandardContains(search) }) { page in
                    Button { selected = page } label: {
                        HStack(spacing: 9) {
                            Image(systemName: page.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 27, height: 27)
                                .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                            Text(page.rawValue).font(.system(size: 13))
                        }
                            .foregroundStyle(selected == page ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(selected == page ? Color.blue : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                if !search.isEmpty && !Page.allCases.contains(where: { $0.rawValue.localizedStandardContains(search) }) {
                    Text("Nenhum resultado").font(.caption).foregroundStyle(.secondary).padding(10)
                }
                Spacer()
                Text("Eko 2.2").font(.caption).foregroundStyle(.tertiary).padding(.bottom, 12).padding(.leading, 7)
            }.padding(.horizontal, 12).frame(width: 220).background(.ultraThinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(selected.rawValue).font(.system(size: 20, weight: .semibold)).padding(.horizontal, 28).padding(.vertical, 20)
                Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detail
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(width: 900, height: 680).tint(.blue).toggleStyle(.switch)
    }
    @ViewBuilder private var detail: some View {
        switch selected {
        case .capsule:
            Text("Hora, conexão e bateria, discretamente no topo da tela.").foregroundStyle(.secondary)
            card("Visibilidade") {
                Toggle("Ativar Capsule", isOn: $coordinator.capsuleEnabled)
                Text("Some quando a barra de menus aparece ou ao passar o mouse. A Siri permanece clicável.").font(.caption).foregroundStyle(.secondary)
            }
            card("Dimensões e fundo") {
                HStack { Text("Tamanho"); Spacer(); Text("\(Int(model.scale * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $model.scale, in: 0.75...1.6, step: 0.05)
                HStack { Text("Opacidade do fundo"); Spacer(); Text("\(Int(model.backgroundOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $model.backgroundOpacity, in: 0...1, step: 0.01)
                Text("0% deixa o fundo transparente; 100% mantém todo o efeito de desfoque.").font(.caption).foregroundStyle(.secondary)
                Button("Restaurar tamanho e fundo") { model.scale = 1; model.backgroundOpacity = 0.92 }
            }
            card("Porcentagem da bateria") {
                Toggle("Mostrar porcentagem sempre", isOn: $model.showsPercentage)
                Toggle("Mostrar porcentagem ao carregar", isOn: $model.showsPercentageWhileCharging)
                Text("Com a primeira opção desativada, a porcentagem aparece ao conectar o carregador e some ao desconectar.").font(.caption).foregroundStyle(.secondary)
            }
        case .indicators:
            Text("Escolha os indicadores e arraste os itens para organizar sua ordem.").foregroundStyle(.secondary)
            ArrangementView(model: model).frame(maxWidth: .infinity)
            card("Música no Capsule") {
                Picker("Informações da faixa", selection: $model.musicMetadataSide) {
                    ForEach(MusicMetadataSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.elements.contains(.music))
                Text("Escolha de qual lado da capa aparecem o nome da música, o artista e o álbum.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            card("Fones de ouvido") {
                Text(model.headphoneName ?? "Nenhum fone conectado").font(.headline)
                Text("O Huawei FreeClip usa o seu vetor. Outros fones recebem o símbolo de fone de ouvido.").foregroundStyle(.secondary)
                Button("Associar saída de áudio atual ao FreeClip") { AudioDeviceManager.shared.associateCurrentDeviceAsFreeClip() }
                Button("Remover associação manual") { AudioDeviceManager.shared.clearFreeClipAssociation() }
            }
        case .hud:
            Text("Indicadores de volume, brilho da tela e iluminação do teclado.").foregroundStyle(.secondary)
            card("Controles") {
                Toggle("Ativar indicadores de volume e brilho", isOn: $coordinator.hudEnabled)
                HStack {
                    Button("Testar volume") { hud.showVolume(0.65) }
                    Button("Testar tela") { hud.showDisplayBrightness(0.65) }
                    Button("Testar teclado") { hud.showKeyboardBrightness(0.65) }
                }.disabled(!coordinator.hudEnabled)
                Text("Os testes só mostram o indicador; não alteram volume ou brilho.").font(.caption).foregroundStyle(.secondary)
            }
            card("Touch Bar") {
                Toggle("Usar indicadores do Eko na Touch Bar", isOn: Binding(get: { native.enabled }, set: { native.setEnabled($0) }))
                    .disabled(!coordinator.hudEnabled)
                Text(native.status).font(.caption).foregroundStyle(.secondary)
                Text("Controle experimental do indicador nativo, válido apenas nesta sessão.").font(.caption).foregroundStyle(.secondary)
            }
        case .music:
            Text("O player acompanha apenas seus aplicativos de música.").foregroundStyle(.secondary)
            card("Player") {
                Toggle("Player flutuante", isOn: Binding(
                    get: { player.enabled && player.floatingPlayerEnabled },
                    set: { value in
                        player.floatingPlayerEnabled = value
                        if value { player.enabled = true }
                    }
                ))
                Text("O player maior que aparece no topo da tela.").font(.caption).foregroundStyle(.secondary)
                Toggle("Player do Capsule", isOn: Binding(
                    get: { player.enabled && model.elements.contains(.music) },
                    set: { model.setElement(.music, enabled: $0) }
                ))
                Text("A capa compacta junto dos indicadores. Ative os dois para usar ambos.").font(.caption).foregroundStyle(.secondary)
                Text(player.status).foregroundStyle(.secondary)
                if !player.songTitle.isEmpty {
                    Text(player.songTitle).font(.headline)
                    Text(player.artistName).foregroundStyle(.secondary)
                    HStack {
                        Button("Anterior") { player.previousTrack() }
                        Button(player.isPlaying ? "Pausar" : "Reproduzir") { player.togglePlayPause() }
                        Button("Próxima") { player.nextTrack() }
                    }
                }
            }
            card("Aplicativos aceitos") {
                Label("Spotify", systemImage: "checkmark.circle.fill")
                Label("Deezer", systemImage: "checkmark.circle.fill")
                Label("Apple Music", systemImage: "checkmark.circle.fill")
                Text("Use os aplicativos instalados. Navegadores, chamadas e outras fontes de áudio não aparecem no player.").font(.caption).foregroundStyle(.secondary)
            }
        case .appearance:
            card("Cantos da tela") {
                Toggle("Arredondar cantos", isOn: $corners.isEnabled)
                HStack { Text("Raio dos cantos"); Spacer(); Text("\(Int(corners.radius)) pt").monospacedDigit() }
                Slider(value: $corners.radius, in: 0...120, step: 1).disabled(!corners.isEnabled)
            }
        case .permissions:
            card("Acessibilidade") {
                Label(keys.isAccessibilityGranted ? "Acesso concedido" : "Acesso necessário para as teclas", systemImage: keys.isAccessibilityGranted ? "checkmark.circle" : "keyboard")
                Text("Autorize o Eko para usar as teclas de volume e brilho com seus indicadores.").foregroundStyle(.secondary)
                Button("Autorizar Acessibilidade") { keys.checkAccessibility(prompt: true) }
                Button("Verificar novamente") { coordinator.updateHUD() }
                if let error = keys.eventTapError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            card("Bluetooth e Siri") {
                Text("O macOS pode pedir acesso ao Bluetooth para identificar fones. O botão da Siri abre a assistente instalada no Mac.").foregroundStyle(.secondary)
            }
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 14) { content() }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.13), lineWidth: 0.7))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
