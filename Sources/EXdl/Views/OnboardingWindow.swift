import SwiftUI
import AppKit

// MARK: - State

enum OnboardingState {
    private static let completedKey = "onboardingCompleted"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}

enum OnboardingPage: Int, CaseIterable {
    case language
    case welcome
    case tour
    case settings
    case permissions
    case drive
    case done
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage = .language

    var isFirstPage: Bool { page == .language }
    var isLastPage: Bool { page == .done }

    func next() {
        guard let following = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { page = following }
    }

    func back() {
        guard let previous = OnboardingPage(rawValue: page.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { page = previous }
    }
}

// MARK: - Window

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private let model = OnboardingModel()

    /// Opens the guide. `restart` jumps back to the beginning (skipping the language step once a language is stored).
    func show(restart: Bool = false) {
        if restart || window == nil {
            model.page = Localizer.hasStoredChoice ? .welcome : .language
        }

        if window == nil {
            let view = OnboardingView(model: model) { [weak self] openDashboard in
                self?.finish(openDashboard: openDashboard)
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
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

    private func finish(openDashboard: Bool) {
        window?.close()
        if openDashboard {
            DashboardWindowController.shared.showWindow(selectedTab: .applications)
        }
    }

    // Closing the window (red button, Finish or Skip) all count as "seen it".
    func windowWillClose(_ notification: Notification) {
        OnboardingState.markCompleted()
        LanguageManager.shared.commitCurrentLanguage()
    }
}

// MARK: - Root view

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var language = LanguageManager.shared
    let onFinish: (_ openDashboard: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageContent
                    .id(model.page)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 24)),
                        removal: .opacity
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 52)
            .padding(.top, 46)
            .padding(.bottom, 8)

            Divider()
            footer
        }
        .frame(width: 640, height: 580)
        .background(VisualEffectSurface())
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.page {
        case .language: LanguagePage()
        case .welcome: WelcomePage()
        case .tour: TourPage()
        case .settings: RecommendedSettingsPage(openSettings: openSettings)
        case .permissions: PermissionsPage()
        case .drive: DrivePage()
        case .done: DonePage(openDashboard: { onFinish(true) })
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Group {
                if model.page != .language && !model.isLastPage {
                    Button(tr("Skip Guide")) { onFinish(false) }
                        .buttonStyle(.link)
                        .foregroundStyle(.secondary)
                } else {
                    // `Color.clear` alone would grow vertically and squeeze the page above.
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 110, alignment: .leading)

            Spacer()

            HStack(spacing: 7) {
                ForEach(OnboardingPage.allCases, id: \.self) { page in
                    Circle()
                        .fill(page == model.page ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if !model.isFirstPage && !model.isLastPage {
                    Button(tr("Back")) { model.back() }
                        .controlSize(.large)
                }

                if model.isLastPage {
                    Button(tr("Finish")) { onFinish(false) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(model.isFirstPage ? "Continue · Devam" : tr("Continue")) { model.next() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func openSettings() {
        DashboardWindowController.shared.showWindow(selectedTab: .settings)
    }
}

// MARK: - Shared pieces

private struct PageHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 470)
            }
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
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct StatusChip: View {
    let isGood: Bool
    let goodText: String
    let badText: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGood ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isGood ? goodText : badText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 1. Language

private struct LanguagePage: View {
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            AppIconImage(size: 96)

            // Both languages on purpose: this is the screen that picks the language.
            VStack(spacing: 6) {
                Text("Choose your language")
                    .font(.system(size: 26, weight: .bold))
                Text("Dilinizi seçin")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(AppLanguage.allCases) { option in
                    LanguageCard(
                        language: option,
                        isSelected: language.language == option
                    ) {
                        language.setLanguage(option)
                    }
                }
            }

            Text("You can change this at any time in Settings.\nBunu istediğiniz zaman Ayarlar'dan değiştirebilirsiniz.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
    }
}

private struct LanguageCard: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(language.rawValue.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08)))

                Text(language.nativeName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 190, height: 112)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. Welcome

private struct WelcomePage: View {
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            AppIconImage(size: 96)

            PageHeader(
                title: tr("Thanks for downloading EXdl"),
                subtitle: tr("EXdl is free and open source. If it saves you disk space, please take a moment to star the project on GitHub. It is the best way to support it and it helps other people find it.")
            )

            Button {
                NSWorkspace.shared.open(AppInfo.repositoryURL)
            } label: {
                Label(tr("Star on GitHub"), systemImage: "star.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
            }
            .buttonStyle(StarButtonStyle())

            Text(tr("It takes a second, and it means a lot."))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
    }
}

private struct StarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(0.85))
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0.25), Color(red: 1.0, green: 0.70, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.1).opacity(0.35), radius: configuration.isPressed ? 2 : 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 3. Tour

private struct TourPage: View {
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(spacing: 24) {
            PageHeader(
                title: tr("How EXdl works"),
                subtitle: tr("Three steps, and your internal disk stays free.")
            )

            Card {
                TourStep(
                    number: 1,
                    symbol: "opticaldiscdrive",
                    title: tr("Open a disk image"),
                    text: tr("EXdl notices the .dmg and shows an install window.")
                )
                Divider().padding(.leading, 70)
                TourStep(
                    number: 2,
                    symbol: "hand.draw",
                    title: tr("Drag the app onto your drive"),
                    text: tr("The app is copied to your external drive instead of filling the internal one.")
                )
                Divider().padding(.leading, 70)
                TourStep(
                    number: 3,
                    symbol: "app.badge.checkmark",
                    title: tr("Open it like any other app"),
                    text: tr("A tiny launcher stays in Applications, so Launchpad and Spotlight still find it. If the drive is unplugged, EXdl tells you.")
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                Text(tr("EXdl lives in the menu bar. Look for the drive icon at the top of your screen."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 0)
        }
    }
}

private struct TourStep: View {
    let number: Int
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)")
                    .font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - 4. Recommended settings

private struct RecommendedSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: tr("Recommended settings"),
                subtitle: tr("These switches live in Settings → Behavior. Here are the ones we suggest turning on.")
            )

            Card {
                VStack(alignment: .leading, spacing: 4) {
                    LaunchAtLoginRow(showsRecommendation: true)
                    caption(tr("EXdl keeps watching in the menu bar after every restart, so you never miss a disk image."))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                RecommendedToggle(
                    title: tr("Show Install Window When a Disk Image Opens"),
                    caption: tr("Open a .dmg and EXdl offers to put the app on your external drive."),
                    isOn: $settings.watchMountedDMGs
                )
                Divider().padding(.leading, 16)

                RecommendedToggle(
                    title: tr("Catch Apps Added to Applications"),
                    caption: tr("Apps installed the usual way can be moved to your drive afterwards."),
                    isOn: $settings.watchApplicationsFolder
                )
                Divider().padding(.leading, 16)

                RecommendedToggle(
                    title: tr("Keep Launcher When an App Updates"),
                    caption: tr("If an update brings the app back to the internal disk, EXdl offers to move it again."),
                    isOn: $settings.protectSymlinksOnAutoUpdate
                )
                Divider().padding(.leading, 16)

                RecommendedToggle(
                    title: tr("Eject Disk Image After Install"),
                    caption: tr("Keeps your desktop tidy once the app has been copied."),
                    isOn: $settings.autoEjectDMGAfterInstall
                )
            }

            Button(tr("Open Settings…")) { openSettings() }
                .controlSize(.regular)

            Spacer(minLength: 0)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RecommendedToggle: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 8) {
                    Text(title)
                    if !isOn { RecommendedBadge() }
                }
            }
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 5. Permissions

private struct PermissionsPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: tr("Permissions"),
                subtitle: tr("EXdl moves apps in and out of /Applications. macOS protects those apps, so EXdl needs your permission.")
            )

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(tr("App Management"), systemImage: "app.badge.checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        RecommendedBadge()
                        Spacer()
                    }
                    Text(tr("Lets EXdl update and replace apps in /Applications. macOS also asks the first time EXdl moves an app: choose Allow."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tr("Open Privacy & Security → App Management and switch EXdl on."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tr("Open App Management…")) {
                        Permissions.openAppManagementSettings()
                    }
                    .controlSize(.regular)
                }
                .padding(16)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(tr("Full Disk Access"), systemImage: "lock.open.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        StatusChip(isGood: hasFullDiskAccess, goodText: tr("Granted"), badText: tr("Not granted"))
                    }
                    Text(tr("Optional. Saves you the extra prompts for Downloads, Desktop, Documents and external drives."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tr("Open Full Disk Access…")) {
                        Permissions.openFullDiskAccessSettings()
                    }
                    .controlSize(.regular)
                }
                .padding(16)

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: settings.isRunningFromApplications ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.isRunningFromApplications ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("EXdl location"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(settings.isRunningFromApplications
                             ? tr("EXdl is in your Applications folder.")
                             : tr("EXdl is running from {path}. Drag it into the Applications folder and open it from there, so launch at login works.", ["path": Bundle.main.bundlePath]))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }

            Spacer(minLength: 0)
        }
        .onAppear { hasFullDiskAccess = Permissions.hasFullDiskAccess }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess
        }
    }
}

// MARK: - 6. Drive

private struct DrivePage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: tr("Choose your external drive"),
                subtitle: tr("Apps you install with EXdl are stored here. You can change it later in Settings.")
            )

            Card {
                if settings.availableExternalDrives.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(tr("No external drive found"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(tr("Plug in a drive and it shows up here."))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(settings.availableExternalDrives.enumerated()), id: \.element.id) { index, drive in
                        if index > 0 { Divider().padding(.leading, 60) }
                        DriveRow(
                            drive: drive,
                            isSelected: settings.externalApplicationsPath == drive.defaultApplicationsFolderURL.path
                        ) {
                            settings.externalApplicationsPath = drive.defaultApplicationsFolderURL.path
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(tr("Choose Another Folder…")) { chooseFolder() }
                Button {
                    settings.refreshExternalDrives()
                } label: {
                    Label(tr("Refresh"), systemImage: "arrow.clockwise")
                }
            }

            if !settings.externalApplicationsPath.isEmpty {
                Text(tr("Install folder: {path}", ["path": settings.externalApplicationsPath]))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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

private struct DriveRow: View {
    let drive: ExternalDriveInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(nsImage: drive.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(tr("{free} free · {total} total", ["free": drive.formattedAvailable, "total": drive.formattedTotal]))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 7. Done

private struct DonePage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var language = LanguageManager.shared
    let openDashboard: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.green)
                .shadow(color: Color.green.opacity(0.3), radius: 12, y: 4)

            PageHeader(
                title: tr("You're all set"),
                subtitle: tr("EXdl now waits quietly in the menu bar. Open a disk image whenever you want to install an app.")
            )

            Card {
                SummaryRow(
                    symbol: "globe",
                    title: tr("Language"),
                    value: language.language.nativeName
                )
                Divider().padding(.leading, 52)
                SummaryRow(
                    symbol: "externaldrive.fill",
                    title: tr("External drive"),
                    value: settings.isExternalTargetReady ? settings.selectedExternalDriveName : tr("Not selected yet")
                )
                Divider().padding(.leading, 52)
                SummaryRow(
                    symbol: "power",
                    title: tr("Launch at Login"),
                    value: launchAtLoginSummary
                )
            }

            Button(tr("Open EXdl")) { openDashboard() }
                .controlSize(.large)

            Spacer(minLength: 0)
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
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13.5))
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
