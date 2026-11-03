import AppKit
import CryptoKit
import Foundation

let reconnectID = "local.elsholtzia.KakaoTalkReconnectExperiment"

func fileHash(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

func validateUpdate(_ directory: URL, target: URL) throws -> [String: String] {
    let manifest = try JSONDecoder().decode([String: String].self,
        from: Data(contentsOf: directory.appendingPathComponent("Ready.json")))
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "KakaoTalkUpdater", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    let source = directory.appendingPathComponent("KakaoTalk.app")
    let infoURL = source.appendingPathComponent("Contents/Info.plist")
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL),
                                                         format: nil) as? [String: Any]
    try require(info?["CFBundleIdentifier"] as? String == reconnectID, "Unexpected update identity.")
    for (field, key) in [("CFBundleShortVersionString", "app_version"),
                          ("CFBundleVersion", "app_build"), ("KakaoTalkPatchRelease", "release_tag")] {
        try require(manifest[key] != nil && info?[field] as? String == manifest[key],
                    "Update version metadata does not match.")
    }
    for (relative, key) in [("Contents/MacOS/KakaoTalk", "executable_sha256"),
                            ("Contents/Frameworks/SessionReconnect.dylib", "helper_sha256")] {
        let file = source.appendingPathComponent(relative)
        try require(file.resolvingSymlinksInPath().path.hasPrefix(source.path + "/"),
                    "An update file escapes the staged application.")
        let actual = try fileHash(file)
        try require(actual == manifest[key], "Update checksum mismatch.")
    }
    let archive = directory.appendingPathComponent("Payload.zip")
    try require(try fileHash(archive) == manifest["archive_sha256"], "Archive checksum mismatch.")
    if let existing = Bundle(url: target) {
        try require(existing.bundleIdentifier == reconnectID, "The installed app identity changed.")
        let current = existing.object(forInfoDictionaryKey: "KakaoTalkPatchRelease") as? String
            ?? "v26.9.0-reconnect.3"
        try require(manifest["release_tag"]!.compare(current, options: .numeric) == .orderedDescending,
                    "Refusing an identical or older patch release.")
        let oldVersion = existing.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let oldBuild = existing.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let order = manifest["app_version"]!.compare(oldVersion, options: .numeric)
        try require(order != .orderedAscending && (order != .orderedSame ||
            manifest["app_build"]!.compare(oldBuild, options: .numeric) != .orderedAscending),
            "Refusing an older KakaoTalk version.")
    } else {
        try require(false, "The installed application is missing.")
    }
    return manifest
}
