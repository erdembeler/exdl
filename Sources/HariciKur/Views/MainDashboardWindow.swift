import SwiftUI
import AppKit

enum DashboardTab: String, CaseIterable, Identifiable {
    case applications = "Uygulamalar"
    case mountedDMGs = "Disk İmajları"
    case settings = "Ayarlar"

    var id: String { rawValue }

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
            win.title = "HariciKur"
            win.toolbarStyle = .unified
            win.minSize = NSSize(width: 680, height: 460)
            win.contentViewController = hostingController
            win.center()
            win.isReleasedWhenClosed = false
            self.window = win
        }

        AppSettings.shared.refreshExternalDrives()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct MainDashboardView: View {
    @ObservedObject private var windowController = DashboardWindowController.shared
    @ObservedObject private var coordinator = MonitorCoordinator.shared
    @ObservedObject private var installer = AppInstallerService.shared

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $windowController.selectedTab) { tab in
                HStack {
                    Label(tab.rawValue, systemImage: tab.icon)
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

    enum AppFilter: String, CaseIterable {
        case all = "Tümü"
        case externalOnly = "Harici"
        case internalOnly = "Dahili"
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
                            Text(settings.isExternalTargetReady ? settings.selectedExternalDriveName : "Harici Disk Seçilmedi")
                                .font(.system(size: 14, weight: .semibold))

                            Spacer()

                            if let drive = settings.selectedExternalDriveInfo {
                                Text("\(drive.formattedTotal) içinde \(drive.formattedAvailable) kullanılabilir")
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
                            Text("Harici diskteki \(coordinator.externalAppsCount) uygulama sayesinde dahili SSD'de \(ByteCountFormatter.string(fromByteCount: coordinator.totalSavedInternalBytes, countStyle: .file)) yer açıldı.")
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
                        Button("Kapat") { self.alertError = nil }
                            .controlSize(.small)
                    }
                }
            }

            // 2. Uygulama Listesi (Apple Grouped Form Satırları)
            Section("Uygulamalar (\(filteredApps.count))") {
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
                                Text(app.isTargetReachable ? "\(app.targetVolumeName ?? "Harici Disk") · Kısayol" : "Disk Takılı Değil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(app.isTargetReachable ? Color.accentColor : Color.orange)
                            } else {
                                Text("Dahili Disk")
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
                            Button("Dahiliye Al…") {
                                restoreApp(app)
                            }
                            .controlSize(.small)
                            .disabled(installer.isBusy || !app.isTargetReachable)
                        } else {
                            Button("Hariciye Taşı…") {
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
        .searchable(text: $searchText, placement: .toolbar, prompt: "Ara")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Görünüm", selection: $filter) {
                    ForEach(AppFilter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
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
                .help("Yenile")
                .disabled(coordinator.isScanningApps)
            }
        }
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

    var body: some View {
        Form {
            if coordinator.mountedDMGApps.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "opticaldiscdrive")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Bağlı Disk İmajı Yok")
                            .font(.system(size: 13, weight: .medium))
                        Text("Bir .dmg dosyası açtığınızda burada listelenir ve kurulum penceresi otomatik olarak açılır.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section("Açık Disk İmajları") {
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

                            Button("Kur…") {
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
                .help("Yenile")
            }
        }
    }
}

// MARK: - SEKME 3: Ayarlar (Apple Sistem Ayarları)

struct SettingsAndPermissionsTabView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Hedef Harici Disk") {
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
                            Text("\(drive.formattedAvailable) boş · Toplam \(drive.formattedTotal)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Button("Seç") {
                                settings.externalApplicationsPath = targetPath
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }

                LabeledContent("Kurulum Klasörü") {
                    HStack(spacing: 8) {
                        Text(settings.externalApplicationsPath.isEmpty ? "Seçilmedi" : settings.externalApplicationsPath)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Seç…") {
                            selectCustomExternalFolder()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Davranış") {
                Toggle("Mac Açıldığında Otomatik Başlat", isOn: Binding(
                    get: { settings.isLaunchAtLoginEnabled },
                    set: { settings.setLaunchAtLogin(enabled: $0) }
                ))
                Toggle("Otomatik İzleme", isOn: $settings.isMonitoringEnabled)
                Toggle("DMG Açıldığında Kurulum Penceresini Göster", isOn: $settings.watchMountedDMGs)
                Toggle("Applications Klasörüne Eklenen Uygulamaları Yakala", isOn: $settings.watchApplicationsFolder)

                Picker("Minimum Uygulama Boyutu", selection: $settings.minimumAppSizeMB) {
                    Text("Tüm Uygulamalar").tag(0.0)
                    Text("100 MB ve üzeri").tag(100.0)
                    Text("250 MB ve üzeri").tag(250.0)
                    Text("500 MB ve üzeri").tag(500.0)
                    Text("1 GB ve üzeri").tag(1000.0)
                }
            }

            Section("Güncellemeler ve Temizlik") {
                Toggle("Uygulama Güncellendiğinde Kısayolu Koru", isOn: $settings.protectSymlinksOnAutoUpdate)
                if settings.protectSymlinksOnAutoUpdate {
                    Toggle("Sormadan Otomatik Harici Diske Taşı", isOn: $settings.autoMoveOnSymlinkOverwrite)
                }
                Toggle("Kurulumdan Sonra DMG Disk İmajını Çıkar", isOn: $settings.autoEjectDMGAfterInstall)
                Toggle("Kurulumdan Sonra .dmg Dosyasını Çöp Kutusu'na Taşı", isOn: $settings.moveDMGToTrashAfterInstall)
            }

            Section("İzinler") {
                LabeledContent("Uygulamalar Klasörü Erişimi") {
                    HStack(spacing: 8) {
                        let writable = AppInstallerService.hasApplicationsWriteAccess()
                        Circle()
                            .fill(writable ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(writable ? "Etkin" : "Yönetici Onayı Gerekebilir")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button("Sistem Ayarları…") {
                            AppInstallerService.openFullDiskAccessSettings()
                        }
                        .controlSize(.small)
                    }
                }

                if !settings.ignoredBundleNames.isEmpty {
                    LabeledContent("Yoksayılan Uygulamalar") {
                        Button("Sıfırla (\(settings.ignoredBundleNames.count))") {
                            settings.ignoredBundleNames.removeAll()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selectCustomExternalFolder() {
        let panel = NSOpenPanel()
        panel.title = "Harici Diskteki Uygulamalar Klasörünü Seçin"
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
