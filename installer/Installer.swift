import AppKit
import CryptoKit
import Foundation

struct InstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct CommandResult { let status: Int32; let output: String }

func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus,
                         output: String(data: data, encoding: .utf8) ?? "")
}
func checked(_ executable: String, _ arguments: [String]) throws -> String {
    let result = try run(executable, arguments)
    guard result.status == 0 else {
        throw InstallError(message: result.output.isEmpty ? "A required installation step failed." : result.output)
    }
    return result.output
}
func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

final class Installer: NSObject, NSApplicationDelegate {
    private let appURL = URL(fileURLWithPath: "/Applications/KakaoTalk.app")
    private let bundleID = "local.elsholtzia.KakaoTalkReconnectExperiment"
    private let knownIDs: Set<String> = ["com.kakao.KakaoTalkMac", "local.elsholtzia.KakaoTalkNoAds",
                                       "local.elsholtzia.KakaoTalkReconnectExperiment"]
    private let schemes = ["kakaotalk", "kakaoopen", "kakaoplus", "kakaoshare"]
    private var window: NSWindow!
    private var status: NSTextField!
    private var button: NSButton!
    private var progress: NSProgressIndicator!
    private var installing = false
    private var installed = false
    private var report: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Installer", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        root.submenu = appMenu
        menu.addItem(root)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 350),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Install KakaoTalk"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "KakaoTalk NoAds + Reconnect")
        title.font = .boldSystemFont(ofSize: 23)
        title.frame = NSRect(x: 28, y: 285, width: 510, height: 32)
        window.contentView!.addSubview(title)
        let detail = NSTextField(wrappingLabelWithString:
            "Install KakaoTalk 26.9.0 with no main-window ads and a sidebar reconnect button.\n\n" +
            "The existing app is backed up. Chat data is kept. If you are switching from the official " +
            "app or older NoAds build, its separate chat history is not automatically migrated.\n\n" +
            "Finish drafts before continuing. KakaoTalk will close during installation. " +
            "Your Mac may ask for administrator or default-link approval.")
        detail.frame = NSRect(x: 28, y: 110, width: 504, height: 165)
        window.contentView!.addSubview(detail)
        status = NSTextField(wrappingLabelWithString: "Ready. No password or account data is collected.")
        status.frame = NSRect(x: 28, y: 54, width: 504, height: 46)
        status.font = .systemFont(ofSize: 12)
        window.contentView!.addSubview(status)
        progress = NSProgressIndicator(frame: NSRect(x: 28, y: 24, width: 22, height: 22))
        progress.style = .spinning
        progress.isDisplayedWhenStopped = false
        window.contentView!.addSubview(progress)
        button = NSButton(title: "Install and Replace KakaoTalk", target: self, action: #selector(start))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 255, y: 18, width: 280, height: 34)
        window.contentView!.addSubview(button)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        installing ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !installing }
    private func update(_ message: String) {
        DispatchQueue.main.async { self.status.stringValue = message }
    }
    @objc private func start() {
        if installed { openKakaoTalk(); return }
        guard !installing else { return }
        installing = true
        button.isEnabled = false
        window.standardWindowButton(.closeButton)?.isEnabled = false
        progress.startAnimation(nil)
        status.stringValue = "Checking the bundled application..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let source = try self.preparePayload()
                self.update("Closing KakaoTalk. Please finish any app confirmation that appears.")
                try self.stopKakaoTalk()
                self.update("Backing up and replacing KakaoTalk...")
                try self.installApp(source)
                self.update("Updating the Dock...")
                try self.updateDock()
                DispatchQueue.main.async { self.setHandler(index: 0, failures: []) }
            } catch {
                DispatchQueue.main.async { self.fail(error) }
            }
        }
    }
    private func resources() throws -> URL {
        guard let url = Bundle.main.resourceURL else { throw InstallError(message: "Installer resources are missing.") }
        return url
    }
    private func preparePayload() throws -> URL {
        let resources = try resources()
        let data = try Data(contentsOf: resources.appendingPathComponent("Payload.json"))
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let archiveHash = payload["archive_sha256"],
              let executableHash = payload["executable_sha256"],
              let helperHash = payload["helper_sha256"] else {
            throw InstallError(message: "The payload manifest is invalid.")
        }
        _ = try checked("/usr/bin/codesign", ["--verify", "--deep", "--strict", Bundle.main.bundlePath])
        let archive = resources.appendingPathComponent("KakaoTalk.zip")
        guard try sha256(archive) == archiveHash else { throw InstallError(message: "Payload checksum mismatch.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KakaoTalkInstall-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        _ = try checked("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        let source = directory.appendingPathComponent("KakaoTalk.app")
        guard Bundle(url: source)?.bundleIdentifier == bundleID,
              try sha256(source.appendingPathComponent("Contents/MacOS/KakaoTalk")) == executableHash,
              try sha256(source.appendingPathComponent("Contents/Frameworks/SessionReconnect.dylib")) == helperHash else {
            throw InstallError(message: "The bundled app does not match this installer.")
        }
        _ = try checked("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        report["payload"] = payload
        report["temporary_payload_directory"] = directory.path
        return source
    }
    private func stopKakaoTalk() throws {
        let applications: [NSRunningApplication] = DispatchQueue.main.sync {
            let matches = NSWorkspace.shared.runningApplications.filter {
                self.knownIDs.contains($0.bundleIdentifier ?? "") || $0.bundleURL?.path == self.appURL.path
            }
            for app in matches { app.terminate() }
            return matches
        }
        for _ in 0..<100 {
            if applications.allSatisfy({ $0.isTerminated }) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw InstallError(message: "KakaoTalk did not quit. Finish its prompts, quit it yourself, and try again. The installed app was not replaced.")
    }
    private func installApp(_ source: URL) throws {
        let resources = try resources()
        let manifest = report["payload"] as! [String: String]
        let arguments = [resources.appendingPathComponent("install-app.sh").path, source.path,
                         appURL.path, manifest["executable_sha256"]!, manifest["helper_sha256"]!]
        var result = try run("/bin/sh", arguments)
        if result.status == 77 {
            update("Administrator approval is required. Enter your Mac password only in the system prompt.")
            let command = (["/bin/sh"] + arguments).map(shellQuote).joined(separator: " ")
            let literal = command.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "\"", with: "\\\"")
            result = try run("/usr/bin/osascript", ["-e", "do shell script \"" + literal + "\" with administrator privileges"])
        }
        guard result.status == 0 else { throw InstallError(message: result.output) }
        report["app_backup"] = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        report["installed_path"] = appURL.path
        guard Bundle(url: appURL)?.bundleIdentifier == bundleID else {
            throw InstallError(message: "Installed application identity mismatch.")
        }
        let register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        _ = try checked(register, ["-f", appURL.path])
        if let temporary = report["temporary_payload_directory"] as? String {
            try FileManager.default.removeItem(atPath: temporary)
            report.removeValue(forKey: "temporary_payload_directory")
        }
    }
    private func updateDock() throws {
        let response = try checked("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
        guard let data = response.data(using: .utf8),
              var dock = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InstallError(message: "Could not read Dock settings. The app is installed.")
        }
        let backupRoot = try reportDirectory()
        try data.write(to: backupRoot.appendingPathComponent("Dock-before-" + UUID().uuidString + ".plist"))
        let oldTiles = dock["persistent-apps"] as? [[String: Any]] ?? []
        var tiles: [[String: Any]] = []
        var replaced = false
        for var tile in oldTiles {
            var tileData = tile["tile-data"] as? [String: Any] ?? [:]
            let file = tileData["file-data"] as? [String: Any] ?? [:]
            let path = file["_CFURLString"] as? String ?? ""
            let identifier = tileData["bundle-identifier"] as? String ?? ""
            if knownIDs.contains(identifier) || path.contains("KakaoTalk.app") || path.contains("KakaoTalk-Reconnect-") {
                if replaced { continue }
                tileData["file-label"] = "KakaoTalk"
                tileData["bundle-identifier"] = bundleID
                tileData["file-data"] = ["_CFURLString": appURL.absoluteString + "/", "_CFURLStringType": 15]
                tileData.removeValue(forKey: "book")
                tile["tile-data"] = tileData
                replaced = true
            }
            tiles.append(tile)
        }
        if !replaced {
            tiles.append(["tile-type": "file-tile", "tile-data": ["file-label": "KakaoTalk",
                "bundle-identifier": bundleID, "file-type": 41,
                "file-data": ["_CFURLString": appURL.absoluteString + "/", "_CFURLStringType": 15]]])
        }
        dock["persistent-apps"] = tiles
        let modified = try PropertyListSerialization.data(fromPropertyList: dock, format: .xml, options: 0)
        let temporary = backupRoot.appendingPathComponent("Dock-current.plist")
        try modified.write(to: temporary)
        _ = try checked("/usr/bin/defaults", ["import", "com.apple.dock", temporary.path])
        let reload = try run("/usr/bin/killall", ["Dock"])
        guard reload.status == 0 || reload.status == 1 else { throw InstallError(message: "Dock restart failed.") }
        let verify = try checked("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
        guard let verifyData = verify.data(using: .utf8),
              let updated = try PropertyListSerialization.propertyList(from: verifyData, format: nil) as? [String: Any],
              let apps = updated["persistent-apps"] as? [[String: Any]],
              apps.contains(where: { tile in
                  let data = tile["tile-data"] as? [String: Any] ?? [:]
                  let file = data["file-data"] as? [String: Any] ?? [:]
                  return data["bundle-identifier"] as? String == self.bundleID &&
                      file["_CFURLString"] as? String == self.appURL.absoluteString + "/"
              }) else { throw InstallError(message: "The app is installed, but the Dock target could not be verified.") }
        report["dock_verified"] = true
    }
    private func setHandler(index: Int, failures: [String]) {
        guard index < schemes.count else { finish(failures); return }
        let scheme = schemes[index]
        status.stringValue = "Setting default links (\(index + 1)/\(schemes.count))..."
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
            DispatchQueue.main.async {
                let resolved = NSWorkspace.shared.urlForApplication(toOpen: URL(string: scheme + "://")!)
                let verified = error == nil && resolved?.standardizedFileURL.path == self.appURL.path &&
                    resolved.flatMap { Bundle(url: $0)?.bundleIdentifier } == self.bundleID
                self.report["handler_" + scheme] = verified
                self.setHandler(index: index + 1, failures: verified ? failures : failures + [scheme])
            }
        }
    }
    private func reportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("KakaoTalk NoAds Installer")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func finish(_ failures: [String]) {
        installing = false
        installed = true
        progress.stopAnimation(nil)
        window.standardWindowButton(.closeButton)?.isEnabled = true
        button.title = "Open KakaoTalk"
        button.isEnabled = true
        report["completed_at"] = ISO8601DateFormatter().string(from: Date())
        report["all_handlers_verified"] = failures.isEmpty
        do {
            let directory = try reportDirectory()
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("Last-install.json"))
        } catch { status.stringValue = "Installed. The local installation report could not be saved."; return }
        status.stringValue = failures.isEmpty ?
            "Installed. Dock and all default links are verified. Sign in directly in KakaoTalk if needed." :
            "Installed. Some default links were not approved: " + failures.joined(separator: ", ")
        openKakaoTalk()
    }
    private func fail(_ error: Error) {
        installing = false
        progress.stopAnimation(nil)
        window.standardWindowButton(.closeButton)?.isEnabled = true
        button.isEnabled = true
        status.stringValue = error.localizedDescription
        let alert = NSAlert()
        alert.messageText = "Installation could not finish"
        alert.informativeText = error.localizedDescription + "\n\nExisting chat data was not removed. Any app backup is kept in /Applications/KakaoTalk Backups."
        alert.runModal()
    }
    private func openKakaoTalk() {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { DispatchQueue.main.async { self.status.stringValue = "Installed, but launch failed: " + error.localizedDescription } }
        }
    }
}
let application = NSApplication.shared
let delegate = Installer()
application.delegate = delegate
application.run()
