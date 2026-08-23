#!/usr/bin/env python3
"""Render the programmatic Automater icon into assets/Automater.icns."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # scripts/swift → repo root? no:
# this file lives in <repo>/AutomaterMac/scripts/
ROOT = Path(__file__).resolve().parents[2]
ICONSET = ROOT / "build" / "Automater.iconset"
ICNS = Path(__file__).resolve().parents[1] / "assets" / "Automater.icns"

SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]

CODE = f"""
import sys
sys.path.insert(0, {str(ROOT)!r})
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication
app = QApplication([])
from app.app_icon import build_app_icon
icon = build_app_icon()
import os
for size, scale in {SIZES!r}:
    pm = icon.pixmap(size * scale, size * scale)
    name = f"icon_{{size}}x{{size}}{{'@2x' if scale == 2 else ''}}.png"
    pm.save(str({str(ICONSET)!r}) + "/" + name, "PNG")
print("rendered")
"""

def main() -> int:
    ICONSET.mkdir(parents=True, exist_ok=True)
    ICNS.parent.mkdir(parents=True, exist_ok=True)
    env_qt = str(ROOT / ".venv/lib/python3.14/site-packages/PySide6/Qt/plugins")
    import os
    os.environ["QT_PLUGIN_PATH"] = env_qt
    os.environ["QT_QPA_PLATFORM"] = "cocoa"
    r = subprocess.run([str(ROOT / ".venv/bin/python"), "-c", CODE],
                       capture_output=True, text=True)
    print(r.stdout.strip(), r.stderr.strip()[:400])
    if r.returncode != 0:
        return 1
    r2 = subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)],
                        capture_output=True, text=True)
    if r2.returncode != 0:
        print(r2.stderr)
        return 1
    print(f"wrote {ICNS}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
