import Foundation
import AppKit

enum TriggerSource: Equatable {
    /// Yaklaşım 2: DMG bağlandığı (mount olduğu) anda yakalandı
    case mountedDMG(volumeURL: URL, dmgImagePath: String?)
    /// Yaklaşım 1: /Applications klasörüne yeni bir uygulama sürüklendi/kopyalandı
    case applicationsFolder
    /// Püf Nokta 2: Daha önce harici diskte olan bir uygulama güncellenirken kısayol üzerine gerçek klasör yazıldı
    case symlinkOverwrittenByUpdate(expectedExternalURL: URL)

    var subtitleText: String {
        switch self {
        case .mountedDMG(let volURL, _):
            return tr("{volume} disk image", ["volume": volURL.lastPathComponent])
        case .applicationsFolder:
            return tr("Added to the Applications folder")
        case .symlinkOverwrittenByUpdate:
            return tr("Update detected · Launcher will be restored")
        }
    }
}

struct PendingInstallPrompt: Identifiable, Equatable {
    let id: UUID
    let appName: String
    let appVersion: String?
    let appBundleURL: URL
    let sizeInBytes: Int64
    let source: TriggerSource
    let detectedAt: Date
    let icon: NSImage

    init(
        id: UUID = UUID(),
        appName: String,
        appVersion: String? = nil,
        appBundleURL: URL,
        sizeInBytes: Int64,
        source: TriggerSource,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.appName = appName
        self.appVersion = appVersion ?? Self.readVersion(from: appBundleURL)
        self.appBundleURL = appBundleURL
        self.sizeInBytes = sizeInBytes
        self.source = source
        self.detectedAt = detectedAt
        self.icon = NSWorkspace.shared.icon(forFile: appBundleURL.path)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    private static func readVersion(from bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        if let shortVer = dict["CFBundleShortVersionString"] as? String, !shortVer.isEmpty {
            return shortVer
        }
        if let ver = dict["CFBundleVersion"] as? String, !ver.isEmpty {
            return ver
        }
        return nil
    }
}

struct InstalledAppInfo: Identifiable, Equatable {
    var id: String { bundleURL.path }
    let name: String
    let version: String?
    let bundleURL: URL
    let sizeInBytes: Int64
    let isSymlink: Bool
    let symlinkTargetURL: URL?
    let isTargetReachable: Bool
    let isSystemApp: Bool
    let icon: NSImage

    init(
        name: String,
        version: String?,
        bundleURL: URL,
        sizeInBytes: Int64,
        isSymlink: Bool,
        symlinkTargetURL: URL?,
        isTargetReachable: Bool,
        isSystemApp: Bool
    ) {
        self.name = name
        self.version = version
        self.bundleURL = bundleURL
        self.sizeInBytes = sizeInBytes
        self.isSymlink = isSymlink
        self.symlinkTargetURL = symlinkTargetURL
        self.isTargetReachable = isTargetReachable
        self.isSystemApp = isSystemApp

        if isSymlink, let target = symlinkTargetURL, isTargetReachable {
            self.icon = NSWorkspace.shared.icon(forFile: target.path)
        } else {
            self.icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
    }

    var formattedSize: String {
        if isSymlink && !isTargetReachable {
            return tr("Drive Not Connected")
        }
        return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var targetVolumeName: String? {
        guard let target = symlinkTargetURL else { return nil }
        let components = target.pathComponents
        if components.count >= 3 && components[1] == "Volumes" {
            return components[2]
        }
        return nil
    }
}

struct ExternalDriveInfo: Identifiable, Equatable, Hashable {
    var id: String { volumeURL.path }
    let name: String
    let volumeURL: URL
    let availableBytes: Int64
    let totalBytes: Int64
    let icon: NSImage

    init(
        name: String,
        volumeURL: URL,
        availableBytes: Int64,
        totalBytes: Int64
    ) {
        self.name = name
        self.volumeURL = volumeURL
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
        self.icon = NSWorkspace.shared.icon(forFile: volumeURL.path)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ExternalDriveInfo, rhs: ExternalDriveInfo) -> Bool {
        lhs.id == rhs.id && lhs.availableBytes == rhs.availableBytes && lhs.totalBytes == rhs.totalBytes
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        let used = max(0, totalBytes - availableBytes)
        return Double(used) / Double(totalBytes)
    }

    var defaultApplicationsFolderURL: URL {
        volumeURL.appendingPathComponent("Applications", isDirectory: true)
    }
}

struct ActivityLogItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let detail: String
    let isSuccess: Bool
}
