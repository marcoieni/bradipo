# bradipo

<img src="Resources/Sloth.png" alt="bradipo logo" width="240" align="right">

bradipo is a menu-bar break reminder for macOS. A monospaced countdown keeps its place in the bar. Every 20 minutes, a soft green glow frames each display and a sleeping sloth invites you to rest your eyes for 20 seconds. You can keep typing or clicking elsewhere on the screen. Click the sloth card on any display to end the break early and start a fresh work interval.

Click the countdown to start a break, pause reminders, restart the timer, or change the work interval and break length. During a break, choose **Stop break** to start a fresh work interval. Choose **Launch at Login** to have macOS open bradipo when you sign in. **About bradipo** shows the installed version.

<br clear="right">

### Meetings and time away

- **Defer Breaks During Meetings** is on by default. The countdown keeps running during calls and dictation. If a break comes due while another app uses the microphone or camera, the timer holds at **00:00**. The full break starts as soon as both devices are free. If either device turns on during a break, the reminder stays visible and the break finishes on schedule. Detection uses Core Audio and AVFoundation, so a call with both devices off can go undetected. You can turn this setting off in the menu.
- After one minute without keyboard or pointer input, bradipo pauses. After five minutes away, you return to a fresh work interval. Time spent in a detected meeting counts as work.
- Putting the Mac or its display to sleep, or switching user sessions, also starts a fresh interval when you return.

### Install

bradipo requires macOS 27.2.1 or later. Download `bradipo-<version>.dmg` from the [latest release](https://github.com/marcoieni/bradipo/releases/latest), open it, and drag bradipo into Applications.

Releases aren't notarized by Apple, so macOS blocks bradipo the first time you open each newly downloaded version. In the warning, click **Done**, not **Move to Trash**. Then open **System Settings > Privacy & Security**, click **Open Anyway** next to the message about bradipo, and confirm. If macOS instead reports that bradipo is damaged and you downloaded it from this repository's [Releases](https://github.com/marcoieni/bradipo/releases) page, remove the download quarantine in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/bradipo.app
```

If your copy came from anywhere else, move it to the Trash and download it again from the Releases page. Every update is a new download, so allow each new version the same way.

### Build and run

Requires macOS 27.2.1 or later and Swift 6.4 from Xcode or the Command Line Tools. The app uses Apple frameworks and builds without downloading any packages.

```sh
./scripts/build-app.sh
open .build/bradipo.app
```

To install it, drag the built `bradipo.app` into Applications.

### Test

Run `swift test` with Xcode selected. With the standalone Command Line Tools, supply the bundled Swift Testing plug-in path.

```sh
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
```

### Release

Push a tag of the form `vMAJOR.MINOR.PATCH`:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The release workflow runs the tests, builds bradipo with the tag's version, and publishes `bradipo-0.2.0.dmg` on a GitHub release for the tag. You don't need to edit `Resources/Info.plist`; its version only applies to local builds. To package a local build the same way, run `./scripts/build-app.sh 0.2.0` and then `./scripts/package-dmg.sh`.

Releases are signed ad hoc and not notarized, which is why users need the Gatekeeper step in [Install](#install). Notarizing requires a paid Apple Developer ID.
