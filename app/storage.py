"""Persist macros and app settings as JSON (Automater)."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from app.models import Macro

APP_DIR = Path.home() / "Library" / "Application Support" / "Automater"
MACROS_DIR = APP_DIR / "macros"
SETTINGS_PATH = APP_DIR / "settings.json"
LEGACY_APP_DIR = Path.home() / "Library" / "Application Support" / "AutoClicker"

DEFAULT_SETTINGS: dict[str, Any] = {
    "click_interval_h": 0,
    "click_interval_m": 0,
    "click_interval_s": 0,
    "click_interval_ms": 100,
    "mouse_button": "left",
    "click_mode": "current",  # current | fixed | multipoint
    "click_kind": "single",  # single | double | triple
    "fixed_x": 0,
    "fixed_y": 0,
    "fixed_coord_space": "screen",  # screen | window
    "fixed_local_x": 0.0,
    "fixed_local_y": 0.0,
    "repeat_count": 0,  # 0 = infinite
    "jitter_ms": 0,
    "hotkey_toggle": "<ctrl>+<alt>+a",
    "hotkey_record": "<ctrl>+<alt>+r",
    "hotkey_stop": "<ctrl>+<alt>+s",
    "failsafe_pauses": True,
    "playback_speed": 1.0,
    "activate_target": False,
    "background_to_app": False,
    "target_bundle_id": "",
    "target_app_name": "",
    "target_window_title": "",
    "record_window_relative": True,
    "multipoints": [],  # list of {x,y} or localized dicts
}


def _migrate_from_legacy() -> None:
    """Copy macros/settings from AutoClicker on first Automater launch."""
    if APP_DIR.exists() and any(MACROS_DIR.glob("*.json")):
        return
    if not LEGACY_APP_DIR.exists():
        return
    APP_DIR.mkdir(parents=True, exist_ok=True)
    legacy_macros = LEGACY_APP_DIR / "macros"
    if legacy_macros.exists() and not any(MACROS_DIR.glob("*.json")):
        MACROS_DIR.mkdir(parents=True, exist_ok=True)
        for path in legacy_macros.glob("*.json"):
            dest = MACROS_DIR / path.name
            if not dest.exists():
                shutil.copy2(path, dest)
    legacy_settings = LEGACY_APP_DIR / "settings.json"
    if legacy_settings.exists() and not SETTINGS_PATH.exists():
        try:
            data = json.loads(legacy_settings.read_text(encoding="utf-8"))
            merged = DEFAULT_SETTINGS.copy()
            merged.update({k: v for k, v in data.items() if k in merged or True})
            # Keep unknown keys too for forward compat
            for k, v in data.items():
                if k not in merged:
                    merged[k] = v
            SETTINGS_PATH.write_text(json.dumps(merged, indent=2), encoding="utf-8")
        except (json.JSONDecodeError, OSError):
            pass


def ensure_dirs() -> None:
    _migrate_from_legacy()
    MACROS_DIR.mkdir(parents=True, exist_ok=True)


def load_settings() -> dict[str, Any]:
    ensure_dirs()
    if not SETTINGS_PATH.exists():
        save_settings(DEFAULT_SETTINGS.copy())
        return DEFAULT_SETTINGS.copy()
    try:
        data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
        merged = DEFAULT_SETTINGS.copy()
        merged.update(data)
        return merged
    except (json.JSONDecodeError, OSError):
        return DEFAULT_SETTINGS.copy()


def save_settings(settings: dict[str, Any]) -> None:
    ensure_dirs()
    SETTINGS_PATH.write_text(json.dumps(settings, indent=2), encoding="utf-8")


def list_macros() -> list[Macro]:
    ensure_dirs()
    macros: list[Macro] = []
    for path in sorted(MACROS_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            macros.append(Macro.from_dict(data))
        except (json.JSONDecodeError, OSError, TypeError, ValueError):
            continue
    return macros


def save_macro(macro: Macro) -> Path:
    ensure_dirs()
    path = MACROS_DIR / f"{macro.id}.json"
    path.write_text(json.dumps(macro.to_dict(), indent=2), encoding="utf-8")
    return path


def delete_macro(macro_id: str) -> None:
    path = MACROS_DIR / f"{macro_id}.json"
    if path.exists():
        path.unlink()


def get_macro(macro_id: str) -> Macro | None:
    path = MACROS_DIR / f"{macro_id}.json"
    if not path.exists():
        return None
    try:
        return Macro.from_dict(json.loads(path.read_text(encoding="utf-8")))
    except (json.JSONDecodeError, OSError, TypeError, ValueError):
        return None


def export_macro(macro: Macro, dest: Path) -> None:
    dest.write_text(json.dumps(macro.to_dict(), indent=2), encoding="utf-8")


def import_macro(src: Path) -> Macro:
    data = json.loads(src.read_text(encoding="utf-8"))
    macro = Macro.from_dict(data)
    # New id so imports don't collide
    from uuid import uuid4

    macro.id = uuid4().hex[:12]
    save_macro(macro)
    return macro


def interval_to_ms(h: int, m: int, s: int, ms: int) -> int:
    return max(1, ((h * 60 + m) * 60 + s) * 1000 + ms)
