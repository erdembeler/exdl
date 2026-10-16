import AppKit

/// EXdl is a menu bar app, but it has real windows too (guide, dashboard).
/// While one of them is open it behaves like a regular app (Dock icon, Cmd-Tab); when the
/// last one closes it goes back to living in the menu bar only.
@MainActor
enum AppPresence {
    private static var trackedWindows: [NSWindow] = []

    static func track(_ window: NSWindow) {
        guard !trackedWindows.contains(where: { $0 === window }) else { return }
        trackedWindows.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            // `isVisible` is still true while the close notification is delivered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Task { @MainActor in refresh() }
            }
        }
    }

    /// Call right before ordering one of the tracked windows to the front.
    static func windowWillShow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func refresh() {
        let hasOpenWindow = trackedWindows.contains { $0.isVisible || $0.isMiniaturized }
        let wanted: NSApplication.ActivationPolicy = hasOpenWindow ? .regular : .accessory
        if NSApp.activationPolicy() != wanted {
            NSApp.setActivationPolicy(wanted)
        }
    }
}

/// Facts about the app that more than one screen needs.
enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/erdembeler/exdl")!
    static let issuesURL = URL(string: "https://github.com/erdembeler/exdl/issues")!

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

/// Permission checks the guide and the settings screen share.
enum Permissions {
    /// Full Disk Access cannot be queried directly. Opening a file that is protected by it
    /// only succeeds when the app has been granted access.
    static var hasFullDiskAccess: Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    static func openFullDiskAccessSettings() {
        openPrivacyPane("Privacy_AllFiles")
    }

    /// "App Management" is the permission macOS asks for before one app may update or delete another.
    static func openAppManagementSettings() {
        openPrivacyPane("Privacy_AppBundles")
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
