"""Main-thread-safe macOS key monitoring via NSEvent (no pynput keyboard)."""

from __future__ import annotations

from typing import Callable

# Virtual keycode → stable name (matches engine/pynput-ish names where possible)
_VK_NAME = {
    36: "enter",
    48: "tab",
    49: "space",
    51: "backspace",
    53: "esc",
    123: "left",
    124: "right",
    125: "down",
    126: "up",
    122: "f1",
    120: "f2",
    99: "f3",
    118: "f4",
    96: "f5",
    97: "f6",
    98: "f7",
    100: "f8",
    101: "f9",
    109: "f10",
    103: "f11",
    111: "f12",
    55: "cmd",
    54: "cmd",
    56: "shift",
    60: "shift",
    59: "ctrl",
    62: "ctrl",
    58: "alt",
    61: "alt",
}


def key_name_from_nsevent(event) -> str:
    code = int(event.keyCode())
    if code in _VK_NAME:
        return _VK_NAME[code]
    try:
        chars = event.charactersIgnoringModifiers()
        if chars:
            ch = str(chars)
            if len(ch) == 1 and ch.isprintable():
                return ch.lower() if ch.isalpha() else ch
    except Exception:
        pass
    return f"vk_{code}"


class KeyMonitor:
    """Local + global NSEvent key monitors (safe on macOS 26+)."""

    def __init__(
        self,
        on_down: Callable[[str, object], None] | None = None,
        on_up: Callable[[str, object], None] | None = None,
    ) -> None:
        self._on_down = on_down
        self._on_up = on_up
        self._local_down = None
        self._global_down = None
        self._local_up = None
        self._global_up = None

    def start(self) -> bool:
        self.stop()
        try:
            from AppKit import NSEvent, NSEventMaskKeyDown, NSEventMaskKeyUp
        except Exception:
            return False

        def down_local(event):
            self._fire_down(event)
            return event

        def down_global(event):
            self._fire_down(event)

        def up_local(event):
            self._fire_up(event)
            return event

        def up_global(event):
            self._fire_up(event)

        try:
            if self._on_down:
                self._local_down = NSEvent.addLocalMonitorForEventsMatchingMask_handler_(
                    NSEventMaskKeyDown, down_local
                )
                self._global_down = NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
                    NSEventMaskKeyDown, down_global
                )
            if self._on_up:
                self._local_up = NSEvent.addLocalMonitorForEventsMatchingMask_handler_(
                    NSEventMaskKeyUp, up_local
                )
                self._global_up = NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
                    NSEventMaskKeyUp, up_global
                )
            return True
        except Exception:
            self.stop()
            return False

    def _fire_down(self, event) -> None:
        if not self._on_down:
            return
        try:
            if event.isARepeat():
                return
            self._on_down(key_name_from_nsevent(event), event)
        except Exception:
            pass

    def _fire_up(self, event) -> None:
        if not self._on_up:
            return
        try:
            self._on_up(key_name_from_nsevent(event), event)
        except Exception:
            pass

    def stop(self) -> None:
        try:
            from AppKit import NSEvent
        except Exception:
            return
        for mon in (
            self._local_down,
            self._global_down,
            self._local_up,
            self._global_up,
        ):
            if mon is not None:
                try:
                    NSEvent.removeMonitor_(mon)
                except Exception:
                    pass
        self._local_down = None
        self._global_down = None
        self._local_up = None
        self._global_up = None
