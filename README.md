# Automater

Automater is a macOS desktop automation app for clicking, macros, and recording.

## Safety and compatibility

Background delivery uses documented macOS accessibility actions and synthetic events. Apps may reject these inputs; Automater reports that as foreground recommended. It does not attempt to bypass app, game, or anti-cheat input protections.

## Testing

Run unit tests with `cd AutomaterMac && swift test`.

For the live Chromium end-to-end suite, grant Accessibility to the terminal, install the development requirements, then run `AUTOMATER_E2E_ENGINE=swift .venv/bin/python tests/e2e_browser.py`.

See [the QA matrix](docs/QA.md), [privacy policy](docs/PRIVACY.md), and [support policy](docs/SUPPORT.md).
