import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class InstallPromptPanelController {
    static let shared = InstallPromptPanelController()
    private var window: NSWindow?

    func showPromptWindow() {
        if window == nil {
            let contentView = InstallPromptView()
            let hostingController = NSHostingController(rootView: contentView)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 390),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "EXdl"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            // Panels hide when their app is not active, and macOS often refuses to activate an
            // app that was started by a background event (a disk image being opened in Finder).
            panel.hidesOnDeactivate = false
            // KRİTİK: İkonu sürüklerken pencerenin kendisinin sürüklenmemesi için false olmalı!
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = hostingController
            panel.center()
            self.window = panel
        }

        AppSettings.shared.refreshExternalDrives()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.orderOut(nil)
    }
}

struct InstallPromptView: View {
    @ObservedObject private var coordinator = MonitorCoordinator.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var installer = AppInstallerService.shared
    @ObservedObject private var language = LanguageManager.shared

    enum DropDestination: Equatable {
        case external
        case internalDrive
    }

    @State private var selectedTarget: DropDestination = .external

    // Sürükle-bırak (Drag & Drop) durum değişkenleri
    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingApp: Bool = false
    @State private var hoveredDestination: DropDestination? = nil
    @State private var externalDropFrame: CGRect = .zero
    @State private var internalDropFrame: CGRect = .zero

    // Finder'dan dış sürükleme (External Drop) durumu
    @State private var isExternalFinderHoveringExt: Bool = false
    @State private var isExternalFinderHoveringInt: Bool = false

    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let prompt = coordinator.pendingPrompts.first {
                promptContent(for: prompt)
            } else {
                // The window is only shown for a real pending install; nothing to draw otherwise.
                Color.clear
            }
        }
        .frame(width: 500)
        .background(VisualEffectSurface())
    }

    private func promptContent(for prompt: PendingInstallPrompt) -> some View {
        VStack(spacing: 18) {
            // Başlık
            VStack(spacing: 3) {
                Text(headerTitle(for: prompt))
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.15), value: hoveredDestination)

                Text("\(prompt.formattedSize) · \(prompt.source.subtitleText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Apple DMG Tarzı Sürükle-Bırak Sahnesi
            // Sol: Uygulama İkonu  ───►  Sağ: Üstlü Altlı 2 Hedef Disk (Üst: Harici, Alt: Dahili)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )

                if installer.isBusy {
                    installingProgressView(prompt: prompt)
                } else {
                    dragAndDropStage(for: prompt)
                }
            }
            .frame(height: 224)
            .coordinateSpace(name: "DragCanvas")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Alt Çubuk
            bottomBar(for: prompt)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func headerTitle(for prompt: PendingInstallPrompt) -> String {
        if hoveredDestination == .external || isExternalFinderHoveringExt {
            return tr("Drop to install on “{drive}”", ["drive": settings.selectedExternalDriveName])
        }
        if hoveredDestination == .internalDrive || isExternalFinderHoveringInt {
            return tr("Drop to install in the internal Applications folder")
        }
        return tr("Drag “{app}” to a destination on the right", ["app": prompt.appName])
    }

    // MARK: - Sürükle-Bırak Sahnesi (Sol: İkon, Sağ: Üstlü Altlı Diskler)

    private func dragAndDropStage(for prompt: PendingInstallPrompt) -> some View {
        HStack(spacing: 0) {
            // SOL: Sürüklenebilir Uygulama İkonu
            VStack(spacing: 8) {
                ZStack {
                    // Sürüklenirken yerinde kalan hafif iz (ghost)
                    if isDraggingApp {
                        Image(nsImage: prompt.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 82, height: 82)
                            .opacity(0.22)
                    }

                    // Asıl sürüklenen uygulama ikonu
                    Image(nsImage: prompt.icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 82, height: 82)
                        .scaleEffect(isDraggingApp ? 1.12 : 1.0)
                        .shadow(
                            color: .black.opacity(isDraggingApp ? 0.30 : 0.0),
                            radius: isDraggingApp ? 14 : 0,
                            y: isDraggingApp ? 6 : 0
                        )
                        .offset(dragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("DragCanvas"))
                                .onChanged { value in
                                    if !isDraggingApp {
                                        withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                                            isDraggingApp = true
                                        }
                                    }
                                    dragOffset = value.translation

                                    let point = value.location
                                    let extHit = externalDropFrame.insetBy(dx: -12, dy: -6).contains(point)
                                    let intHit = internalDropFrame.insetBy(dx: -12, dy: -6).contains(point)

                                    let newHover: DropDestination? = extHit ? .external : (intHit ? .internalDrive : nil)
                                    if newHover != hoveredDestination {
                                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                            hoveredDestination = newHover
                                            if let newHover {
                                                selectedTarget = newHover
                                            }
                                        }
                                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                    }
                                }
                                .onEnded { _ in
                                    let droppedTarget = hoveredDestination
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        isDraggingApp = false
                                        dragOffset = .zero
                                        hoveredDestination = nil
                                    }
                                    if let target = droppedTarget {
                                        triggerInstall(for: prompt, destination: target)
                                    }
                                }
                        )
                }
                .zIndex(50)

                VStack(spacing: 1) {
                    Text(prompt.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(tr("Hold and drag"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .opacity(isDraggingApp ? 0.3 : 1.0)
            }
            .frame(width: 155)
            .zIndex(50)

            // ORTA: Hedefe Göre Yönlenen Ok İkonu
            VStack {
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(hoveredDestination != nil ? Color.accentColor : Color.secondary.opacity(0.35))
                    .rotationEffect(.degrees(arrowRotationAngle))
                    .scaleEffect(hoveredDestination != nil ? 1.18 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hoveredDestination)
            }
            .frame(width: 44)
            .zIndex(1)

            // SAĞ: Üstlü Altlı (VStack) Hedef Disk Kutuları
            VStack(spacing: 10) {
                // ÜST: HARİCİ DİSK HEDEFİ
                StackedDropTargetRow(
                    icon: settings.selectedExternalDriveInfo?.icon ?? NSWorkspace.shared.icon(forFile: "/Volumes"),
                    showApplicationsBadge: true,
                    title: settings.isExternalTargetReady ? settings.selectedExternalDriveName : tr("External Drive"),
                    subtitle: tr("External drive + Applications launcher"),
                    capacityText: settings.selectedExternalDriveInfo.map { tr("{size} free", ["size": $0.formattedAvailable]) } ?? tr("Ready"),
                    isHighlighted: hoveredDestination == .external || isExternalFinderHoveringExt,
                    isSelected: selectedTarget == .external && hoveredDestination == nil
                ) {
                    selectedTarget = .external
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                externalDropFrame = geo.frame(in: .named("DragCanvas"))
                            }
                            .onChange(of: geo.frame(in: .named("DragCanvas"))) { _, newFrame in
                                externalDropFrame = newFrame
                            }
                    }
                )
                .onDrop(of: [.fileURL], isTargeted: $isExternalFinderHoveringExt) { _ in
                    triggerInstall(for: prompt, destination: .external)
                    return true
                }

                // ALT: DAHİLİ DİSK HEDEFİ (Applications / Macintosh HD)
                StackedDropTargetRow(
                    icon: NSWorkspace.shared.icon(forFile: "/Applications"),
                    showApplicationsBadge: false,
                    title: "Applications",
                    subtitle: tr("Internal disk ({name})", ["name": settings.internalDrive.name]),
                    capacityText: settings.internalDrive.availableBytes > 0 ? tr("{size} free", ["size": settings.internalDrive.formattedAvailable]) : "/Applications",
                    isHighlighted: hoveredDestination == .internalDrive || isExternalFinderHoveringInt,
                    isSelected: selectedTarget == .internalDrive && hoveredDestination == nil
                ) {
                    selectedTarget = .internalDrive
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                internalDropFrame = geo.frame(in: .named("DragCanvas"))
                            }
                            .onChange(of: geo.frame(in: .named("DragCanvas"))) { _, newFrame in
                                internalDropFrame = newFrame
                            }
                    }
                )
                .onDrop(of: [.fileURL], isTargeted: $isExternalFinderHoveringInt) { _ in
                    triggerInstall(for: prompt, destination: .internalDrive)
                    return true
                }
            }
            .padding(.trailing, 16)
            .zIndex(2)
        }
    }

    private var arrowRotationAngle: Double {
        switch hoveredDestination {
        case .external: return -18
        case .internalDrive: return 18
        case nil: return 0
        }
    }

    // MARK: - Kurulum İlerleme Görünümü

    private func installingProgressView(prompt: PendingInstallPrompt) -> some View {
        let destIcon: NSImage = {
            if selectedTarget == .external {
                return settings.selectedExternalDriveInfo?.icon ?? NSWorkspace.shared.icon(forFile: "/Volumes")
            } else {
                return NSWorkspace.shared.icon(forFile: "/Applications")
            }
        }()

        return InstallingProgressView(
            appIcon: prompt.icon,
            destIcon: destIcon,
            statusMessage: installer.statusMessage
        )
    }

    // MARK: - Alt Çubuk

    private func bottomBar(for prompt: PendingInstallPrompt) -> some View {
        HStack(spacing: 10) {
            Button(tr("Ignore")) {
                coordinator.declinePrompt(prompt, ignoreFuture: true)
            }
            .controlSize(.large)

            Spacer()

            Button(tr("Cancel")) {
                coordinator.declinePrompt(prompt, ignoreFuture: false)
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            if !installer.isBusy {
                Button {
                    triggerInstall(for: prompt, destination: selectedTarget)
                } label: {
                    Text(selectedTarget == .external
                         ? tr("Install on {drive}", ["drive": settings.selectedExternalDriveName])
                         : tr("Install on Internal Disk"))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - İşlem Tetikleyici

    private func triggerInstall(for prompt: PendingInstallPrompt, destination: DropDestination) {
        selectedTarget = destination
        errorMessage = nil

        if destination == .external {
            Task {
                do {
                    switch prompt.source {
                    case .mountedDMG(let volumeURL, let dmgPath):
                        try await installer.installFromDMGToExternal(
                            appBundleURL: prompt.appBundleURL,
                            volumeURL: volumeURL,
                            dmgImagePath: dmgPath
                        )
                    case .applicationsFolder, .symlinkOverwrittenByUpdate:
                        try await installer.moveInternalAppToExternal(
                            appBundleURL: prompt.appBundleURL
                        )
                    }
                    coordinator.dismissPrompt(prompt)
                    await coordinator.scanInstalledApplications()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            switch prompt.source {
            case .mountedDMG(let volumeURL, let dmgPath):
                Task {
                    do {
                        try await installer.installFromDMGToInternal(
                            appBundleURL: prompt.appBundleURL,
                            volumeURL: volumeURL,
                            dmgImagePath: dmgPath
                        )
                        coordinator.dismissPrompt(prompt)
                        await coordinator.scanInstalledApplications()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            case .applicationsFolder, .symlinkOverwrittenByUpdate:
                settings.unregisterManagedSymlink(appBundleName: prompt.appBundleURL.lastPathComponent)
                coordinator.dismissPrompt(prompt)
            }
        }
    }
}

private struct StackedDropTargetRow: View {
    let icon: NSImage
    let showApplicationsBadge: Bool
    let title: String
    let subtitle: String
    let capacityText: String
    let isHighlighted: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 46, height: 46)

                    if showApplicationsBadge {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications"))
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 19, height: 19)
                            .offset(x: 3, y: 2)
                    }
                }
                .scaleEffect(isHighlighted ? 1.14 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.68), value: isHighlighted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHighlighted || isSelected ? Color.accentColor : .secondary)
                        .lineLimit(1)

                    Text(capacityText)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: 235, height: 86)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isHighlighted
                        ? Color.accentColor.opacity(0.18)
                        : (isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.65))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isHighlighted
                        ? Color.accentColor
                        : (isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08)),
                        style: StrokeStyle(
                            lineWidth: isHighlighted ? 2.2 : (isSelected ? 1.5 : 1),
                            dash: isHighlighted ? [6, 3] : []
                        )
                    )
            )
            .scaleEffect(isHighlighted ? 1.03 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHighlighted)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct VisualEffectSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct InstallingProgressView: View {
    let appIcon: NSImage
    let destIcon: NSImage
    let statusMessage: String

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)

                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)

                Image(nsImage: destIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
            }
            .transaction { $0.animation = nil }

            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 280)

            Text(statusMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .transaction { $0.animation = nil }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
}
