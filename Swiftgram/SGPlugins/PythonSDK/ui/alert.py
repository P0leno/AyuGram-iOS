"""Native alert dialog builder bridged to iOS `TextAlertController` / `UIAlertController`."""

from __future__ import annotations

import _ayu_runtime_host


class AlertDialogBuilder:
    """Fluent builder matching exteraGram `ui.alert.AlertDialogBuilder`."""

    BUTTON_POSITIVE = -1
    BUTTON_NEGATIVE = -2
    BUTTON_NEUTRAL = -3

    def __init__(self, context=None, title: str = "", message: str = ""):
        self._context = context
        self._title = str(title) if title else ""
        self._message = str(message) if message else ""
        self._buttons: list[dict] = []

    def set_title(self, title: str) -> "AlertDialogBuilder":
        self._title = str(title)
        return self

    def set_message(self, message: str) -> "AlertDialogBuilder":
        self._message = str(message)
        return self

    def set_positive_button(self, text: str, listener=None) -> "AlertDialogBuilder":
        self._buttons.append({"style": "default", "text": str(text), "callback": listener})
        return self

    def set_negative_button(self, text: str, listener=None) -> "AlertDialogBuilder":
        self._buttons.append({"style": "cancel", "text": str(text), "callback": listener})
        return self

    def set_neutral_button(self, text: str, listener=None) -> "AlertDialogBuilder":
        self._buttons.append({"style": "neutral", "text": str(text), "callback": listener})
        return self

    def create(self) -> "AlertDialogBuilder":
        return self

    def show(self) -> "AlertDialogBuilder":
        _ayu_runtime_host.show_alert(self._title, self._message, self._buttons)
        return self

    def dismiss(self) -> None:
        pass


__all__ = ["AlertDialogBuilder"]
