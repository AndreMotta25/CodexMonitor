import SwiftUI

@main
struct CodexMonitorApp: App {
    @State private var controller = QuotaController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView(controller: controller)
                .tint(Color(red: 0.10, green: 0.64, blue: 0.49))
                .task { await controller.activate() }
                .onOpenURL { url in
                    if url.scheme == "codexmonitor", url.host == "refresh" {
                        Task { await controller.refresh() }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await controller.activate() }
                    }
                }
        }
    }
}
