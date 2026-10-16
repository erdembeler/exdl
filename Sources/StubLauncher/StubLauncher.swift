import Foundation
import AppKit

@main
struct StubLauncher {
    static func main() {
        let info = Bundle.main.infoDictionary ?? [:]
        let targetPath = (info["HariciKurTargetAppPath"] as? String) ?? ""
        let appName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? Bundle.main.bundleURL.deletingPathExtension().lastPathComponent

        guard !targetPath.isEmpty else {
            showAlert(
                title: "Hedef Uygulama Bulunamadı",
                message: "\(appName) için harici disk hedef yolu okunamadı."
            )
            return
        }

        let targetURL = URL(fileURLWithPath: targetPath)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            var args = ["-a", targetURL.path]
            let cliArgs = Array(CommandLine.arguments.dropFirst())
            for arg in cliArgs where !arg.hasPrefix("-psn_") {
                args.append(arg)
            }
            proc.arguments = args
            try? proc.run()
            proc.waitUntilExit()
        } else {
            showAlert(
                title: "Harici Disk Takılı Değil",
                message: "'\(appName)' uygulaması harici diskinizde (\(targetPath)) kurulu.\n\nUygulamayı başlatmak için lütfen harici diskinizi Mac'inize bağlayın."
            )
        }
    }

    private static func showAlert(title: String, message: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }
}
