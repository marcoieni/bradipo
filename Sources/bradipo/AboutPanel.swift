import AppKit
import SwiftUI

@MainActor
final class AboutPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = "About bradipo"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior.insert(.moveToActiveSpace)
        let content = NSHostingView(rootView: AboutContent())
        contentView = content
        setContentSize(content.fittingSize)
        center()
    }
}

private struct AboutContent: View {
    private let repository = URL(string: "https://github.com/marcoieni/bradipo")!
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    private let commit = Bundle.main.object(forInfoDictionaryKey: "BradipoGitCommit") as? String

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("bradipo").font(.headline)
            if let version {
                if let build, build != version {
                    Text("Version \(version) (\(build))")
                } else {
                    Text("Version \(version)")
                }
            }
            VStack(spacing: 2) {
                Link("github.com/marcoieni/bradipo", destination: repository)
                if let commit {
                    HStack(spacing: 0) {
                        Text("Commit ")
                        Link(String(commit.prefix(12)), destination: repository.appending(path: "commit/\(commit)"))
                    }
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 284)
    }
}
