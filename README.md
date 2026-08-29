# Automater

Automater is a native macOS desktop automation app for clicking, macro recording, and keyboard workflows.

## Highlights

- Configurable clicking with interval, jitter, button, click-type, and repeat controls
- Current-cursor, fixed-point, and multi-point modes
- Recorded macros for clicks, typing, keyboard shortcuts, scrolling, and swipes
- Readable, editable macro steps with individual deletion
- An always-on-top control panel plus a redesigned status-bar quick-control menu
- Background delivery where macOS supports it, with compatibility feedback
- Custom app icon and a drag-to-Applications DMG installer

## Safety and compatibility

Background delivery uses documented macOS accessibility actions and synthetic events. Apps may reject these inputs; Automater reports that as foreground recommended. It does not attempt to bypass app input protections.

## Testing

Run unit tests with `cd AutomaterMac && swift test`.

To produce a local review build, run `AutomaterMac/scripts/bundle_app.sh`, then `AutomaterMac/scripts/install_local.sh`. This installer closes the existing Automater instance before replacing it, so duplicate windows are not left running. Use `AutomaterMac/scripts/create_dmg.sh` to produce the custom DMG installer.

The current local release artifacts are written to `dist/Automater.zip` and `dist/Automater.dmg`. Public release signing and notarization require a Developer ID identity and a `notarytool` keychain profile; credentials are never stored in this repository.

See [the QA matrix](docs/QA.md), [privacy policy](docs/PRIVACY.md), and [support policy](docs/SUPPORT.md).
