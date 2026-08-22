#!/bin/zsh
cd "$(dirname "$0")"

ROOT="$PWD/.venv/lib/python3.14/site-packages/PySide6/Qt"
COCOA="$ROOT/plugins/platforms/libqcocoa.dylib"

# Homebrew Python looks for platform plugins next to Python.app; link cocoa in.
BASE="$("$PWD/.venv/bin/python" -c 'import sys; print(sys.base_prefix)')"
PLATFORMS="$BASE/Resources/Python.app/Contents/MacOS/platforms"
mkdir -p "$PLATFORMS"
ln -sfn "$COCOA" "$PLATFORMS/libqcocoa.dylib"

export DYLD_FRAMEWORK_PATH="$ROOT/lib${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
unset QT_QPA_PLATFORM_PLUGIN_PATH
unset QT_DEBUG_PLUGINS
export QT_PLUGIN_PATH="$ROOT/plugins"

# Keep the process attached to this Terminal session (do not background).
exec .venv/bin/python main.py
