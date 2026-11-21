# bradipo

bradipo is a menu-bar break reminder for macOS. A monospaced countdown keeps its place in the bar. Every 20 minutes, a soft green glow frames each display and a sleeping sloth invites you to rest your eyes for 20 seconds. You can finish a sentence or click a control underneath the reminder. The break ends on its own.

Click the countdown to start a break, pause reminders, or change the work interval and break length. bradipo remembers your timing choices.

### When the clock pauses

- While another app uses a microphone or camera, bradipo holds the work countdown. It reads device activity through Core Audio and AVFoundation. Calls with both devices inactive can go undetected, and recording apps can also pause the timer.
- After one minute without keyboard or pointer input, bradipo pauses. After five minutes away, you return to a fresh work interval.
- Putting the Mac or its display to sleep, or switching user sessions, also starts a fresh interval when you return.

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
