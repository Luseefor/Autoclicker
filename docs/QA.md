# Release QA matrix

Before each release, run `swift test`, then exercise the app on a clean macOS user account with Accessibility initially disabled.

| Area | Targets | Expected result |
| --- | --- | --- |
| Permissions | Automater | Clear prompt and recovery after Accessibility is granted |
| Foreground clicking | Calculator, TextEdit | Correct click count; emergency stop works |
| Background clicking | Safari or Chromium fixture | Pointer remains still and supported controls receive actions |
| Incompatible target | A target with no AX windows | “Foreground recommended”; no claim that background input will work |
| Coordinates | Two displays, scaled display, moved window | Fixed and multi-point targets remain accurate |
| Macro recording | TextEdit | Recording, stop hotkey, replay, and cancellation behave correctly |
| Upgrade | Previous signed build | Settings and macros survive an app upgrade |

The real-app matrix is a compatibility test, not proof that every third-party app accepts automated input.
