"""macOS Accessibility / Input Monitoring permission helpers."""

from __future__ import annotations

import subprocess
from dataclasses import dataclass


@dataclass
class PermissionStatus:
    accessibility: bool
    input_monitoring: bool | None  # None = unknown
    input_monitoring_note: str


def is_accessibility_trusted(prompt: bool = False) -> bool:
    """Return True if this process is trusted for Accessibility."""
    try:
        from ApplicationServices import AXIsProcessTrusted, AXIsProcessTrustedWithOptions
        from Foundation import NSDictionary

        if prompt:
            opts = NSDictionary.dictionaryWithDictionary_(
                {"AXTrustedCheckOptionPrompt": True}
            )
            return bool(AXIsProcessTrustedWithOptions(opts))
        return bool(AXIsProcessTrusted())
    except Exception:
        # Fallback via Quartz / ctypes if pyobjc ApplicationServices missing pieces
        try:
            import ctypes
            import ctypes.util

            path = ctypes.util.find_library("ApplicationServices")
            if not path:
                return False
            lib = ctypes.cdll.LoadLibrary(path)
            if prompt:
                # Without options dict, just check
                pass
            lib.AXIsProcessTrusted.restype = ctypes.c_bool
            return bool(lib.AXIsProcessTrusted())
        except Exception:
            return False


def request_accessibility() -> bool:
    """Trigger the system Accessibility trust prompt when possible."""
    return is_accessibility_trusted(prompt=True)


def open_accessibility_settings() -> None:
    """Open System Settings → Privacy & Security → Accessibility."""
    urls = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
    ]
    for url in urls:
        try:
            subprocess.run(["open", url], check=False)
            return
        except OSError:
            continue
    subprocess.run(
        ["open", "x-apple.systempreferences:com.apple.preference.security"],
        check=False,
    )


def open_input_monitoring_settings() -> None:
    """Open System Settings → Privacy & Security → Input Monitoring."""
    urls = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
    ]
    for url in urls:
        try:
            subprocess.run(["open", url], check=False)
            return
        except OSError:
            continue


def is_input_monitoring_granted() -> bool | None:
    """True/False when macOS reports it; None if the API is unavailable."""
    try:
        import ctypes
        import ctypes.util

        path = ctypes.util.find_library("IOKit") or (
            "/System/Library/Frameworks/IOKit.framework/IOKit"
        )
        lib = ctypes.cdll.LoadLibrary(path)
        if not hasattr(lib, "IOHIDCheckAccess"):
            return None
        lib.IOHIDCheckAccess.argtypes = [ctypes.c_int]
        lib.IOHIDCheckAccess.restype = ctypes.c_int
        # kIOHIDRequestTypeListenEvent = 1
        # kIOHIDAccessTypeGranted = 0, Denied = 1, Unknown = 2
        result = int(lib.IOHIDCheckAccess(1))
        if result == 0:
            return True
        if result == 1:
            return False
        return None
    except Exception:
        return None


def get_status() -> PermissionStatus:
    trusted = is_accessibility_trusted(prompt=False)
    listen = is_input_monitoring_granted()
    if listen is True:
        note = ""
    elif listen is False:
        note = "Needed for global hotkeys and keyboard recording."
    else:
        note = "Enable if global hotkeys or keyboard recording fail."
    return PermissionStatus(
        accessibility=trusted,
        input_monitoring=listen,
        input_monitoring_note=note,
    )
