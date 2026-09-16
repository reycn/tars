import SwiftUI

struct FaceView: View {
    private let state: AgentState
    private let connected: Bool
    private let detail: String?
    private let pairingRequired: Bool
    private let serverName: String?
    private let paired: Bool
    private let onPairingChanged: () -> Void
    @State private var settingsVisible = false
    @State private var pinPrompt = false
    @State private var pinDraft = ""

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    // Saving battery (Settings)
    @AppStorage("batteryReduceMotion") private var batteryReduceMotion = false
    @AppStorage("batteryDim") private var batteryDim = false
    @AppStorage("batteryLowRefresh") private var batteryLowRefresh = false
    @State private var dimmed = false
    private var reduceMotion: Bool { systemReduceMotion || batteryReduceMotion }
    private var slowRefresh: Bool { lowPowerMode || batteryLowRefresh }
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var statusVisible = false

    init(state: AgentState, connected: Bool, detail: String? = nil, pairingRequired: Bool = false,
         serverName: String? = nil, paired: Bool = false, onPairingChanged: @escaping () -> Void = {}) {
        self.paired = paired
        self.state = state
        self.connected = connected
        self.detail = detail
        self.pairingRequired = pairingRequired
        self.serverName = serverName
        self.onPairingChanged = onPairingChanged
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                face
                    .opacity(dimmed ? 0.12 : 1)
                    .frame(
                        width: min(proxy.size.width * 0.74, 760),
                        height: min(proxy.size.height * 0.56, 360)
                    )
                    // Lift the eyes when the status capsule occupies the bottom edge.
                    .offset(y: statusVisible ? -proxy.size.height * 0.05 : 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))

                if let detail, state != .waiting {
                    VStack {
                        Spacer()
                        Text(detail)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(accent.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: proxy.size.width * 0.7)
                            .transition(.opacity)
                        Spacer().frame(height: proxy.size.height * 0.16)
                    }
                    .id(detail)
                }

                if statusVisible {
                    VStack {
                        Spacer()

                        Text("\(stateLabel)  •  \(connectionLabel)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black, in: Rectangle())
                            .overlay(Rectangle().stroke(accent.opacity(0.5), lineWidth: 2))
                            .padding(.bottom, 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                } else if let hint {
                    VStack {
                        Spacer()

                        Text(hint)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(accent.opacity(dimmed ? 0.25 : 0.52))
                            .padding(.bottom, 28)
                            .transition(.opacity)
                    }
                    .id(hint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if statusVisible {
                    Button { settingsVisible = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(12)
                            .background(.black, in: Rectangle())
                            .overlay(Rectangle().stroke(.white.opacity(0.5), lineWidth: 2))
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 16)
                    .accessibilityLabel("Settings")
                    .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $settingsVisible) {
            SettingsSheet(serverName: serverName, pairingRequired: pairingRequired, onPairingChanged: onPairingChanged)
        }
        .alert("Enter PIN from your Mac", isPresented: $pinPrompt) {
            TextField("6-digit code", text: $pinDraft).keyboardType(.numberPad)
            Button("Connect") {
                UserDefaults.standard.set(String(pinDraft.filter(\.isNumber).prefix(6)), forKey: "pairingCode")
                onPairingChanged()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(serverName.map { "Found \($0). " } ?? "No Mac found yet. ") + Text("Open Tars → Settings on the Mac to read the code.")
        }
        .onChange(of: pairingRequired) { _, required in
            if required && !settingsVisible { pinDraft = UserDefaults.standard.string(forKey: "pairingCode") ?? ""; pinPrompt = true }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                statusVisible.toggle()
                dimmed = false
            }
        }
        // Dim to minimal light 10 s after the last update; any state/detail change or tap wakes it.
        .task(id: "\(batteryDim)-\(stateID)-\(detail ?? "")-\(statusVisible)-\(settingsVisible)") {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { dimmed = false }
            guard batteryDim, !settingsVisible else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.5)) { dimmed = true }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.24),
            value: stateID
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent is \(stateLabel.lowercased()). Connection is \(connectionLabel.lowercased()).")
        .accessibilityHint("Double tap to show or hide status.")
    }

    // AMOLED: the panel is always pure black; state lives in the glyph shape and its pixel colour.
    private var backgroundColor: Color { .black }

    @AppStorage(Palette.nameKey) private var paletteName = Palette.presets[2].name
    @AppStorage(Palette.customKey(.waiting)) private var customWaiting = ""
    @AppStorage(Palette.customKey(.working)) private var customWorking = ""
    @AppStorage(Palette.customKey(.approval)) private var customApproval = ""
    @AppStorage(Palette.customKey(.completed)) private var customCompleted = ""

    private var accent: Color {
        // Reading the custom keys above keeps the view live when a picker changes them.
        _ = (customWaiting, customWorking, customApproval, customCompleted)
        return Palette.load(name: paletteName).color(for: state)
    }

    @ViewBuilder
    private var face: some View {
        switch state {
        case .waiting:
            BlinkingEyes(color: accent, reduceMotion: reduceMotion, scenePhase: scenePhase, lowPowerMode: slowRefresh)
        case .working:
            WorkingEyes(color: accent, reduceMotion: reduceMotion, scenePhase: scenePhase, lowPowerMode: slowRefresh)
        case .approval:
            PulsingEyes(glyph: .ring, color: accent, reduceMotion: reduceMotion)
        case .completed:
            PixelEyes(glyph: .check, color: accent)
        }
    }

    private var stateID: String { state.rawValue }

    private var stateLabel: String {
        switch state {
        case .waiting: return "Waiting"
        case .working: return "Working"
        case .approval: return "Approval needed"
        case .completed: return "Completed"
        }
    }

    private var connectionLabel: String { connected ? "Connected" : "Disconnected" }

    /// Idle hint under the eyes. Nil while a detail line is showing for an active state.
    private var hint: String? {
        if pairingRequired { return "Pairing needed · tap the screen, then ⚙" }
        if !paired { return "Looking for your Mac…" }
        if !connected { return "Mac found · no agent events yet" }
        return state == .waiting ? "Waiting for Mac events" : nil
    }
}

// MARK: - Pixel glyphs

/// 12×12 bitmaps. `#` is lit. Every state is a glyph so the whole face reads as one sprite sheet.
enum PixelGlyph: String, CaseIterable {
    case bar, blink, smile, ring, check

    var rows: [String] {
        switch self {
        case .bar: return [
            "............", "............", "............", "............",
            "############", "############", "############", "############",
            "............", "............", "............", "............"]
        case .blink: return [
            "............", "............", "............", "............",
            "............", "############", "############", "............",
            "............", "............", "............", "............"]
        case .smile: return [
            "............", "............", "....####....", "..########..",
            ".###....###.", "###......###", "##........##", "##........##",
            "............", "............", "............", "............"]
        case .ring: return [
            "....####....", "..########..", ".###....###.", "###......###",
            "##........##", "##........##", "##........##", "##........##",
            "###......###", ".###....###.", "..########..", "....####...."]
        case .check: return [
            "............", "..........##", ".........###", "........###.",
            ".......###..", "##....###...", "###..###....", ".######.....",
            "..####......", "...##.......", "............", "............"]
        }
    }
}

private struct PixelGlyphView: View {
    let glyph: PixelGlyph
    let color: Color

    var body: some View {
        Canvas { context, size in
            let rows = glyph.rows
            let cell = min(size.width / CGFloat(rows[0].count), size.height / CGFloat(rows.count))
            let gap = max(1, cell * 0.12)   // visible seams = pixel feel
            let originX = (size.width - cell * CGFloat(rows[0].count)) / 2
            let originY = (size.height - cell * CGFloat(rows.count)) / 2
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    let rect = CGRect(x: originX + CGFloat(x) * cell, y: originY + CGFloat(y) * cell,
                                      width: cell - gap, height: cell - gap)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .drawingGroup()
    }
}

private struct PixelEyes: View {
    let glyph: PixelGlyph
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let layout = EyeLayout(in: proxy.size)
            HStack(spacing: layout.spacing) {
                PixelGlyphView(glyph: glyph, color: color).frame(width: layout.eye, height: layout.eye)
                PixelGlyphView(glyph: glyph, color: color).frame(width: layout.eye, height: layout.eye)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(glyph)
        .transition(.opacity)
    }
}

/// Idle: flat bars that blink every few seconds. Blink is a glyph swap, no interpolation, keeps the pixel look.
private struct BlinkingEyes: View {
    let color: Color
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    let lowPowerMode: Bool
    @State private var glyph = PixelGlyph.bar

    var body: some View {
        PixelEyes(glyph: glyph, color: color)
            .task(id: "\(scenePhase)-\(reduceMotion)-\(lowPowerMode)") {
                glyph = .bar
                guard !reduceMotion, scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(lowPowerMode ? 6 : 3.5))
                    guard !Task.isCancelled else { return }
                    glyph = .blink
                    try? await Task.sleep(for: .milliseconds(140))
                    glyph = .bar
                }
            }
    }
}

/// Working: alternates bar and smile, same cadence as before.
private struct WorkingEyes: View {
    let color: Color
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    let lowPowerMode: Bool
    @State private var glyph = PixelGlyph.bar

    var body: some View {
        PixelEyes(glyph: glyph, color: color)
            .task(id: "\(scenePhase)-\(reduceMotion)-\(lowPowerMode)") {
                glyph = .bar
                guard !reduceMotion, scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(lowPowerMode ? 1200 : 700))
                    guard !Task.isCancelled else { return }
                    glyph = .smile
                    try? await Task.sleep(for: .milliseconds(lowPowerMode ? 2200 : 1200))
                    guard !Task.isCancelled else { return }
                    glyph = .bar
                }
            }
    }
}

/// Approval: steady glyph with a slow brightness pulse so it reads as "needs you" from across the room.
private struct PulsingEyes: View {
    let glyph: PixelGlyph
    let color: Color
    let reduceMotion: Bool
    @State private var dim = false

    var body: some View {
        PixelEyes(glyph: glyph, color: color)
            .opacity(dim ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

private struct EyeLayout {
    let eye: CGFloat
    let spacing: CGFloat

    init(in size: CGSize) {
        let unit = min(size.width, size.height)
        // Square glyph cells so 12×12 bitmaps never stretch.
        eye = min(size.width * 0.3, unit * 0.9)
        spacing = min(size.width * 0.14, unit * 0.4)
    }
}

private struct SettingsSheet: View {
    let serverName: String?
    let pairingRequired: Bool
    let onPairingChanged: () -> Void

    @AppStorage("pairingCode") private var pairingCode = ""
    @AppStorage("batteryReduceMotion") private var batteryReduceMotion = false
    @AppStorage("batteryDim") private var batteryDim = false
    @AppStorage("batteryLowRefresh") private var batteryLowRefresh = false
    @AppStorage(Palette.nameKey) private var paletteName = Palette.presets[2].name
    @AppStorage(Palette.customKey(.waiting)) private var customWaiting = ""
    @AppStorage(Palette.customKey(.working)) private var customWorking = ""
    @AppStorage(Palette.customKey(.approval)) private var customApproval = ""
    @AppStorage(Palette.customKey(.completed)) private var customCompleted = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("6-digit code from the Mac", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .focused($codeFocused)
                        .onChange(of: pairingCode) { _, value in
                            pairingCode = String(value.filter(\.isNumber).prefix(6))
                        }
                } header: {
                    Text("Pairing code")
                } footer: {
                    Text(footer)
                }
                Section("Colors") {
                    Picker("Palette", selection: $paletteName) {
                        ForEach(Palette.presets, id: \.name) { Text($0.name).tag($0.name) }
                        Text(Palette.customName).tag(Palette.customName)
                    }
                    if paletteName == Palette.customName {
                        ColorPicker("Waiting", selection: customBinding(.waiting), supportsOpacity: false)
                        ColorPicker("Working", selection: customBinding(.working), supportsOpacity: false)
                        ColorPicker("Approval", selection: customBinding(.approval), supportsOpacity: false)
                        ColorPicker("Completed", selection: customBinding(.completed), supportsOpacity: false)
                    }
                    PalettePreview(palette: Palette.load(name: paletteName))
                }
                Section {
                    Toggle("Reduce motion", isOn: $batteryReduceMotion)
                    Toggle("Dim after 10 s without updates", isOn: $batteryDim)
                    Toggle("Reduce refresh rate", isOn: $batteryLowRefresh)
                } header: {
                    Text("Saving battery")
                } footer: {
                    Text("Reduce motion freezes blinks and pulses. Dimming drops the eyes to minimal light until the next event or a tap. Reduced refresh uses the slower low‑power animation cadence.")
                }
                Section("Style") {
                    LabeledContent("Eyes", value: "Upcoming")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onPairingChanged(); dismiss() }
                }
            }
            .onAppear { codeFocused = pairingRequired }
        }
        .presentationDetents([.medium])
    }

    /// Custom colours are stored as hex so they survive as plain strings; empty = preset default.
    private func customBinding(_ state: AgentState) -> Binding<Color> {
        Binding(
            get: { Palette.load(name: Palette.customName).color(for: state) },
            set: { color in
                let hex = color.hexString
                switch state {
                case .waiting: customWaiting = hex
                case .working: customWorking = hex
                case .approval: customApproval = hex
                case .completed: customCompleted = hex
                }
                _ = (customWaiting, customWorking, customApproval, customCompleted)
            })
    }

    private var footer: String {
        let mac = serverName.map { "Found \($0)." } ?? "Looking for a Mac running Tars on this network."
        return mac + " Open Tars → Settings on the Mac to read the code. Saved here so you only pair once."
    }
}

private struct PalettePreview: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 14) {
            ForEach([AgentState.waiting, .working, .approval, .completed], id: \.self) { state in
                VStack(spacing: 4) {
                    Rectangle().fill(palette.color(for: state)).frame(width: 28, height: 28)
                    Text(state.rawValue).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
