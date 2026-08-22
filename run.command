#!/bin/zsh
cd "$(dirname "$0")"

PY="$PWD/.venv/bin/python"
[ -x "$PY" ] || { echo "Missing .venv — create it and run: pip install -r requirements.txt"; exit 1; }

# Auto-detect the interpreter version (no hardcoded python3.x path).
PYVER="$("$PY" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
QT_ROOT="$PWD/.venv/lib/python$PYVER/site-packages/PySide6/Qt"
COCOA="$QT_ROOT/plugins/platforms/libqcocoa.dylib"
if [ ! -f "$COCOA" ]; then
  echo "PySide6 not found in .venv (python $PYVER) — run: pip install -r requirements.txt"
  exit 1
fi

# Homebrew Python looks for platform plugins next to Python.app; link cocoa in.
BASE="$("$PY" -c 'import sys; print(sys.base_prefix)')"
PLATFORMS="$BASE/Resources/Python.app/Contents/MacOS/platforms"
mkdir -p "$PLATFORMS"
ln -sfn "$COCOA" "$PLATFORMS/libqcocoa.dylib" 2>/dev/null

export DYLD_FRAMEWORK_PATH="$QT_ROOT/lib${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
unset QT_QPA_PLATFORM_PLUGIN_PATH
unset QT_DEBUG_PLUGINS
export QT_PLUGIN_PATH="$QT_ROOT/plugins"

# Keep the process attached to this Terminal session (do not background).
exec "$PY" main.py
