"""Playback engine for clicker and macros. Stopping never quits the app."""

from __future__ import annotations

import random
import re
import threading
import time
from typing import Callable

from pynput.keyboard import Controller as KeyController
from pynput.keyboard import Key

from app import windows as winmod
from app.models import Macro, MacroStep, StepType

StatusCallback = Callable[[str], None]

# Quartz mouse button codes
_BTN_LEFT = 0
_BTN_RIGHT = 1
_BTN_CENTER = 2


def _resolve_key(name: str):
    if not name:
        return None
    lowered = name.lower()
    special = {
        "space": Key.space,
        "enter": Key.enter,
        "return": Key.enter,
        "tab": Key.tab,
        "esc": Key.esc,
        "escape": Key.esc,
        "backspace": Key.backspace,
        "delete": Key.delete,
        "shift": Key.shift,
        "shift_r": Key.shift_r,
        "ctrl": Key.ctrl,
        "ctrl_l": Key.ctrl_l,
        "ctrl_r": Key.ctrl_r,
        "alt": Key.alt,
        "alt_l": Key.alt_l,
        "alt_r": Key.alt_r,
        "cmd": Key.cmd,
        "cmd_l": Key.cmd,
        "cmd_r": Key.cmd_r,
        "up": Key.up,
        "down": Key.down,
        "left": Key.left,
        "right": Key.right,
        "home": Key.home,
        "end": Key.end,
        "page_up": Key.page_up,
        "page_down": Key.page_down,
        "caps_lock": Key.caps_lock,
    }
    if lowered in special:
        return special[lowered]
    if lowered.startswith("f") and lowered[1:].isdigit():
        return getattr(Key, lowered, None)
    if len(name) == 1:
        return name
    return getattr(Key, lowered, name)


_CHORD_MODS = {
    "cmd": Key.cmd,
    "command": Key.cmd,
    "ctrl": Key.ctrl,
    "control": Key.ctrl,
    "alt": Key.alt,
    "option": Key.alt,
    "opt": Key.alt,
    "shift": Key.shift,
}


def _resolve_chord(name: str) -> tuple[list, object | None]:
    """Resolve 'ctrl+shift+t' into ([Key.ctrl, Key.shift], 't').

    Modifier parts must resolve to pynput modifier keys; anything else is
    treated as the (single) tail key. Returns ([], tail) for plain keys.
    """
    parts = [p for p in re.split(r"\+", name or "") if p.strip()]
    if not parts:
        return [], None
    if len(parts) == 1:
        return [], _resolve_key(parts[0])
    mods: list = []
    tails: list[str] = []
    for raw in parts:
        resolved = _resolve_key(raw)
        if raw.lower() in _CHORD_MODS and not isinstance(resolved, str):
            if resolved not in mods:
                mods.append(resolved)
        else:
            tails.append(raw)
    tail = _resolve_key("+".join(tails)) if tails else None
    return mods, tail


def _button_code(name: str | None) -> int:
    return {
        "left": _BTN_LEFT,
        "right": _BTN_RIGHT,
        "middle": _BTN_CENTER,
    }.get((name or "left").lower(), _BTN_LEFT)


def _click_count(kind: str | None, clicks: int) -> int:
    if kind == "double":
        return 2
    if kind == "triple":
        return 3
    return max(1, clicks)


def _cursor_pos() -> tuple[float, float]:
    try:
        from Quartz import CGEventCreate, CGEventGetLocation

        event = CGEventCreate(None)
        loc = CGEventGetLocation(event)
        return float(loc.x), float(loc.y)
    except Exception:
        return 0.0, 0.0


def _event_source(private: bool = False):
    from Quartz import (
        CGEventSourceCreate,
        kCGEventSourceStateHIDSystemState,
        kCGEventSourceStatePrivate,
    )

    kind = kCGEventSourceStatePrivate if private else kCGEventSourceStateHIDSystemState
    return CGEventSourceCreate(kind)


def _post_mouse_event(
    etype,
    x: float,
    y: float,
    button: int,
    pid: int | None,
    click_state: int = 1,
) -> None:
    from Quartz import (
        CGEventCreateMouseEvent,
        CGEventPost,
        CGEventPostToPid,
        CGEventSetIntegerValueField,
        CGEventSetLocation,
        kCGHIDEventTap,
        kCGMouseEventButtonNumber,
        kCGMouseEventClickState,
    )

    src = _event_source(private=bool(pid))
    event = CGEventCreateMouseEvent(src, etype, (float(x), float(y)), button)
    if event is None:
        return
    CGEventSetLocation(event, (float(x), float(y)))
    CGEventSetIntegerValueField(event, kCGMouseEventClickState, int(click_state))
    if button:
        CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, int(button))
    if pid:
        CGEventPostToPid(int(pid), event)
    else:
        CGEventPost(kCGHIDEventTap, event)


def _pids_at_point(app_pid: int, x: float, y: float) -> list[int]:
    """App pid plus WebKit/Chrome renderer pid when the point is in web content."""
    import re

    pids = [int(app_pid)]
    try:
        from ApplicationServices import AXUIElementCopyElementAtPosition, AXUIElementCreateApplication

        app_ref = AXUIElementCreateApplication(int(app_pid))
        err, el = AXUIElementCopyElementAtPosition(app_ref, float(x), float(y), None)
        if err == 0 and el is not None:
            m = re.search(r"pid=(\d+)", str(el))
            if m:
                child = int(m.group(1))
                if child not in pids:
                    pids.append(child)
    except Exception:
        pass
    return pids


_FLAG_FOR_MOD = {
    "cmd": "kCGEventFlagMaskCommand",
    "command": "kCGEventFlagMaskCommand",
    "ctrl": "kCGEventFlagMaskControl",
    "control": "kCGEventFlagMaskControl",
    "alt": "kCGEventFlagMaskAlternate",
    "option": "kCGEventFlagMaskAlternate",
    "opt": "kCGEventFlagMaskAlternate",
    "shift": "kCGEventFlagMaskShift",
}


def _post_key_combo_to_pid(pid: int, combo: str) -> bool:
    """Send a key (or modifier chord like 'cmd+c') straight to a process.

    Returns False when any part of the combo has no virtual keycode or
    posting failed, so the caller can fall back to global delivery.
    """
    from app import keycodes as kc

    parts = [p for p in re.split(r"\+", combo or "") if p.strip()]
    if not parts:
        return False
    mods: list[int] = []
    tail: int | None = None
    for raw in parts:
        lowered = raw.strip().lower()
        code = kc.keycode_for(lowered)
        if code is None:
            return False
        if lowered in _FLAG_FOR_MOD:
            mods.append(code)
        else:
            tail = code
    if tail is None:
        return False

    try:
        from Quartz import (
            CGEventCreateKeyboardEvent,
            CGEventPostToPid,
            CGEventSetFlags,
        )

        flag_names = [_FLAG_FOR_MOD[p.strip().lower()] for p in parts
                      if p.strip().lower() in _FLAG_FOR_MOD]
        flags = 0
        if flag_names:
            import Quartz as _Q

            flags = 0
            for fname in flag_names:
                flags |= getattr(_Q, fname)
        src = _event_source(private=True)

        def post(keycode: int, down: bool) -> None:
            event = CGEventCreateKeyboardEvent(src, int(keycode), bool(down))
            if event is None:
                raise RuntimeError("CGEventCreateKeyboardEvent failed")
            if flags:
                CGEventSetFlags(event, flags)
            CGEventPostToPid(int(pid), event)

        for code in mods:
            post(code, True)
        post(tail, True)
        time.sleep(0.008)
        post(tail, False)
        for code in reversed(mods):
            post(code, False)
        return True
    except Exception:
        return False


def _warp_cursor(x: float, y: float) -> None:
    """Actually move the system pointer. MouseMoved events alone do not."""
    try:
        from Quartz import CGAssociateMouseAndMouseCursorPosition, CGWarpMouseCursorPosition

        CGWarpMouseCursorPosition((float(x), float(y)))
        CGAssociateMouseAndMouseCursorPosition(True)
    except Exception:
        pass


def _move_cursor(x: float, y: float, pid: int | None = None) -> None:
    try:
        from Quartz import kCGEventMouseMoved

        _post_mouse_event(kCGEventMouseMoved, x, y, _BTN_LEFT, pid, click_state=0)
    except Exception:
        pass


def _click_at(
    x: float | None = None,
    y: float | None = None,
    button: str = "left",
    count: int = 1,
    pid: int | None = None,
    move_cursor: bool = True,
) -> None:
    """Click at screen coordinates.

    With a target pid the click goes straight to that process via
    CGEventPostToPid — the physical cursor never moves. Without one we
    warp the pointer first so the HID click lands at (x, y)."""
    if x is None or y is None:
        x, y = _cursor_pos()
    code = _button_code(button)

    def _click_series(target_pid: int | None) -> None:
        for i in range(max(1, count)):
            state = i + 1
            _mouse_down(x, y, code, pid=target_pid, click_state=state)
            time.sleep(0.012)
            _mouse_up(x, y, code, pid=target_pid, click_state=state)
            if i + 1 < count:
                time.sleep(0.05)

    if pid:
        # Pure background delivery: no warp, no global HID tap.
        for target in _pids_at_point(int(pid), x, y):
            _move_cursor(x, y, pid=target)
            _click_series(target)
        return

    if move_cursor:
        _warp_cursor(x, y)
        time.sleep(0.02)
        _move_cursor(x, y)

    _click_series(None)


def _mouse_down(
    x: float,
    y: float,
    button: int = _BTN_LEFT,
    pid: int | None = None,
    click_state: int = 1,
) -> None:
    from Quartz import kCGEventLeftMouseDown, kCGEventOtherMouseDown, kCGEventRightMouseDown

    etype = {
        _BTN_LEFT: kCGEventLeftMouseDown,
        _BTN_RIGHT: kCGEventRightMouseDown,
        _BTN_CENTER: kCGEventOtherMouseDown,
    }.get(button, kCGEventLeftMouseDown)
    _post_mouse_event(etype, x, y, button, pid, click_state=click_state)


def _mouse_up(
    x: float,
    y: float,
    button: int = _BTN_LEFT,
    pid: int | None = None,
    click_state: int = 1,
) -> None:
    from Quartz import kCGEventLeftMouseUp, kCGEventOtherMouseUp, kCGEventRightMouseUp

    etype = {
        _BTN_LEFT: kCGEventLeftMouseUp,
        _BTN_RIGHT: kCGEventRightMouseUp,
        _BTN_CENTER: kCGEventOtherMouseUp,
    }.get(button, kCGEventLeftMouseUp)
    _post_mouse_event(etype, x, y, button, pid, click_state=click_state)


def _scroll(dx: int, dy: int) -> None:
    try:
        from Quartz import CGEventCreateScrollWheelEvent, CGEventPost, kCGHIDEventTap, kCGScrollEventUnitLine

        event = CGEventCreateScrollWheelEvent(None, kCGScrollEventUnitLine, 2, int(dy), int(dx))
        CGEventPost(kCGHIDEventTap, event)
    except Exception:
        pass


class Engine:
    """Background worker for click spam and macro playback."""

    def __init__(self, on_status: StatusCallback | None = None) -> None:
        self._on_status = on_status or (lambda _msg: None)
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._mode: str | None = None
        self._lock = threading.Lock()
        self.keyboard = KeyController()

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    @property
    def mode(self) -> str | None:
        return self._mode if self.running else None

    def _emit(self, message: str) -> None:
        self._on_status(message)

    def stop(self, silent: bool = False) -> None:
        self._stop.set()
        thread = self._thread
        if thread and thread.is_alive() and thread is not threading.current_thread():
            thread.join(timeout=2.0)
        with self._lock:
            self._thread = None
            self._mode = None
        if not silent:
            self._emit("Stopped")

    def _resolve_screen_xy(
        self,
        step: MacroStep | None = None,
        *,
        x: int | float | None = None,
        y: int | float | None = None,
        local_x: float | None = None,
        local_y: float | None = None,
        coord_space: str = "screen",
        app_bundle_id: str | None = None,
        app_name: str | None = None,
        window_title: str | None = None,
        window_id: int | None = None,
        activate: bool = False,
        macro_defaults: Macro | None = None,
    ) -> tuple[float, float] | None:
        if step is not None:
            coord_space = step.coord_space or "screen"
            x, y = step.x, step.y
            local_x, local_y = step.local_x, step.local_y
            app_bundle_id = step.app_bundle_id or (
                macro_defaults.target_app_bundle_id if macro_defaults else None
            )
            app_name = step.app_name or (
                macro_defaults.target_app_name if macro_defaults else None
            )
            window_title = step.window_title or (
                macro_defaults.target_window_title if macro_defaults else None
            )
            window_id = step.window_id

        if coord_space != "window":
            if x is None or y is None:
                return None
            return float(x), float(y)

        window = winmod.find_window(
            bundle_id=app_bundle_id or None,
            app_name=app_name or None,
            window_title=window_title or None,
            window_id=int(window_id) if window_id else None,
        )
        if window is None:
            # Fall back to last known screen coords rather than giving up.
            if x is not None and y is not None:
                return float(x), float(y)
            self._emit("Target window not found")
            return None
        if activate:
            winmod.activate_app(bundle_id=window.bundle_id or None, pid=window.pid)
            time.sleep(0.05)
            window = (
                winmod.find_window(
                    bundle_id=window.bundle_id or None,
                    app_name=window.app_name,
                    window_title=window_title or window.title,
                    window_id=window.window_id,
                )
                or window
            )
        lx = local_x if local_x is not None else 0.0
        ly = local_y if local_y is not None else 0.0
        sx, sy = winmod.local_to_screen(lx, ly, window)
        return float(sx), float(sy)

    def _live_pid(
        self,
        *,
        pid: int | None = None,
        bundle_id: str | None = None,
        app_name: str | None = None,
        window_title: str | None = None,
        window_id: int | None = None,
    ) -> int | None:
        w = winmod.find_window(
            bundle_id=bundle_id or None,
            app_name=app_name or None,
            window_title=window_title or None,
            window_id=int(window_id) if window_id else None,
        )
        if w:
            return int(w.pid)
        if pid:
            try:
                from AppKit import NSRunningApplication

                app = NSRunningApplication.runningApplicationWithProcessIdentifier_(int(pid))
                if app is not None and not app.isTerminated():
                    return int(pid)
            except Exception:
                pass
        return winmod.pid_for_target(
            bundle_id=bundle_id, app_name=app_name, window_title=window_title
        )

    def start_clicker(
        self,
        interval_ms: int,
        button: str = "left",
        mode: str = "current",
        fixed_x: int = 0,
        fixed_y: int = 0,
        failsafe_pauses: bool = True,
        click_kind: str = "single",
        repeat_count: int = 0,
        jitter_ms: int = 0,
        coord_space: str = "screen",
        local_x: float = 0.0,
        local_y: float = 0.0,
        app_bundle_id: str | None = None,
        app_name: str | None = None,
        window_title: str | None = None,
        window_id: int | None = None,
        activate_target: bool = False,
        multipoints: list[dict] | None = None,
        background_to_app: bool = False,
    ) -> None:
        self.stop(silent=True)
        self._stop.clear()
        points = list(multipoints or [])

        def worker() -> None:
            self._mode = "clicker"
            self._emit("Clicker ON" + (" (background app)" if background_to_app else ""))
            base_interval = max(1, interval_ms) / 1000.0
            n_clicks = _click_count(click_kind, 1)
            done = 0
            point_idx = 0
            while not self._stop.is_set():
                if repeat_count > 0 and done >= repeat_count:
                    break
                try:
                    xy: tuple[float, float] | None = None
                    target_pid: int | None = None
                    p_meta: dict = {}

                    if mode == "fixed":
                        space = coord_space if coord_space == "window" else "screen"
                        xy = self._resolve_screen_xy(
                            x=fixed_x,
                            y=fixed_y,
                            local_x=local_x,
                            local_y=local_y,
                            coord_space=space,
                            app_bundle_id=app_bundle_id,
                            app_name=app_name,
                            window_title=window_title,
                            window_id=window_id,
                            activate=activate_target and space == "window" and not background_to_app,
                        )
                        if xy is None:
                            if failsafe_pauses:
                                break
                            time.sleep(0.2)
                            continue
                        if background_to_app:
                            target_pid = self._live_pid(
                                bundle_id=app_bundle_id,
                                app_name=app_name,
                                window_title=window_title,
                                window_id=window_id,
                            )
                    elif mode == "multipoint":
                        if not points:
                            self._emit("No multi-points set")
                            break
                        p_meta = points[point_idx % len(points)]
                        point_idx += 1
                        xy = self._resolve_screen_xy(
                            x=p_meta.get("x"),
                            y=p_meta.get("y"),
                            local_x=p_meta.get("local_x"),
                            local_y=p_meta.get("local_y"),
                            coord_space=p_meta.get("coord_space", "screen"),
                            app_bundle_id=p_meta.get("app_bundle_id") or app_bundle_id,
                            app_name=p_meta.get("app_name") or app_name,
                            window_title=p_meta.get("window_title") or window_title,
                            window_id=p_meta.get("window_id"),
                            activate=activate_target
                            and p_meta.get("coord_space") == "window"
                            and not background_to_app,
                        )
                        if xy is None:
                            if failsafe_pauses:
                                break
                            time.sleep(0.2)
                            continue
                        if background_to_app:
                            target_pid = self._live_pid(
                                pid=p_meta.get("pid"),
                                bundle_id=p_meta.get("app_bundle_id") or app_bundle_id,
                                app_name=p_meta.get("app_name") or app_name,
                                window_title=p_meta.get("window_title") or window_title,
                                window_id=p_meta.get("window_id"),
                            )
                    else:
                        xy = _cursor_pos()

                    _click_at(
                        xy[0],
                        xy[1],
                        button=button,
                        count=n_clicks,
                        pid=int(target_pid) if target_pid else None,
                        move_cursor=True,
                    )
                    done += 1
                except Exception as exc:  # noqa: BLE001
                    if failsafe_pauses:
                        self._emit(f"Paused: {exc}")
                        break
                    time.sleep(0.2)
                    continue
                wait = base_interval
                if jitter_ms > 0:
                    wait += random.uniform(-jitter_ms, jitter_ms) / 1000.0
                    wait = max(0.001, wait)
                if self._stop.wait(wait):
                    break
            self._emit("Clicker OFF")
            with self._lock:
                self._thread = None
                self._mode = None

        with self._lock:
            self._thread = threading.Thread(target=worker, daemon=True)
            self._thread.start()

    def play_macro(
        self,
        macro: Macro,
        speed: float | None = None,
        background_to_app: bool = False,
    ) -> None:
        self.stop(silent=True)
        self._stop.clear()
        playback_speed = max(0.05, speed if speed is not None else macro.speed)

        def worker() -> None:
            self._mode = "macro"
            self._emit(f"Playing: {macro.name}")
            if macro.activate_before_play and (
                macro.target_app_bundle_id or macro.target_app_name
            ):
                winmod.activate_app(bundle_id=macro.target_app_bundle_id or None)
                time.sleep(0.1)
            loops = macro.loop_count
            iteration = 0
            while not self._stop.is_set():
                iteration += 1
                if loops > 0 and iteration > loops:
                    break
                for step in macro.steps:
                    if self._stop.is_set():
                        break
                    ok = self._run_step(
                        step, playback_speed, macro, background_to_app=background_to_app
                    )
                    if not ok:
                        self._emit("Paused: target missing")
                        with self._lock:
                            self._thread = None
                            self._mode = None
                        return
            self._emit("Playback finished" if not self._stop.is_set() else "Stopped")
            with self._lock:
                self._thread = None
                self._mode = None

        with self._lock:
            self._thread = threading.Thread(target=worker, daemon=True)
            self._thread.start()

    def _run_step(
        self,
        step: MacroStep,
        speed: float,
        macro: Macro | None = None,
        background_to_app: bool = False,
    ) -> bool:
        delay = max(0, step.delay_ms) / 1000.0 / speed
        if step.type == StepType.DELAY:
            if delay > 0:
                self._stop.wait(delay)
            return True

        if step.type == StepType.ACTIVATE_APP:
            ok = winmod.activate_app(bundle_id=step.app_bundle_id or None)
            if not ok and step.app_name:
                w = winmod.find_window(app_name=step.app_name)
                if w:
                    winmod.activate_app(pid=w.pid)
            if delay > 0:
                self._stop.wait(delay)
            return True

        if step.type == StepType.WAIT_WINDOW:
            timeout = max(0, step.timeout_ms) / 1000.0
            deadline = time.perf_counter() + timeout
            while not self._stop.is_set():
                w = winmod.find_window(
                    bundle_id=step.app_bundle_id
                    or (macro.target_app_bundle_id if macro else None),
                    app_name=step.app_name or (macro.target_app_name if macro else None),
                    window_title=step.window_title
                    or (macro.target_window_title if macro else None),
                )
                if w:
                    break
                if time.perf_counter() >= deadline:
                    self._emit("Wait window timed out")
                    return False
                if self._stop.wait(0.2):
                    return True
            if delay > 0:
                self._stop.wait(delay)
            return True

        activate = bool(macro.activate_before_play) if macro else False
        if background_to_app:
            activate = False
        step_pid = None
        if background_to_app and (
            step.app_bundle_id or step.app_name or (macro and (macro.target_app_bundle_id or macro.target_app_name))
        ):
            step_pid = self._live_pid(
                bundle_id=step.app_bundle_id
                or (macro.target_app_bundle_id if macro else None),
                app_name=step.app_name or (macro.target_app_name if macro else None),
                window_title=step.window_title
                or (macro.target_window_title if macro else None),
                window_id=step.window_id,
            )

        if step.type == StepType.MOVE:
            xy = self._resolve_screen_xy(step, activate=activate, macro_defaults=macro)
            if xy is None and step.coord_space == "window":
                return False
            if xy:
                _move_cursor(xy[0], xy[1], pid=step_pid)
        elif step.type == StepType.CLICK:
            xy = self._resolve_screen_xy(step, activate=activate, macro_defaults=macro)
            if step.coord_space == "window" and xy is None:
                return False
            if xy is None:
                xy = _cursor_pos()
            _click_at(
                xy[0],
                xy[1],
                button=step.button or "left",
                count=_click_count(step.click_kind, step.clicks),
                pid=step_pid,
                move_cursor=True,
            )
        elif step.type == StepType.HOLD:
            xy = self._resolve_screen_xy(step, activate=activate, macro_defaults=macro)
            if step.coord_space == "window" and xy is None:
                return False
            if xy is None:
                xy = _cursor_pos()
            code = _button_code(step.button)
            _move_cursor(xy[0], xy[1], pid=step_pid)
            _mouse_down(xy[0], xy[1], code, pid=step_pid)
            self._stop.wait(max(0, step.hold_ms) / 1000.0 / speed)
            _mouse_up(xy[0], xy[1], code, pid=step_pid)
        elif step.type == StepType.DRAG:
            start = self._resolve_screen_xy(step, activate=activate, macro_defaults=macro)
            if step.coord_space == "window" and start is None:
                return False
            if step.coord_space == "window":
                end = self._resolve_screen_xy(
                    local_x=step.end_local_x,
                    local_y=step.end_local_y,
                    coord_space="window",
                    app_bundle_id=step.app_bundle_id
                    or (macro.target_app_bundle_id if macro else None),
                    app_name=step.app_name or (macro.target_app_name if macro else None),
                    window_title=step.window_title
                    or (macro.target_window_title if macro else None),
                    window_id=step.window_id,
                    activate=False,
                )
            else:
                end = (
                    (float(step.end_x), float(step.end_y))
                    if step.end_x is not None and step.end_y is not None
                    else None
                )
            if start and end:
                code = _button_code(step.button)
                _move_cursor(start[0], start[1], pid=step_pid)
                _mouse_down(start[0], start[1], code, pid=step_pid)
                steps_n = max(5, int(20 / speed))
                for i in range(1, steps_n + 1):
                    if self._stop.is_set():
                        break
                    t = i / steps_n
                    cx = start[0] + (end[0] - start[0]) * t
                    cy = start[1] + (end[1] - start[1]) * t
                    _move_cursor(cx, cy, pid=step_pid)
                    time.sleep(0.01)
                _mouse_up(end[0], end[1], code, pid=step_pid)
        elif step.type == StepType.SCROLL:
            if step.x is not None or step.coord_space == "window":
                xy = self._resolve_screen_xy(step, activate=activate, macro_defaults=macro)
                if xy:
                    _move_cursor(xy[0], xy[1])
            _scroll(step.dx or 0, step.dy or 0)
        elif step.type == StepType.KEY:
            delivered = False
            if background_to_app and step_pid:
                delivered = _post_key_combo_to_pid(int(step_pid), step.key or "")
            if not delivered:
                mods, tail = _resolve_chord(step.key or "")
                if tail is not None or mods:
                    for m in mods:
                        self.keyboard.press(m)
                    try:
                        if tail is not None:
                            self.keyboard.press(tail)
                            self.keyboard.release(tail)
                    finally:
                        for m in reversed(mods):
                            self.keyboard.release(m)
        elif step.type == StepType.KEY_DOWN:
            mods, tail = _resolve_chord(step.key or "")
            if tail is not None:
                for m in mods:
                    self.keyboard.press(m)
                self.keyboard.press(tail)
        elif step.type == StepType.KEY_UP:
            mods, tail = _resolve_chord(step.key or "")
            if tail is not None:
                self.keyboard.release(tail)
            for m in reversed(mods):
                self.keyboard.release(m)
        elif step.type == StepType.TYPE:
            if step.text:
                self.keyboard.type(step.text)

        if delay > 0:
            self._stop.wait(delay)
        return True
