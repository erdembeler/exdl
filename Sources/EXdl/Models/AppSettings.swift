import Foundation
import SwiftUI
import AppKit
import ServiceManagement

/// State of the "Launch at Login" item, as reported by macOS.
enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    /// Registered, but the user still has to approve it in System Settings → Login Items.
    case requiresApproval
    /// macOS cannot find the app bundle (for example when it runs from a disk image).
    case unavailable
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    @Published var launchAtLoginError: String?

    @Published var isMonitoringEnabled: Bool {
        didSet { UserDefaults.standard.set(isMonitoringEnabled, forKey: "isMonitoringEnabled") }
    }

    @Published var watchMountedDMGs: Bool {
        didSet { UserDefaults.standard.set(watchMountedDMGs, forKey: "watchMountedDMGs") }
    }

    @Published var watchApplicationsFolder: Bool {
        didSet { UserDefaults.standard.set(watchApplicationsFolder, forKey: "watchApplicationsFolder") }
    }

    @Published var protectSymlinksOnAutoUpdate: Bool {
        didSet { UserDefaults.standard.set(protectSymlinksOnAutoUpdate, forKey: "protectSymlinksOnAutoUpdate") }
    }

    @Published var autoMoveOnSymlinkOverwrite: Bool {
        didSet { UserDefaults.standard.set(autoMoveOnSymlinkOverwrite, forKey: "autoMoveOnSymlinkOverwrite") }
    }

    @Published var minimumAppSizeMB: Double {
        didSet { UserDefaults.standard.set(minimumAppSizeMB, forKey: "minimumAppSizeMB") }
    }

    @Published var autoEjectDMGAfterInstall: Bool {
        didSet { UserDefaults.standard.set(autoEjectDMGAfterInstall, forKey: "autoEjectDMGAfterInstall") }
    }

    @Published var moveDMGToTrashAfterInstall: Bool {
        didSet { UserDefaults.standard.set(moveDMGToTrashAfterInstall, forKey: "moveDMGToTrashAfterInstall") }
    }

    @Published var externalApplicationsPath: String {
        didSet { UserDefaults.standard.set(externalApplicationsPath, forKey: "externalApplicationsPath") }
    }

    @Published var managedSymlinks: [String: String] {
        didSet { UserDefaults.standard.set(managedSymlinks, forKey: "managedSymlinks") }
    }

    @Published var ignoredBundleNames: Set<String> {
        didSet { UserDefaults.standard.set(Array(ignoredBundleNames), forKey: "ignoredBundleNames") }
    }

    @Published var menuBarIconStyleRaw: Int {
        didSet { UserDefaults.standard.set(menuBarIconStyleRaw, forKey: "menuBarIconStyleRaw") }
    }

    var menuBarIconStyle: MenuBarIconStyle {
        get { MenuBarIconStyle(rawValue: menuBarIconStyleRaw) ?? .exMonogram }
        set { menuBarIconStyleRaw = newValue.rawValue }
    }

    @Published var availableExternalDrives: [ExternalDriveInfo] = []
    @Published var internalDrive: ExternalDriveInfo = ExternalDriveInfo(
        name: "Macintosh HD",
        volumeURL: URL(fileURLWithPath: "/"),
        availableBytes: 0,
        totalBytes: 0
    )
    @Published var activityLogs: [ActivityLogItem] = []

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "isMonitoringEnabled": true,
            "watchMountedDMGs": true,
            "watchApplicationsFolder": true,
            "protectSymlinksOnAutoUpdate": true,
            "autoMoveOnSymlinkOverwrite": false,
            "minimumAppSizeMB": 0.0,
            "autoEjectDMGAfterInstall": true,
            "moveDMGToTrashAfterInstall": false,
            "externalApplicationsPath": "",
            "menuBarIconStyleRaw": MenuBarIconStyle.exMonogram.rawValue
        ])

        self.isMonitoringEnabled = defaults.bool(forKey: "isMonitoringEnabled")
        self.watchMountedDMGs = defaults.bool(forKey: "watchMountedDMGs")
        self.watchApplicationsFolder = defaults.bool(forKey: "watchApplicationsFolder")
        self.protectSymlinksOnAutoUpdate = defaults.bool(forKey: "protectSymlinksOnAutoUpdate")
        self.autoMoveOnSymlinkOverwrite = defaults.bool(forKey: "autoMoveOnSymlinkOverwrite")
        self.minimumAppSizeMB = defaults.double(forKey: "minimumAppSizeMB")
        self.autoEjectDMGAfterInstall = defaults.bool(forKey: "autoEjectDMGAfterInstall")
        self.moveDMGToTrashAfterInstall = defaults.bool(forKey: "moveDMGToTrashAfterInstall")
        self.externalApplicationsPath = defaults.string(forKey: "externalApplicationsPath") ?? ""
        self.managedSymlinks = (defaults.dictionary(forKey: "managedSymlinks") as? [String: String]) ?? [:]
        let ignoredArray = defaults.stringArray(forKey: "ignoredBundleNames") ?? []
        self.ignoredBundleNames = Set(ignoredArray)
        let savedIconStyle = defaults.integer(forKey: "menuBarIconStyleRaw")
        self.menuBarIconStyleRaw = (1...10).contains(savedIconStyle) ? savedIconStyle : MenuBarIconStyle.exMonogram.rawValue

        refreshExternalDrives()
        refreshLaunchAtLogin()

        // The user can switch the login item off in System Settings; pick that up when we come back to the front.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLaunchAtLogin() }
        }
    }

    var externalApplicationsURL: URL? {
        guard !externalApplicationsPath.isEmpty else { return nil }
        return URL(fileURLWithPath: externalApplicationsPath, isDirectory: true)
    }

    var selectedExternalDriveName: String {
        if let drive = selectedExternalDriveInfo {
            return drive.name
        }
        guard let targetURL = externalApplicationsURL else { return tr("External Drive") }
        let components = targetURL.pathComponents
        if components.count >= 3 && components[1] == "Volumes" {
            return components[2]
        }
        return targetURL.lastPathComponent
    }

    var selectedExternalDriveInfo: ExternalDriveInfo? {
        guard let targetURL = externalApplicationsURL else { return nil }
        return availableExternalDrives.first { drive in
            targetURL.path == drive.volumeURL.path || targetURL.path.hasPrefix(drive.volumeURL.path + "/")
        }
    }

    var isExternalTargetReady: Bool {
        guard let targetURL = externalApplicationsURL else { return false }
        let pathComponents = targetURL.pathComponents
        if pathComponents.count >= 3 && pathComponents[1] == "Volumes" {
            let volumePath = "/Volumes/\(pathComponents[2])"
            return FileManager.default.fileExists(atPath: volumePath)
        }
        return FileManager.default.fileExists(atPath: targetURL.deletingLastPathComponent().path)
    }

    // MARK: - Launch at login

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    /// Login items are only reliable for apps that live in /Applications.
    var isRunningFromApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    func refreshLaunchAtLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: launchAtLoginStatus = .enabled
        case .requiresApproval: launchAtLoginStatus = .requiresApproval
        case .notRegistered: launchAtLoginStatus = .disabled
        case .notFound: launchAtLoginStatus = .unavailable
        @unknown default: launchAtLoginStatus = .disabled
        }
    }

    func setLaunchAtLogin(enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            logActivity(tr("Launch at Login Error"), detail: error.localizedDescription, isSuccess: false)
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Activity log and managed launchers

    func logActivity(_ title: String, detail: String, isSuccess: Bool = true) {
        let item = ActivityLogItem(timestamp: Date(), title: title, detail: detail, isSuccess: isSuccess)
        activityLogs.insert(item, at: 0)
        if activityLogs.count > 50 {
            activityLogs.removeLast()
        }
    }

    func registerManagedSymlink(appBundleName: String, externalDestinationPath: String) {
        managedSymlinks[appBundleName] = externalDestinationPath
    }

    func unregisterManagedSymlink(appBundleName: String) {
        managedSymlinks.removeValue(forKey: appBundleName)
    }

    func refreshExternalDrives() {
        let dmgMountPoints = Set(DiskImageHelper.mountedDMGMap().keys)
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
            .volumeIsBrowsableKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        // Dahili disk bilgisini oku
        let rootURL = URL(fileURLWithPath: "/")
        if let rootValues = try? rootURL.resourceValues(forKeys: Set(keys)) {
            let rootName = rootValues.volumeName ?? "Macintosh HD"
            let availImp = rootValues.volumeAvailableCapacityForImportantUsage ?? 0
            let availStd = Int64(rootValues.volumeAvailableCapacity ?? 0)
            let total = Int64(rootValues.volumeTotalCapacity ?? 0)
            self.internalDrive = ExternalDriveInfo(
                name: rootName,
                volumeURL: rootURL,
                availableBytes: max(availImp, availStd),
                totalBytes: total
            )
        }

        guard let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return
        }

        var drives: [ExternalDriveInfo] = []
        for url in volumeURLs {
            if url.path == "/" || url.path == "/System/Volumes/Data" { continue }
            if dmgMountPoints.contains(url.path) { continue }

            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isReadOnly = values.volumeIsReadOnly ?? false
            if isReadOnly { continue }
            // App bundles do not belong on network shares.
            if values.volumeIsLocal == false { continue }

            guard url.path.hasPrefix("/Volumes/") else { continue }

            let name = values.volumeName ?? url.lastPathComponent
            let availImportant = values.volumeAvailableCapacityForImportantUsage ?? 0
            let availStandard = Int64(values.volumeAvailableCapacity ?? 0)
            let available = max(availImportant, availStandard)
            let total = Int64(values.volumeTotalCapacity ?? 0)

            drives.append(
                ExternalDriveInfo(
                    name: name,
                    volumeURL: url,
                    availableBytes: available,
                    totalBytes: total
                )
            )
        }

        self.availableExternalDrives = drives

        if externalApplicationsPath.isEmpty, let firstDrive = drives.first {
            externalApplicationsPath = firstDrive.defaultApplicationsFolderURL.path
        }
    }
}
