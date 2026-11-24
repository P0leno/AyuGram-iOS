"""Lightweight `packaging` shim providing `packaging.version.Version`."""

from .version import InvalidVersion, Version

__all__ = ["InvalidVersion", "Version"]
