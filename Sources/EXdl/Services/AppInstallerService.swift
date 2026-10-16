import Foundation
import AppKit

enum AppInstallError: LocalizedError {
    case externalDriveNotConfigured
    case externalDriveNotConnected(String)
    case sourceAppNotFound(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .externalDriveNotConfigured:
            return tr("No external drive or folder has been chosen yet. Pick a target drive in Settings.")
        case .externalDriveNotConnected(let path):
            return tr("The selected external drive is not connected ({path}). Please connect it.", ["path": path])
        case .sourceAppNotFound(let path):
            return tr("The source app could not be found: {path}", ["path": path])
        case .operationFailed(let reason):
            return tr("The operation failed: {reason}", ["reason": reason])
        }
    }
}

@MainActor
final class AppInstallerService: ObservableObject {
    static let shared = AppInstallerService()

    /// Kendi yaptığımız dosya işlemleri sırasında FSEvents'in tekrar tetiklenmesini önlemek için kullanılan kilit listesi
    private(set) var activeOperations: Set<String> = []

    @Published var isBusy: Bool = false
    @Published var statusMessage: String = ""

    private init() {}

    func isAppBeingOperatedOn(_ bundleName: String) -> Bool {
        activeOperations.contains(bundleName)
    }

    /// 1) DMG'den doğrudan Harici Diske kurar ve /Applications içine Akıllı Kısayol Paketi (Smart App Stub) oluşturur (Yaklaşım 2)
    func installFromDMGToExternal(
        appBundleURL: URL,
        volumeURL: URL,
        dmgImagePath: String?
    ) async throws {
        let settings = AppSettings.shared
        guard let externalAppsDir = settings.externalApplicationsURL else {
            throw AppInstallError.externalDriveNotConfigured
        }
        guard settings.isExternalTargetReady else {
            throw AppInstallError.externalDriveNotConnected(externalAppsDir.path)
        }
        guard FileManager.default.fileExists(atPath: appBundleURL.path) else {
            throw AppInstallError.sourceAppNotFound(appBundleURL.path)
        }

        let bundleName = appBundleURL.lastPathComponent
        activeOperations.insert(bundleName)
        isBusy = true
        statusMessage = tr("Copying {app} to the external drive…", ["app": bundleName])

        defer {
            isBusy = false
            statusMessage = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.activeOperations.remove(bundleName)
            }
        }

        let destinationExternalAppURL = externalAppsDir.appendingPathComponent(bundleName)
        let internalStubURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleName)

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default

            if !fm.fileExists(atPath: externalAppsDir.path) {
                try fm.createDirectory(at: externalAppsDir, withIntermediateDirectories: true)
            }

            // Doğrudan DMG'den harici diske kopyala
            try Self.copyReplacing(from: appBundleURL, to: destinationExternalAppURL, useAdminFallback: false)

            // Dahili /Applications klasörüne macOS Apps.app / Launchpad / Spotlight uyumlu Akıllı Kısayol Paketi oluştur
            try Self.createSmartAppStubInApplications(
                stubURL: internalStubURL,
                destinationURL: destinationExternalAppURL
            )
        }.value

        settings.registerManagedSymlink(
            appBundleName: bundleName,
            externalDestinationPath: destinationExternalAppURL.path
        )
        settings.logActivity(
            tr("{app} installed on the external drive", ["app": bundleName]),
            detail: tr("Disk image → {path} (launcher: /Applications/{app})", ["path": destinationExternalAppURL.path, "app": bundleName])
        )

        if settings.autoEjectDMGAfterInstall {
            statusMessage = tr("Ejecting the disk image…")
            await ejectDMGAndOptionallyTrash(volumeURL: volumeURL, dmgImagePath: dmgImagePath)
        }
    }

    /// 2) DMG'den Dahili Diske (/Applications) normal kurulum yapar
    func installFromDMGToInternal(
        appBundleURL: URL,
        volumeURL: URL,
        dmgImagePath: String?
    ) async throws {
        let settings = AppSettings.shared
        let bundleName = appBundleURL.lastPathComponent
        let internalAppURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleName)

        activeOperations.insert(bundleName)
        isBusy = true
        statusMessage = tr("Copying {app} to the internal disk (/Applications)…", ["app": bundleName])

        defer {
            isBusy = false
            statusMessage = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.activeOperations.remove(bundleName)
            }
        }

        try await Task.detached(priority: .userInitiated) {
            try Self.copyReplacing(from: appBundleURL, to: internalAppURL, useAdminFallback: true)
        }.value

        settings.unregisterManagedSymlink(appBundleName: bundleName)
        settings.logActivity(
            tr("{app} installed on the internal disk", ["app": bundleName]),
            detail: "/Applications/\(bundleName)"
        )

        if settings.autoEjectDMGAfterInstall {
            await ejectDMGAndOptionallyTrash(volumeURL: volumeURL, dmgImagePath: dmgImagePath)
        }
    }

    /// 3) /Applications içindeki mevcut bir uygulamayı Harici Diske taşır ve yerine Akıllı Kısayol Paketi bırakır
    func moveInternalAppToExternal(appBundleURL: URL) async throws {
        let settings = AppSettings.shared
        guard let externalAppsDir = settings.externalApplicationsURL else {
            throw AppInstallError.externalDriveNotConfigured
        }
        guard settings.isExternalTargetReady else {
            throw AppInstallError.externalDriveNotConnected(externalAppsDir.path)
        }
        guard FileManager.default.fileExists(atPath: appBundleURL.path) else {
            throw AppInstallError.sourceAppNotFound(appBundleURL.path)
        }

        let bundleName = appBundleURL.lastPathComponent
        activeOperations.insert(bundleName)
        isBusy = true
        statusMessage = tr("Moving {app} to the external drive and creating a launcher…", ["app": bundleName])

        defer {
            isBusy = false
            statusMessage = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.activeOperations.remove(bundleName)
            }
        }

        let destinationExternalAppURL = externalAppsDir.appendingPathComponent(bundleName)
        let internalStubURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleName)

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: externalAppsDir.path) {
                try fm.createDirectory(at: externalAppsDir, withIntermediateDirectories: true)
            }

            // Önce harici diske tam kopyala
            try Self.copyReplacing(from: appBundleURL, to: destinationExternalAppURL, useAdminFallback: false)

            // Kopyalama başarılıysa dahili diskteki asıl klasörü sil ve yerine Akıllı Kısayol Paketi koy
            try Self.createSmartAppStubInApplications(
                stubURL: internalStubURL,
                destinationURL: destinationExternalAppURL
            )
        }.value

        settings.registerManagedSymlink(
            appBundleName: bundleName,
            externalDestinationPath: destinationExternalAppURL.path
        )
        settings.logActivity(
            tr("{app} moved to the external drive", ["app": bundleName]),
            detail: tr("Destination: {path}", ["path": destinationExternalAppURL.path])
        )
    }

    /// 4) Harici diskte olan bir uygulamayı tekrar Dahili Diske (/Applications) geri alır
    func restoreExternalAppToInternal(appInfo: InstalledAppInfo) async throws {
        guard appInfo.isSymlink, let externalTargetURL = appInfo.symlinkTargetURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: externalTargetURL.path) else {
            throw AppInstallError.externalDriveNotConnected(externalTargetURL.path)
        }

        let bundleName = appInfo.bundleURL.lastPathComponent
        let internalAppURL = appInfo.bundleURL

        activeOperations.insert(bundleName)
        isBusy = true
        statusMessage = tr("Moving {app} back to the internal disk…", ["app": bundleName])

        defer {
            isBusy = false
            statusMessage = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.activeOperations.remove(bundleName)
            }
        }

        try await Task.detached(priority: .userInitiated) {
            try Self.copyReplacing(from: externalTargetURL, to: internalAppURL, useAdminFallback: true)
            try? FileManager.default.removeItem(at: externalTargetURL)
            Self.registerAndIndexApp(at: internalAppURL)
        }.value

        AppSettings.shared.unregisterManagedSymlink(appBundleName: bundleName)
        AppSettings.shared.logActivity(
            tr("{app} restored to the internal disk", ["app": bundleName]),
            detail: tr("/Applications/{app} now lives on the internal disk.", ["app": bundleName])
        )
    }

    /// Eski POSIX symlink'leri (ln -s) macOS 26 Apps.app / Launchpad'de görünmesi için otomatik olarak Akıllı Kısayol Paketine yükseltir
    func upgradeLegacySymlinkIfNeeded(at appURL: URL, externalTargetURL: URL) async {
        let bundleName = appURL.lastPathComponent
        activeOperations.insert(bundleName)
        defer {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.activeOperations.remove(bundleName)
            }
        }

        try? await Task.detached(priority: .utility) {
            try Self.createSmartAppStubInApplications(stubURL: appURL, destinationURL: externalTargetURL)
        }.value
    }

    // MARK: - Yardımcı Sistem İşlemleri

    private func ejectDMGAndOptionallyTrash(volumeURL: URL, dmgImagePath: String?) async {
        let shouldTrash = AppSettings.shared.moveDMGToTrashAfterInstall
        do {
            try await Task.detached {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
            }.value

            if shouldTrash, let dmgPath = dmgImagePath, !dmgPath.isEmpty {
                let dmgURL = URL(fileURLWithPath: dmgPath)
                if FileManager.default.fileExists(atPath: dmgURL.path) {
                    do {
                        try FileManager.default.trashItem(at: dmgURL, resultingItemURL: nil)
                        AppSettings.shared.logActivity(
                            tr("Disk image removed"),
                            detail: tr("{file} was moved to the Trash.", ["file": dmgURL.lastPathComponent])
                        )
                    } catch {
                        AppSettings.shared.logActivity(
                            tr("Could not move the disk image to the Trash"),
                            detail: error.localizedDescription,
                            isSuccess: false
                        )
                    }
                }
            }
        } catch {
            AppSettings.shared.logActivity(
                tr("Could not eject the disk image"),
                detail: error.localizedDescription,
                isSuccess: false
            )
        }
    }

    nonisolated private static func runDittoCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [sourceURL.path, destinationURL.path]
        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? tr("Copy failed")
            throw AppInstallError.operationFailed(errMsg)
        }
    }

    /// macOS 26 Apps.app, Launchpad, Spotlight ve Finder'ın %100 gerçek bir uygulama olarak gördüğü,
    /// orijinal ikona sahip ~50 KB boyutunda imzalı bir Akıllı Kısayol Paketi (.app stub) oluşturur.
    nonisolated static func createSmartAppStubInApplications(stubURL: URL, destinationURL: URL) throws {
        let fm = FileManager.default

        // 1. Önce hedef uygulamanın Info.plist dosyasını oku
        let sourceContentsURL = destinationURL.appendingPathComponent("Contents")
        let sourceInfoPlistURL = sourceContentsURL.appendingPathComponent("Info.plist")
        let sourceResourcesURL = sourceContentsURL.appendingPathComponent("Resources")

        guard let plistData = try? Data(contentsOf: sourceInfoPlistURL),
              var infoDict = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any] else {
            throw AppInstallError.operationFailed(tr("The app's Info.plist could not be read."))
        }

        // 3. Geçici dizinde Smart App Stub paketini hazırla
        // (The existing app in /Applications is only replaced at the very end, so nothing is lost if a step here fails.)
        let tempStubURL = fm.temporaryDirectory.appendingPathComponent("EXdlStub_\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: tempStubURL) }
        let stubContentsURL = tempStubURL.appendingPathComponent("Contents", isDirectory: true)
        let stubMacOSURL = stubContentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let stubResourcesURL = stubContentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fm.createDirectory(at: stubMacOSURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: stubResourcesURL, withIntermediateDirectories: true)

        // 4. Uygulamanın ikon dosyalarını (.icns ve Assets.car) Resources içine kopyala
        if let resourceItems = try? fm.contentsOfDirectory(at: sourceResourcesURL, includingPropertiesForKeys: nil) {
            for item in resourceItems {
                let ext = item.pathExtension.lowercased()
                let name = item.lastPathComponent
                if ext == "icns" || name == "Assets.car" {
                    let destIcon = stubResourcesURL.appendingPathComponent(name)
                    try? fm.copyItem(at: item, to: destIcon)
                }
            }
        }
        // Eğer CFBundleIconFile alt klasördeyse (örn. images/Icon.icns) onu da koru
        if let iconFile = infoDict["CFBundleIconFile"] as? String, !iconFile.isEmpty {
            let iconRelative = iconFile.hasSuffix(".icns") ? iconFile : "\(iconFile).icns"
            let srcIconURL = sourceResourcesURL.appendingPathComponent(iconRelative)
            let dstIconURL = stubResourcesURL.appendingPathComponent(iconRelative)
            if fm.fileExists(atPath: srcIconURL.path) && !fm.fileExists(atPath: dstIconURL.path) {
                try? fm.createDirectory(at: dstIconURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: srcIconURL, to: dstIconURL)
            }
        }

        // 5. Info.plist değerlerini vekil paket için yapılandır
        let originalBundleID = (infoDict["CFBundleIdentifier"] as? String) ?? "app.\(stubURL.deletingPathExtension().lastPathComponent)"
        let launcherName = "EXdlStubLauncher"

        infoDict["CFBundleExecutable"] = launcherName
        infoDict["CFBundleIdentifier"] = "com.erdem.exdl.stub.\(originalBundleID)"
        infoDict["CFBundlePackageType"] = "APPL"
        infoDict["EXdlIsStub"] = true
        infoDict["EXdlTargetAppPath"] = destinationURL.path
        infoDict["HariciKurTargetAppPath"] = destinationURL.path
        infoDict["EXdlOriginalBundleIdentifier"] = originalBundleID
        infoDict.removeValue(forKey: "NSPrincipalClass")
        infoDict.removeValue(forKey: "LSEnvironment")

        let updatedPlistData = try PropertyListSerialization.data(
            fromPropertyList: infoDict,
            format: .xml,
            options: 0
        )
        try updatedPlistData.write(to: stubContentsURL.appendingPathComponent("Info.plist"))

        // 6. Başlatıcı (Launcher) Mach-O binary'sini kopyala veya oluştur
        let stubExecutableURL = stubMacOSURL.appendingPathComponent(launcherName)
        let bundledLauncherURL = Bundle.main.url(forResource: "EXdlStubLauncher", withExtension: nil)
            ?? Bundle.main.url(forResource: "HariciKurStubLauncher", withExtension: nil)
        if let bundledLauncherURL = bundledLauncherURL,
           fm.fileExists(atPath: bundledLauncherURL.path) {
            try fm.copyItem(at: bundledLauncherURL, to: stubExecutableURL)
        } else {
            // Yedek olarak hızlı zsh başlatıcı betiği yaz
            // Text lands inside an AppleScript string that sits inside a single-quoted shell string.
            func escaped(_ text: String) -> String {
                text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "'", with: "'\\''")
            }
            let escapedTarget = destinationURL.path.replacingOccurrences(of: "\"", with: "\\\"")
            let appTitle = stubURL.deletingPathExtension().lastPathComponent
            let alertTitle = escaped(tr("External Drive Not Connected"))
            let alertMessage = escaped(tr(
                "{app} is installed on your external drive ({path}).\n\nConnect the drive to your Mac to open it.",
                ["app": appTitle, "path": destinationURL.path]
            ))
            let script = """
            #!/bin/zsh
            TARGET="\(escapedTarget)"
            if [ -d "$TARGET" ]; then
                /usr/bin/open -a "$TARGET" "$@"
            else
                /usr/bin/osascript -e 'display alert "\(alertTitle)" message "\(alertMessage)" as warning'
            fi
            """
            try script.write(to: stubExecutableURL, atomically: true, encoding: .utf8)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubExecutableURL.path)

        // 7. Paketi imzala (macOS Gatekeeper ve Apps.app uyumluluğu için)
        let signProc = Process()
        signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProc.arguments = ["--force", "--deep", "--sign", "-", tempStubURL.path]
        try? signProc.run()
        signProc.waitUntilExit()

        // 8. Eski klasörü veya symlink'i temizle ve /Applications içine taşı
        if fm.fileExists(atPath: stubURL.path) || DiskImageHelper.isSymbolicLink(at: stubURL) {
            try removeItemWithFallback(at: stubURL)
        }
        try moveItem(from: tempStubURL, to: stubURL, useAdminFallback: true)

        // 9. LaunchServices ve Spotlight (Apps.app) indeksini anında güncelle
        registerAndIndexApp(at: stubURL)
    }

    nonisolated static func registerAndIndexApp(at appURL: URL) {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregisterPath) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: lsregisterPath)
            proc.arguments = ["-f", appURL.path]
            try? proc.run()
            proc.waitUntilExit()
        }

        // Spotlight (ve macOS 26 Apps.app) indeksine hemen ekle
        let mdimportProc = Process()
        mdimportProc.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        mdimportProc.arguments = [appURL.path]
        try? mdimportProc.run()
    }

    nonisolated private static func removeItemWithFallback(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
            try runAdminShellCommand("/bin/rm -rf '\(escaped)'")
        }
    }

    nonisolated private static func moveItem(from source: URL, to destination: URL, useAdminFallback: Bool) throws {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            guard useAdminFallback else { throw error }
            let escapedSource = source.path.replacingOccurrences(of: "'", with: "'\\''")
            let escapedDestination = destination.path.replacingOccurrences(of: "'", with: "'\\''")
            try runAdminShellCommand("/bin/rm -rf '\(escapedDestination)' && /bin/mv '\(escapedSource)' '\(escapedDestination)'")
        }
    }

    /// Copies `source` next to `destination` under a temporary name and swaps it in only after the copy
    /// succeeded, so a failed or interrupted copy never destroys the item that is already there.
    nonisolated private static func copyReplacing(from source: URL, to destination: URL, useAdminFallback: Bool) throws {
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".exdl-\(UUID().uuidString).tmp")
        do {
            try runDittoCopy(from: source, to: temporary)
            if fm.fileExists(atPath: destination.path) || DiskImageHelper.isSymbolicLink(at: destination) {
                if useAdminFallback {
                    try removeItemWithFallback(at: destination)
                } else {
                    try fm.removeItem(at: destination)
                }
            }
            try moveItem(from: temporary, to: destination, useAdminFallback: useAdminFallback)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    nonisolated private static func runAdminShellCommand(_ command: String) throws {
        let appleScriptSource = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptSource]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            var errStr = String(data: errData, encoding: .utf8) ?? tr("Administrator permission was denied.")
            if errStr.localizedCaseInsensitiveContains("not permitted") {
                errStr += "\n" + tr("macOS blocked the change. Allow EXdl under System Settings → Privacy & Security → App Management, then try again.")
            }
            throw AppInstallError.operationFailed(errStr)
        }
    }
}
