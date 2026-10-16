import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            MonitorCoordinator.shared.start()
            InstallPromptPanelController.shared.showPromptWindow()
        }
    }
}

@main
struct EXdlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var coordinator = MonitorCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIconName)
                if !coordinator.pendingPrompts.isEmpty {
                    Text("\(coordinator.pendingPrompts.count)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIconName: String {
        if !coordinator.pendingPrompts.isEmpty {
            return "externaldrive.fill.badge.exclamationmark"
        }
        return settings.isMonitoringEnabled ? "externaldrive.fill.badge.checkmark" : "externaldrive"
    }
}
