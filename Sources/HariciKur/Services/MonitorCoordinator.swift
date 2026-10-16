import Foundation
import AppKit
import CoreServices

@MainActor
final class MonitorCoordinator: ObservableObject {
    static let shared = MonitorCoordinator()

    @Published var pendingPrompts: [PendingInstallPrompt] = []
    @Published var mountedDMGApps: [PendingInstallPrompt] = []
    @Published var installedApps: [InstalledAppInfo] = []
    @Published var isScanningApps: Bool = false

    /// /Applications klasöründeki önceki durum snapshot'ı: [BundleName : IsExternalLinkOrStub]
    private var previousApplicationsState: [String: Bool] = [:]

    private var eventStream: FSEventStreamRef?
    private var promptPanelController: InstallPromptPanelController?

    private init() {}

    func start() {
        Task {
            await upgradeAnyLegacyLinksAndTakeSnapshot()
            setupWorkspaceVolumeNotifications()
            startFSEventsForApplicationsFolder()
            refreshMountedDMGs(enqueueIfInitial: true)
            await scanInstalledApplications()
        }
    }

    // MARK: - 1) Başlangıç Snapshot'ı, Eski Symlink Yükseltme ve /Applications Tarama

    private func upgradeAnyLegacyLinksAndTakeSnapshot() async {
        let appsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var snapshot: [String: Bool] = [:]
        for url in items where url.pathExtension.lowercased() == "app" {
            let bundleName = url.lastPathComponent

            // Eğer eski tip POSIX symlink ise ve /Volumes/... altındaki bir uygulamayı gösteriyorsa
            // macOS 26 Apps.app'te görünmesi için otomatik olarak Smart App Stub'a yükselt
            if DiskImageHelper.isSymbolicLink(at: url),
               let dest = DiskImageHelper.externalTargetURL(for: url),
               dest.path.hasPrefix("/Volumes/"),
               FileManager.default.fileExists(atPath: dest.path) {
                await AppInstallerService.shared.upgradeLegacySymlinkIfNeeded(at: url, externalTargetURL: dest)
            } else if let managedPath = AppSettings.shared.managedSymlinks[bundleName],
                      DiskImageHelper.stubTargetURL(for: url) == nil,
                      FileManager.default.fileExists(atPath: managedPath) {
                let dest = URL(fileURLWithPath: managedPath)
                await AppInstallerService.shared.upgradeLegacySymlinkIfNeeded(at: url, externalTargetURL: dest)
            }

            let isExtLink = DiskImageHelper.isExternalAppLink(at: url)
            snapshot[bundleName] = isExtLink
            if isExtLink, let dest = DiskImageHelper.externalTargetURL(for: url),
               dest.path.hasPrefix("/Volumes/") {
                AppSettings.shared.registerManagedSymlink(
                    appBundleName: bundleName,
                    externalDestinationPath: dest.path
                )
            }
        }
        self.previousApplicationsState = snapshot
    }

    func scanInstalledApplications() async {
        isScanningApps = true
        defer { isScanningApps = false }

        let result: [InstalledAppInfo] = await Task.detached(priority: .utility) {
            let appsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: appsURL,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var items: [InstalledAppInfo] = []
            for url in urls where url.pathExtension.lowercased() == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let isExt = DiskImageHelper.isExternalAppLink(at: url)
                let extTarget = DiskImageHelper.externalTargetURL(for: url)
                let reachable: Bool
                if let target = extTarget {
                    reachable = FileManager.default.fileExists(atPath: target.path)
                } else {
                    reachable = true
                }
                let size = reachable ? DiskImageHelper.calculateBundleSize(at: url) : 0
                let isSystem = url.path.hasPrefix("/System/") || name == "Safari"

                let plistURL = url.appendingPathComponent("Contents/Info.plist")
                let version: String?
                if let data = try? Data(contentsOf: plistURL),
                   let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    version = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String)
                } else {
                    version = nil
                }

                items.append(
                    InstalledAppInfo(
                        name: name,
                        version: version,
                        bundleURL: url,
                        sizeInBytes: size,
                        isSymlink: isExt,
                        symlinkTargetURL: extTarget,
                        isTargetReachable: reachable,
                        isSystemApp: isSystem
                    )
                )
            }

            return items.sorted { a, b in
                if a.isSymlink != b.isSymlink {
                    return a.isSymlink && !b.isSymlink
                }
                return a.sizeInBytes > b.sizeInBytes
            }
        }.value

        self.installedApps = result
    }

    var totalSavedInternalBytes: Int64 {
        installedApps
            .filter { $0.isSymlink && $0.isTargetReachable }
            .reduce(0) { $0 + $1.sizeInBytes }
    }

    var externalAppsCount: Int {
        installedApps.filter { $0.isSymlink }.count
    }

    // MARK: - 2) Yaklaşım 2: DMG Mount / Unmount İzleme (NSWorkspace)

    private func setupWorkspaceVolumeNotifications() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppSettings.shared.refreshExternalDrives()
                self.refreshMountedDMGs()
                if let volumeURL {
                    await self.handleMountedVolume(volumeURL)
                }
                await self.scanInstalledApplications()
            }
        }

        nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppSettings.shared.refreshExternalDrives()
                self.refreshMountedDMGs()
                await self.scanInstalledApplications()
            }
        }
    }

    func refreshMountedDMGs(enqueueIfInitial: Bool = false) {
        Task {
            let dmgMap = await Task.detached { DiskImageHelper.mountedDMGMap() }.value
            var detected: [PendingInstallPrompt] = []
            for (mountPoint, dmgPath) in dmgMap {
                let volURL = URL(fileURLWithPath: mountPoint)
                let apps = DiskImageHelper.findAppsInVolume(at: volURL)
                for appURL in apps {
                    let size = await Task.detached { DiskImageHelper.calculateBundleSize(at: appURL) }.value
                    detected.append(
                        PendingInstallPrompt(
                            appName: appURL.deletingPathExtension().lastPathComponent,
                            appBundleURL: appURL,
                            sizeInBytes: size,
                            source: .mountedDMG(volumeURL: volURL, dmgImagePath: dmgPath)
                        )
                    )
                }
            }
            self.mountedDMGApps = detected
            if enqueueIfInitial, AppSettings.shared.isMonitoringEnabled, AppSettings.shared.watchMountedDMGs {
                for item in detected where !AppSettings.shared.ignoredBundleNames.contains(item.appBundleURL.lastPathComponent) {
                    enqueuePrompt(item)
                }
            }
        }
    }

    private func handleMountedVolume(_ volumeURL: URL) async {
        let settings = AppSettings.shared
        guard settings.isMonitoringEnabled, settings.watchMountedDMGs else { return }

        try? await Task.sleep(nanoseconds: 400_000_000)

        let dmgMap = await Task.detached { DiskImageHelper.mountedDMGMap() }.value
        let dmgFilePath = dmgMap[volumeURL.path]

        let appURLs = DiskImageHelper.findAppsInVolume(at: volumeURL)
        guard !appURLs.isEmpty else { return }

        let isReadOnly = (try? volumeURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        guard dmgFilePath != nil || isReadOnly else { return }

        for appURL in appURLs {
            let bundleName = appURL.lastPathComponent
            if settings.ignoredBundleNames.contains(bundleName) { continue }

            let size = await Task.detached { DiskImageHelper.calculateBundleSize(at: appURL) }.value
            let minBytes = Int64(settings.minimumAppSizeMB * 1_048_576.0)
            if size < minBytes { continue }

            let prompt = PendingInstallPrompt(
                appName: appURL.deletingPathExtension().lastPathComponent,
                appBundleURL: appURL,
                sizeInBytes: size,
                source: .mountedDMG(volumeURL: volumeURL, dmgImagePath: dmgFilePath)
            )
            enqueuePrompt(prompt)
        }
    }

    // MARK: - 3) Yaklaşım 1 & Püf Nokta 2: /Applications Klasörü İzleme (FSEvents)

    private func startFSEventsForApplicationsFolder() {
        let pathToWatch = "/Applications" as CFString
        let pathsToWatch = [pathToWatch] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (
            _,
            clientCallBackInfo,
            _,
            _,
            _,
            _
        ) in
            guard let info = clientCallBackInfo else { return }
            let coordinator = Unmanaged<MonitorCoordinator>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                await coordinator.handleApplicationsFolderChange()
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            return
        }

        self.eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    private func handleApplicationsFolderChange() async {
        let appsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard let currentURLs = try? FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var currentSnapshot: [String: Bool] = [:]
        for url in currentURLs where url.pathExtension.lowercased() == "app" {
            currentSnapshot[url.lastPathComponent] = DiskImageHelper.isExternalAppLink(at: url)
        }

        let previous = self.previousApplicationsState
        self.previousApplicationsState = currentSnapshot

        let settings = AppSettings.shared
        guard settings.isMonitoringEnabled else {
            await scanInstalledApplications()
            return
        }

        for (bundleName, isCurrentlyExternalStub) in currentSnapshot {
            if AppInstallerService.shared.isAppBeingOperatedOn(bundleName) {
                continue
            }

            if bundleName.lowercased().contains("haricikur") {
                continue
            }

            let appURL = appsURL.appendingPathComponent(bundleName)
            let wasPresentBefore = previous[bundleName] != nil
            let wasExternalBefore = previous[bundleName] == true
            let managedTarget = settings.managedSymlinks[bundleName]

            // PÜF NOKTA 2: Daha önce Harici Diskte olan bir uygulama güncellendi ve gerçek klasöre dönüştü!
            if !isCurrentlyExternalStub && (wasExternalBefore || managedTarget != nil) && settings.protectSymlinksOnAutoUpdate {
                let copyDone = await DiskImageHelper.waitForCopyCompletion(at: appURL)
                guard copyDone, !DiskImageHelper.isExternalAppLink(at: appURL) else { continue }

                if settings.autoMoveOnSymlinkOverwrite && settings.isExternalTargetReady {
                    do {
                        try await AppInstallerService.shared.moveInternalAppToExternal(appBundleURL: appURL)
                        settings.logActivity(
                            "\(bundleName) Otomatik Güncelleme Onarıldı",
                            detail: "Güncellenen sürüm tekrar harici diske taşındı ve kısayol yenilendi."
                        )
                    } catch {
                        settings.logActivity(
                            "\(bundleName) Otomatik Onarım Hatası",
                            detail: error.localizedDescription,
                            isSuccess: false
                        )
                    }
                } else {
                    let size = await Task.detached { DiskImageHelper.calculateBundleSize(at: appURL) }.value
                    let expectedURL = URL(fileURLWithPath: managedTarget ?? settings.externalApplicationsPath)
                    let prompt = PendingInstallPrompt(
                        appName: appURL.deletingPathExtension().lastPathComponent,
                        appBundleURL: appURL,
                        sizeInBytes: size,
                        source: .symlinkOverwrittenByUpdate(expectedExternalURL: expectedURL)
                    )
                    enqueuePrompt(prompt)
                }
                continue
            }

            // YAKLAŞIM 1: /Applications klasörüne YENİ bir gerçek uygulama (.app) sürüklendi / kuruldu
            if !wasPresentBefore && !isCurrentlyExternalStub && settings.watchApplicationsFolder {
                if settings.ignoredBundleNames.contains(bundleName) { continue }

                let copyDone = await DiskImageHelper.waitForCopyCompletion(at: appURL)
                guard copyDone, !DiskImageHelper.isExternalAppLink(at: appURL) else { continue }

                pendingPrompts.removeAll { $0.appBundleURL.lastPathComponent == bundleName }

                let size = await Task.detached { DiskImageHelper.calculateBundleSize(at: appURL) }.value
                let minBytes = Int64(settings.minimumAppSizeMB * 1_048_576.0)
                if size < minBytes { continue }

                let prompt = PendingInstallPrompt(
                    appName: appURL.deletingPathExtension().lastPathComponent,
                    appBundleURL: appURL,
                    sizeInBytes: size,
                    source: .applicationsFolder
                )
                enqueuePrompt(prompt)
            }
        }

        await scanInstalledApplications()
    }

    // MARK: - 4) Kurulum Sorusu Penceresi Yönetimi

    func enqueuePrompt(_ prompt: PendingInstallPrompt) {
        if pendingPrompts.contains(where: { $0.appBundleURL.path == prompt.appBundleURL.path }) {
            showPromptWindowIfNeeded()
            return
        }
        pendingPrompts.append(prompt)
        showPromptWindowIfNeeded()
    }

    func dismissPrompt(_ prompt: PendingInstallPrompt, ignoreFuture: Bool = false) {
        if ignoreFuture {
            AppSettings.shared.ignoredBundleNames.insert(prompt.appBundleURL.lastPathComponent)
        }
        pendingPrompts.removeAll { $0.id == prompt.id }
        if pendingPrompts.isEmpty {
            InstallPromptPanelController.shared.close()
        }
    }

    func showPromptWindowIfNeeded() {
        guard !pendingPrompts.isEmpty else { return }
        InstallPromptPanelController.shared.showPromptWindow()
    }
}
