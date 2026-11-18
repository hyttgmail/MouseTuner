# MouseTuner

A small macOS app that gives each mouse its own tracking speed, scrolling speed and scroll direction. Your trackpad stays untouched.

System Settings › Mouse has one set of options shared by every mouse. MouseTuner keeps a separate set for each one.

- **Website:** https://alphapengwang.com/apps/mousetuner
- **Download:** [MouseTuner.dmg](https://github.com/hyttgmail/MouseTuner/releases/latest/download/MouseTuner.dmg) (free, signed and notarized)
- **Requires:** macOS 26 or later

## What it does

For each mouse:

- **Tracking speed**, 0–3, on the same scale as System Settings › Mouse › Tracking speed
- **Scrolling speed**
- **Reverse vertical / horizontal scrolling**, for that mouse only; the trackpad and other mice keep their own direction

Also:

- Settings are re-applied when a mouse reconnects or the Mac wakes.
- After you close the window MouseTuner stays in the menu bar. It can open at login.
- The interface is in English and Simplified Chinese. It follows the system language, or you can choose one in General (takes effect after a restart of the app).
- When you quit MouseTuner, every adjusted mouse goes back to the system defaults.

## Install

1. Download [MouseTuner.dmg](https://github.com/hyttgmail/MouseTuner/releases/latest/download/MouseTuner.dmg) and drag MouseTuner to Applications.
2. Open it. Connected mice appear in the sidebar within a second or two.
3. To reverse scrolling, allow MouseTuner in System Settings › Privacy & Security › Accessibility (named "Device Control and Data Access" on macOS 27). Changing speed needs no permission.

To update, download the DMG again and replace the app in Applications; your settings are kept. There is no automatic update. Versions are listed under [Releases](https://github.com/hyttgmail/MouseTuner/releases).

## Good to know

- Tools such as SteerMouse, LinearMouse, USB Overdrive and Mac Mouse Fix change the same settings, so they and MouseTuner overwrite each other. MouseTuner shows a notice while one of them is running.
- Logitech Logi Options+ has its own scroll direction and speed settings for Logitech mice; they add to the ones set here.
- MouseTuner collects no data and does not connect to the internet ([privacy policy](https://alphapengwang.com/apps/mousetuner/privacy)).

## Build from source

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/hyttgmail/MouseTuner.git
cd MouseTuner
./build.sh CODE_SIGN_IDENTITY=-   # result: build/MouseTuner.app
```

`build.sh` generates the Xcode project from `project.yml`, builds the Release configuration and copies the app to `build/`. It first quits a running MouseTuner. Extra arguments are passed to `xcodebuild`.

`CODE_SIGN_IDENTITY=-` signs the build ad hoc, which needs no certificate. macOS ties the scrolling permission to the signature, so an ad hoc build asks for it again after every rebuild. To avoid that, sign with a certificate of your own: set `DEVELOPMENT_TEAM` in `project.yml` to your team ID and run `./build.sh` without arguments.

### Packaging a release

```sh
Scripts/package.sh   # result: build/MouseTuner.dmg
```

The script signs with a Developer ID certificate, has Apple notarize the app and the DMG, staples the tickets and checks the result with Gatekeeper. It needs the "Developer ID Application" certificate named in the script and notary credentials saved once with `xcrun notarytool store-credentials MouseTuner-notary`. Before a release, raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.

## How it works

- **Speed:** MouseTuner writes `HIDMouseAcceleration` / `HIDMouseScrollAcceleration` to the HID service of one mouse through `IOHIDEventSystemClient`.
- **Scroll direction:** a session-level `CGEventTap` receives scroll-wheel events, reads integer field 87 of the `CGEvent` (the sender ID, which is the registry ID of the HID service) to tell which mouse sent it, and flips only the matching events. The field is not in the headers, but it is read with the public `CGEventGetIntegerValueField`.
- **Storage:** settings are kept in `UserDefaults`, keyed by vendor ID, product ID and name.
- The app is sandboxed and uses the hardened runtime.

The interface follows System Settings › Mouse on macOS 27: grouped forms, sliders with tick marks, system controls and semantic colors only.

### Icon

`Sources/AppIcon.icon` is a layered Icon Composer icon: `icon.json` and three SVG layers (the purple mouse behind, the blue mouse in front, the two scroll wheels). The system renders the Liquid Glass highlights and the dark, clear and tinted appearances. `Scripts/render-icon.sh <output directory>` renders every appearance into a contact sheet.

### Localization

Strings live in `Sources/Localizable.xcstrings`, a string catalog whose keys are the Chinese source text, with `zh-Hans` and `en` values. Add an English value for every new string, and keep the `zh-Hans` entries: without them the build has no `zh-Hans.lproj`.

## Support

Report a bug or ask for a feature in [Issues](https://github.com/hyttgmail/MouseTuner/issues), or write to support@alphapengwang.com. Please include your mouse model and macOS version. Answers to common questions are on the [support page](https://alphapengwang.com/apps/mousetuner/support).

## License

[MIT](LICENSE)
