"""Compatibility shims for `android_utils` helper calls used by exteraGram plugins."""

from __future__ import annotations

import threading
from typing import Any, Callable

import _ayu_runtime_host


def log(message: Any, tag: str = "Plugin") -> None:
    """Write a plugin log entry visible in AyuGram's in-app Python Console."""
    _ayu_runtime_host.log("info", tag, str(message))


def run_on_ui_thread(fn: Callable[..., Any], delay: float = 0.0) -> None:
    """Execute callback asynchronously (host UI actions are already dispatched on MainActor)."""
    if delay and delay > 0:
        timer = threading.Timer(float(delay), fn)
        timer.daemon = True
        timer.start()
    else:
        fn()


class OnClickListener:
    def __init__(self, fn: Callable[..., Any]) -> None:
        self._fn = fn

    def __call__(self, *args: Any, **kwargs: Any) -> Any:
        return self._fn(*args, **kwargs)


class _StubNamespace:
    def __getattr__(self, name: str) -> Any:
        return name


R = _StubNamespace()


class ApplicationLoader:
    applicationContext = None


__all__ = [
    "ApplicationLoader",
    "OnClickListener",
    "R",
    "log",
    "run_on_ui_thread",
]
