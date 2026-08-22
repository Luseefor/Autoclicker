"""Running apps / windows and screen ↔ window-local coordinates (macOS)."""

from __future__ import annotations

from dataclasses import dataclass

# Ignore menu-bar strips, tooltips, and other tiny surfaces.
_MIN_WINDOW_W = 120
_MIN_WINDOW_H = 80


@dataclass
class AppInfo:
    name: str
    bundle_id: str
    pid: int


@dataclass
class WindowInfo:
    app_name: str
    bundle_id: str
    pid: int
    window_id: int
    title: str
    x: float
    y: float
    width: float
    height: float

    @property
    def area(self) -> float:
        return max(0.0, self.width) * max(0.0, self.height)


def _cg_windows(on_screen_only: bool = True) -> list[dict]:
    try:
        from Quartz import (
            CGWindowListCopyWindowInfo,
            kCGNullWindowID,
            kCGWindowListExcludeDesktopElements,
            kCGWindowListOptionAll,
            kCGWindowListOptionOnScreenOnly,
        )

        opts = kCGWindowListExcludeDesktopElements
        if on_screen_only:
            opts |= kCGWindowListOptionOnScreenOnly
        else:
            opts |= kCGWindowListOptionAll
        raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
        return list(raw) if raw else []
    except Exception:
        return []


def _skip_owner(name: str) -> bool:
    lowered = (name or "").lower()
    return lowered in {
        "window server",
        "dock",
        "control center",
        "notification center",
        "systemuiserver",
        "spotlight",
        "loginwindow",
    }


def list_running_apps() -> list[AppInfo]:
    """Running regular GUI apps, sorted by name."""
    seen: dict[str, AppInfo] = {}
    try:
        from AppKit import NSApplicationActivationPolicyRegular, NSWorkspace

        for app in NSWorkspace.sharedWorkspace().runningApplications():
            try:
                if app.activationPolicy() != NSApplicationActivationPolicyRegular:
                    continue
            except Exception:
                continue
            if app.isTerminated():
                continue
            name = str(app.localizedName() or "").strip()
            pid = int(app.processIdentifier())
            bundle = str(app.bundleIdentifier() or "")
            if not name or not pid:
                continue
            if name.lower() in {"automater", "python", "python3"}:
                # Still allow Python if it has a real window title elsewhere
                if "python" in name.lower() and not bundle.startswith("org.python"):
                    pass
                elif name.lower() in {"automater"}:
                    continue
            key = bundle or f"pid:{pid}"
            seen[key] = AppInfo(name=name, bundle_id=bundle, pid=pid)
    except Exception:
        pass

    # Supplement from window owners (covers some Electron / game hosts)
    for w in list_windows():
        if _skip_owner(w.app_name):
            continue
        key = w.bundle_id or f"pid:{w.pid}"
        if key not in seen:
            seen[key] = AppInfo(name=w.app_name, bundle_id=w.bundle_id, pid=w.pid)

    return sorted(seen.values(), key=lambda a: a.name.lower())


def list_windows(
    bundle_id: str | None = None,
    pid: int | None = None,
    *,
    on_screen_only: bool = True,
    min_size: bool = True,
) -> list[WindowInfo]:
    """Windows large enough to be real content, largest first."""
    results: list[WindowInfo] = []
    seen_ids: set[int] = set()
    min_w = _MIN_WINDOW_W if min_size else 2
    min_h = _MIN_WINDOW_H if min_size else 2
    for w in _cg_windows(on_screen_only=on_screen_only):
        layer = int(w.get("kCGWindowLayer", 0) or 0)
        if layer != 0:
            continue
        owner_pid = int(w.get("kCGWindowOwnerPID") or 0)
        owner = str(w.get("kCGWindowOwnerName") or "")
        if _skip_owner(owner):
            continue
        title = str(w.get("kCGWindowName") or "")
        wid = int(w.get("kCGWindowNumber") or 0)
        if wid in seen_ids:
            continue
        bounds = w.get("kCGWindowBounds") or {}
        x = float(bounds.get("X", 0))
        y = float(bounds.get("Y", 0))
        width = float(bounds.get("Width", 0))
        height = float(bounds.get("Height", 0))
        if width < min_w or height < min_h:
            continue
        alpha = float(w.get("kCGWindowAlpha", 1) or 1)
        if alpha < 0.05:
            continue
        b_id = _bundle_id_for_pid(owner_pid) or ""
        if bundle_id and b_id != bundle_id:
            continue
        if pid is not None and owner_pid != pid:
            continue
        if owner.lower() in {"python", "python3"} and "automater" in title.lower():
            continue
        seen_ids.add(wid)
        results.append(
            WindowInfo(
                app_name=owner,
                bundle_id=b_id,
                pid=owner_pid,
                window_id=wid,
                title=title or f"{owner} window",
                x=x,
                y=y,
                width=width,
                height=height,
            )
        )
    results.sort(key=lambda w: w.area, reverse=True)
    return results


def _bundle_id_for_pid(pid: int) -> str | None:
    try:
        from AppKit import NSRunningApplication

        app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        if app is None:
            return None
        bid = app.bundleIdentifier()
        return str(bid) if bid else None
    except Exception:
        return None


def frontmost_window() -> WindowInfo | None:
    try:
        from AppKit import NSWorkspace

        front = NSWorkspace.sharedWorkspace().frontmostApplication()
        if front is None:
            return None
        pid = int(front.processIdentifier())
        wins = list_windows(pid=pid)
        return wins[0] if wins else None
    except Exception:
        return None


def find_window(
    bundle_id: str | None = None,
    app_name: str | None = None,
    window_title: str | None = None,
    window_id: int | None = None,
) -> WindowInfo | None:
    # Playback must see covered / other-Space windows (fullscreen games).
    all_wins = list_windows(on_screen_only=False, min_size=True)
    if window_id is not None:
        exact = list_windows(on_screen_only=False, min_size=False)
        for w in exact:
            if w.window_id == int(window_id):
                return w

    candidates = all_wins
    if bundle_id:
        matched = [w for w in all_wins if w.bundle_id == bundle_id]
        if matched:
            candidates = matched
        elif app_name:
            name_l = app_name.lower()
            candidates = [w for w in all_wins if w.app_name.lower() == name_l]
        else:
            candidates = []
    elif app_name:
        name_l = app_name.lower()
        matched = [w for w in all_wins if w.app_name.lower() == name_l]
        candidates = matched

    if window_title:
        title_l = window_title.lower()
        titled = [w for w in candidates if title_l in (w.title or "").lower()]
        if titled:
            return titled[0]
    if candidates:
        return candidates[0]
    return None


def activate_app(bundle_id: str | None = None, pid: int | None = None) -> bool:
    try:
        from AppKit import NSApplicationActivateIgnoringOtherApps, NSRunningApplication

        app = None
        if pid is not None:
            app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        elif bundle_id:
            apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(bundle_id)
            app = apps[0] if apps else None
        if app is None:
            return False
        return bool(app.activateWithOptions_(NSApplicationActivateIgnoringOtherApps))
    except Exception:
        return False


def screen_to_local(screen_x: float, screen_y: float, window: WindowInfo) -> tuple[float, float]:
    return screen_x - window.x, screen_y - window.y


def local_to_screen(local_x: float, local_y: float, window: WindowInfo) -> tuple[float, float]:
    return window.x + local_x, window.y + local_y


def point_in_window(screen_x: float, screen_y: float, window: WindowInfo) -> bool:
    return (
        window.x <= screen_x <= window.x + window.width
        and window.y <= screen_y <= window.y + window.height
    )


def window_at_point(screen_x: float, screen_y: float) -> WindowInfo | None:
    """Topmost real content window under a screen point (layer 0, large enough)."""
    hits: list[WindowInfo] = []
    for w in list_windows():
        if point_in_window(screen_x, screen_y, w):
            hits.append(w)
    if not hits:
        # Fallback: include smaller windows for the hit-test only
        for raw in _cg_windows():
            layer = int(raw.get("kCGWindowLayer", 0) or 0)
            if layer != 0:
                continue
            owner = str(raw.get("kCGWindowOwnerName") or "")
            if _skip_owner(owner):
                continue
            bounds = raw.get("kCGWindowBounds") or {}
            x = float(bounds.get("X", 0))
            y = float(bounds.get("Y", 0))
            width = float(bounds.get("Width", 0))
            height = float(bounds.get("Height", 0))
            if width < 2 or height < 2:
                continue
            if not (x <= screen_x <= x + width and y <= screen_y <= y + height):
                continue
            pid = int(raw.get("kCGWindowOwnerPID") or 0)
            hits.append(
                WindowInfo(
                    app_name=owner,
                    bundle_id=_bundle_id_for_pid(pid) or "",
                    pid=pid,
                    window_id=int(raw.get("kCGWindowNumber") or 0),
                    title=str(raw.get("kCGWindowName") or owner),
                    x=x,
                    y=y,
                    width=width,
                    height=height,
                )
            )
    if not hits:
        return None
    # Prefer largest among hits (main content, not a thin chrome strip)
    hits.sort(key=lambda w: w.area, reverse=True)
    return hits[0]


def pid_for_target(
    bundle_id: str | None = None,
    app_name: str | None = None,
    window_title: str | None = None,
) -> int | None:
    w = find_window(bundle_id=bundle_id, app_name=app_name, window_title=window_title)
    return w.pid if w else None


def our_app_pids() -> set[int]:
    import os

    pids = {os.getpid()}
    try:
        from AppKit import NSRunningApplication

        me = NSRunningApplication.currentApplication()
        if me:
            pids.add(int(me.processIdentifier()))
    except Exception:
        pass
    return pids
