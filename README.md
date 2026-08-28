# Automater

Automater is a macOS desktop automation app for clicking, macros, and recording.

## Safety and compatibility

Background delivery uses documented macOS accessibility actions and synthetic events. Apps may reject these inputs; Automater reports that as foreground recommended. It does not attempt to bypass app input protections.

## Testing

Run unit tests with `cd AutomaterMac && swift test`.

To produce a local review build, run `AutomaterMac/scripts/bundle_app.sh`, then `AutomaterMac/scripts/install_local.sh`. This installer closes the existing Automater instance before replacing it, so duplicate windows are not left running. Use `AutomaterMac/scripts/create_dmg.sh` to produce the DMG. Release signing and notarization require a Developer ID identity and a `notarytool` keychain profile; credentials are never stored in this repository.

See [the QA matrix](docs/QA.md), [privacy policy](docs/PRIVACY.md), and [support policy](docs/SUPPORT.md).

## License

This project is licensed under the [MIT License](LICENSE).
