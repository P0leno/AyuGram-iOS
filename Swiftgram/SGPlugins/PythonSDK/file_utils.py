"""Compatibility shims for exteraGram `file_utils` helpers."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import _ayu_runtime_host


def get_files_dir() -> str:
    p = Path(_ayu_runtime_host.get_plugin_data_dir())
    p.mkdir(parents=True, exist_ok=True)
    return str(p)


def get_plugins_dir() -> str:
    p = Path(_ayu_runtime_host.get_plugin_data_dir()).parent / "scripts"
    p.mkdir(parents=True, exist_ok=True)
    return str(p)


def get_cache_dir() -> str:
    p = Path(_ayu_runtime_host.get_plugin_data_dir()) / "cache"
    p.mkdir(parents=True, exist_ok=True)
    return str(p)


def ensure_dir_exists(path: str | Path) -> str:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return str(p)


def read_file(path: str | Path, encoding: str = "utf-8") -> str:
    return Path(path).read_text(encoding=encoding)


def write_file(path: str | Path, content: Any, encoding: str = "utf-8") -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(str(content), encoding=encoding)


__all__ = [
    "ensure_dir_exists",
    "get_cache_dir",
    "get_files_dir",
    "get_plugins_dir",
    "read_file",
    "write_file",
]
