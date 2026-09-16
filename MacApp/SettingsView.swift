import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Pairing") {
                if model.developmentMode {
                    Text("Development mode: any phone on the network can connect without a code.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Pairing code") {
                        HStack {
                            Text(model.pairingCode.spacedCode)
                                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                            Button("New code") { model.regenerateCode() }
                        }
                    }
                    Text("On the phone, tap the gear and enter this code once. It is remembered.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Toggle("Development mode (no pairing)", isOn: $model.developmentMode)
                if let last = model.lastPairing { Text(last).font(.callout).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(AppModel.providers) { provider in
                    Toggle(provider.label, isOn: Binding(get: { model.hooked[provider.id] ?? false },
                                                         set: { model.setHook(provider.id, installed: $0) }))
                }
                if model.hooked["codex"] == true {
                    Text("Codex only runs hooks you trust: open Codex, run /hooks, and trust the Tars entries in ~/.codex/hooks.json.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Registers ~/.tars/bin/tars-hook in each agent's own lifecycle hooks: a config entry for Claude Code and Codex, a plugin file for opencode (~/.config/opencode/plugin/tars.js) and pi (~/.pi/agent/extensions/tars.ts). The hook sends only session id, state and one clipped detail line to this Mac; it never blocks the agent. New agent sessions pick it up.")
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Hide this window after startup", isOn: $model.hideWindowAtStartup)
                    .disabled(!model.showMenuBarItem)
                Toggle("Show menu bar item", isOn: $model.showMenuBarItem)
                    .onChange(of: model.showMenuBarItem) { _, shown in if !shown { model.hideWindowAtStartup = false } }
                if !model.showMenuBarItem {
                    Text("With the menu bar item hidden, reopen Tars from Applications to see this window.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Status") {
                LabeledContent("Agent", value: model.state.capitalized)
                LabeledContent("Event source", value: model.sourceAvailable ? "Connected" : "No events yet")
                if let detail = model.detail { Text(detail).font(.callout).lineLimit(2) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension String {
    /// "123456" → "123 456"
    var spacedCode: String { count == 6 ? prefix(3) + " " + suffix(3) : self }
}
