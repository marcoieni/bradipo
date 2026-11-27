# Notes for agents

Build, run, and test commands are in [README.md](README.md), along with how each feature should behave. `swift test` covers the logic in `Sources/BradipoCore`. Nothing checks how the app in `Sources/bradipo` looks or behaves on screen.

## Check changes in the running app

Decide for each task whether you need to see the result:

- Changes to anything the app shows (such as the countdown, the menu, the glow, the sloth card, or any panel or dialog), or to how anything moves, resizes, or responds to input: yes. Build the app, run it, and check the result with computer use.
- Logic covered by `swift test`, docs, and scripts: usually no. Tests or a careful read are enough.

If you're not sure, look.

Build and launch your copy:

```sh
pkill -f "$(pwd -P)/.build/bradipo.app/"
./scripts/build-app.sh && open -n .build/bradipo.app --args -workSeconds 5999 -breakSeconds 300
```

- `-workSeconds 5999` starts your countdown at 99:59, so you can tell it apart from an installed copy that may also be running. Don't quit that copy.
- `-breakSeconds 300` keeps a break on screen for five minutes. Launch arguments like these last only until the app quits and don't change saved settings.
- Click your countdown in the menu bar to open the menu. Choose **Take a Break** to see the glow and the sloth card now instead of waiting (with **Defer Breaks During Meetings** on, it's greyed out while a mic or camera is in use).
- Your build shares saved settings with the installed copy. Before you change a setting, drag or resize the card, or reset anything, save them once with `defaults export com.marcoieni.bradipo "$TMPDIR/bradipo-settings.plist"`. Don't use **Launch at Login** or **Check for Updates…** unless the task is about them.
- When you're done, quit your copy with `pkill -f "$(pwd -P)/.build/bradipo.app/"`. If you saved the settings, then restore them with `defaults delete com.marcoieni.bradipo; defaults import com.marcoieni.bradipo "$TMPDIR/bradipo-settings.plist"`. If there were none before, this leaves none.

## Without computer use

Browser and simulator previews can't show the Mac desktop or menu bar. If you have no tool that can see the desktop, make sure the app at least builds and launches (`pgrep -fl "$(pwd -P)/.build/bradipo.app/"` should list your copy), then try `screencapture -x "$TMPDIR/bradipo.png"` and view the image. A short `-workSeconds` starts a break without a click, but the countdown only runs if someone used the keyboard or pointer, in any app, within the last minute, even right after launch. If `screencapture` reports "could not create image from display", the process running it lacks Screen Recording permission, so don't retry or change privacy settings.

If you couldn't see the change, say so plainly in your final reply and list what the user should check. Never claim you checked something visually when you didn't.
