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
            panel.title = "HariciKur"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
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

    enum DropDestination: Equatable {
        case external
        case internalDrive
    }

    /// Demo modu açıkken hiçbir gerçek disk/dosya işlemi yapılmaz, sadece sürükle-bırak deneyimi simüle edilir
    @State private var isDemoMode: Bool = true
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

    // Demo simülasyon durumu
    @State private var demoIsInstalling: Bool = false
    @State private var demoProgress: Double = 0.0
    @State private var demoCompletedTarget: DropDestination? = nil
    @State private var errorMessage: String?

    private var activePrompt: PendingInstallPrompt {
        if let first = coordinator.pendingPrompts.first {
            return first
        }
        let samplePath = "/Applications/Creality Print.app"
        let fallbackPath = FileManager.default.fileExists(atPath: samplePath) ? samplePath : "/System/Applications/Chess.app"
        return PendingInstallPrompt(
            appName: "Creality Print",
            appVersion: "7.3.0",
            appBundleURL: URL(fileURLWithPath: fallbackPath),
            sizeInBytes: 444_200_000,
            source: .mountedDMG(volumeURL: URL(fileURLWithPath: "/Volumes/Creality Print App"), dmgImagePath: nil)
        )
    }

    var body: some View {
        let prompt = activePrompt

        VStack(spacing: 0) {
            // Üst Bar: Demo Modu Anahtarı
            HStack {
                Spacer()
                Toggle(isOn: $isDemoMode) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isDemoMode ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)
                        Text(isDemoMode ? "Demo Modu (Gerçek İşlem Yapılmaz)" : "Canlı Mod (Gerçek Kurulum)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)

            VStack(spacing: 18) {
                // Başlık
                VStack(spacing: 3) {
                    Text(headerTitle(for: prompt))
                        .font(.system(size: 16, weight: .bold))
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

                    if let completed = demoCompletedTarget {
                        demoCompletedView(prompt: prompt, target: completed)
                    } else if demoIsInstalling || installer.isBusy {
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
            .padding(.top, 6)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 500)
        .background(VisualEffectSurface())
    }

    private func headerTitle(for prompt: PendingInstallPrompt) -> String {
        if let completed = demoCompletedTarget {
            return completed == .external
                ? "“\(prompt.appName)” \(settings.selectedExternalDriveName) diskine kuruldu (Demo)"
                : "“\(prompt.appName)” Dahili Diske kuruldu (Demo)"
        }
        if hoveredDestination == .external || isExternalFinderHoveringExt {
            return "“\(settings.selectedExternalDriveName)” harici diskine kurmak için bırakın"
        }
        if hoveredDestination == .internalDrive || isExternalFinderHoveringInt {
            return "Dahili Applications klasörüne kurmak için bırakın"
        }
        return "“\(prompt.appName)” ikonunu sağdaki hedefe sürükleyin"
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
                                        triggerInstallOrDemo(for: prompt, destination: target)
                                    }
                                }
                        )
                }
                .zIndex(50)

                VStack(spacing: 1) {
                    Text(prompt.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Tut ve Sürükle")
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
                // ÜST: HARİCİ DİSK HEDEFİ (KIOXIA)
                StackedDropTargetRow(
                    icon: settings.selectedExternalDriveInfo?.icon ?? NSWorkspace.shared.icon(forFile: "/Volumes"),
                    showApplicationsBadge: true,
                    title: settings.isExternalTargetReady ? settings.selectedExternalDriveName : "Harici Disk",
                    subtitle: "Harici Disk + Applications Kısayolu",
                    capacityText: settings.selectedExternalDriveInfo.map { "\($0.formattedAvailable) boş" } ?? "Hazır",
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
                    triggerInstallOrDemo(for: prompt, destination: .external)
                    return true
                }

                // ALT: DAHİLİ DİSK HEDEFİ (Applications / Macintosh HD)
                StackedDropTargetRow(
                    icon: NSWorkspace.shared.icon(forFile: "/Applications"),
                    showApplicationsBadge: false,
                    title: "Applications",
                    subtitle: "Dahili Disk (\(settings.internalDrive.name))",
                    capacityText: settings.internalDrive.availableBytes > 0 ? "\(settings.internalDrive.formattedAvailable) boş" : "/Applications",
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
                    triggerInstallOrDemo(for: prompt, destination: .internalDrive)
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

    // MARK: - Demo & Kurulum İlerleme Görünümleri

    private func installingProgressView(prompt: PendingInstallPrompt) -> some View {
        let destIcon: NSImage = {
            if selectedTarget == .external {
                return settings.selectedExternalDriveInfo?.icon ?? NSWorkspace.shared.icon(forFile: "/Volumes")
            } else {
                return NSWorkspace.shared.icon(forFile: "/Applications")
            }
        }()

        let statusText = isDemoMode
            ? (selectedTarget == .external
                ? "Demo: \(settings.selectedExternalDriveName)/Applications klasörüne kopyalanıyor ve kısayol oluşturuluyor…"
                : "Demo: Dahili /Applications klasörüne kopyalanıyor…")
            : installer.statusMessage

        return InstallingProgressView(
            appIcon: prompt.icon,
            destIcon: destIcon,
            isDemoMode: isDemoMode,
            demoProgress: demoProgress,
            statusMessage: statusText
        )
    }

    private func demoCompletedView(prompt: PendingInstallPrompt, target: DropDestination) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.green)

            VStack(spacing: 3) {
                Text(target == .external
                     ? "Harici Diske Kurulum + Kısayol Simüle Edildi"
                     : "Dahili Diske Kurulum Simüle Edildi")
                    .font(.system(size: 13.5, weight: .semibold))

                Text(target == .external
                     ? "Gerçek işlemde \(prompt.appName) “\(settings.selectedExternalDriveName)” diskine kurulur ve Applications içine kısayol eklenir."
                     : "Gerçek işlemde \(prompt.appName) dahili /Applications klasörüne kurulur.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button("Sürüklemeyi Tekrar Dene") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    demoCompletedTarget = nil
                    demoProgress = 0
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
    }

    // MARK: - Alt Çubuk

    private func bottomBar(for prompt: PendingInstallPrompt) -> some View {
        HStack(spacing: 10) {
            if demoCompletedTarget != nil {
                Button("Sıfırla") {
                    withAnimation {
                        demoCompletedTarget = nil
                        demoProgress = 0
                    }
                }
                .controlSize(.large)
            } else {
                Button("Yoksay") {
                    if let first = coordinator.pendingPrompts.first {
                        coordinator.dismissPrompt(first, ignoreFuture: true)
                    }
                }
                .controlSize(.large)
            }

            Spacer()

            Button("Vazgeç") {
                if let first = coordinator.pendingPrompts.first {
                    coordinator.dismissPrompt(first, ignoreFuture: false)
                } else {
                    InstallPromptPanelController.shared.close()
                }
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            if demoCompletedTarget == nil && !demoIsInstalling && !installer.isBusy {
                Button {
                    triggerInstallOrDemo(for: prompt, destination: selectedTarget)
                } label: {
                    Text(selectedTarget == .external
                         ? "\(settings.selectedExternalDriveName) Diskine Kur"
                         : "Dahiliye Kur")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - İşlem Tetikleyici (Demo vs Gerçek)

    private func triggerInstallOrDemo(for prompt: PendingInstallPrompt, destination: DropDestination) {
        selectedTarget = destination
        errorMessage = nil

        if isDemoMode {
            withAnimation(.easeInOut(duration: 0.2)) {
                demoIsInstalling = true
                demoProgress = 0.05
            }
            Task { @MainActor in
                for step in 1...10 {
                    try? await Task.sleep(nanoseconds: 85_000_000)
                    demoProgress = Double(step) / 10.0
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    demoIsInstalling = false
                    demoCompletedTarget = destination
                }
            }
            return
        }

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
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(capacityText)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHighlighted || isSelected ? Color.accentColor : .secondary)
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
    let isDemoMode: Bool
    let demoProgress: Double
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

            ProgressView(value: isDemoMode ? demoProgress : nil)
                .progressViewStyle(.linear)
                .frame(width: 280)
                .animation(.linear(duration: 0.08), value: demoProgress)

            Text(statusMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .transaction { $0.animation = nil }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
}
