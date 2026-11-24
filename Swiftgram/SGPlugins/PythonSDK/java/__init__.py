"""Pure-Python / iOS Smart Bridge shims for Android/Java `jclass` and Xposed hooks."""

from __future__ import annotations

from typing import Any


class JavaNotSupportedError(RuntimeError):
    """Raised when an Android plugin invokes an unbridged JVM/ART reflection API."""


def _report_jvm_usage(api_name: str, detail: str = "") -> None:
    try:
        import _ayu_runtime_host

        msg = f"Unsupported Android/Java API `{api_name}`"
        if detail:
            msg += f" ({detail})"
        msg += ": Android ART/Xposed reflection is not available on iOS."
        _ayu_runtime_host.record_current_incompatibility(msg)
    except Exception:
        pass


def jclass(class_name: str):
    """Resolve `from java import jclass` via Smart iOS Bridge for supported Telegram/Android classes."""
    from _java_bridge import resolve_bridged_class

    bridged = resolve_bridged_class(class_name)
    if bridged is not None:
        return bridged

    _report_jvm_usage("java.jclass", class_name)
    raise JavaNotSupportedError(
        f"Cannot resolve Java class '{class_name}' on iOS. "
        "Plugins relying on Android Java/Telegram Xposed hooks cannot run on iOS; "
        "only pure-Python or Smart-Bridged plugins are supported."
    )


def dynamic_proxy(*_interfaces):
    """Create a lightweight callable/attribute-tolerant Python proxy class for Android listener interfaces."""

    class _DynamicProxyBase:
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            pass

    return _DynamicProxyBase


def cast(_target_type, value):
    return value


def jarray(_element_type):
    return lambda *items: list(items)
