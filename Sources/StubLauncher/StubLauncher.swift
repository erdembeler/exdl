import Foundation
import AppKit

@main
struct StubLauncher {
    static func main() {
        let info = Bundle.main.infoDictionary ?? [:]
        let targetPath = (info["EXdlTargetAppPath"] as? String)
            ?? (info["HariciKurTargetAppPath"] as? String)
            ?? ""
        let appName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
        let turkish = prefersTurkish()

        guard !targetPath.isEmpty else {
            showAlert(
                title: turkish ? "Hedef Uygulama Bulunamadı" : "Target App Not Found",
                message: turkish
                    ? "\(appName) için harici disk hedef yolu okunamadı."
                    : "The external drive location for \(appName) could not be read.",
                buttonTitle: turkish ? "Tamam" : "OK"
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
                title: turkish ? "Harici Disk Takılı Değil" : "External Drive Not Connected",
                message: turkish
                    ? "'\(appName)' uygulaması harici diskinizde (\(targetPath)) kurulu.\n\nUygulamayı başlatmak için lütfen harici diskinizi Mac'inize bağlayın."
                    : "\(appName) is installed on your external drive (\(targetPath)).\n\nConnect the drive to your Mac to open it.",
                buttonTitle: turkish ? "Tamam" : "OK"
            )
        }
    }

    /// Uses the language chosen inside EXdl, read straight from its preferences file;
    /// falls back to the system language.
    private static func prefersTurkish() -> Bool {
        let prefsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.erdem.EXdl.plist")
        if let data = try? Data(contentsOf: prefsURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let language = plist["appLanguage"] as? String {
            return language == "tr"
        }
        return Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
    }

    private static func showAlert(title: String, message: String, buttonTitle: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: buttonTitle)
        alert.runModal()
    }
}
