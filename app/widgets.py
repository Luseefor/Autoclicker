"""Reusable UI bits — keycaps, hotkey rows, modern hotkey editor."""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QKeyEvent
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QWidget,
)

# pynput token -> friendly label
_DISPLAY = {
    "ctrl": "Ctrl",
    "control": "Ctrl",
    "alt": "Opt",
    "option": "Opt",
    "shift": "Shift",
    "cmd": "Cmd",
    "cmd_l": "Cmd",
    "cmd_r": "Cmd",
    "super": "Cmd",
    "esc": "Esc",
    "escape": "Esc",
    "space": "Space",
    "enter": "Enter",
    "return": "Enter",
    "tab": "Tab",
    "backspace": "⌫",
    "delete": "Del",
    "up": "↑",
    "down": "↓",
    "left": "←",
    "right": "→",
}

_FRIENDLY_TO_PYNPUT = {
    "ctrl": "ctrl",
    "control": "ctrl",
    "opt": "alt",
    "option": "alt",
    "alt": "alt",
    "shift": "shift",
    "cmd": "cmd",
    "command": "cmd",
    "super": "cmd",
    "esc": "esc",
    "escape": "esc",
    "space": "space",
    "enter": "enter",
    "return": "enter",
    "tab": "tab",
}

_QT_KEY_LABEL = {
    Qt.Key.Key_Escape: "Esc",
    Qt.Key.Key_Space: "Space",
    Qt.Key.Key_Return: "Enter",
    Qt.Key.Key_Enter: "Enter",
    Qt.Key.Key_Tab: "Tab",
    Qt.Key.Key_Backspace: "Backspace",
    Qt.Key.Key_Delete: "Delete",
    Qt.Key.Key_Up: "Up",
    Qt.Key.Key_Down: "Down",
    Qt.Key.Key_Left: "Left",
    Qt.Key.Key_Right: "Right",
}


def keycap(text: str) -> QLabel:
    lab = QLabel(text)
    lab.setObjectName("keycap")
    lab.setAlignment(Qt.AlignmentFlag.AlignCenter)
    lab.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
    return lab


def hotkey_chip(keys: list[str], caption: str) -> QWidget:
    wrap = QWidget()
    wrap.setObjectName("hotkeyChip")
    row = QHBoxLayout(wrap)
    row.setContentsMargins(8, 5, 10, 5)
    row.setSpacing(4)
    for i, k in enumerate(keys):
        if i:
            plus = QLabel("+")
            plus.setObjectName("keyPlus")
            row.addWidget(plus)
        row.addWidget(keycap(k))
    cap = QLabel(caption)
    cap.setObjectName("hotkeyCaption")
    row.addSpacing(6)
    row.addWidget(cap)
    return wrap


def hotkey_bar(items: list[tuple[list[str], str]]) -> QWidget:
    bar = QWidget()
    bar.setObjectName("hotkeyBar")
    layout = QHBoxLayout(bar)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(10)
    for keys, caption in items:
        layout.addWidget(hotkey_chip(keys, caption))
    layout.addStretch(1)
    return bar


def parse_hotkey(binding: str) -> list[str]:
    """'<ctrl>+<alt>+a' -> ['Ctrl', 'Opt', 'A']"""
    if not binding:
        return []
    parts: list[str] = []
    for raw in binding.split("+"):
        token = raw.strip().strip("<>").lower()
        if not token:
            continue
        if token in _DISPLAY:
            parts.append(_DISPLAY[token])
        elif len(token) == 1:
            parts.append(token.upper())
        elif token.startswith("f") and token[1:].isdigit():
            parts.append(token.upper())
        else:
            parts.append(token.replace("_", " ").title())
    return parts


def format_hotkey(parts: list[str]) -> str:
    """['Ctrl', 'Opt', 'A'] -> '<ctrl>+<alt>+a'"""
    out: list[str] = []
    for p in parts:
        low = p.lower().strip()
        if low in _FRIENDLY_TO_PYNPUT:
            tok = _FRIENDLY_TO_PYNPUT[low]
            out.append(f"<{tok}>")
        elif len(p) == 1:
            out.append(p.lower())
        elif low.startswith("f") and low[1:].isdigit():
            out.append(f"<{low}>")
        else:
            out.append(f"<{low}>")
    return "+".join(out)


class HotkeyEditor(QWidget):
    """Shows a binding as keycaps; Change records the next combo via Qt (no pynput)."""

    changed = Signal(str)

    def __init__(self, binding: str = "", parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._binding = binding or "<ctrl>+<alt>+a"
        self._listening = False
        self._on_listen_start = None
        self._on_listen_stop = None

        self.setObjectName("hotkeyEditor")
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        root = QHBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(8)

        self._keys_host = QWidget()
        self._keys_host.setObjectName("hotkeyChip")
        self._keys_layout = QHBoxLayout(self._keys_host)
        self._keys_layout.setContentsMargins(10, 6, 10, 6)
        self._keys_layout.setSpacing(4)
        root.addWidget(self._keys_host, 1)

        self._hint = QLabel("")
        self._hint.setObjectName("hotkeyCaption")
        root.addWidget(self._hint)

        self._btn = QPushButton("Change")
        self._btn.setFixedWidth(88)
        self._btn.clicked.connect(self._toggle_listen)
        root.addWidget(self._btn)

        self._rebuild_caps()

    def set_listen_hooks(self, on_start=None, on_stop=None) -> None:
        self._on_listen_start = on_start
        self._on_listen_stop = on_stop

    def binding(self) -> str:
        return self._binding

    def set_binding(self, binding: str) -> None:
        self._stop_listen(silent=True)
        self._binding = binding.strip() or self._binding
        self._rebuild_caps()

    def _clear_keys_layout(self) -> None:
        while self._keys_layout.count():
            item = self._keys_layout.takeAt(0)
            w = item.widget()
            if w:
                w.deleteLater()

    def _rebuild_caps(self) -> None:
        self._clear_keys_layout()
        parts = parse_hotkey(self._binding)
        if not parts:
            empty = QLabel("Not set")
            empty.setObjectName("hotkeyCaption")
            self._keys_layout.addWidget(empty)
        else:
            for i, part in enumerate(parts):
                if i:
                    plus = QLabel("+")
                    plus.setObjectName("keyPlus")
                    self._keys_layout.addWidget(plus)
                self._keys_layout.addWidget(keycap(part))
        self._keys_layout.addStretch(1)
        self._hint.setText("")
        self._btn.setText("Change")

    def _toggle_listen(self) -> None:
        if self._listening:
            self._stop_listen()
        else:
            self._start_listen()

    def _start_listen(self) -> None:
        self._listening = True
        self._btn.setText("Cancel")
        self._hint.setText("Press a shortcut")
        self._clear_keys_layout()
        wait = QLabel("…")
        wait.setObjectName("hotkeyCaption")
        self._keys_layout.addWidget(wait)
        self._keys_layout.addStretch(1)

        if self._on_listen_start:
            try:
                self._on_listen_start()
            except Exception:
                pass

        self.grabKeyboard()
        self.setFocus(Qt.FocusReason.OtherFocusReason)

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if not self._listening:
            super().keyPressEvent(event)
            return

        if event.isAutoRepeat():
            event.accept()
            return

        key = event.key()
        if key == Qt.Key.Key_Escape:
            self._stop_listen()
            event.accept()
            return

        if key in (
            Qt.Key.Key_Control,
            Qt.Key.Key_Shift,
            Qt.Key.Key_Alt,
            Qt.Key.Key_Meta,
            Qt.Key.Key_AltGr,
        ):
            event.accept()
            return

        mods = event.modifiers()
        parts: list[str] = []
        if mods & Qt.KeyboardModifier.ControlModifier:
            parts.append("Ctrl")
        if mods & Qt.KeyboardModifier.AltModifier:
            parts.append("Opt")
        if mods & Qt.KeyboardModifier.ShiftModifier:
            parts.append("Shift")
        if mods & Qt.KeyboardModifier.MetaModifier:
            parts.append("Cmd")

        label: str | None = None
        if key in _QT_KEY_LABEL:
            label = _QT_KEY_LABEL[key]
        elif Qt.Key.Key_F1 <= key <= Qt.Key.Key_F12:
            label = f"F{key - Qt.Key.Key_F1 + 1}"
        elif Qt.Key.Key_A <= key <= Qt.Key.Key_Z:
            label = chr(ord("A") + (key - Qt.Key.Key_A))
        elif Qt.Key.Key_0 <= key <= Qt.Key.Key_9:
            label = chr(ord("0") + (key - Qt.Key.Key_0))
        else:
            text = event.text().strip()
            if text and text.isprintable() and len(text) == 1:
                label = text.upper()

        if not label:
            event.accept()
            return

        parts.append(label)
        self._apply_captured(format_hotkey(parts))
        event.accept()

    def _apply_captured(self, binding: str) -> None:
        self._stop_listen(silent=True)
        self._binding = binding
        self._rebuild_caps()
        self.changed.emit(binding)

    def _stop_listen(self, silent: bool = False) -> None:
        was = self._listening
        self._listening = False
        try:
            self.releaseKeyboard()
        except Exception:
            pass
        if was and self._on_listen_stop:
            try:
                self._on_listen_stop()
            except Exception:
                pass
        if not silent:
            self._rebuild_caps()
