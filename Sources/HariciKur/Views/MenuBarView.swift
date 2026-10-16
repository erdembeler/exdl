import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var coordinator = MonitorCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Üst Başlık ve Anahtar
            HStack {
                Text("HariciKur")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Toggle("", isOn: $settings.isMonitoringEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            // 2. Harici Disk Durum Kartı
            HStack(spacing: 11) {
                let driveIcon = settings.selectedExternalDriveInfo?.icon ?? NSWorkspace.shared.icon(forFile: "/Volumes")
                Image(nsImage: driveIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(settings.isExternalTargetReady ? settings.selectedExternalDriveName : "Harici Disk Yok")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        if let drive = settings.selectedExternalDriveInfo {
                            Text("\(drive.formattedAvailable) boş")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let drive = settings.selectedExternalDriveInfo, drive.totalBytes > 0 {
                        ProgressView(value: drive.usedPercentage)
                            .controlSize(.small)
                    }

                    HStack {
                        Text("\(coordinator.externalAppsCount) harici uygulama")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(ByteCountFormatter.string(fromByteCount: coordinator.totalSavedInternalBytes, countStyle: .file)) kazanıldı")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Bekleyen Kurulum Varsa
            if let firstPrompt = coordinator.pendingPrompts.first {
                Button {
                    coordinator.showPromptWindowIfNeeded()
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: firstPrompt.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(firstPrompt.appName) kurulum bekliyor")
                                .font(.caption.weight(.semibold))
                            Text(firstPrompt.formattedSize)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Alt Menü Satırları
            VStack(spacing: 2) {
                MenuRowButton(title: "Sürükle-Bırak Demo Penceresi…", icon: "hand.draw") {
                    InstallPromptPanelController.shared.showPromptWindow()
                }

                MenuRowButton(title: "Uygulamaları Yönet…", icon: "square.grid.2x2") {
                    DashboardWindowController.shared.showWindow(selectedTab: .applications)
                }

                MenuRowButton(title: "Ayarlar…", icon: "gearshape") {
                    DashboardWindowController.shared.showWindow(selectedTab: .settings)
                }

                Divider()
                    .padding(.vertical, 4)

                MenuRowButton(title: "HariciKur'dan Çık", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

private struct MenuRowButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
