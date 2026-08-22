"""Record mouse and keyboard into Macro steps."""

from __future__ import annotations

import threading
import time
from typing import Callable

from pynput import mouse

from app import windows as winmod
from app.mac_keys import KeyMonitor
from app.models import MacroStep, StepType

StatusCallback = Callable[[str], None]
StepsCallback = Callable[[list[MacroStep]], None]


class Recorder:
    """Capture clicks, moves, drags, and keys with relative delays."""

    def __init__(
        self,
        on_status: StatusCallback | None = None,
        on_steps: StepsCallback | None = None,
    ) -> None:
        self._on_status = on_status or (lambda _m: None)
        self._on_steps = on_steps or (lambda _s: None)
        self._steps: list[MacroStep] = []
        self._last_t: float | None = None
        self._mouse_listener: mouse.Listener | None = None
        self._key_monitor: KeyMonitor | None = None
        self._recording = False
        self._lock = threading.Lock()
        self.record_moves = False
        self.record_keys = True
        self.record_clicks = True
        self.record_scroll = True
        self.min_move_px = 8
        self.ignore_pids: set[int] = set()
        self.window_relative = False
        self.target_bundle_id: str | None = None
        self.target_app_name: str | None = None
        self.target_window_title: str | None = None
        # Drag tracking
        self._press_pos: tuple[int, int] | None = None
        self._press_button: str | None = None
        self._press_time: float | None = None
        self._drag_moved = False

    @property
    def recording(self) -> bool:
        return self._recording

    @property
    def steps(self) -> list[MacroStep]:
        with self._lock:
            return list(self._steps)

    def clear(self) -> None:
        with self._lock:
            self._steps.clear()
            self._last_t = None
        self._on_steps([])

    def _elapsed_ms(self) -> int:
        now = time.perf_counter()
        if self._last_t is None:
            self._last_t = now
            return 0
        ms = int((now - self._last_t) * 1000)
        self._last_t = now
        return max(0, ms)

    def _append(self, step: MacroStep) -> None:
        with self._lock:
            self._steps.append(step)
            snapshot = list(self._steps)
        self._on_steps(snapshot)

    def _target_window(self):
        if self.target_bundle_id or self.target_app_name or self.target_window_title:
            return winmod.find_window(
                bundle_id=self.target_bundle_id,
                app_name=self.target_app_name,
                window_title=self.target_window_title,
            )
        return winmod.frontmost_window()

    def _localize(self, x: int, y: int) -> dict:
        """Return MacroStep kwargs for position, optionally window-local."""
        base = {
            "x": int(x),
            "y": int(y),
            "coord_space": "screen",
            "local_x": None,
            "local_y": None,
            "app_bundle_id": None,
            "app_name": None,
            "window_title": None,
        }
        if not self.window_relative:
            return base
        window = self._target_window()
        if window is None or not winmod.point_in_window(x, y, window):
            return base
        lx, ly = winmod.screen_to_local(x, y, window)
        return {
            "x": int(x),
            "y": int(y),
            "coord_space": "window",
            "local_x": float(lx),
            "local_y": float(ly),
            "app_bundle_id": window.bundle_id or None,
            "app_name": window.app_name,
            "window_title": window.title,
            "window_id": window.window_id,
        }

    def _event_on_ignored_window(self, x: int, y: int) -> bool:
        if not self.ignore_pids:
            return False
        for w in winmod.list_windows():
            if w.pid in self.ignore_pids and winmod.point_in_window(x, y, w):
                return True
        return False

    def start(self) -> None:
        if self._recording:
            return
        self.clear()
        self._recording = True
        self._last_t = time.perf_counter()
        self._press_pos = None
        self._drag_moved = False
        self._on_status("Recording…")

        def on_click(x, y, button, pressed):
            if not self._recording or not self.record_clicks:
                return
            ix, iy = int(x), int(y)
            if self._event_on_ignored_window(ix, iy):
                return
            btn = str(button).split(".")[-1]
            if pressed:
                self._press_pos = (ix, iy)
                self._press_button = btn
                self._press_time = time.perf_counter()
                self._drag_moved = False
                return
            # Release
            if self._press_pos is None:
                return
            delay = self._elapsed_ms()
            loc = self._localize(self._press_pos[0], self._press_pos[1])
            if self._drag_moved or (
                abs(ix - self._press_pos[0]) > self.min_move_px
                or abs(iy - self._press_pos[1]) > self.min_move_px
            ):
                end_loc = self._localize(ix, iy)
                step = MacroStep(
                    type=StepType.DRAG,
                    button=self._press_button or btn,
                    delay_ms=delay,
                    end_x=ix,
                    end_y=iy,
                    end_local_x=end_loc.get("local_x"),
                    end_local_y=end_loc.get("local_y"),
                    **{k: v for k, v in loc.items()},
                )
            else:
                hold_ms = 0
                if self._press_time is not None:
                    hold_ms = int((time.perf_counter() - self._press_time) * 1000)
                if hold_ms >= 400:
                    step = MacroStep(
                        type=StepType.HOLD,
                        button=self._press_button or btn,
                        delay_ms=delay,
                        hold_ms=hold_ms,
                        **{k: v for k, v in loc.items()},
                    )
                else:
                    step = MacroStep(
                        type=StepType.CLICK,
                        button=self._press_button or btn,
                        delay_ms=delay,
                        click_kind="single",
                        **{k: v for k, v in loc.items()},
                    )
            self._press_pos = None
            self._append(step)

        def on_move(x, y):
            if not self._recording:
                return
            ix, iy = int(x), int(y)
            if self._press_pos is not None:
                if (
                    abs(ix - self._press_pos[0]) >= self.min_move_px
                    or abs(iy - self._press_pos[1]) >= self.min_move_px
                ):
                    self._drag_moved = True
                return
            if not self.record_moves:
                return
            if self._event_on_ignored_window(ix, iy):
                return
            with self._lock:
                if self._steps:
                    last = self._steps[-1]
                    if last.type == StepType.MOVE:
                        lx = last.local_x if last.coord_space == "window" else last.x
                        ly = last.local_y if last.coord_space == "window" else last.y
                        if lx is not None and ly is not None:
                            # Compare in screen space
                            if last.x is not None and last.y is not None:
                                if abs(last.x - ix) < self.min_move_px and abs(last.y - iy) < self.min_move_px:
                                    return
            delay = self._elapsed_ms()
            loc = self._localize(ix, iy)
            self._append(MacroStep(type=StepType.MOVE, delay_ms=delay, **loc))

        def on_scroll(x, y, dx, dy):
            if not self._recording or not self.record_scroll:
                return
            ix, iy = int(x), int(y)
            if self._event_on_ignored_window(ix, iy):
                return
            delay = self._elapsed_ms()
            loc = self._localize(ix, iy)
            self._append(
                MacroStep(
                    type=StepType.SCROLL,
                    dx=int(dx),
                    dy=int(dy),
                    delay_ms=delay,
                    **loc,
                )
            )

        def on_press(name: str, _event) -> None:
            if not self._recording or not self.record_keys:
                return
            if name in {"cmd", "shift", "ctrl", "alt"}:
                return
            delay = self._elapsed_ms()
            self._append(MacroStep(type=StepType.KEY_DOWN, key=name, delay_ms=delay))

        def on_release(name: str, _event) -> None:
            if not self._recording or not self.record_keys:
                return
            if name in {"cmd", "shift", "ctrl", "alt"}:
                return
            delay = self._elapsed_ms()
            with self._lock:
                if (
                    self._steps
                    and self._steps[-1].type == StepType.KEY_DOWN
                    and self._steps[-1].key == name
                    and delay < 50
                ):
                    prev = self._steps.pop()
                    step = MacroStep(type=StepType.KEY, key=name, delay_ms=prev.delay_ms)
                    snapshot = list(self._steps) + [step]
                    self._steps.append(step)
                    self._on_steps(snapshot)
                    return
            self._append(MacroStep(type=StepType.KEY_UP, key=name, delay_ms=delay))

        self._mouse_listener = mouse.Listener(
            on_click=on_click,
            on_move=on_move,
            on_scroll=on_scroll,
        )
        self._key_monitor = KeyMonitor(on_down=on_press, on_up=on_release)
        self._mouse_listener.start()
        self._key_monitor.start()

    def stop(self) -> list[MacroStep]:
        self._recording = False
        if self._mouse_listener:
            self._mouse_listener.stop()
            self._mouse_listener = None
        if self._key_monitor:
            self._key_monitor.stop()
            self._key_monitor = None
        steps = self.steps
        self._on_status(f"Recorded {len(steps)} steps")
        return steps
