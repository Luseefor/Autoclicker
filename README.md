# Automater

Automater is a macOS desktop automation app for clicking, macros, and recording.

## Safety and compatibility

Background delivery uses documented macOS accessibility actions and synthetic events. Apps may reject these inputs; Automater reports that as foreground recommended. It does not attempt to bypass app, game, or anti-cheat input protections.

## Testing

Run unit tests with `cd AutomaterMac && swift test`.

To produce a local review build, run `AutomaterMac/scripts/bundle_app.sh`, then `AutomaterMac/scripts/create_dmg.sh`. Release signing and notarization require a Developer ID identity and a `notarytool` keychain profile; credentials are never stored in this repository.

See [the QA matrix](docs/QA.md), [privacy policy](docs/PRIVACY.md), and [support policy](docs/SUPPORT.md).
