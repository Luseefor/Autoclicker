"""Global hotkeys via NSEvent monitors (main-thread safe on macOS 26+).

pynput's keyboard listener calls HIToolbox from a background thread, which
trips dispatch_assert_queue and kills Python with SIGTRAP. NSEvent monitors
run on the main CFRunLoop that Qt already pumps.
"""

from __future__ import annotations

from typing import Callable

# macOS virtual keycodes (ANSI) for common shortcut keys
_VK = {
    "a": 0,
    "s": 1,
    "d": 2,
    "f": 3,
    "h": 4,
    "g": 5,
    "z": 6,
    "x": 7,
    "c": 8,
    "v": 9,
    "b": 11,
    "q": 12,
    "w": 13,
    "e": 14,
    "r": 15,
    "y": 16,
    "t": 17,
    "1": 18,
    "2": 19,
    "3": 20,
    "4": 21,
    "6": 22,
    "5": 23,
    "9": 25,
    "7": 26,
    "8": 28,
    "0": 29,
    "o": 31,
    "u": 32,
    "i": 34,
    "p": 35,
    "l": 37,
    "j": 38,
    "k": 40,
    "n": 45,
    "m": 46,
    "f1": 122,
    "f2": 120,
    "f3": 99,
    "f4": 118,
    "f5": 96,
    "f6": 97,
    "f7": 98,
    "f8": 100,
    "f9": 101,
    "f10": 109,
    "f11": 103,
    "f12": 111,
    "space": 49,
    "esc": 53,
    "escape": 53,
    "tab": 48,
    "enter": 36,
    "return": 36,
    "delete": 51,
    "backspace": 51,
}

_MOD_NAMES = {
    "ctrl": "ctrl",
    "control": "ctrl",
    "alt": "alt",
    "option": "alt",
    "opt": "alt",
    "shift": "shift",
    "cmd": "cmd",
    "command": "cmd",
    "super": "cmd",
}


def _parse_binding(binding: str) -> tuple[set[str], int] | None:
    """'<ctrl>+<alt>+a' -> ({'ctrl','alt'}, keycode)."""
    mods: set[str] = set()
    keycode: int | None = None
    for raw in binding.split("+"):
        token = raw.strip().strip("<>").lower()
        if not token:
            continue
        if token in _MOD_NAMES:
            mods.add(_MOD_NAMES[token])
            continue
        if token in _VK:
            keycode = _VK[token]
            continue
        if len(token) == 1 and token in _VK:
            keycode = _VK[token]
            continue
        return None
    if keycode is None:
        return None
    return mods, keycode


class HotkeyManager:
    def __init__(self) -> None:
        self._bindings: list[tuple[set[str], int, Callable[[], None]]] = []
        self._local = None
        self._global = None
        self._ns = None  # AppKit enums cached

    def set_bindings(self, bindings: dict[str, Callable[[], None]]) -> None:
        self.stop()
        compiled: list[tuple[set[str], int, Callable[[], None]]] = []
        for key, cb in bindings.items():
            if not key or not cb:
                continue
            parsed = _parse_binding(key)
            if parsed is None:
                continue
            mods, code = parsed
            compiled.append((mods, code, cb))
        self._bindings = compiled
        if not self._bindings:
            return
        try:
            from AppKit import (
                NSEvent,
                NSEventModifierFlagCommand,
                NSEventModifierFlagControl,
                NSEventModifierFlagOption,
                NSEventModifierFlagShift,
                NSEventMaskKeyDown,
            )
        except Exception:
            return

        self._ns = {
            "ctrl": NSEventModifierFlagControl,
            "alt": NSEventModifierFlagOption,
            "shift": NSEventModifierFlagShift,
            "cmd": NSEventModifierFlagCommand,
        }
        mask = NSEventMaskKeyDown

        def handle(event):
            self._dispatch(event)
            return event

        def handle_global(event):
            self._dispatch(event)

        try:
            self._local = NSEvent.addLocalMonitorForEventsMatchingMask_handler_(mask, handle)
            self._global = NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
                mask, handle_global
            )
        except Exception:
            self.stop()

    def _dispatch(self, event) -> None:
        if not self._bindings or self._ns is None:
            return
        try:
            # Ignore key-repeat
            if event.isARepeat():
                return
            code = int(event.keyCode())
            flags = int(event.modifierFlags())
            present = {name for name, bit in self._ns.items() if flags & bit}
            for want_mods, want_code, cb in self._bindings:
                if code != want_code:
                    continue
                if present != want_mods:
                    continue
                try:
                    cb()
                except Exception:
                    pass
                return
        except Exception:
            return

    def stop(self) -> None:
        try:
            from AppKit import NSEvent
        except Exception:
            NSEvent = None  # type: ignore
        if NSEvent is not None:
            if self._local is not None:
                try:
                    NSEvent.removeMonitor_(self._local)
                except Exception:
                    pass
            if self._global is not None:
                try:
                    NSEvent.removeMonitor_(self._global)
                except Exception:
                    pass
        self._local = None
        self._global = None
        self._bindings = []
