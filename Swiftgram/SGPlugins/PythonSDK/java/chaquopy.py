"""Chaquopy compatibility types for exteraGram plugins."""

from typing import Any


class JavaClass(type):
    pass


class _DynamicProxy:
    pass


__all__ = ["JavaClass", "_DynamicProxy"]
