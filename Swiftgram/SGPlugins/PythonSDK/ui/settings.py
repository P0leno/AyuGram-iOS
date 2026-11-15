"""Declarative plugin settings items rendered natively in SwiftUI / ItemListController."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable


class SettingItem:
    """Base class for serializable plugin settings rows."""

    item_type: str = "unknown"

    def to_dict(self) -> dict[str, Any]:
        raise NotImplementedError


@dataclass
class Header(SettingItem):
    text: str
    item_type: str = field(default="header", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {"type": self.item_type, "text": str(self.text)}


@dataclass
class Divider(SettingItem):
    text: str = ""
    item_type: str = field(default="divider", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {"type": self.item_type, "text": str(self.text)}


@dataclass
class Switch(SettingItem):
    key: str
    text: str
    default: bool = False
    subtext: str = ""
    icon: str | None = None
    on_change: Callable[[bool], Any] | None = None
    item_type: str = field(default="switch", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.item_type,
            "key": self.key,
            "text": str(self.text),
            "default": bool(self.default),
            "subtext": str(self.subtext),
            "icon": self.icon or "",
        }


@dataclass
class Input(SettingItem):
    key: str
    text: str
    default: str = ""
    subtext: str = ""
    icon: str | None = None
    multiline: bool = False
    password: bool = False
    on_change: Callable[[str], Any] | None = None
    item_type: str = field(default="input", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.item_type,
            "key": self.key,
            "text": str(self.text),
            "default": "" if self.default is None else str(self.default),
            "subtext": str(self.subtext),
            "icon": self.icon or "",
            "multiline": bool(self.multiline),
            "password": bool(self.password),
        }


EditText = Input


@dataclass
class Selector(SettingItem):
    key: str
    text: str
    items: list[str]
    default: int = 0
    subtext: str = ""
    icon: str | None = None
    on_change: Callable[[int], Any] | None = None
    item_type: str = field(default="selector", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.item_type,
            "key": self.key,
            "text": str(self.text),
            "items": [str(item) for item in self.items],
            "default": int(self.default),
            "subtext": str(self.subtext),
            "icon": self.icon or "",
        }


@dataclass
class Slider(SettingItem):
    key: str
    text: str
    min: float = 0.0
    max: float = 100.0
    default: float = 0.0
    step: float = 1.0
    subtext: str = ""
    on_change: Callable[[float], Any] | None = None
    item_type: str = field(default="slider", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.item_type,
            "key": self.key,
            "text": str(self.text),
            "min": float(self.min),
            "max": float(self.max),
            "default": float(self.default),
            "step": float(self.step),
            "subtext": str(self.subtext),
        }


@dataclass
class Text(SettingItem):
    text: str
    icon: str | None = None
    on_click: Callable[..., Any] | None = None
    accent: bool = False
    red: bool = False
    subtext: str = ""
    on_long_click: Callable[..., Any] | None = None
    item_type: str = field(default="text", init=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.item_type,
            "text": str(self.text),
            "icon": self.icon or "",
            "accent": bool(self.accent),
            "red": bool(self.red),
            "subtext": str(self.subtext),
            "clickable": self.on_click is not None,
        }


__all__ = [
    "Divider",
    "EditText",
    "Header",
    "Input",
    "Selector",
    "SettingItem",
    "Slider",
    "Switch",
    "Text",
]
