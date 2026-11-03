import AppKit
import Darwin
import Foundation

func execute(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return (task.terminationStatus, String(decoding: data, as: UTF8.self))
}
func requireCommand(_ executable: String, _ arguments: [String]) throws -> String {
    let result = try execute(executable, arguments)
    if result.0 != 0 {
        throw NSError(domain: "KakaoTalkUpdater", code: Int(result.0),
                      userInfo: [NSLocalizedDescriptionKey: result.1])
    }
    return result.1
}
func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

final class UpdateDelegate: NSObject, NSApplicationDelegate {
    private var lockDescriptor: Int32 = -1
    private var exitSource: DispatchSourceProcess?
    private var directory: URL!
    private let target = URL(fileURLWithPath: "/Applications/KakaoTalk.app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let args = ProcessInfo.processInfo.arguments
            guard args.count == 5, args[1] == "--parent-pid", args[3] == "--staging",
                  let pid = Int32(args[2]), pid > 1 else {
                throw NSError(domain: "KakaoTalkUpdater", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid updater arguments."])
            }
            directory = URL(fileURLWithPath: args[4]).standardizedFileURL
            lockDescriptor = open(directory.appendingPathComponent("Update.lock").path,
                                  O_CREAT | O_WRONLY, S_IRUSR | S_IWUSR)
            guard lockDescriptor >= 0 else {
                throw NSError(domain: "KakaoTalkUpdater", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not lock the staged update."])
            }
            if flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 { NSApp.terminate(nil); return }
            _ = try validateUpdate(directory, target: target)
            if kill(pid, 0) == -1 && errno == ESRCH { apply(); return }
            guard let parent = NSRunningApplication(processIdentifier: pid),
                  parent.bundleIdentifier == reconnectID else {
                throw NSError(domain: "KakaoTalkUpdater", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Unexpected parent application."])
            }
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit,
                                                          queue: DispatchQueue.global())
            exitSource = source
            source.setEventHandler { self.apply() }
            source.resume()
            if kill(pid, 0) == -1 && errno == ESRCH {
                source.cancel()
                apply()
            }
        } catch { fail(error) }
    }
    private let applyLock = NSLock()
    private var applying = false
    private func apply() {
        applyLock.lock()
        if applying { applyLock.unlock(); return }
        applying = true
        applyLock.unlock()
        DispatchQueue.global().async {
            do {
                let manifest = try validateUpdate(self.directory, target: self.target)
                let source = self.directory.appendingPathComponent("KakaoTalk.app")
                _ = try requireCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
                guard let script = Bundle.main.url(forResource: "install-app", withExtension: "sh") else {
                    throw NSError(domain: "KakaoTalkUpdater", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing replacement helper."])
                }
                let arguments = [script.path, source.path, self.target.path,
                                 manifest["executable_sha256"]!, manifest["helper_sha256"]!,
                                 manifest["app_version"]!, manifest["app_build"]!]
                var result = try execute("/bin/sh", arguments)
                if result.0 == 77 {
                    let command = (["/bin/sh"] + arguments).map(shellQuote).joined(separator: " ")
                    let literal = command.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    result = try execute("/usr/bin/osascript", ["-e",
                        "do shell script \"" + literal + "\" with administrator privileges"])
                }
                if result.0 != 0 {
                    throw NSError(domain: "KakaoTalkUpdater", code: Int(result.0),
                                  userInfo: [NSLocalizedDescriptionKey: result.1])
                }
                _ = try requireCommand("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                                       ["-f", self.target.path])
                let pointer = self.directory.deletingLastPathComponent().appendingPathComponent("PendingUpdate.plist")
                if FileManager.default.fileExists(atPath: pointer.path) {
                    let pending = try PropertyListSerialization.propertyList(
                        from: Data(contentsOf: pointer), format: nil) as? [String: String]
                    if pending?["directory"] == self.directory.path { try FileManager.default.removeItem(at: pointer) }
                }
                let report = ["release_tag": manifest["release_tag"]!, "app_backup": result.1,
                              "completed_at": ISO8601DateFormatter().string(from: Date())]
                DispatchQueue.main.async { self.finishUpdate(report, index: 0, failures: []) }
            } catch { self.fail(error) }
        }
    }
    private func finishUpdate(_ report: [String: String], index: Int, failures: [String]) {
        let schemes = ["kakaotalk", "kakaoopen", "kakaoplus", "kakaoshare"]
        if index < schemes.count {
            let scheme = schemes[index]
            NSWorkspace.shared.setDefaultApplication(at: target, toOpenURLsWithScheme: scheme) { error in
                DispatchQueue.main.async {
                    let resolved = NSWorkspace.shared.urlForApplication(toOpen: URL(string: scheme + "://")!)
                    let verified = error == nil && resolved?.standardizedFileURL.path == self.target.path
                    self.finishUpdate(report, index: index + 1,
                                      failures: verified ? failures : failures + [scheme])
                }
            }
            return
        }
        do {
            var result = report
            result["default_link_failures"] = failures.joined(separator: ",")
            try JSONEncoder().encode(result).write(to: directory.appendingPathComponent("Result.json"),
                                                  options: .atomic)
            NSWorkspace.shared.openApplication(at: target,
                configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { self.fail(error) }
                    else { NSApp.terminate(nil) }
                }
        } catch { fail(error) }
    }
    private func fail(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "KakaoTalk update could not finish"
            alert.informativeText = error.localizedDescription +
                "\n\nChat data was not removed. The previous app or its backup is retained."
            alert.addButton(withTitle: "Open KakaoTalk")
            alert.runModal()
            NSWorkspace.shared.openApplication(at: self.target,
                configuration: NSWorkspace.OpenConfiguration()) { _, _ in NSApp.terminate(nil) }
        }
    }
}
@main struct UpdaterMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = UpdateDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}
