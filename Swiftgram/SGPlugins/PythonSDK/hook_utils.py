"""Compatibility shims for `hook_utils` Xposed/Android reflection imports on iOS."""

from __future__ import annotations

from typing import Any

from java import JavaNotSupportedError, _report_jvm_usage


def _unsupported(api_name: str, detail: str = "") -> JavaNotSupportedError:
    _report_jvm_usage(api_name, detail)
    target = f" `{detail}`" if detail else ""
    return JavaNotSupportedError(
        f"{api_name}{target} is unavailable on iOS: Android ART/Xposed reflection is not supported. "
        "Pure-Python plugins using BasePlugin, send/update hooks, client_utils, and ui.* work on iOS."
    )


def find_class(class_name: str, class_loader: Any = None) -> Any:
    from _java_bridge import resolve_bridged_class

    bridged = resolve_bridged_class(class_name)
    if bridged is not None:
        return bridged
    raise _unsupported("hook_utils.find_class", str(class_name))


def find_method(*_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.find_method")


def find_constructor(*_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.find_constructor")


def hook_method(method_ref: Any, *args: Any, **kwargs: Any) -> Any:
    import _ayu_runtime_host
    from _java_bridge import MessagesControllerBridge, SendMessagesHelperBridge

    handler = args[-1] if args else kwargs.get("handler")
    method_name = str(args[0]) if len(args) >= 2 and isinstance(args[0], str) else str(method_ref)
    if method_ref in (SendMessagesHelperBridge, "SendMessagesHelper") or "sendMessage" in method_name:
        if getattr(method_ref, "_ayu_bridged", False) or isinstance(method_ref, type) and method_ref is SendMessagesHelperBridge:
            return _ayu_runtime_host.register_method_hook("send_message", handler)
    if method_ref in (MessagesControllerBridge, "MessagesController") and (
        "processUpdates" in method_name or "Notification" in method_name
    ):
        return _ayu_runtime_host.register_method_hook("receive_message", handler)

    raise _unsupported("hook_utils.hook_method", str(method_ref))


def hook_methods(*_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.hook_methods")


def hook_all_methods(clazz: Any, method_name: str, *args: Any, **_kwargs: Any) -> Any:
    from _java_bridge import MessagesControllerBridge, SendMessagesHelperBridge

    if clazz is SendMessagesHelperBridge and "send" in str(method_name).lower():
        return hook_method(clazz, method_name, args[-1] if args else None)
    if clazz is MessagesControllerBridge and "update" in str(method_name).lower():
        return hook_method(clazz, method_name, args[-1] if args else None)
    raise _unsupported("hook_utils.hook_all_methods", f"{clazz}.{method_name}")


def hook_all_constructors(clazz: Any, *_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.hook_all_constructors", str(clazz))


def unhook_method(_handle: Any) -> None:
    return None


def _is_bridged_target(obj: Any) -> bool:
    return isinstance(obj, dict) or getattr(obj, "_ayu_bridged", False)


def get_private_field(obj: Any, field_name: str) -> Any:
    if _is_bridged_target(obj):
        if isinstance(obj, dict):
            return obj.get(field_name)
        if hasattr(obj, field_name):
            return getattr(obj, field_name)
    raise _unsupported("hook_utils.get_private_field", str(field_name))


def set_private_field(obj: Any, field_name: str, value: Any) -> None:
    if _is_bridged_target(obj):
        if isinstance(obj, dict):
            obj[field_name] = value
            return
        setattr(obj, field_name, value)
        return
    raise _unsupported("hook_utils.set_private_field", str(field_name))


def get_static_field(clazz: Any, field_name: str) -> Any:
    if _is_bridged_target(clazz) and hasattr(clazz, field_name):
        return getattr(clazz, field_name)
    raise _unsupported("hook_utils.get_static_field", f"{clazz}.{field_name}")


def set_static_field(clazz: Any, field_name: str, value: Any) -> None:
    if _is_bridged_target(clazz):
        setattr(clazz, field_name, value)
        return
    raise _unsupported("hook_utils.set_static_field", f"{clazz}.{field_name}")


def call_private_method(obj: Any, method_name: str, *args: Any) -> Any:
    if _is_bridged_target(obj) and hasattr(obj, method_name):
        fn = getattr(obj, method_name)
        if callable(fn):
            return fn(*args)
    raise _unsupported("hook_utils.call_private_method", str(method_name))


def call_static_method(clazz: Any, method_name: str, *args: Any) -> Any:
    if _is_bridged_target(clazz) and hasattr(clazz, method_name):
        fn = getattr(clazz, method_name)
        if callable(fn):
            return fn(*args)
    raise _unsupported("hook_utils.call_static_method", f"{clazz}.{method_name}")


class XposedHelpers:
    findClass = staticmethod(find_class)
    findMethodBestMatch = staticmethod(find_method)
    findConstructorBestMatch = staticmethod(find_constructor)
    findAndHookMethod = staticmethod(hook_method)
    hookAllMethods = staticmethod(hook_all_methods)
    hookAllConstructors = staticmethod(hook_all_constructors)
    getObjectField = staticmethod(get_private_field)
    setObjectField = staticmethod(set_private_field)
    getStaticObjectField = staticmethod(get_static_field)
    setStaticObjectField = staticmethod(set_static_field)
    callMethod = staticmethod(call_private_method)
    callStaticMethod = staticmethod(call_static_method)


__all__ = [
    "XposedHelpers",
    "call_private_method",
    "call_static_method",
    "find_class",
    "find_constructor",
    "find_method",
    "get_private_field",
    "get_static_field",
    "hook_all_constructors",
    "hook_all_methods",
    "hook_method",
    "hook_methods",
    "set_private_field",
    "set_static_field",
    "unhook_method",
]
