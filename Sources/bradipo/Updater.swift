import AppKit
import BradipoCore

@MainActor
final class Updater: NSObject {
    let menuItem = NSMenuItem()
    private let releasesPage = URL(string: "https://github.com/marcoieni/bradipo/releases")!
    private let latestRelease = URL(string: "https://api.github.com/repos/marcoieni/bradipo/releases/latest")!
    private let session = URLSession(configuration: .ephemeral)

    override init() {
        super.init()
        menuItem.target = self
        menuItem.action = #selector(checkForUpdates)
        showProgress(nil)
    }

    private func showProgress(_ title: String?) {
        menuItem.title = title ?? "Check for Updates…"
        menuItem.isEnabled = title == nil
    }

    @objc private func checkForUpdates() {
        showProgress("Checking for Updates…")
        Task {
            do {
                try await update()
            } catch {
                let openPage = await ask("Couldn’t update bradipo", error.localizedDescription,
                                         buttons: "Open Releases Page", "Cancel")
                if openPage { NSWorkspace.shared.open(releasesPage) }
            }
            showProgress(nil)
        }
    }

    private func update() async throws {
        let app = Bundle.main.bundleURL
        let release = try await Release(json: fetch(latestRelease))
        guard let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let current = Version(string) else { throw UpdateError.notReplaceable }
        guard release.version > current else {
            _ = await ask("bradipo is up to date", "You have version \(current).", buttons: "OK")
            return
        }
        guard let archive = release.archive else { throw UpdateError.noArchive(release.version) }
        // A quarantined app can run from a read-only copy (App Translocation), and only administrators can
        // change /Applications.
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            throw UpdateError.notReplaceable
        }
        guard await ask("bradipo \(release.version) is available",
                        "You have version \(current). Relaunching restarts the timer and resumes paused reminders.",
                        buttons: "Install and Relaunch", "Cancel") else { return }

        showProgress("Installing bradipo \(release.version)…")
        let data = try await fetch(archive.url)
        try await Task.detached {
            try UpdateInstaller.install(data, digest: archive.digest, version: release.version, over: app)
        }.value
        await relaunch(app)
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw UpdateError.http(status: status)
        }
        return data
    }

    private func relaunch(_ app: URL) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        do {
            // Otherwise both instances would run until an open menu or alert closes.
            await whenIdle {}
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            // A menu can open during the launch.
            await whenIdle { NSApp.terminate(nil) }
        } catch {
            _ = await ask("Update installed", "Quit bradipo and open it again. \(error.localizedDescription)",
                          buttons: "OK")
        }
    }

    /// Returns whether the user chose the first button.
    private func ask(_ message: String, _ details: String, buttons: String...) async -> Bool {
        await whenIdle {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = details
            for button in buttons { alert.addButton(withTitle: button) }
            NSApp.activate()
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    /// Runs the action from the run loop, because an alert run by a task would block the main queue, which
    /// delivers sleep and microphone changes. The default mode waits for an open menu or alert to close.
    /// Until then, AppKit can ignore a request to quit.
    private func whenIdle<T: Sendable>(_ action: @escaping @MainActor @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform {
                continuation.resume(returning: MainActor.assumeIsolated(action))
            }
        }
    }
}
