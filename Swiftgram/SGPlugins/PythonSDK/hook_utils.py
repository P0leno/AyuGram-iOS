"""Compatibility shims for `hook_utils` so Xposed/Java hooks fail cleanly with diagnostics on iOS."""

from __future__ import annotations

from typing import Any

import _ayu_runtime_host
from java import JavaNotSupportedError


class _JavaClassStub:
    def __init__(self, name: str) -> None:
        self.name = name


def find_class(class_name: str, _loader: Any = None) -> _JavaClassStub:
    msg = (
        f"hook_utils.find_class('{class_name}') uses Android JVM classes "
        "which do not exist on iOS."
    )
    _ayu_runtime_host.record_current_incompatibility(msg)
    raise JavaNotSupportedError(
        f"Android class '{class_name}' is unavailable on iOS. "
        "This plugin requires Android Java/ART hooking and cannot run on iOS."
    )


def hook_method(target: Any, method_name: str = "", _hook: Any = None) -> None:
    target_desc = getattr(target, "name", str(target))
    detail = f"{target_desc}.{method_name}".strip(".")
    msg = (
        f"hook_utils.hook_method('{detail}') targets Android Xposed/LSPosed hooking, "
        "which is unsupported on iOS."
    )
    _ayu_runtime_host.record_current_incompatibility(msg)
    raise JavaNotSupportedError(msg)


def hook_all_methods(target: Any, method_name: str = "", _hook: Any = None) -> None:
    hook_method(target, method_name, _hook)


def unhook_method(_handle: Any) -> None:
    pass


__all__ = [
    "find_class",
    "hook_all_methods",
    "hook_method",
    "unhook_method",
]
