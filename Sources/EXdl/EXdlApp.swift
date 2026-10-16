import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let openedByLoginItem = Self.eventSaysLaunchedAtLogin()
        Task { @MainActor in
            MonitorCoordinator.shared.start()

            if !OnboardingState.isCompleted {
                OnboardingWindowController.shared.show()
            } else if !(openedByLoginItem || Self.looksLikeLoginLaunch()) {
                // Opened by hand: show the dashboard instead of disappearing into the menu bar.
                DashboardWindowController.shared.showWindow()
            }
        }
    }

    /// Double-clicking the app icon while EXdl is already running brings a window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            if !OnboardingState.isCompleted {
                OnboardingWindowController.shared.show()
            } else if !flag {
                DashboardWindowController.shared.showWindow()
            }
        }
        return true
    }

    /// macOS marks the "open application" event with a flag when a login item starts the app.
    private static func eventSaysLaunchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let flag = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return flag.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// Backup for the check above: a login item that starts within two minutes of boot.
    @MainActor
    private static func looksLikeLoginLaunch() -> Bool {
        AppSettings.shared.isLaunchAtLoginEnabled && ProcessInfo.processInfo.systemUptime < 120
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
