import AppKit
import Darwin

/// EXdl is a menu bar app, but it has real windows too (guide, dashboard, software update).
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
    static let releasesURL = URL(string: "https://github.com/erdembeler/exdl/releases")!
    static let issuesURL = URL(string: "https://github.com/erdembeler/exdl/issues")!

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

/// Permission checks and TCC registration helpers shared by Onboarding and Settings.
enum Permissions {
    /// Full Disk Access cannot be queried via public API. Opening a TCC-protected file
    /// succeeds only when the app has been granted Full Disk Access.
    static var hasFullDiskAccess: Bool {
        let tccPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = open(tccPath, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }
        let safariBookmarks = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Safari/Bookmarks.plist")
        let safariFD = open(safariBookmarks, O_RDONLY)
        if safariFD >= 0 {
            close(safariFD)
            return true
        }
        return false
    }

    /// Checks whether macOS App Management (`kTCCServiceSystemPolicyAppBundles`) is granted
    /// by performing a harmless no-op open/xattr check on an existing third-party bundle in `/Applications`.
    /// Note: Calling this when undetermined also prompts macOS to register EXdl in the
    /// System Settings → Privacy & Security → App Management list with a switch!
    static func checkAppManagementAccess(triggerPromptIfUndetermined: Bool = false) -> Bool {
        guard let targetAppURL = findCandidateThirdPartyAppInApplications() else {
            // If there are no other third-party apps in /Applications to probe, fall back to Full Disk Access status.
            return hasFullDiskAccess
        }

        let infoPlistPath = targetAppURL.appendingPathComponent("Contents/Info.plist").path
        let fd = open(infoPlistPath, O_WRONLY | O_APPEND)
        if fd >= 0 {
            close(fd)
            return true
        }

        if triggerPromptIfUndetermined {
            // Also probe xattr on the bundle root so TCC registers `kTCCServiceSystemPolicyAppBundles`
            // even if Info.plist had restrictive POSIX permissions.
            _ = removexattr(targetAppURL.path, "com.erdem.exdl.tccprobe", 0)
        }

        return false
    }

    /// Finds a third-party `.app` in `/Applications` (excluding EXdl itself and EXdl stubs)
    /// that is owned/writable by the current user so POSIX permissions don't mask TCC checks.
    private static func findCandidateThirdPartyAppInApplications() -> URL? {
        let fm = FileManager.default
        let appsDir = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(
            at: appsDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let myBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let currentUID = getuid()
        var fallbackCandidate: URL?

        for url in urls where url.pathExtension.lowercased() == "app" {
            let stdPath = url.standardizedFileURL.path
            if stdPath == myBundlePath || url.lastPathComponent == "EXdl.app" || url.lastPathComponent == "Safari.app" {
                continue
            }
            if DiskImageHelper.isExternalAppLink(at: url) {
                continue
            }
            let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
            guard fm.fileExists(atPath: infoPlistURL.path) else { continue }

            if let attrs = try? fm.attributesOfItem(atPath: infoPlistURL.path),
               let ownerID = attrs[.ownerAccountID] as? NSNumber,
               ownerID.uint32Value == currentUID {
                return url
            }

            if fallbackCandidate == nil {
                fallbackCandidate = url
            }
        }

        return fallbackCandidate
    }

    static func openFullDiskAccessSettings() {
        // Touch TCC-protected paths first so macOS knows EXdl requested Full Disk Access.
        _ = hasFullDiskAccess
        openPrivacyPane("Privacy_AllFiles")
    }

    /// Triggers the App Management TCC registration probe first so EXdl appears with a toggle switch
    /// in System Settings → Privacy & Security → App Management, then opens the pane.
    static func openAppManagementSettings() {
        _ = checkAppManagementAccess(triggerPromptIfUndetermined: true)
        openPrivacyPane("Privacy_AppBundles")
    }

    /// Reveals `EXdl.app` in Finder so the user can easily drag-and-drop it into System Settings if needed.
    static func revealAppInFinder() {
        let appURL: URL
        if FileManager.default.fileExists(atPath: "/Applications/EXdl.app") {
            appURL = URL(fileURLWithPath: "/Applications/EXdl.app")
        } else {
            appURL = Bundle.main.bundleURL
        }
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
