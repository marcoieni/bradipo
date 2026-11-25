import Foundation

/// An app or macOS version. Missing components count as zero.
public struct Version: Comparable, CustomStringConvertible, Sendable {
    private let components: [Int]
    public var description: String { components.map(String.init).joined(separator: ".") }

    public init?(_ string: some StringProtocol) {
        var components: [Int] = []
        for part in string.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(part), number >= 0 else { return nil }
            components.append(number)
        }
        guard components.count <= 3 else { return nil }
        self.components = components + Array(repeating: 0, count: 3 - components.count)
    }

    init(_ system: OperatingSystemVersion) {
        components = [system.majorVersion, system.minorVersion, system.patchVersion]
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// What an update needs from GitHub's description of a release.
public struct Release: Sendable {
    public struct Archive: Sendable {
        public let url: URL
        public let digest: String
    }

    public let version: Version
    /// Nil if the release has no archive, or no digest to check it against.
    public let archive: Archive?

    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: json)
        guard response.tagName.hasPrefix("v"), let version = Version(response.tagName.dropFirst()) else {
            throw UpdateError.unexpectedTag(response.tagName)
        }
        self.version = version
        archive = response.assets.first { $0.name == "bradipo.tar.gz" }.flatMap { asset in
            asset.digest.map { Archive(url: asset.browserDownloadUrl, digest: $0) }
        }
    }

    private struct Response: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            let digest: String?
        }

        let tagName: String
        let assets: [Asset]
    }
}
