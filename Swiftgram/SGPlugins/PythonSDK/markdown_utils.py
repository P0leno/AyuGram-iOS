"""Markdown -> plain text + UTF-16 Telegram message entities parser."""

from __future__ import annotations

import re
from dataclasses import dataclass, field


def _utf16_len(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


@dataclass
class RawEntity:
    """Serialized entity matching Telegram / TelegramCore attribute ranges."""

    type: str
    offset: int
    length: int
    url: str = ""
    language: str = ""

    def to_dict(self) -> dict:
        data = {
            "type": self.type,
            "offset": self.offset,
            "length": self.length,
        }
        if self.url:
            data["url"] = self.url
        if self.language:
            data["language"] = self.language
        return data


@dataclass
class ParsedMessage:
    text: str
    entities: list[RawEntity] = field(default_factory=list)

    @property
    def raw_entities(self) -> list[dict]:
        return [e.to_dict() for e in self.entities]


_TOKEN_PATTERN = re.compile(
    r"```(?:([A-Za-z0-9_+-]+)\n)?([\s\S]*?)```"
    r"|`([^`\n]+)`"
    r"|\*\*(.+?)\*\*"
    r"|__(.+?)__"
    r"|~~(.+?)~~"
    r"|\|\|(.+?)\|\|"
    r"|\[([^\]]+)\]\((https?://[^)\s]+|tg://[^)\s]+)\)"
)


def parse_markdown(text: str) -> ParsedMessage:
    """Parse common Telegram markdown syntax into clean text and UTF-16 entity offsets."""
    if not text:
        return ParsedMessage(text="", entities=[])

    out_parts: list[str] = []
    entities: list[RawEntity] = []
    pos = 0
    utf16_cursor = 0

    for match in _TOKEN_PATTERN.finditer(text):
        start, end = match.span()
        if start > pos:
            plain = text[pos:start]
            out_parts.append(plain)
            utf16_cursor += _utf16_len(plain)

        if match.group(2) is not None:  # ```code```
            lang = match.group(1) or ""
            content = match.group(2)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="pre", offset=utf16_cursor, length=length, language=lang))
            utf16_cursor += length
        elif match.group(3) is not None:  # `code`
            content = match.group(3)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="code", offset=utf16_cursor, length=length))
            utf16_cursor += length
        elif match.group(4) is not None:  # **bold**
            content = match.group(4)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="bold", offset=utf16_cursor, length=length))
            utf16_cursor += length
        elif match.group(5) is not None:  # __italic__
            content = match.group(5)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="italic", offset=utf16_cursor, length=length))
            utf16_cursor += length
        elif match.group(6) is not None:  # ~~strike~~
            content = match.group(6)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="strike", offset=utf16_cursor, length=length))
            utf16_cursor += length
        elif match.group(7) is not None:  # ||spoiler||
            content = match.group(7)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="spoiler", offset=utf16_cursor, length=length))
            utf16_cursor += length
        elif match.group(8) is not None:  # [label](url)
            content = match.group(8)
            url = match.group(9)
            out_parts.append(content)
            length = _utf16_len(content)
            entities.append(RawEntity(type="text_url", offset=utf16_cursor, length=length, url=url))
            utf16_cursor += length

        pos = end

    if pos < len(text):
        tail = text[pos:]
        out_parts.append(tail)

    return ParsedMessage(text="".join(out_parts), entities=entities)


__all__ = ["ParsedMessage", "RawEntity", "parse_markdown"]
