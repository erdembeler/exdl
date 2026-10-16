import SwiftUI
import AppKit

enum DashboardTab: String, CaseIterable, Identifiable {
    case applications
    case mountedDMGs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: return tr("Apps")
        case .mountedDMGs: return tr("Disk Images")
        case .settings: return tr("Settings")
        }
    }

    var icon: String {
        switch self {
        case .applications: return "app.badge.checkmark"
        case .mountedDMGs: return "opticaldiscdrive"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class DashboardWindowController: ObservableObject {
    static let shared = DashboardWindowController()

    @Published var selectedTab: DashboardTab = .applications
    private var window: NSWindow?

    private init() {}

    func showWindow(selectedTab: DashboardTab? = nil) {
        if let selectedTab {
            self.selectedTab = selectedTab
        }

        if window == nil {
            let contentView = MainDashboardView()
            let hostingController = NSHostingController(rootView: contentView)

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "EXdl"
            win.toolbarStyle = .unified
            win.minSize = NSSize(width: 680, height: 460)
            win.contentViewController = hostingController
            // The hosting controller shrinks the window to the SwiftUI minimum; ask for the intended size.
            win.setContentSize(NSSize(width: 780, height: 540))
            win.center()
            win.isReleasedWhenClosed = false
            AppPresence.track(win)
            self.window = win
        }

        AppSettings.shared.refreshExternalDrives()
        AppPresence.windowWillShow()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct MainDashboardView: View {
    @ObservedObject private var windowController = DashboardWindowController.shared
    @ObservedObject private var coordinator = MonitorCoordinator.shared
    @ObservedObject private var installer = AppInstallerService.shared
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $windowController.selectedTab) { tab in
                HStack {
                    Label(tab.title, systemImage: tab.icon)
                    Spacer()
                    if tab == .mountedDMGs && !coordinator.mountedDMGApps.isEmpty {
                        Text("\(coordinator.mountedDMGApps.count)")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 185, ideal: 200, max: 220)
        } detail: {
            Group {
                switch windowController.selectedTab {
                case .applications:
                    ApplicationsManagerTabView()
                case .mountedDMGs:
                    MountedDMGsTabView()
                case .settings:
                    SettingsAndPermissionsTabView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if installer.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(installer.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) { Divider() }
                }
            }
        }
    }
}

// MARK: - SEKME 1: Uygulamalar (Apple Sistem Ayarları > Depolama Stili)

struct ApplicationsManagerTabView: View {
    @ObservedObject private var coordinator = MonitorCoordinator.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var installer = AppInstallerService.shared
    @ObservedObject private var language = LanguageManager.shared

    enum AppFilter: CaseIterable {
        case all
        case externalOnly
        case internalOnly

        var title: String {
            switch self {
            case .all: return tr("All")
            case .externalOnly: return tr("External")
            case .internalOnly: return tr("Internal")
            }
        }
    }

    @State private var filter: AppFilter = .all
    @State private var searchText: String = ""
    @State private var alertError: String?

    private var filteredApps: [InstalledAppInfo] {
        coordinator.installedApps.filter { app in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .externalOnly: matchesFilter = app.isSymlink
            case .internalOnly: matchesFilter = !app.isSymlink
            }
            let matchesSearch = searchText.isEmpty || app.name.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        Form {
            // 1. Apple Sistem Ayarları > Depolama Başlık Kartı
            Section {
                HStack(spacing: 14) {
                    let driveIcon = settings.selectedExternalDriveInfo?.icon ?? NSWorkspace.shared.icon(forFile: "/Volumes")
                    Image(nsImage: driveIcon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(settings.isExternalTargetReady ? settings.selectedExternalDriveName : tr("No External Drive Selected"))
                                .font(.system(size: 14, weight: .semibold))

                            Spacer()

                            if let drive = settings.selectedExternalDriveInfo {
                                Text(tr("{free} available of {total}", ["free": drive.formattedAvailable, "total": drive.formattedTotal]))
                                    .font(.system(size: 11.5).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let drive = settings.selectedExternalDriveInfo, drive.totalBytes > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: max(8, geo.size.width * drive.usedPercentage))
                                }
                            }
                            .frame(height: 8)
                        }

                        HStack {
                            Text(savedSpaceText)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let alertError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(alertError)
                            .font(.caption)
                        Spacer()
                        Button(tr("Dismiss")) { self.alertError = nil }
                            .controlSize(.small)
                    }
                }
            }

            // 2. Uygulama Listesi (Apple Grouped Form Satırları)
            Section(tr("Apps ({count})", ["count": String(filteredApps.count)])) {
                ForEach(filteredApps) { app in
                    HStack(spacing: 12) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))

                            if app.isSymlink {
                                Text(app.isTargetReachable
                                     ? tr("{drive} · Launcher", ["drive": app.targetVolumeName ?? tr("External Drive")])
                                     : tr("Drive Not Connected"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(app.isTargetReachable ? Color.accentColor : Color.orange)
                            } else {
                                Text(tr("Internal Disk"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(app.formattedSize)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)

                        if app.isSymlink {
                            Button(tr("Move to Internal…")) {
                                restoreApp(app)
                            }
                            .controlSize(.small)
                            .disabled(installer.isBusy || !app.isTargetReachable)
                        } else {
                            Button(tr("Move to External…")) {
                                moveAppToExternal(app)
                            }
                            .controlSize(.small)
                            .disabled(installer.isBusy || !settings.isExternalTargetReady || app.isSystemApp)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
        .searchable(text: $searchText, placement: .toolbar, prompt: tr("Search"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(tr("View"), selection: $filter) {
                    ForEach(AppFilter.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await coordinator.scanInstalledApplications() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("Refresh"))
                .disabled(coordinator.isScanningApps)
            }
        }
    }

    private var savedSpaceText: String {
        let count = coordinator.externalAppsCount
        let size = ByteCountFormatter.string(fromByteCount: coordinator.totalSavedInternalBytes, countStyle: .file)
        if count == 1 {
            return tr("1 app on your external drive frees up {size} on the internal SSD.", ["size": size])
        }
        return tr("{count} apps on your external drive free up {size} on the internal SSD.", ["count": String(count), "size": size])
    }

    private func moveAppToExternal(_ app: InstalledAppInfo) {
        alertError = nil
        Task {
            do {
                try await installer.moveInternalAppToExternal(appBundleURL: app.bundleURL)
                await coordinator.scanInstalledApplications()
            } catch {
                alertError = error.localizedDescription
            }
        }
    }

    private func restoreApp(_ app: InstalledAppInfo) {
        alertError = nil
        Task {
            do {
                try await installer.restoreExternalAppToInternal(appInfo: app)
                await coordinator.scanInstalledApplications()
            } catch {
                alertError = error.localizedDescription
            }
        }
    }
}

// MARK: - SEKME 2: Açık DMG İmajları

struct MountedDMGsTabView: View {
    @ObservedObject private var coordinator = MonitorCoordinator.shared
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        Form {
            if coordinator.mountedDMGApps.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "opticaldiscdrive")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(tr("No Disk Images Mounted"))
                            .font(.system(size: 13, weight: .medium))
                        Text(tr("When you open a .dmg file it is listed here and the install window opens automatically."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section(tr("Mounted Disk Images")) {
                    ForEach(coordinator.mountedDMGApps) { dmgApp in
                        HStack(spacing: 12) {
                            Image(nsImage: dmgApp.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(dmgApp.appName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(dmgApp.source.subtitleText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(dmgApp.formattedSize)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)

                            Button(tr("Install…")) {
                                coordinator.enqueuePrompt(dmgApp)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    coordinator.refreshMountedDMGs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("Refresh"))
            }
        }
    }
}

// MARK: - SEKME 3: Ayarlar (Apple Sistem Ayarları)

struct SettingsAndPermissionsTabView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updater = UpdateService.shared
    @ObservedObject private var language = LanguageManager.shared

    @State private var hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var body: some View {
        Form {
            Section(tr("Target External Drive")) {
                ForEach(settings.availableExternalDrives) { drive in
                    let targetPath = drive.defaultApplicationsFolderURL.path
                    let isSelected = settings.externalApplicationsPath == targetPath
                    HStack(spacing: 12) {
                        Image(nsImage: drive.icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(drive.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(tr("{free} free · {total} total", ["free": drive.formattedAvailable, "total": drive.formattedTotal]))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Button(tr("Select")) {
                                settings.externalApplicationsPath = targetPath
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }

                LabeledContent(tr("Install Folder")) {
                    HStack(spacing: 8) {
                        Text(settings.externalApplicationsPath.isEmpty ? tr("Not selected") : settings.externalApplicationsPath)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(tr("Choose…")) {
                            selectCustomExternalFolder()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section(tr("Behavior")) {
                LaunchAtLoginRow(showsRecommendation: false)

                Toggle(tr("Automatic Monitoring"), isOn: $settings.isMonitoringEnabled)

                // These only act while monitoring is on, so they are greyed out otherwise.
                Group {
                    Toggle(tr("Show Install Window When a Disk Image Opens"), isOn: $settings.watchMountedDMGs)
                    Toggle(tr("Catch Apps Added to Applications"), isOn: $settings.watchApplicationsFolder)

                    Picker(tr("Minimum App Size"), selection: $settings.minimumAppSizeMB) {
                        Text(tr("All Apps")).tag(0.0)
                        Text(tr("{size} and larger", ["size": "100 MB"])).tag(100.0)
                        Text(tr("{size} and larger", ["size": "250 MB"])).tag(250.0)
                        Text(tr("{size} and larger", ["size": "500 MB"])).tag(500.0)
                        Text(tr("{size} and larger", ["size": "1 GB"])).tag(1000.0)
                    }
                }
                .disabled(!settings.isMonitoringEnabled)

                if !settings.isMonitoringEnabled {
                    Text(tr("Turn on Automatic Monitoring to use these options."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(tr("Updates and Cleanup")) {
                Toggle(tr("Keep Launcher When an App Updates"), isOn: $settings.protectSymlinksOnAutoUpdate)
                    .disabled(!settings.isMonitoringEnabled)
                if settings.protectSymlinksOnAutoUpdate {
                    Toggle(tr("Move to External Drive Without Asking"), isOn: $settings.autoMoveOnSymlinkOverwrite)
                        .disabled(!settings.isMonitoringEnabled)
                }
                Toggle(tr("Eject Disk Image After Install"), isOn: $settings.autoEjectDMGAfterInstall)
                Toggle(tr("Move .dmg File to Trash After Install"), isOn: $settings.moveDMGToTrashAfterInstall)
                    .disabled(!settings.autoEjectDMGAfterInstall)
                if !settings.autoEjectDMGAfterInstall {
                    Text(tr("The .dmg file can only be moved to the Trash after the disk image has been ejected."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(tr("Permissions")) {
                LabeledContent(tr("App Management")) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hasAppManagement ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(hasAppManagement ? tr("Granted") : tr("Not granted"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button(tr("System Settings…")) {
                            Permissions.openAppManagementSettings()
                        }
                        .controlSize(.small)
                    }
                }

                LabeledContent(tr("Full Disk Access")) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hasFullDiskAccess ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(hasFullDiskAccess ? tr("Granted") : tr("Not granted"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button(tr("System Settings…")) {
                            Permissions.openFullDiskAccessSettings()
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    Text(tr("If EXdl is not listed in System Settings, click the “+” button at the bottom left and select EXdl from Applications."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Show EXdl in Finder")) {
                        Permissions.revealAppInFinder()
                    }
                    .controlSize(.small)
                }

                if !settings.ignoredBundleNames.isEmpty {
                    LabeledContent(tr("Ignored Apps")) {
                        Button(tr("Reset ({count})", ["count": String(settings.ignoredBundleNames.count)])) {
                            settings.ignoredBundleNames.removeAll()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section(tr("Language")) {
                Picker(tr("Interface Language"), selection: Binding(
                    get: { language.language },
                    set: { language.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.nativeName).tag(option)
                    }
                }
            }

            Section(tr("About EXdl")) {
                LabeledContent(tr("Version")) {
                    HStack(spacing: 10) {
                        Text(AppInfo.version)
                            .foregroundStyle(.secondary)
                        Button(tr("Check for Updates…")) {
                            Task { await updater.checkForUpdates(userInitiated: true) }
                        }
                        .controlSize(.small)
                    }
                }

                Toggle(tr("Check for updates automatically"), isOn: $updater.automaticallyCheckForUpdates)

                LabeledContent(tr("Setup Assistant")) {
                    Button(tr("Open Setup Assistant…")) {
                        OnboardingWindowController.shared.show(restart: true)
                    }
                    .controlSize(.small)
                }

                LabeledContent(tr("Source Code & Support")) {
                    HStack(spacing: 8) {
                        Button(tr("GitHub Repository")) {
                            NSWorkspace.shared.open(AppInfo.repositoryURL)
                        }
                        .controlSize(.small)

                        Button(tr("Report an Issue")) {
                            NSWorkspace.shared.open(AppInfo.issuesURL)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasFullDiskAccess = Permissions.hasFullDiskAccess
            hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
            settings.refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess
            hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
        }
    }

    private func selectCustomExternalFolder() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose the Applications Folder on Your External Drive")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")

        if panel.runModal() == .OK, let selectedURL = panel.url {
            settings.externalApplicationsPath = selectedURL.path
        }
    }
}

/// The "Launch at Login" switch with the explanation macOS needs the user to see:
/// pending approval, errors and the Applications-folder requirement.
struct LaunchAtLoginRow: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared

    /// Adds a "Recommended" hint while the switch is off (used by the first-run guide).
    let showsRecommendation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { settings.isLaunchAtLoginEnabled },
                set: { settings.setLaunchAtLogin(enabled: $0) }
            )) {
                HStack(spacing: 8) {
                    Text(tr("Launch at Login"))
                    if showsRecommendation && !settings.isLaunchAtLoginEnabled {
                        RecommendedBadge()
                    }
                }
            }

            if settings.launchAtLoginStatus == .requiresApproval {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(tr("macOS needs your approval: turn EXdl on in System Settings → General → Login Items."))
                        .font(.caption)
                    Spacer()
                    Button(tr("Open Login Items")) {
                        settings.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                }
            } else if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !settings.isRunningFromApplications {
                Text(tr("Move EXdl to the Applications folder first, otherwise macOS may not start it at login."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct RecommendedBadge: View {
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        Text(tr("Recommended"))
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
            .foregroundStyle(Color.accentColor)
    }
}
