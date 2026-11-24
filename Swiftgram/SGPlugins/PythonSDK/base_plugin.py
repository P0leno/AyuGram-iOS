"""Core exteraGram plugin base classes and hook strategies compatible with iOS."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable

import _ayu_runtime_host


class HookStrategy(Enum):
    """Determines how a hook return value alters outgoing messages or updates."""

    DEFAULT = 0
    MODIFY = 1
    CANCEL = 2
    MODIFY_FINAL = 3


class MenuItemType(Enum):
    """Supported context menu targets declared by plugins."""

    MESSAGE_CONTEXT_MENU = "message_context_menu"
    CHAT_ACTION_MENU = "chat_action_menu"
    PROFILE_ACTION_MENU = "profile_action_menu"
    DRAWER_MENU = "drawer_menu"


@dataclass
class MenuItemData:
    menu_type: MenuItemType
    text: str
    on_click: Callable[..., Any] | None = None
    item_id: str = ""
    icon: str = ""
    subtext: str = ""
    condition: str = ""
    priority: int = 0


@dataclass
class HookResult:
    strategy: HookStrategy = HookStrategy.DEFAULT
    params: Any = None
    update: Any = None
    updates: Any = None
    response: Any = None
    error: Any = None
    result: Any = None


class MethodHook:
    """Base class for exteraGram Xposed-style method hooks."""

    def before_hooked_method(self, param: Any) -> None:
        pass

    def after_hooked_method(self, param: Any) -> None:
        pass

    def replace_hooked_method(self, param: Any) -> Any:
        return None


XposedHook = MethodHook
BaseHook = MethodHook


class MethodReplacement(MethodHook):
    pass


class HookFilter:
    """Compatibility filters matching exteraGram `@hook_filters(HookFilter.*)` decorators."""

    @staticmethod
    def ArgumentEqual(index: int, value: Any):
        return ("eq", int(index), value)

    @staticmethod
    def ArgumentNotEqual(index: int, value: Any):
        return ("ne", int(index), value)

    @staticmethod
    def ResultEqual(value: Any):
        return ("res_eq", 0, value)

    @staticmethod
    def Condition(predicate: Callable[..., bool]):
        return ("cond", 0, predicate)


def hook_filters(*filters: Any):
    """Attach filter metadata to a `MethodHook` method while wrapping check evaluation."""

    def decorator(fn: Callable[..., Any]) -> Callable[..., Any]:
        setattr(fn, "_ayu_hook_filters", list(filters))
        return fn

    return decorator


def method_hook(*_args, **_kwargs):
    """Decorator compatibility helper."""

    def decorator(cls):
        return cls

    return decorator


_SUPPORTED_SEND_HOOK_ALIASES = frozenset({
    "send_message",
    "on_send_message",
    "tl_messages_sendmessage",
    "tlrpc.tl_messages_sendmessage",
    "messages.sendmessage",
})

_SUPPORTED_UPDATE_HOOK_ALIASES = frozenset({
    "update",
    "receive_message",
    "on_receive_message",
    "tlrpc.update",
    "updates",
})


class BasePlugin:
    """Base class inherited by every `.plugin` script."""

    id: str = ""
    name: str = ""
    description: str = ""
    author: str = ""
    version: str = "1.0"
    min_version: str = ""
    icon: str = ""

    def __init__(self) -> None:
        self._ayu_plugin_id: str = ""
        self._ayu_metadata: dict[str, str] = {}
        self._ayu_send_hook_active: bool = False
        self._ayu_send_hook_priority: int = 0
        self._ayu_registered_hooks: list[tuple[str, str | None, int]] = []
        self._ayu_menu_items: list[MenuItemData] = []
        self._ayu_incompatible_hooks: list[str] = []

    def _ayu_bind_runtime(self, plugin_id: str, metadata: dict[str, str]) -> None:
        self._ayu_plugin_id = plugin_id
        self._ayu_metadata = dict(metadata)
        self.id = metadata.get("id", plugin_id)
        self.name = metadata.get("name", plugin_id)
        self.description = metadata.get("description", "")
        self.author = metadata.get("author", "")
        self.version = metadata.get("version", "1.0")
        self.min_version = metadata.get("min_version", "")
        self.icon = metadata.get("icon", "")

    def log(self, message: Any) -> None:
        _ayu_runtime_host.log("info", self._ayu_plugin_id or self.id or "plugin", str(message))

    def get_setting(self, key: str, default: Any = None) -> Any:
        pid = self._ayu_plugin_id or self.id or self.__class__.__name__
        return _ayu_runtime_host.get_setting(pid, key, default)

    def set_setting(self, key: str, value: Any) -> None:
        pid = self._ayu_plugin_id or self.id or self.__class__.__name__
        _ayu_runtime_host.set_setting(pid, key, value)

    def add_on_send_message_hook(self, priority: int = 0) -> None:
        self._ayu_send_hook_active = True
        self._ayu_send_hook_priority = int(priority)

    def remove_on_send_message_hook(self) -> None:
        self._ayu_send_hook_active = False

    def add_hook(
        self,
        name: str,
        match_substring: str | None = None,
        priority: int = 0,
    ) -> None:
        normalized = str(name).strip().lower()
        self._ayu_registered_hooks.append((normalized, match_substring, int(priority)))
        if normalized in _SUPPORTED_SEND_HOOK_ALIASES:
            self.add_on_send_message_hook(priority=priority)
            return
        if normalized in _SUPPORTED_UPDATE_HOOK_ALIASES:
            return
        msg = (
            f"Hook `{name}` targets Android TL/client hook surface not wired individually on iOS; "
            "pure-Python send/receive message hooks remain active."
        )
        self._ayu_incompatible_hooks.append(msg)
        _ayu_runtime_host.record_current_incompatibility(msg)
        self.log(msg)

    def remove_hook(self, name: str, *_args) -> None:
        normalized = str(name).strip().lower()
        self._ayu_registered_hooks = [
            item for item in self._ayu_registered_hooks if item[0] != normalized
        ]
        if normalized in _SUPPORTED_SEND_HOOK_ALIASES:
            self.remove_on_send_message_hook()

    def _ayu_wants_update(self, update_name: str) -> bool:
        target = update_name.strip().lower()
        for hook_name, substring, _ in self._ayu_registered_hooks:
            if hook_name not in _SUPPORTED_UPDATE_HOOK_ALIASES:
                continue
            if substring is None or substring.lower() in target:
                return True
        return type(self).on_update_hook is not BasePlugin.on_update_hook

    def hook_method(self, method_ref: Any, hook_handler: Any) -> None:
        import hook_utils

        hook_utils.hook_method(method_ref, "", hook_handler)

    def unhook_method(self, _handle: Any) -> None:
        pass

    def add_menu_item(self, item: MenuItemData) -> MenuItemData:
        self._ayu_menu_items.append(item)
        return item

    def remove_menu_item(self, item_id: str) -> None:
        self._ayu_menu_items = [m for m in self._ayu_menu_items if m.item_id != item_id]

    def on_plugin_load(self) -> None:
        pass

    def on_plugin_unload(self) -> None:
        pass

    def create_settings(self) -> list[Any]:
        return []

    def on_setting_changed(self, _key: str, _value: Any) -> None:
        pass

    def on_send_message_hook(self, _account: int, _params: Any) -> HookResult:
        return HookResult(strategy=HookStrategy.DEFAULT)

    def on_update_hook(self, _update_name: str, _account: int, _update: Any) -> HookResult:
        return HookResult(strategy=HookStrategy.DEFAULT)


__all__ = [
    "BaseHook",
    "BasePlugin",
    "HookFilter",
    "HookResult",
    "HookStrategy",
    "MenuItemData",
    "MenuItemType",
    "MethodHook",
    "MethodReplacement",
    "XposedHook",
    "hook_filters",
    "method_hook",
]
