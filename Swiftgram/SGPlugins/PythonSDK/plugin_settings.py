"""Compatibility shims for exteraGram `plugin_settings` helpers."""

from __future__ import annotations

from typing import Any

import _ayu_runtime_host


def _resolve_pid(plugin_id: str | None) -> str:
    return str(plugin_id or _ayu_runtime_host.get_current_plugin_id() or "default")


def get_setting(plugin_id: str | None, key: str, default: Any = None) -> Any:
    return _ayu_runtime_host.get_setting(_resolve_pid(plugin_id), str(key), default)


def set_setting(plugin_id: str | None, key: str, value: Any) -> None:
    _ayu_runtime_host.set_setting(_resolve_pid(plugin_id), str(key), value)


class PluginSettings:
    def __init__(self, plugin_id: str | None = None) -> None:
        self.plugin_id = _resolve_pid(plugin_id)

    def get(self, key: str, default: Any = None) -> Any:
        return get_setting(self.plugin_id, key, default)

    def set(self, key: str, value: Any) -> None:
        set_setting(self.plugin_id, key, value)


__all__ = ["PluginSettings", "get_setting", "set_setting"]
