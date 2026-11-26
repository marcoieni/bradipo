import BradipoCore
import Foundation
import Testing

@Test func versionsCompareByNumber() throws {
    let older = try #require(Version("0.9.0"))
    let newer = try #require(Version("0.10.0"))
    #expect(older < newer)
    // macOS versions can leave out trailing zeros.
    #expect(Version("28") == Version("28.0.0"))
}

@Test(arguments: ["", "1..2", "1.-2.3", "1.2.3-beta", "1.2.3.4"])
func malformedVersionsAreRejected(_ string: String) {
    #expect(Version(string) == nil)
}

private func release(tag: String = "v0.2.0", assets: String) throws -> Release {
    try Release(json: Data(#"{"tag_name": "\#(tag)", "draft": false, "assets": [\#(assets)]}"#.utf8))
}

private func asset(_ name: String, digest: String) -> String {
    #"{"name": "\#(name)", "size": 1, "digest": \#(digest), "browser_download_url": "https://example.com/\#(name)"}"#
}

@Test func releaseOffersItsArchiveAlongsideTheDiskImage() throws {
    let release = try release(assets: asset("bradipo-0.2.0.dmg", digest: #""sha256:01""#) + ","
                                    + asset("bradipo.tar.gz", digest: #""sha256:02""#))
    #expect(release.version == Version("0.2.0"))
    #expect(release.archive?.url.absoluteString == "https://example.com/bradipo.tar.gz")
    #expect(release.archive?.digest == "sha256:02")
}

// v0.1.0 has only a disk image, and GitHub has no digest for files uploaded before it computed them.
@Test(arguments: [asset("bradipo-0.1.0.dmg", digest: #""sha256:01""#), asset("bradipo.tar.gz", digest: "null")])
func releaseWithoutAVerifiableArchiveStillHasAVersion(assets: String) throws {
    let release = try release(assets: assets)
    #expect(release.version == Version("0.2.0"))
    #expect(release.archive == nil)
}

@Test(arguments: ["0.2.0", "v0.2.0-beta", "nightly"])
func releaseWithAnotherKindOfTagIsRejected(tag: String) {
    #expect(throws: UpdateError.unexpectedTag(tag)) { try release(tag: tag, assets: "") }
}
