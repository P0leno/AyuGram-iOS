"""Pure-Python PEP-440 subset implementing `packaging.version.Version`."""

from __future__ import annotations

import re
from functools import total_ordering


class InvalidVersion(ValueError):
    pass


_VERSION_RE = re.compile(
    r"^\s*v?(?P<release>\d+(?:\.\d+)*)(?P<pre>(?:a|b|rc|alpha|beta|dev|post)?\d*)?.*$",
    re.IGNORECASE,
)


@total_ordering
class Version:
    def __init__(self, version: str) -> None:
        self._raw = str(version).strip()
        m = _VERSION_RE.match(self._raw)
        if not m:
            raise InvalidVersion(f"Invalid version: {version!r}")
        parts = [int(p) for p in m.group("release").split(".")]
        while len(parts) > 1 and parts[-1] == 0:
            parts.pop()
        self.release = tuple(parts)
        pre = (m.group("pre") or "").lower()
        self._pre = (0, "") if not pre else (-1, pre)

    @property
    def major(self) -> int:
        return self.release[0] if len(self.release) > 0 else 0

    @property
    def minor(self) -> int:
        return self.release[1] if len(self.release) > 1 else 0

    @property
    def micro(self) -> int:
        return self.release[2] if len(self.release) > 2 else 0

    @property
    def base_version(self) -> str:
        return ".".join(str(x) for x in self.release)

    def _key(self):
        return (self.release, self._pre)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        return self._key() == other._key()

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        return self._key() < other._key()

    def __hash__(self) -> int:
        return hash(self._key())

    def __str__(self) -> str:
        return self._raw

    def __repr__(self) -> str:
        return f"<Version({self._raw!r})>"


__all__ = ["InvalidVersion", "Version"]
