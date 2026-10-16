import Foundation
import SwiftUI
import AppKit

struct ReleaseAssetInfo: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

struct GitHubReleaseResponse: Decodable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: String?
    let assets: [ReleaseAssetInfo]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    var cleanVersion: String {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    /// Prefers the `.zip` archive for fast in-place OTA extraction, falling back to `.dmg`.
    var preferredAsset: ReleaseAssetInfo? {
        if let zip = assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
            return zip
        }
        return assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
    }
}

@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(version: String)
        case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
        case installing
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestRelease: GitHubReleaseResponse?
    @Published var automaticallyCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckForUpdates, forKey: "automaticallyCheckForUpdates")
        }
    }

    private let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/erdembeler/exdl/releases/latest")!
    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?
    private var periodicTimer: Timer?

    private override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["automaticallyCheckForUpdates": true])
        self.automaticallyCheckForUpdates = defaults.bool(forKey: "automaticallyCheckForUpdates")
        super.init()
    }

    var hasAvailableUpdate: Bool {
        guard let release = latestRelease else { return false }
        return Self.isVersion(release.cleanVersion, newerThan: AppInfo.version)
    }

    func startAutomaticChecksIfNeeded() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.automaticallyCheckForUpdates else { return }
                await self.checkForUpdates(userInitiated: false)
            }
        }

        guard automaticallyCheckForUpdates else { return }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await checkForUpdates(userInitiated: false)
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }

        state = .checking
        if userInitiated {
            UpdateWindowController.shared.showWindow()
        }

        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EXdl/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
            self.latestRelease = release

            if Self.isVersion(release.cleanVersion, newerThan: AppInfo.version) {
                state = .updateAvailable(version: release.cleanVersion)
                if !userInitiated {
                    UpdateWindowController.shared.showWindow()
                }
            } else {
                state = .upToDate(version: AppInfo.version)
            }
        } catch {
            if userInitiated {
                state = .failed(message: tr("Could not check for updates. Please check your internet connection."))
            } else {
                state = .idle
            }
        }
    }

    func downloadAndInstallUpdate() {
        guard let release = latestRelease, let asset = release.preferredAsset else {
            if let url = latestRelease?.htmlURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        downloadTask?.cancel()
        state = .downloading(progress: 0, downloadedBytes: 0, totalBytes: asset.size)

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("EXdl/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self else { return }
            if let error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                Task { @MainActor in
                    self.state = .failed(message: error.localizedDescription)
                }
                return
            }

            guard let tempURL,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                Task { @MainActor in
                    self.state = .failed(message: tr("Update download failed."))
                }
                return
            }

            // Move downloaded file before URLSession deletes the temporary location.
            let fm = FileManager.default
            let stageRoot = fm.temporaryDirectory.appendingPathComponent("EXdlUpdate_\(UUID().uuidString)", isDirectory: true)
            do {
                try fm.createDirectory(at: stageRoot, withIntermediateDirectories: true)
                let savedArchive = stageRoot.appendingPathComponent(asset.name)
                try fm.moveItem(at: tempURL, to: savedArchive)

                Task { @MainActor in
                    self.state = .installing
                    await self.installDownloadedArchive(at: savedArchive, in: stageRoot)
                }
            } catch {
                Task { @MainActor in
                    self.state = .failed(message: error.localizedDescription)
                }
            }
        }

        downloadObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor in
                guard let self else { return }
                if case .downloading = self.state {
                    self.state = .downloading(
                        progress: max(0, min(1, progress.fractionCompleted)),
                        downloadedBytes: progress.completedUnitCount,
                        totalBytes: max(progress.totalUnitCount, asset.size)
                    )
                }
            }
        }

        self.downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadObservation = nil
        if let release = latestRelease, Self.isVersion(release.cleanVersion, newerThan: AppInfo.version) {
            state = .updateAvailable(version: release.cleanVersion)
        } else {
            state = .idle
        }
    }

    private func installDownloadedArchive(at archiveURL: URL, in stageRoot: URL) async {
        do {
            let extractedAppURL = try await Task.detached(priority: .userInitiated) { () -> URL in
                let fm = FileManager.default
                let extractDir = stageRoot.appendingPathComponent("extracted", isDirectory: true)
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

                if archiveURL.pathExtension.lowercased() == "zip" {
                    let ditto = Process()
                    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    ditto.arguments = ["-x", "-k", archiveURL.path, extractDir.path]
                    try ditto.run()
                    ditto.waitUntilExit()
                    guard ditto.terminationStatus == 0 else {
                        throw NSError(domain: "EXdlUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("Could not extract the update archive.")])
                    }
                } else if archiveURL.pathExtension.lowercased() == "dmg" {
                    let mountPoint = stageRoot.appendingPathComponent("mnt", isDirectory: true)
                    try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
                    let attach = Process()
                    attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    attach.arguments = ["attach", archiveURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
                    try attach.run()
                    attach.waitUntilExit()
                    defer {
                        let detach = Process()
                        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                        detach.arguments = ["detach", mountPoint.path, "-force", "-quiet"]
                        try? detach.run()
                        detach.waitUntilExit()
                    }
                    let mountedApp = mountPoint.appendingPathComponent("EXdl.app")
                    guard fm.fileExists(atPath: mountedApp.path) else {
                        throw NSError(domain: "EXdlUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: tr("Updated application bundle was not found in the disk image.")])
                    }
                    let targetApp = extractDir.appendingPathComponent("EXdl.app")
                    try fm.copyItem(at: mountedApp, to: targetApp)
                }

                let appCandidate = extractDir.appendingPathComponent("EXdl.app")
                guard fm.fileExists(atPath: appCandidate.path) else {
                    throw NSError(domain: "EXdlUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: tr("Updated application bundle was not found.")])
                }

                // Clear quarantine attributes and verify signature integrity.
                let xattr = Process()
                xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattr.arguments = ["-cr", appCandidate.path]
                try? xattr.run()
                xattr.waitUntilExit()

                let verify = Process()
                verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                verify.arguments = ["--verify", "--deep", "--strict", appCandidate.path]
                try verify.run()
                verify.waitUntilExit()
                guard verify.terminationStatus == 0 else {
                    throw NSError(domain: "EXdlUpdate", code: 4, userInfo: [NSLocalizedDescriptionKey: tr("The downloaded update failed code signature verification.")])
                }

                return appCandidate
            }.value

            // Determine install destination (/Applications/EXdl.app if running from Applications, otherwise current bundle path)
            let currentBundlePath = Bundle.main.bundleURL.path
            let destinationPath = currentBundlePath.hasSuffix(".app") ? currentBundlePath : "/Applications/EXdl.app"
            let currentPID = ProcessInfo.processInfo.processIdentifier

            let escapedSrc = extractedAppURL.path.replacingOccurrences(of: "'", with: "'\\''")
            let escapedDst = destinationPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedStage = stageRoot.path.replacingOccurrences(of: "'", with: "'\\''")

            let relaunchScript = """
            while kill -0 \(currentPID) 2>/dev/null; do
                sleep 0.1
            done
            rm -rf '\(escapedDst)'
            mv '\(escapedSrc)' '\(escapedDst)'
            rm -rf '\(escapedStage)'
            open '\(escapedDst)'
            """

            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/zsh")
            updater.arguments = ["-c", relaunchScript]
            try updater.run()

            NSApp.terminate(nil)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - Native Software Update Window

@MainActor
final class UpdateWindowController: NSObject {
    static let shared = UpdateWindowController()

    private var window: NSWindow?

    func showWindow() {
        if window == nil {
            let view = SoftwareUpdateView { [weak self] in
                self?.window?.close()
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = tr("Software Update")
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.contentViewController = NSHostingController(rootView: view)
            win.center()
            AppPresence.track(win)
            self.window = win
        }

        AppPresence.windowWillShow()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct SoftwareUpdateView: View {
    @ObservedObject private var updater = UpdateService.shared
    @ObservedObject private var language = LanguageManager.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headerTitle)
                        .font(.system(size: 16, weight: .semibold))

                    Text(headerSubtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let notes = updater.latestRelease?.body,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               updater.hasAvailableUpdate {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Release Notes"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }

            if case let .downloading(progress, downloaded, total) = updater.state {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(tr("Downloading update…"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else if case .installing = updater.state {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tr("Installing update and restarting EXdl…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if case .checking = updater.state {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tr("Checking for updates…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Toggle(tr("Check for updates automatically"), isOn: $updater.automaticallyCheckForUpdates)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                actionButtons
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .frame(width: 460, height: updater.hasAvailableUpdate ? 320 : 210)
        .background(VisualEffectSurface())
    }

    private var headerTitle: String {
        switch updater.state {
        case .checking:
            return tr("Checking for Updates…")
        case .upToDate:
            return tr("EXdl is up to date")
        case let .updateAvailable(version):
            return tr("EXdl {version} is available", ["version": version])
        case .downloading:
            return tr("Downloading EXdl Update")
        case .installing:
            return tr("Installing Update")
        case .failed:
            return tr("Update Check Failed")
        case .idle:
            return tr("Software Update")
        }
    }

    private var headerSubtitle: String {
        switch updater.state {
        case .checking:
            return tr("Contacting GitHub Releases to check for a newer version.")
        case let .upToDate(version):
            return tr("EXdl {version} is currently the newest version available.", ["version": version])
        case let .updateAvailable(version):
            return tr("You currently have version {current}. Would you like to download and install version {new} now?", ["current": AppInfo.version, "new": version])
        case .downloading:
            return tr("EXdl will automatically restart once the update is installed.")
        case .installing:
            return tr("Replacing application bundle and restarting…")
        case let .failed(message):
            return message
        case .idle:
            return tr("Current version: {version}", ["version": AppInfo.version])
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch updater.state {
        case .updateAvailable:
            Button(tr("Later")) {
                onClose()
            }
            .controlSize(.regular)

            Button(tr("Update & Restart")) {
                updater.downloadAndInstallUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)

        case .downloading:
            Button(tr("Cancel")) {
                updater.cancelDownload()
            }
            .controlSize(.regular)

        case .installing, .checking:
            Button(tr("Close")) {
                onClose()
            }
            .disabled(updater.state == .installing)
            .controlSize(.regular)

        case .failed:
            Button(tr("Close")) {
                onClose()
            }
            .controlSize(.regular)

            Button(tr("Try Again")) {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

        case .upToDate, .idle:
            Button(tr("OK")) {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
    }
}
