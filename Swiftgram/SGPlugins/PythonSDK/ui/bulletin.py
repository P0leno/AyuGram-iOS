"""Bulletin/toast notifications backed by Telegram `UndoOverlayController` on iOS."""

from __future__ import annotations

import _ayu_runtime_host


class BulletinHelper:
    """Static helper matching exteraGram `ui.bulletin.BulletinHelper`."""

    @staticmethod
    def show_info(message: str, title: str | None = None) -> None:
        _ayu_runtime_host.show_bulletin(title or "", str(message), "info")

    @staticmethod
    def show_success(message: str, title: str | None = None) -> None:
        _ayu_runtime_host.show_bulletin(title or "", str(message), "success")

    @staticmethod
    def show_error(message: str, title: str | None = None) -> None:
        _ayu_runtime_host.show_bulletin(title or "", str(message), "error")

    @staticmethod
    def show_simple(message: str, icon_name: str = "info") -> None:
        _ayu_runtime_host.show_bulletin("", str(message), icon_name or "info")

    @staticmethod
    def show_with_button(
        message: str,
        button_text: str,
        on_click=None,
        icon_name: str = "info",
    ) -> None:
        text = f"{message} [{button_text}]" if button_text else str(message)
        _ayu_runtime_host.show_bulletin("", text, icon_name or "info")


__all__ = ["BulletinHelper"]
