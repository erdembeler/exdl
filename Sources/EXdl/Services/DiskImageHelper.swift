import Foundation

enum DiskImageHelper {
    /// `hdiutil info -plist` çalıştırarak şu an bağlı (mount edilmiş) olan DMG disk imajlarını
    /// [MountNoktası ("/Volumes/App") : KaynakDMGDosyası ("/Users/.../Downloads/App.dmg")] olarak döndürür.
    static func mountedDMGMap() -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let images = plist["images"] as? [[String: Any]] else {
                return [:]
            }

            var result: [String: String] = [:]
            for image in images {
                let imagePath = (image["image-path"] as? String) ?? ""
                guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
                for entity in entities {
                    if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                        result[mountPoint] = imagePath
                    }
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    /// Verilen bir DMG mount dizini içindeki .app paketlerini bulur
    static func findAppsInVolume(at volumeURL: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumeURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var foundApps: [URL] = []
        for itemURL in contents {
            guard itemURL.pathExtension.lowercased() == "app" else { continue }
            if isSymbolicLink(at: itemURL) { continue }
            foundApps.append(itemURL)
        }
        return foundApps
    }

    /// Bir URL'in POSIX sembolik link (ln -s) olup olmadığını kontrol eder
    static func isSymbolicLink(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileType = attrs[.type] as? FileAttributeType else {
            return false
        }
        return fileType == .typeSymbolicLink
    }

    /// Bir .app paketinin EXdl tarafından oluşturulmuş Akıllı Kısayol Paketi (Smart App Stub)
    /// VEYA POSIX sembolik link olup olmadığını kontrol eder.
    static func isExternalAppLink(at url: URL) -> Bool {
        if isSymbolicLink(at: url) {
            if let dest = externalTargetURL(for: url), dest.path.hasPrefix("/Volumes/") {
                return true
            }
            // /Applications/Safari.app -> ../System/... gibi sistem symlinklerini hariç tut
            return false
        }
        return stubTargetURL(for: url) != nil
    }

    /// EXdl Smart App Stub (.app) içindeki Info.plist'ten hedef harici disk yolunu okur
    static func stubTargetURL(for url: URL) -> URL? {
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let targetPath = (plist["EXdlTargetAppPath"] as? String) ?? (plist["HariciKurTargetAppPath"] as? String),
              !targetPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: targetPath)
    }

    /// Hem Smart App Stub hem de POSIX symlink için işaret edilen gerçek harici disk hedef URL'sini döndürür
    static func externalTargetURL(for url: URL) -> URL? {
        if let stubTarget = stubTargetURL(for: url) {
            return stubTarget
        }
        guard isSymbolicLink(at: url),
              let destPath = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        if destPath.hasPrefix("/") {
            return URL(fileURLWithPath: destPath)
        } else {
            return url.deletingLastPathComponent().appendingPathComponent(destPath).standardizedFileURL
        }
    }

    /// Bir .app paketinin toplam disk boyutunu (Byte) hesaplar (Stub/Symlink ise harici diskteki gerçek boyutu ölçer)
    static func calculateBundleSize(at bundleURL: URL) -> Int64 {
        let targetURL: URL
        if let extDest = externalTargetURL(for: bundleURL) {
            targetURL = extDest
        } else {
            targetURL = bundleURL
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return 0
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: targetURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                totalBytes += Int64(allocated)
            } else if let size = values.fileSize {
                totalBytes += Int64(size)
            }
        }
        return totalBytes
    }

    /// Finder bir .app paketini /Applications klasörüne kopyalarken kopyalamanın bitmesini bekler
    static func waitForCopyCompletion(at appURL: URL) async -> Bool {
        var previousSize: Int64 = -1
        var stableCount = 0

        for _ in 0..<120 {
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                return false
            }

            let currentSize = calculateBundleSize(at: appURL)
            let infoPlistPath = appURL.appendingPathComponent("Contents/Info.plist").path
            let hasInfoPlist = FileManager.default.fileExists(atPath: infoPlistPath)

            if currentSize > 0 && currentSize == previousSize && hasInfoPlist {
                stableCount += 1
                if stableCount >= 2 {
                    return true
                }
            } else {
                stableCount = 0
            }

            previousSize = currentSize
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return FileManager.default.fileExists(atPath: appURL.path)
    }

    // MARK: - Harici Disk Uyumluluk Denetimi (Incompatible App Filtering)

    /// EXdl'in kendisi ve macOS sistem kripteks kısayolları (Safari vb.) uygulama listesinde hiç gösterilmez.
    static func shouldHideFromAppList(at bundleURL: URL) -> Bool {
        let name = bundleURL.deletingPathExtension().lastPathComponent
        let lowerName = name.lowercased()
        if bundleURL.path.hasPrefix("/System/") || lowerName == "safari" || lowerName == "exdl" || lowerName == "haricikur" {
            return true
        }
        if isSymbolicLink(at: bundleURL) && !isExternalAppLink(at: bundleURL) {
            return true
        }
        return false
    }

    /// Harici diske taşındığında (ve /Applications içinde vekil paket bırakıldığında) sorun çıkaracak
    /// uygulamaları tespit eder ve nedenini döndürür. Uygun (taşınabilir) uygulamalar için `nil` döner.
    static func incompatibilityReason(for bundleURL: URL) -> String? {
        if shouldHideFromAppList(at: bundleURL) {
            return tr("Requires internal disk")
        }

        // Zaten harici diskte olan bir uygulama ise geri alınabilmesi için engelleme
        if isExternalAppLink(at: bundleURL) {
            return nil
        }

        let fm = FileManager.default
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")

        var bundleID = ""
        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            bundleID = (plist["CFBundleIdentifier"] as? String)?.lowercased() ?? ""
        }

        let lowerName = bundleURL.deletingPathExtension().lastPathComponent.lowercased()

        // 1. Xcode ve Geliştirici Araç Zinciri (xcode-select, xcrun, simctl, CoreSimulator /Applications/Xcode.app yolunu zorunlu kılar)
        if bundleID == "com.apple.dt.xcode"
            || lowerName == "xcode"
            || lowerName.hasPrefix("xcode-")
            || fm.fileExists(atPath: contentsURL.appendingPathComponent("Developer").path) {
            return tr("Developer toolchain requires internal disk")
        }

        // 2. Apple Sistem ve App Store Araçları (com.apple.*)
        if bundleID.hasPrefix("com.apple.") {
            return tr("Apple system app requires internal disk")
        }

        // 3. macOS Sistem Uzantıları (SystemExtensions / DriverKit / NetworkExtension)
        // macOS sysextd yalnızca dahili /Applications dizinindeki sistem uzantılarını yükler.
        let sysExtURL = contentsURL.appendingPathComponent("Library/SystemExtensions", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(atPath: sysExtURL.path), !items.isEmpty {
            return tr("Contains macOS System Extension")
        }

        let kextURL = contentsURL.appendingPathComponent("Library/Extensions", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(atPath: kextURL.path), !items.isEmpty {
            return tr("Contains system kernel extension")
        }

        // 4. Yetkili Arka Plan Servisleri (SMJobBless / LaunchServices / Daemons)
        let launchServicesURL = contentsURL.appendingPathComponent("Library/LaunchServices", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(atPath: launchServicesURL.path), !items.isEmpty {
            return tr("Contains privileged background service")
        }

        // 5. Gömülü Oturum Açılışı Servisleri (LoginItems) ve Donanım/Sanallaştırma Sürücüleri
        let loginItemsURL = contentsURL.appendingPathComponent("Library/LoginItems", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(atPath: loginItemsURL.path), !items.isEmpty {
            return tr("Contains background login service")
        }

        let internalOnlyPrefixes: [String] = [
            "com.docker.",
            "org.pqrs.karabiner",
            "pro.betterdisplay.",
            "com.nuebling.mac-mouse-fix",
            "com.if.amphetamine",
            "com.1password.",
            "com.agilebits.",
            "com.raycast.",
            "com.runningwithcrayons.alfred",
            "at.obdev.littlesnitch",
            "com.objective-see.",
            "com.rogueamoeba.",
            "io.tailscale.",
            "com.wireguard.",
            "com.cloudflare.1dot1dot1dot1",
            "com.parallels.desktop",
            "com.vmware.fusion",
            "org.virtualbox.app"
        ]
        if internalOnlyPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
            return tr("System service requires internal disk")
        }

        return nil
    }
}
