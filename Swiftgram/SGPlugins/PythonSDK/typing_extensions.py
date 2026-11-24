"""Pure-Python `typing_extensions` shim re-exporting stdlib typing + `@deprecated`."""

from __future__ import annotations

import functools
import typing
from typing import (
    Any,
    Callable,
    Generic,
    Literal,
    Optional,
    Protocol,
    TypeVar,
    Union,
    get_args,
    get_origin,
    overload,
)


def deprecated(_message: str = "", **_kwargs: Any):
    def decorator(obj):
        if callable(obj) and not isinstance(obj, type):
            @functools.wraps(obj)
            def wrapper(*args, **kwargs):
                return obj(*args, **kwargs)

            return wrapper
        return obj

    return decorator


def __getattr__(name: str) -> Any:
    return getattr(typing, name)
