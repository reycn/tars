import SwiftUI

@main
struct TarsApp: App {
    @StateObject private var link = AgentLink()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            FaceView(state: link.state, connected: link.connected, detail: link.detail, pairingRequired: link.pairingRequired, serverName: link.serverName, paired: link.paired, onPairingChanged: { link.repair() })
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.dark)
                .task { link.start(); UIApplication.shared.isIdleTimerDisabled = true }
                .onChange(of: phase) { _, value in
                    // Display screen: never auto-lock while showing eyes.
                    UIApplication.shared.isIdleTimerDisabled = value == .active
                    if value == .active { link.start() } else { link.stop() }
                }
        }
    }
}
