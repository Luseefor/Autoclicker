"""Macro data models and serialization."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any
from uuid import uuid4


class StepType(str, Enum):
    CLICK = "click"
    MOVE = "move"
    KEY = "key"
    KEY_DOWN = "key_down"
    KEY_UP = "key_up"
    TYPE = "type"
    DELAY = "delay"
    SCROLL = "scroll"
    DRAG = "drag"
    HOLD = "hold"
    ACTIVATE_APP = "activate_app"
    WAIT_WINDOW = "wait_window"


@dataclass
class MacroStep:
    type: str
    x: int | None = None
    y: int | None = None
    button: str | None = None  # left, right, middle
    key: str | None = None
    text: str | None = None
    delay_ms: int = 0
    clicks: int = 1
    dx: int | None = None
    dy: int | None = None
    # Localization
    coord_space: str = "screen"  # screen | window
    app_bundle_id: str | None = None
    app_name: str | None = None
    window_title: str | None = None
    window_id: int | None = None
    local_x: float | None = None
    local_y: float | None = None
    # Drag / hold endpoints (screen or local depending on coord_space)
    end_x: int | None = None
    end_y: int | None = None
    end_local_x: float | None = None
    end_local_y: float | None = None
    hold_ms: int = 0
    click_kind: str = "single"  # single | double | triple
    timeout_ms: int = 10_000

    def label(self) -> str:
        t = self.type
        loc = ""
        if self.coord_space == "window":
            target = self.app_name or self.app_bundle_id or "app"
            loc = f" [{target}]"
            pos = f"({self.local_x:.0f}, {self.local_y:.0f})" if self.local_x is not None else ""
        else:
            pos = f"({self.x}, {self.y})" if self.x is not None else ""

        if t == StepType.CLICK:
            kind = self.click_kind or "single"
            btn = self.button or "left"
            return f"{kind.title()} {btn} click {pos}{loc}".strip()
        if t == StepType.MOVE:
            return f"Move to {pos}{loc}".strip()
        if t == StepType.KEY:
            return f"Press key: {self.key}"
        if t == StepType.KEY_DOWN:
            return f"Key down: {self.key}"
        if t == StepType.KEY_UP:
            return f"Key up: {self.key}"
        if t == StepType.TYPE:
            sample = (self.text or "")[:40]
            return f'Type: "{sample}"'
        if t == StepType.DELAY:
            return f"Wait {self.delay_ms} ms"
        if t == StepType.SCROLL:
            return f"Scroll ({self.dx or 0}, {self.dy or 0}){loc}"
        if t == StepType.DRAG:
            if self.coord_space == "window":
                end = f"({self.end_local_x:.0f}, {self.end_local_y:.0f})" if self.end_local_x is not None else "?"
            else:
                end = f"({self.end_x}, {self.end_y})"
            return f"Drag {pos} → {end}{loc}".strip()
        if t == StepType.HOLD:
            return f"Hold {self.button or 'left'} {self.hold_ms} ms {pos}{loc}".strip()
        if t == StepType.ACTIVATE_APP:
            return f"Activate {self.app_name or self.app_bundle_id or 'app'}"
        if t == StepType.WAIT_WINDOW:
            return f"Wait for window: {self.window_title or self.app_name or self.app_bundle_id}"
        return t

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> MacroStep:
        known = {f.name for f in cls.__dataclass_fields__.values()}  # type: ignore[attr-defined]
        return cls(**{k: v for k, v in data.items() if k in known})


@dataclass
class Macro:
    name: str
    steps: list[MacroStep] = field(default_factory=list)
    id: str = field(default_factory=lambda: uuid4().hex[:12])
    loop_count: int = 1  # 0 = forever until stopped
    speed: float = 1.0
    target_app_bundle_id: str | None = None
    target_app_name: str | None = None
    target_window_title: str | None = None
    activate_before_play: bool = True

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "loop_count": self.loop_count,
            "speed": self.speed,
            "target_app_bundle_id": self.target_app_bundle_id,
            "target_app_name": self.target_app_name,
            "target_window_title": self.target_window_title,
            "activate_before_play": self.activate_before_play,
            "steps": [s.to_dict() for s in self.steps],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Macro:
        steps = [MacroStep.from_dict(s) for s in data.get("steps", [])]
        return cls(
            id=data.get("id") or uuid4().hex[:12],
            name=data.get("name") or "Untitled",
            loop_count=int(data.get("loop_count", 1)),
            speed=float(data.get("speed", 1.0)),
            target_app_bundle_id=data.get("target_app_bundle_id"),
            target_app_name=data.get("target_app_name"),
            target_window_title=data.get("target_window_title"),
            activate_before_play=bool(data.get("activate_before_play", True)),
            steps=steps,
        )
