"""Compatibility shims for `extera_utils.classes` (`Base`, `java_subclass`, `joverride`)."""

from __future__ import annotations

from typing import Any, Callable


class Base:
    """Base mixin for Java-backed subclass helpers in exteraGram."""

    def __init__(self, *_args: Any, **_kwargs: Any) -> None:
        pass

    @classmethod
    def new_instance(cls, *args: Any, **kwargs: Any) -> "Base":
        return cls(*args, **kwargs)

    @property
    def java(self) -> "Base":
        return self

    def __getattr__(self, name: str) -> Any:
        if name.startswith("__"):
            raise AttributeError(name)
        return lambda *_args, **_kwargs: None


def java_subclass(*_interfaces: Any, **_kwargs: Any):
    """Class decorator creating a Python subclass tolerant of Java interface methods."""

    def decorator(cls):
        return cls

    return decorator


def joverride(fn_or_type: Any = None, *_args: Any, **_kwargs: Any) -> Any:
    """Method decorator marking a Java override in Python (supports `@joverride` and `@joverride()`)."""
    if callable(fn_or_type) and not isinstance(fn_or_type, type):
        return fn_or_type

    def decorator(fn: Callable[..., Any]) -> Callable[..., Any]:
        return fn

    return decorator


__all__ = ["Base", "java_subclass", "joverride"]
