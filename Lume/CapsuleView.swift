import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

struct CapsuleView: View {
    @ObservedObject var model: StatusModel
    @ObservedObject private var media = MediaRemoteWrapper.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var layout
    private var scale: CGFloat { CGFloat(model.scale) }
    private var visibleElements: [StatusElement] {
        model.elements.filter { element in
            if element == .headphones { return model.headphoneName != nil }
            if element == .music { return !media.songTitle.isEmpty }
            return true
        }
    }
    var body: some View {
        HStack(spacing: 10 * scale) {
            ForEach(visibleElements, id: \.self) { element in
                Group {
                switch element {
                case .siri:
                    Button(action: { model.activateSiri() }) {
                        Image(nsImage: SiriArtwork.image)
                            .resizable().interpolation(.high)
                            .frame(width: 19 * scale, height: 19 * scale)
                            .frame(width: 25 * scale, height: 30 * scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Abrir Siri")
                    .accessibilityLabel("Abrir Siri")
                    .background(HitAreaProbe { model.siriHitView = $0 })
                case .bluetooth:
                    BluetoothSymbol().stroke(style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round))
                        .frame(width: 9 * scale, height: 15 * scale)
                        .opacity(model.bluetoothOn ? 1 : 0.35)
                        .help(model.bluetoothOn ? "Bluetooth ativado" : "Bluetooth desativado")
                        .accessibilityLabel(model.bluetoothOn ? "Bluetooth ativado" : "Bluetooth desativado")
                case .headphones:
                    Group {
                        if model.freeClipConnected {
                            FreeClipIcon().frame(width: 20 * scale, height: 20 * scale)
                        } else {
                            Image(systemName: "headphones").font(.system(size: 15 * scale, weight: .medium))
                        }
                    }
                    .help(model.headphoneName ?? "Fones de ouvido")
                    .accessibilityLabel(model.headphoneName ?? "Fones de ouvido")
                case .music:
                    CapsuleMusicItem(media: media, scale: scale, metadataSide: model.musicMetadataSide)
                case .time:
                    AnimatedClock(text: model.timeText, scale: scale)
                case .wifi:
                    Image(systemName: model.isWiFiConnected ? "wifi" : "wifi.slash")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .opacity(model.isWiFiConnected ? 1 : 0.65)
                        .accessibilityLabel(model.isWiFiConnected ? "Wi-Fi conectado" : "Wi-Fi desconectado")
                case .battery:
                    if model.hasBattery {
                        HStack(spacing: 5 * scale) {
                            BatteryIndicator(level: model.batteryLevel, lowPower: model.isLowPowerMode, charging: model.isCharging, scale: scale)
                            if model.effectiveShowsPercentage {
                                Text("\(Int((model.batteryLevel * 100).rounded()))%")
                                    .font(.system(size: 12 * scale, weight: .medium))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                }
                .matchedGeometryEffect(id: element, in: layout)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: 14).combined(with: .opacity), removal: .scale(scale: 0.85).combined(with: .opacity)))
                .offset(x: model.isPresented || reduceMotion ? 0 : 10)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.46, dampingFraction: 0.78).delay(Double(visibleElements.firstIndex(of: element) ?? 0) * 0.025), value: model.isPresented)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.46, dampingFraction: 0.78), value: visibleElements)
        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.78), value: model.effectiveShowsPercentage)
        .foregroundStyle(.primary)
        .padding(.horizontal, 12 * scale)
        .frame(height: 36 * scale)
        .background {
            SoftMaterial()
                .opacity(model.backgroundOpacity)
                .mask { RoundedRectangle(cornerRadius: 15 * scale).padding(4 * scale).blur(radius: 5 * scale) }
        }
        .fixedSize()
        .background(HitAreaProbe { model.contentHitView = $0 })
        .blur(radius: model.isPresented || reduceMotion ? 0 : 6)
        .opacity(model.isPresented ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28), value: model.isPresented)
        .padding(.top, 4)
        .frame(width: 560, height: 68, alignment: .topTrailing)
        .coordinateSpace(name: "overlayPanel")
        .accessibilityElement(children: .contain)
    }
}

private struct CapsuleMusicItem: View {
    @ObservedObject var media: MediaRemoteWrapper
    let scale: CGFloat
    let metadataSide: MusicMetadataSide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedArtwork: NSImage?
    @State private var flipAngle: Double = 0
    @State private var artworkScale: CGFloat = 1
    @State private var showsMetadata = false
    @State private var revealGeneration: UInt64 = 0
    @State private var visualPlaying = true
    @State private var visualIdentity = ""
    @State private var visualTitle = ""
    @State private var visualSubtitle = ""
    @State private var flipping = false

    private var trackIdentity: String {
        "\(media.track.pid)|\(media.songTitle)|\(media.artistName)"
    }
    private var metadataWidth: CGFloat {
        let title = (visualTitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5 * scale, weight: .semibold)]).width
        let subtitle = (visualSubtitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9.5 * scale, weight: .medium)]).width
        return min(175 * scale, max(40 * scale, ceil(max(title, subtitle))))
    }

    var body: some View {
        HStack(spacing: 0) {
            if metadataSide == .left { metadata }
            artwork
                .frame(width: 25 * scale, height: 25 * scale)
                .compositingGroup()
                .blur(radius: visualPlaying ? 0 : 4 * scale)
                .overlay {
                        ZStack {
                            Color.black.opacity(0.24)
                            Image(systemName: "pause.fill")
                                .font(.system(size: 11 * scale, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .opacity(visualPlaying ? 0 : 1)
                        .scaleEffect(visualPlaying ? 0.88 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous))
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.42), value: visualPlaying)
                .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                .scaleEffect(artworkScale)
                .shadow(color: .black.opacity(0.16), radius: 1.5 * scale, y: 0.7 * scale)
            if metadataSide == .right { metadata }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28), value: showsMetadata)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28), value: metadataSide)
        .help("\(media.songTitle) — \(media.artistName)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(media.isPlaying ? "Tocando" : "Pausado") \(media.songTitle), \(media.artistName)")
        .onAppear {
            displayedArtwork = media.albumArtwork
            visualPlaying = media.isPlaying
            visualIdentity = trackIdentity
            visualTitle = media.songTitle
            visualSubtitle = metadataSubtitle
        }
        .onReceive(media.$track.debounce(for: .milliseconds(90), scheduler: RunLoop.main)) { _ in
            guard !media.songTitle.isEmpty else { return }
            visualPlaying = media.isPlaying
            if visualIdentity != trackIdentity {
                visualIdentity = trackIdentity
                flipToCurrentTrack()
            } else if !flipping, let image = media.albumArtwork {
                displayedArtwork = image
            }
            if !visualPlaying {
                withAnimation(.easeInOut(duration: 0.34)) { showsMetadata = false }
            }
        }
        .onChange(of: metadataSide) { _ in
            flipAngle = 0
            artworkScale = 1
            displayedArtwork = media.albumArtwork
        }
        .onDisappear { invalidateReveal() }
    }

    @ViewBuilder private var metadata: some View {
            VStack(alignment: metadataSide == .left ? .trailing : .leading, spacing: 0) {
                Text(visualTitle)
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(visualSubtitle)
                    .font(.system(size: 9.5 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(width: metadataWidth, alignment: metadataSide == .left ? .trailing : .leading)
            .blur(radius: showsMetadata || reduceMotion ? 0 : 6)
            .opacity(showsMetadata ? 1 : 0)
            .padding(metadataSide == .left ? .trailing : .leading, 7 * scale)
            .frame(width: showsMetadata ? metadataWidth + 7 * scale : 0, alignment: metadataSide == .left ? .trailing : .leading)
            .clipped()
            .accessibilityHidden(!showsMetadata)
    }

    private var metadataSubtitle: String {
        let artist = media.artistName.isEmpty ? media.track.source : media.artistName
        return media.albumName.isEmpty ? artist : "\(artist) · \(media.albumName)"
    }

    @ViewBuilder private var artwork: some View {
        if let displayedArtwork {
            Image(nsImage: displayedArtwork)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                Color.primary.opacity(0.10)
                Image(systemName: "music.note")
                    .font(.system(size: 12 * scale, weight: .semibold))
            }
        }
    }

    private func flipToCurrentTrack() {
        visualTitle = media.songTitle
        visualSubtitle = metadataSubtitle
        guard media.isPlaying, !media.songTitle.isEmpty else {
            invalidateReveal()
            displayedArtwork = media.albumArtwork
            return
        }
        revealGeneration &+= 1
        let generation = revealGeneration
        showsMetadata = false
        flipping = true
        guard !reduceMotion else {
            displayedArtwork = media.albumArtwork
            flipping = false
            presentMetadata(after: 0.05)
            return
        }
        let direction = metadataSide == .left ? -1.0 : 1.0
        withAnimation(.easeIn(duration: 0.18)) {
            flipAngle = 90 * direction
            artworkScale = 0.82
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard revealGeneration == generation else { return }
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) {
                if let image = media.albumArtwork { displayedArtwork = image }
                flipAngle = -90 * direction
            }
            DispatchQueue.main.async {
                guard revealGeneration == generation else { return }
                withAnimation(.easeInOut(duration: 0.30)) {
                    flipAngle = 0
                    artworkScale = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    guard revealGeneration == generation else { return }
                    flipping = false
                    if let image = media.albumArtwork { displayedArtwork = image }
                    presentMetadata(after: 0.05)
                }
            }
        }
    }

    private func presentMetadata(after delay: TimeInterval) {
        revealGeneration &+= 1
        let generation = revealGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard revealGeneration == generation, media.isPlaying, !media.songTitle.isEmpty else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28)) { showsMetadata = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                guard revealGeneration == generation else { return }
                withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28)) { showsMetadata = false }
            }
        }
    }

    private func invalidateReveal() {
        revealGeneration &+= 1
        flipping = false
        showsMetadata = false
        flipAngle = 0
        artworkScale = 1
    }
}

private struct MusicMetadataBlur: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let offset: CGFloat
    let scale: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity).offset(x: offset).scaleEffect(scale)
    }
}

private struct DigitBlur: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

private struct AnimatedClock: View {
    let text: String
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                ZStack {
                    Text(String(character))
                        .id(character)
                        .transition(reduceMotion ? .opacity : .modifier(
                            active: DigitBlur(radius: 4, opacity: 0),
                            identity: DigitBlur(radius: 0, opacity: 1)
                        ))
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.38), value: character)
            }
        }
        .font(.system(size: 13 * scale, weight: .semibold))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct BatteryIndicator: View {
    let level: Double
    let lowPower: Bool
    let charging: Bool
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme
    private var fill: Color {
        if lowPower { return .yellow }
        if charging { return .green }
        if level <= 0.2 { return .red }
        return .primary
    }
    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "battery.0")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary.opacity(0.65))
            RoundedRectangle(cornerRadius: 1.5 * scale)
                .fill(fill)
                .frame(width: 20.5 * scale * min(1, max(0, level)), height: 8 * scale)
                .padding(.leading, 2 * scale)
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(.primary)
                    .shadow(color: fill, radius: 0.8)
                    .frame(width: 24 * scale)
            }
        }
        .frame(width: 27 * scale, height: 13 * scale)
        .accessibilityLabel(charging ? "Bateria carregando" : "Bateria")
        .accessibilityValue("\(Int((level * 100).rounded())) por cento")
    }
}

private struct SoftMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ArrangementView: View {
    @ObservedObject var model: StatusModel
    @State private var dragged: StatusElement?
    var body: some View {
        VStack(spacing: 20) {
            Text("Arraste os itens para mudar a posição.")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(model.elements, id: \.self) { element in
                    VStack(spacing: 7) {
                        arrangementIcon(element).frame(width: 25, height: 25)
                        Text(element.title).font(.system(size: 10, weight: .medium))
                    }
                        .frame(width: 58, height: 64)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .help("Arrastar \(element.title)")
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .onDrag {
                            dragged = element
                            return NSItemProvider(object: element.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: IndicatorDrop(target: element, model: model, dragged: $dragged))
                        .accessibilityAction(named: "Mover para a esquerda") { move(element, offset: -1) }
                        .accessibilityAction(named: "Mover para a direita") { move(element, offset: 1) }
                }
            }
            HStack(spacing: 18) {
                ForEach([StatusElement.siri, .bluetooth, .headphones, .music], id: \.self) { element in
                    Toggle(element.title, isOn: Binding(
                        get: { model.elements.contains(element) },
                        set: { model.setElement(element, enabled: $0) }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            Text("Fones aparecem quando conectados. Música mantém a capa com indicação de pausa. Clique no ícone da Siri para falar com ela.")
                .font(.caption).foregroundStyle(.secondary)
            Text("As alterações são salvas automaticamente.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }
    private func move(_ element: StatusElement, offset: Int) {
        guard let index = model.elements.firstIndex(of: element), model.elements.indices.contains(index + offset) else { return }
        model.elements.swapAt(index, index + offset)
    }
    @ViewBuilder private func arrangementIcon(_ element: StatusElement) -> some View {
        switch element {
        case .siri:
            Image(nsImage: SiriArtwork.image).resizable().scaledToFit()
        case .bluetooth:
            BluetoothSymbol().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 11, height: 20)
        case .headphones:
            if model.freeClipConnected { FreeClipIcon() }
            else { Image(systemName: "headphones").font(.system(size: 20)) }
        case .time: Image(systemName: "clock").font(.system(size: 20))
        case .wifi: Image(systemName: "wifi").font(.system(size: 20))
        case .battery: Image(systemName: "battery.100").font(.system(size: 20))
        case .music: Image(systemName: "music.note").font(.system(size: 20))
        }
    }
}

private struct IndicatorDrop: DropDelegate {
    let target: StatusElement
    let model: StatusModel
    @Binding var dragged: StatusElement?
    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let source = model.elements.firstIndex(of: dragged),
              let destination = model.elements.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            model.elements.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}

private enum SiriArtwork {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "SiriTahoe", withExtension: "png"), let image = NSImage(contentsOf: url) { return image }
        return NSWorkspace.shared.icon(forFile: "/System/Applications/Siri.app")
    }()
}

private struct HitAreaProbe: NSViewRepresentable {
    let resolve: (NSView) -> Void
    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView {
        let view = Probe()
        resolve(view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { resolve(nsView) }
}

private struct BluetoothSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.height * 0.25))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.75))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.25))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.75))
        return p
    }
}

struct FreeClipIcon: View {
    var body: some View {
        Rectangle().fill(.primary).mask {
            Canvas { context, size in
                context.drawLayer { layer in
                    for part in FreeClipSymbol.parts(in: CGRect(origin: .zero, size: size)) {
                        layer.blendMode = part.cutout ? .destinationOut : .normal
                        layer.fill(part.path, with: .color(.white))
                    }
                }
            }
        }
    }
}

enum FreeClipSymbol {
    struct Part { let path: Path; let cutout: Bool }
    static func parts(in rect: CGRect) -> [Part] {
        // Contours follow the supplied 270 x 286 reference, without an added outline.
        var rear = Path()
        rear.move(to: CGPoint(x: 151, y: 3))
        rear.addCurve(to: CGPoint(x: 186, y: 25), control1: CGPoint(x: 166, y: 2), control2: CGPoint(x: 178, y: 13))
        rear.addCurve(to: CGPoint(x: 247, y: 33), control1: CGPoint(x: 208, y: 17), control2: CGPoint(x: 233, y: 21))
        rear.addCurve(to: CGPoint(x: 266, y: 105), control1: CGPoint(x: 270, y: 52), control2: CGPoint(x: 277, y: 81))
        rear.addCurve(to: CGPoint(x: 262, y: 145), control1: CGPoint(x: 277, y: 119), control2: CGPoint(x: 270, y: 134))
        rear.addCurve(to: CGPoint(x: 190, y: 178), control1: CGPoint(x: 247, y: 167), control2: CGPoint(x: 210, y: 180))
        rear.addCurve(to: CGPoint(x: 159, y: 153), control1: CGPoint(x: 171, y: 177), control2: CGPoint(x: 160, y: 168))
        rear.addCurve(to: CGPoint(x: 177, y: 115), control1: CGPoint(x: 151, y: 134), control2: CGPoint(x: 161, y: 124))
        rear.addCurve(to: CGPoint(x: 247, y: 93), control1: CGPoint(x: 202, y: 100), control2: CGPoint(x: 230, y: 85))
        rear.addCurve(to: CGPoint(x: 237, y: 49), control1: CGPoint(x: 254, y: 77), control2: CGPoint(x: 248, y: 59))
        rear.addCurve(to: CGPoint(x: 194, y: 44), control1: CGPoint(x: 226, y: 39), control2: CGPoint(x: 209, y: 39))
        rear.addCurve(to: CGPoint(x: 174, y: 87), control1: CGPoint(x: 198, y: 61), control2: CGPoint(x: 187, y: 81))
        rear.addCurve(to: CGPoint(x: 117, y: 77), control1: CGPoint(x: 157, y: 98), control2: CGPoint(x: 132, y: 90))
        rear.addCurve(to: CGPoint(x: 113, y: 24), control1: CGPoint(x: 106, y: 61), control2: CGPoint(x: 105, y: 40))
        rear.addCurve(to: CGPoint(x: 151, y: 3), control1: CGPoint(x: 121, y: 10), control2: CGPoint(x: 137, y: 3))
        rear.closeSubpath()

        var front = Path()
        front.move(to: CGPoint(x: 77, y: 99))
        front.addCurve(to: CGPoint(x: 119, y: 132), control1: CGPoint(x: 99, y: 97), control2: CGPoint(x: 119, y: 111))
        front.addCurve(to: CGPoint(x: 99, y: 170), control1: CGPoint(x: 121, y: 148), control2: CGPoint(x: 111, y: 162))
        front.addCurve(to: CGPoint(x: 45, y: 174), control1: CGPoint(x: 81, y: 184), control2: CGPoint(x: 61, y: 184))
        front.addCurve(to: CGPoint(x: 32, y: 161), control1: CGPoint(x: 39, y: 171), control2: CGPoint(x: 35, y: 166))
        front.addCurve(to: CGPoint(x: 32, y: 221), control1: CGPoint(x: 15, y: 180), control2: CGPoint(x: 18, y: 206))
        front.addCurve(to: CGPoint(x: 61, y: 235), control1: CGPoint(x: 41, y: 230), control2: CGPoint(x: 49, y: 233))
        front.addCurve(to: CGPoint(x: 99, y: 206), control1: CGPoint(x: 72, y: 220), control2: CGPoint(x: 82, y: 213))
        front.addCurve(to: CGPoint(x: 146, y: 202), control1: CGPoint(x: 116, y: 198), control2: CGPoint(x: 131, y: 194))
        front.addCurve(to: CGPoint(x: 170, y: 240), control1: CGPoint(x: 165, y: 211), control2: CGPoint(x: 174, y: 223))
        front.addCurve(to: CGPoint(x: 139, y: 270), control1: CGPoint(x: 167, y: 253), control2: CGPoint(x: 153, y: 263))
        front.addCurve(to: CGPoint(x: 88, y: 285), control1: CGPoint(x: 119, y: 281), control2: CGPoint(x: 104, y: 288))
        front.addCurve(to: CGPoint(x: 58, y: 254), control1: CGPoint(x: 70, y: 283), control2: CGPoint(x: 59, y: 270))
        front.addCurve(to: CGPoint(x: 14, y: 221), control1: CGPoint(x: 38, y: 249), control2: CGPoint(x: 23, y: 238))
        front.addCurve(to: CGPoint(x: 12, y: 169), control1: CGPoint(x: 4, y: 204), control2: CGPoint(x: 4, y: 186))
        front.addCurve(to: CGPoint(x: 34, y: 140), control1: CGPoint(x: 16, y: 157), control2: CGPoint(x: 27, y: 146))
        front.addCurve(to: CGPoint(x: 77, y: 99), control1: CGPoint(x: 35, y: 117), control2: CGPoint(x: 53, y: 99))
        front.closeSubpath()

        func slit(_ rect: CGRect, angle: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
                .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
        }
        let parts = [Part(path: rear, cutout: false), Part(path: front, cutout: false),
                     Part(path: slit(CGRect(x: 143, y: 39, width: 8, height: 23), angle: -0.42), cutout: true),
                     Part(path: slit(CGRect(x: 220, y: 120, width: 26, height: 7), angle: -0.44), cutout: true),
                     Part(path: slit(CGRect(x: 90, y: 122, width: 13, height: 28), angle: 0.37), cutout: true),
                     Part(path: slit(CGRect(x: 73, y: 251, width: 19, height: 7), angle: -0.44), cutout: true)]
        let scale = min(rect.width / 270, rect.height / 286)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.midX - 135 * scale, y: rect.midY - 143 * scale))
        return parts.map { Part(path: $0.path.applying(transform), cutout: $0.cutout) }
    }
}
