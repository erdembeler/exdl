import SwiftUI
import AppKit

// MARK: - Persistent Onboarding State

enum OnboardingState {
    private static let completedKey = "onboardingCompleted"
    private static let currentPageKey = "onboardingCurrentPage"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static var savedPage: OnboardingPage {
        let raw = UserDefaults.standard.integer(forKey: currentPageKey)
        return OnboardingPage(rawValue: raw) ?? .welcome
    }

    static func savePage(_ page: OnboardingPage) {
        UserDefaults.standard.set(page.rawValue, forKey: currentPageKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: currentPageKey)
    }

    static func resetForReplay() {
        UserDefaults.standard.set(OnboardingPage.welcome.rawValue, forKey: currentPageKey)
    }
}

enum OnboardingPage: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case drive = 2
    case done = 3
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage {
        didSet {
            OnboardingState.savePage(page)
        }
    }

    init() {
        self.page = OnboardingState.savedPage
    }

    var isFirstPage: Bool { page == .welcome }
    var isLastPage: Bool { page == .done }

    func next() {
        guard let following = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = following }
    }

    func back() {
        guard let previous = OnboardingPage(rawValue: page.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = previous }
    }
}

// MARK: - Window Controller

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private let model = OnboardingModel()

    /// Opens the setup assistant. When `restart` is true, starts from the first step.
    /// When the app restarts after granting a macOS permission, `restart` is false and the window
    /// automatically resumes on the saved step (e.g. `.permissions`).
    func show(restart: Bool = false) {
        if restart {
            OnboardingState.resetForReplay()
            model.page = .welcome
        } else {
            model.page = OnboardingState.savedPage
        }

        if window == nil {
            let view = OnboardingView(model: model) { [weak self] openDashboard in
                self?.completeOnboarding(openDashboard: openDashboard)
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 590),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "EXdl"
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.contentViewController = NSHostingController(rootView: view)
            win.delegate = self
            win.center()
            AppPresence.track(win)
            window = win
        }

        AppSettings.shared.refreshExternalDrives()
        AppSettings.shared.refreshLaunchAtLogin()
        AppPresence.windowWillShow()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func completeOnboarding(openDashboard: Bool) {
        OnboardingState.markCompleted()
        LanguageManager.shared.commitCurrentLanguage()
        window?.close()
        if openDashboard {
            DashboardWindowController.shared.showWindow(selectedTab: .applications)
        }
    }

    // IMPORTANT: Do NOT mark onboarding completed in `windowWillClose`.
    // When macOS restarts the app ("Quit & Reopen") after toggling a permission in System Settings,
    // AppKit closes open windows during termination. Keeping `isCompleted == false` ensures EXdl
    // reopens right back on the Permissions step after the restart!
    func windowWillClose(_ notification: Notification) {
        LanguageManager.shared.commitCurrentLanguage()
    }
}

// MARK: - Root Setup Assistant View

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var language = LanguageManager.shared
    let onFinish: (_ openDashboard: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageContent
                    .id("\(model.page.rawValue)-\(language.language.rawValue)")
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 12)

            Divider()
            footer
        }
        .frame(width: 640, height: 590)
        .background(VisualEffectSurface())
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.page {
        case .welcome:
            WelcomeSetupPage()
        case .permissions:
            PermissionsSetupPage()
        case .drive:
            DriveAndPreferencesPage()
        case .done:
            SetupCompletedPage()
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Group {
                if !model.isLastPage {
                    Button(tr("Skip Setup")) {
                        onFinish(false)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 7) {
                ForEach(OnboardingPage.allCases, id: \.self) { page in
                    Circle()
                        .fill(page == model.page ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if !model.isFirstPage {
                    Button(tr("Back")) {
                        model.back()
                    }
                    .controlSize(.large)
                }

                if model.isLastPage {
                    Button(tr("Start Using EXdl")) {
                        onFinish(true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("Continue")) {
                        LanguageManager.shared.commitCurrentLanguage()
                        model.next()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 210, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Shared Apple-Style Building Blocks

private struct SetupPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.3)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 490)
        }
    }
}

private struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
    }
}

private struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct PermissionStatusBadge: View {
    let isGranted: Bool
    let grantedText: String
    let pendingText: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isGranted ? grantedText : pendingText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isGranted ? Color.primary.opacity(0.85) : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((isGranted ? Color.green : Color.orange).opacity(0.12))
        )
    }
}

// MARK: - Step 1: Welcome & Dynamic Language Selection

private struct WelcomeSetupPage: View {
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(spacing: 20) {
            // Top bar: native language selector that updates the entire UI immediately
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { language.language },
                        set: { language.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.nativeName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            AppIconImage(size: 76)

            SetupPageHeader(
                title: tr("Welcome to EXdl"),
                subtitle: tr("Install and manage large macOS applications on your external drive while keeping them in Launchpad and Spotlight.")
            )

            GroupedCard {
                FeatureRow(
                    symbol: "opticaldiscdrive",
                    title: tr("Automatic Disk Image Detection"),
                    description: tr("When you open a .dmg file, EXdl presents a drag-and-drop window targeting your external drive directly.")
                )
                Divider().padding(.leading, 56)
                FeatureRow(
                    symbol: "app.badge.checkmark",
                    title: tr("Smart Application Launchers"),
                    description: tr("Full application bundles live on your external SSD while a lightweight ~500 KB launcher stays in /Applications for Spotlight and Launchpad.")
                )
                Divider().padding(.leading, 56)
                FeatureRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: tr("Update Protection & Storage Manager"),
                    description: tr("Automatically keeps external links intact across app updates and lets you move existing apps with one click.")
                )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Step 2: Permissions

private struct PermissionsSetupPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared

    @State private var hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var body: some View {
        VStack(spacing: 16) {
            SetupPageHeader(
                title: tr("System Permissions"),
                subtitle: tr("EXdl needs permission from macOS to manage application bundles in /Applications and access external drives without repeated prompts.")
            )

            GroupedCard {
                // 1. App Management
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(tr("1. App Management"))
                            .font(.system(size: 13.5, weight: .semibold))
                        RecommendedBadge()
                        Spacer()
                        PermissionStatusBadge(
                            isGranted: hasAppManagement,
                            grantedText: tr("Granted"),
                            pendingText: tr("Required")
                        )
                    }

                    Text(tr("Allows EXdl to create launchers and replace app bundles inside /Applications."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        Text(tr("In System Settings, switch EXdl on. If EXdl is not listed yet, click the “+” button at the bottom left and add EXdl from Applications."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Button(tr("Open App Management…")) {
                            Permissions.openAppManagementSettings()
                            refreshStatusesAfterDelay()
                        }
                        .controlSize(.small)

                        Button(tr("Show EXdl in Finder")) {
                            Permissions.revealAppInFinder()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                .padding(14)

                Divider()

                // 2. Full Disk Access
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(tr("2. Full Disk Access"))
                            .font(.system(size: 13.5, weight: .semibold))
                        RecommendedBadge()
                        Spacer()
                        PermissionStatusBadge(
                            isGranted: hasFullDiskAccess,
                            grantedText: tr("Granted"),
                            pendingText: tr("Not granted")
                        )
                    }

                    Text(tr("Prevents repeated permission prompts when reading disk images from Downloads and copying apps to external drives."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        Text(tr("If EXdl is not in the Full Disk Access list, click the “+” button at the bottom left and select EXdl from Applications."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Button(tr("Open Full Disk Access…")) {
                            Permissions.openFullDiskAccessSettings()
                        }
                        .controlSize(.small)

                        Button(tr("Show EXdl in Finder")) {
                            Permissions.revealAppInFinder()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                .padding(14)

                if !settings.isRunningFromApplications {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("EXdl location"))
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(tr("EXdl is running from {path}. Move it into /Applications so permissions and login items work reliably.", ["path": Bundle.main.bundlePath]))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                }
            }

            // Reassuring note about macOS "Quit & Reopen" behavior
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(tr("When macOS asks to “Quit & Reopen” after enabling a permission, confirm it. EXdl will reopen right back on this step so you can complete both permissions."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .onAppear {
            // Trigger TCC registration probe so macOS lists EXdl in App Management automatically
            DispatchQueue.global(qos: .userInitiated).async {
                let appMgmt = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: true)
                let fda = Permissions.hasFullDiskAccess
                DispatchQueue.main.async {
                    self.hasAppManagement = appMgmt
                    self.hasFullDiskAccess = fda
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatuses()
        }
    }

    private func refreshStatuses() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
    }

    private func refreshStatusesAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshStatuses()
        }
    }
}

// MARK: - Step 3: External Drive & Automation Preferences

private struct DriveAndPreferencesPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            SetupPageHeader(
                title: tr("External Drive & Automation"),
                subtitle: tr("Select the external drive where applications will be stored and configure automatic monitoring.")
            )

            GroupedCard {
                if settings.availableExternalDrives.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("No external drive found"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(tr("Connect an external SSD or drive to select it as your installation target."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            settings.refreshExternalDrives()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }
                    .padding(14)
                } else {
                    ForEach(Array(settings.availableExternalDrives.enumerated()), id: \.element.id) { index, drive in
                        if index > 0 { Divider().padding(.leading, 54) }
                        DriveSelectionRow(
                            drive: drive,
                            isSelected: settings.externalApplicationsPath == drive.defaultApplicationsFolderURL.path
                        ) {
                            settings.externalApplicationsPath = drive.defaultApplicationsFolderURL.path
                        }
                    }
                }

                Divider()

                HStack {
                    Text(settings.externalApplicationsPath.isEmpty
                         ? tr("Not selected yet")
                         : tr("Install folder: {path}", ["path": settings.externalApplicationsPath]))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(tr("Choose Folder…")) { chooseFolder() }
                        .controlSize(.small)
                    Button {
                        settings.refreshExternalDrives()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(tr("Refresh"))
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }

            GroupedCard {
                VStack(alignment: .leading, spacing: 4) {
                    LaunchAtLoginRow(showsRecommendation: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().padding(.leading, 14)

                PreferenceToggleRow(
                    title: tr("Show Install Window When a Disk Image Opens"),
                    caption: tr("Automatically detects mounted .dmg files and offers to install on your external drive."),
                    isOn: $settings.watchMountedDMGs
                )

                Divider().padding(.leading, 14)

                PreferenceToggleRow(
                    title: tr("Keep Launcher When an App Updates"),
                    caption: tr("Restores the external launcher automatically if an app update overwrites /Applications."),
                    isOn: $settings.protectSymlinksOnAutoUpdate
                )

                Divider().padding(.leading, 14)

                PreferenceToggleRow(
                    title: tr("Eject Disk Image After Install"),
                    caption: tr("Unmounts the .dmg volume automatically after installation finishes."),
                    isOn: $settings.autoEjectDMGAfterInstall
                )
            }

            Spacer(minLength: 0)
        }
        .onAppear { settings.refreshExternalDrives() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose the Applications Folder on Your External Drive")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url {
            settings.externalApplicationsPath = url.path
        }
    }
}

private struct DriveSelectionRow: View {
    let drive: ExternalDriveInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: drive.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(drive.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(tr("{free} free · {total} total", ["free": drive.formattedAvailable, "total": drive.formattedTotal]))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Step 4: Setup Complete (Restrained Apple Design)

private struct SetupCompletedPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updater = UpdateService.shared
    @ObservedObject private var language = LanguageManager.shared

    @State private var hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            AppIconImage(size: 72)

            SetupPageHeader(
                title: tr("Setup Complete"),
                subtitle: tr("EXdl is now active in the macOS menu bar. Open any .dmg file to install directly onto your external drive.")
            )

            GroupedCard {
                SummaryRow(
                    symbol: "externaldrive.fill",
                    title: tr("External drive"),
                    value: settings.isExternalTargetReady ? settings.selectedExternalDriveName : tr("Not selected yet")
                )
                Divider().padding(.leading, 48)
                SummaryRow(
                    symbol: "lock.shield",
                    title: tr("Permissions"),
                    value: permissionsSummaryText
                )
                Divider().padding(.leading, 48)
                SummaryRow(
                    symbol: "power",
                    title: tr("Launch at Login"),
                    value: launchAtLoginSummary
                )
                Divider().padding(.leading, 48)
                SummaryRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: tr("Automatic Updates"),
                    value: updater.automaticallyCheckForUpdates ? tr("On") : tr("Off")
                )
            }

            // Subtle menu bar indicator hint
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(tr("You can access EXdl anytime from the drive icon in the top-right menu bar."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            hasAppManagement = Permissions.checkAppManagementAccess(triggerPromptIfUndetermined: false)
            hasFullDiskAccess = Permissions.hasFullDiskAccess
        }
    }

    private var permissionsSummaryText: String {
        if hasAppManagement && hasFullDiskAccess {
            return tr("All granted")
        } else if hasAppManagement || hasFullDiskAccess {
            return tr("Partially granted")
        } else {
            return tr("Can be enabled in Settings")
        }
    }

    private var launchAtLoginSummary: String {
        switch settings.launchAtLoginStatus {
        case .enabled: return tr("On")
        case .requiresApproval: return tr("Waiting for approval")
        case .disabled, .unavailable: return tr("Off")
        }
    }
}

private struct SummaryRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
