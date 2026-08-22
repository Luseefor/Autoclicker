"""macOS ANSI virtual keycodes, shared by background key delivery."""

from __future__ import annotations

LETTERS: dict[str, int] = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
    "j": 38, "k": 40, "n": 45, "m": 46,
}

DIGITS: dict[str, int] = {
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
}

PUNCTUATION: dict[str, int] = {
    "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41,
    "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
}

SPECIALS: dict[str, int] = {
    "space": 49, "esc": 53, "escape": 53, "tab": 48,
    "enter": 36, "return": 36, "backspace": 51, "delete": 117,
    "forwarddelete": 117, "home": 115, "end": 119,
    "page_up": 116, "page_down": 121, "caps_lock": 57,
    "up": 126, "down": 125, "left": 123, "right": 124,
}

FUNCTION_KEYS: dict[str, int] = {
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
}

MODIFIERS: dict[str, int] = {
    "cmd": 55, "command": 55, "right_cmd": 54,
    "ctrl": 59, "control": 59, "right_ctrl": 62,
    "alt": 58, "option": 58, "opt": 58, "right_alt": 61,
    "shift": 56, "right_shift": 60,
}

ALL: dict[str, int] = {
    **LETTERS, **DIGITS, **PUNCTUATION, **SPECIALS, **FUNCTION_KEYS, **MODIFIERS,
}


def keycode_for(name: str) -> int | None:
    """Virtual keycode for a key name or single character, None if unknown."""
    lowered = (name or "").strip().lower()
    return ALL.get(lowered)
