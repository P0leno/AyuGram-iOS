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
    raise _unsupported("hook_utils.find_class", str(class_name))


def find_method(*_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.find_method")


def find_constructor(*_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.find_constructor")


def hook_method(method_ref: Any, *_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.hook_method", str(method_ref))


def hook_methods(*_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.hook_methods")


def hook_all_methods(clazz: Any, method_name: str, *_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.hook_all_methods", f"{clazz}.{method_name}")


def hook_all_constructors(clazz: Any, *_args: Any, **_kwargs: Any) -> Any:
    raise _unsupported("hook_utils.hook_all_constructors", str(clazz))


def unhook_method(_handle: Any) -> None:
    return None


def get_private_field(_obj: Any, field_name: str) -> Any:
    raise _unsupported("hook_utils.get_private_field", str(field_name))


def set_private_field(_obj: Any, field_name: str, _value: Any) -> None:
    raise _unsupported("hook_utils.set_private_field", str(field_name))


def get_static_field(clazz: Any, field_name: str) -> Any:
    raise _unsupported("hook_utils.get_static_field", f"{clazz}.{field_name}")


def set_static_field(clazz: Any, field_name: str, _value: Any) -> None:
    raise _unsupported("hook_utils.set_static_field", f"{clazz}.{field_name}")


def call_private_method(_obj: Any, method_name: str, *_args: Any) -> Any:
    raise _unsupported("hook_utils.call_private_method", str(method_name))


def call_static_method(clazz: Any, method_name: str, *_args: Any) -> Any:
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
