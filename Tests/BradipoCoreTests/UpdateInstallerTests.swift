import BradipoCore
import CryptoKit
import Foundation
import Testing

final class UpdateInstallerTests {
    struct App: Sendable {
        var identifier = "com.marcoieni.bradipo"
        var version = "0.2.0"
        var minimumSystemVersion = "1.0"
        var versionAfterSigning: String?

        func build(in folder: URL) throws -> URL {
            let app = folder.appending(path: "bradipo.app")
            let executable = app.appending(path: "Contents/MacOS/bradipo")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // codesign signs a script through extended attributes, which the archive leaves out.
            let binary = try Data(contentsOf: URL(filePath: "/usr/bin/true"))
            #expect(FileManager.default.createFile(atPath: executable.path, contents: binary,
                                                   attributes: [.posixPermissions: 0o755]))
            try writeInfo(version: version, to: app)
            try run("/usr/bin/codesign", "--force", "--sign", "-", app.path)
            if let versionAfterSigning { try writeInfo(version: versionAfterSigning, to: app) }
            return app
        }

        private func writeInfo(version: String, to app: URL) throws {
            let info = ["CFBundleExecutable": "bradipo", "CFBundleIdentifier": identifier,
                        "CFBundleShortVersionString": version, "LSMinimumSystemVersion": minimumSystemVersion]
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try encoder.encode(info).write(to: app.appending(path: "Contents/Info.plist"))
        }
    }

    private let files = FileManager.default
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    private var applications: URL { root.appending(path: "Applications") }

    deinit { try? files.removeItem(at: root) }

    private func archive(_ update: App) throws -> Data {
        let release = try update.build(in: root.appending(path: "Release")).deletingLastPathComponent()
        let tarball = root.appending(path: "bradipo.tar.gz")
        try run("/usr/bin/tar", "--no-mac-metadata", "--no-xattrs", "-czf", tarball.path,
                "-C", release.path, "bradipo.app")
        return try Data(contentsOf: tarball)
    }

    private func install(_ archive: Data, digest: String? = nil) throws {
        let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        try UpdateInstaller.install(archive, digest: digest ?? "sha256:\(hash)", version: #require(Version("0.2.0")),
                                    over: applications.appending(path: "bradipo.app"))
    }

    /// Expects the installation to fail and leave the installed app as it was.
    private func expectRejection(_ error: UpdateError, over version: String = "0.1.0",
                                 installation: () throws -> Void) throws {
        let installed = try App(version: version).build(in: applications)
        let copy = root.appending(path: "copy.app")
        try files.copyItem(at: installed, to: copy)
        #expect(throws: error) { try installation() }
        #expect(files.contentsEqual(atPath: installed.path, andPath: copy.path))
    }

    @Test func updateReplacesTheInstalledApp() throws {
        let installed = try App(version: "0.1.0").build(in: applications)
        try install(archive(App()))
        #expect(files.contentsEqual(atPath: installed.path, andPath: root.appending(path: "Release/bradipo.app").path))
        // Nothing else must be left in Applications.
        #expect(try files.contentsOfDirectory(atPath: applications.path) == ["bradipo.app"])
    }

    @Test(arguments: [
        (App(identifier: "com.example.other"), UpdateError.wrongApp),
        (App(version: "0.1.9"), .wrongApp),
        (App(minimumSystemVersion: "999.0"), .requiresMacOS("999.0")),
        (App(version: "0.1.9", versionAfterSigning: "0.2.0"), .invalidSignature),
    ])
    func unsuitableAppIsRejected(update: App, error: UpdateError) throws {
        try expectRejection(error) { try install(archive(update)) }
    }

    @Test func downloadMustMatchTheDigestOfTheRelease() throws {
        let otherDigest = "sha256:" + String(repeating: "0", count: 64)
        try expectRejection(.damagedDownload) { try install(archive(App()), digest: otherDigest) }
    }

    @Test func downloadMustBeAnArchive() throws {
        try expectRejection(.unreadableArchive) { try install(Data("not an archive".utf8)) }
    }

    // The offer depends on the version that is running, but a newer one can have replaced it on disk.
    @Test func newerInstalledAppIsKept() throws {
        let newer = try #require(Version("0.3.0"))
        try expectRejection(.newerInstalled(newer), over: "0.3.0") { try install(archive(App())) }
    }

    @Test func swapFailsInAReadOnlyFolder() throws {
        try expectRejection(.notReplaceable) {
            let archive = try archive(App())
            try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
            // Otherwise deinit couldn't remove the app.
            defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path) }
            try install(archive)
        }
    }
}

private func run(_ tool: String, _ arguments: String...) throws {
    let process = try Process.run(URL(filePath: tool), arguments: arguments)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
