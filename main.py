#!/usr/bin/env python3
"""Launch Automater."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def _prepare_qt_env() -> None:
    try:
        import PySide6

        base = Path(PySide6.__file__).resolve().parent / "Qt"
        plugins = base / "plugins"
        frameworks = base / "lib"
        if plugins.is_dir():
            os.environ.setdefault("QT_PLUGIN_PATH", str(plugins))
        # Avoid QT_QPA_PLATFORM_PLUGIN_PATH — it can break cocoa discovery.
        os.environ.pop("QT_QPA_PLATFORM_PLUGIN_PATH", None)
        os.environ.pop("QT_DEBUG_PLUGINS", None)
        if frameworks.is_dir():
            path = str(frameworks)
            existing = os.environ.get("DYLD_FRAMEWORK_PATH", "")
            if path not in existing.split(":"):
                os.environ["DYLD_FRAMEWORK_PATH"] = (
                    f"{path}:{existing}" if existing else path
                )
    except Exception:
        pass


_prepare_qt_env()

from PySide6.QtWidgets import QApplication

from app import APP_NAME
from app.app_icon import apply_dock_icon, build_app_icon
from app.main_window import MainWindow


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationDisplayName(APP_NAME)
    app.setOrganizationName(APP_NAME)
    icon = build_app_icon()
    app.setWindowIcon(icon)
    apply_dock_icon(icon)
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
