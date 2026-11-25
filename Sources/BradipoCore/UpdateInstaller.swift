import CryptoKit
import Foundation

public enum UpdateError: LocalizedError, Equatable {
    case http(status: Int)
    case unexpectedTag(String)
    case noArchive(Version)
    case notReplaceable
    case damagedDownload
    case unreadableArchive
    case invalidSignature
    case wrongApp
    case requiresMacOS(String)
    case newerInstalled(Version)
    case notReplaced(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .http(let status): "GitHub answered with HTTP status \(status). Try again later."
        case .unexpectedTag(let tag): "The latest release has an unexpected tag, “\(tag)”."
        case .noArchive(let version):
            "bradipo \(version) is available, but you need to install it from the Releases page."
        case .notReplaceable:
            "This copy of bradipo can’t be replaced. "
                + "Quit it, use Finder to copy it to a folder you can change, "
                + "such as Applications in your home folder, and open the new copy."
        case .damagedDownload: "The download is incomplete or damaged."
        case .unreadableArchive: "The downloaded archive couldn’t be extracted."
        case .invalidSignature: "The downloaded app’s code signature isn’t valid."
        case .wrongApp: "The downloaded app isn’t the expected version of bradipo."
        case .requiresMacOS(let version): "The update requires macOS \(version) or later."
        case .newerInstalled(let version):
            "bradipo \(version) is already installed. Quit bradipo and open it again."
        case .notReplaced(let code):
            "macOS didn’t let bradipo replace itself: \(String(cString: strerror(code)))."
                // App Management denies with EPERM.
                + (code == EPERM
                    ? " Check that System Settings > Privacy & Security > App Management allows bradipo." : "")
        }
    }
}

public enum UpdateInstaller {
    /// Replaces the app with the one in the archive, or throws and leaves it as it was.
    public static func install(_ archive: Data, digest: String, version: Version, over app: URL) throws {
        let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard digest == "sha256:\(hash)" else { throw UpdateError.damagedDownload }

        // A directory on the app's volume, as the swap below requires.
        let stage = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                appropriateFor: app, create: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let tarball = stage.appending(path: "bradipo.tar.gz")
        try archive.write(to: tarball)
        guard try run("/usr/bin/tar", "-xzf", tarball.path, "-C", stage.path) else {
            throw UpdateError.unreadableArchive
        }

        let update = stage.appending(path: "bradipo.app")
        guard try run("/usr/bin/codesign", "--verify", "--strict", update.path) else {
            throw UpdateError.invalidSignature
        }
        let info = try Info(of: update)
        let installed = try Info(of: app)
        guard info.identifier == installed.identifier, Version(info.version) == version else {
            throw UpdateError.wrongApp
        }
        // The app can have been updated on disk since the running one was opened.
        if let newer = Version(installed.version), newer > version { throw UpdateError.newerInstalled(newer) }
        let required = info.minimumSystemVersion ?? "0"
        guard let minimum = Version(required), minimum <= Version(ProcessInfo.processInfo.operatingSystemVersion) else {
            throw UpdateError.requiresMacOS(required)
        }

        // The swap is atomic and leaves the old app in the stage, which is removed on return.
        guard renamex_np(update.path, app.path, UInt32(RENAME_SWAP)) == 0 else {
            let code = errno
            // Another account can own the app, even if this one can change its folder.
            throw code == EACCES ? UpdateError.notReplaceable : .notReplaced(errno: code)
        }
    }

    private static func run(_ tool: String, _ arguments: String...) throws -> Bool {
        let process = try Process.run(URL(filePath: tool), arguments: arguments)
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private struct Info: Decodable {
        let identifier: String
        let version: String
        let minimumSystemVersion: String?

        private enum CodingKeys: String, CodingKey {
            case identifier = "CFBundleIdentifier"
            case version = "CFBundleShortVersionString"
            case minimumSystemVersion = "LSMinimumSystemVersion"
        }

        init(of app: URL) throws {
            let plist = try Data(contentsOf: app.appending(path: "Contents/Info.plist"))
            self = try PropertyListDecoder().decode(Info.self, from: plist)
        }
    }
}
