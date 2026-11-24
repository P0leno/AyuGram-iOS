"""Client and MTProto request helpers bridging exteraGram `client_utils` calls to TelegramCore."""

from __future__ import annotations

import threading
from typing import Any, Callable

import _ayu_runtime_host


class _UserObject:
    """Represents the active Telegram user record returned by `UserConfig.getCurrentUser()`."""

    def __init__(self, payload: dict[str, Any]) -> None:
        self.id = int(payload.get("id", 0) or 0)
        self.first_name = str(payload.get("first_name", ""))
        self.last_name = str(payload.get("last_name", ""))
        self.username = str(payload.get("username", ""))
        self.phone = str(payload.get("phone", ""))
        self.premium = bool(payload.get("is_premium", False))


class UserConfigShim:
    def getClientUserId(self) -> int:
        return int(_ayu_runtime_host.get_current_account().get("id", 0) or 0)

    def getCurrentUser(self) -> _UserObject:
        return _UserObject(_ayu_runtime_host.get_current_account())

    def isPremium(self) -> bool:
        return bool(_ayu_runtime_host.get_current_account().get("is_premium", False))


class MessagesControllerShim:
    def loadFullUser(self, user_id: int) -> dict[str, Any]:
        return _ayu_runtime_host.execute_request("users.getFullUser", {"user_id": int(user_id)})


class SendMessagesHelperShim:
    def sendMessage(self, params: dict[str, Any]) -> dict[str, Any]:
        return send_message(params)


class ConnectionsManagerShim:
    def sendRequest(self, request: Any, callback: Callable[..., Any] | None = None) -> dict[str, Any]:
        return send_request(request, callback=callback)


class RequestCallback:
    """Wrapper matching exteraGram callback helper objects."""

    def __init__(self, fn: Callable[[Any, Any], Any]) -> None:
        self._fn = fn

    def on_complete(self, response: Any, error: Any) -> None:
        self._fn(response, error)


def get_user_config(_account: int = 0) -> UserConfigShim:
    return UserConfigShim()


def get_messages_controller(_account: int = 0) -> MessagesControllerShim:
    return MessagesControllerShim()


def get_send_messages_helper(_account: int = 0) -> SendMessagesHelperShim:
    return SendMessagesHelperShim()


def get_connections_manager(_account: int = 0) -> ConnectionsManagerShim:
    return ConnectionsManagerShim()


def send_message(params: Any) -> dict[str, Any]:
    """Send a Telegram message through the active iOS TelegramCore account engine."""
    if not isinstance(params, dict):
        if hasattr(params, "to_dict"):
            params = params.to_dict()
        elif hasattr(params, "__dict__"):
            params = {k: v for k, v in vars(params).items() if not k.startswith("_")}
        else:
            params = {"message": str(params)}
    return _ayu_runtime_host.send_message(params)


def send_request(
    request: Any,
    params_or_callback: Any = None,
    callback: Callable[[Any, Any], Any] | None = None,
    async_run: bool = False,
) -> dict[str, Any]:
    """Execute a supported Telegram API request (`method`, `params`, optional callback)."""
    if isinstance(request, str):
        method = request
        if callable(params_or_callback):
            cb = params_or_callback
            params: dict[str, Any] = {}
        else:
            params = dict(params_or_callback or {})
            cb = callback
    elif isinstance(request, dict):
        method = str(request.get("_") or request.get("method") or "")
        params = {k: v for k, v in request.items() if k not in ("_", "method")}
        cb = params_or_callback if callable(params_or_callback) else callback
    else:
        method = str(getattr(request, "CONSTRUCTOR_NAME", getattr(request, "METHOD_NAME", type(request).__name__)))
        params = {
            k: v for k, v in vars(request).items() if not str(k).startswith("_")
        }
        cb = params_or_callback if callable(params_or_callback) else callback

    def invoke() -> dict[str, Any]:
        result = _ayu_runtime_host.execute_request(method, params)
        if cb is not None:
            if result.get("ok"):
                cb(result.get("result", result), None)
            else:
                cb(None, result.get("error", "Request failed"))
        return result

    if async_run:
        t = threading.Thread(target=invoke, daemon=True)
        t.start()
        return {"ok": True, "async": True}
    return invoke()


def run_on_queue(fn: Callable[..., Any], *args: Any, **kwargs: Any) -> threading.Thread:
    thread = threading.Thread(target=fn, args=args, kwargs=kwargs, daemon=True)
    thread.start()
    return thread


__all__ = [
    "RequestCallback",
    "get_connections_manager",
    "get_messages_controller",
    "get_send_messages_helper",
    "get_user_config",
    "run_on_queue",
    "send_message",
    "send_request",
]


GLOBAL_QUEUE = "global"
STAGE_QUEUE = "stage"
PLUGINS_QUEUE = "plugins"


class _NotificationCenterShim:
    def addObserver(self, *_args, **_kwargs) -> None:
        return None

    def removeObserver(self, *_args, **_kwargs) -> None:
        return None

    def postNotificationName(self, *_args, **_kwargs) -> None:
        return None


class _AccountInstanceShim:
    def getUserConfig(self):
        return get_user_config()

    def getMessagesController(self):
        return get_messages_controller()

    def getSendMessagesHelper(self):
        return get_send_messages_helper()

    def getConnectionsManager(self):
        return get_connections_manager()

    def getNotificationCenter(self):
        return _NotificationCenterShim()


class _GenericClientShim:
    def __getattr__(self, _name: str):
        return lambda *_args, **_kwargs: None


class _FragmentShim:
    _ayu_bridged = True

    def __init__(self, chat_info: dict[str, Any]) -> None:
        self._chat_info = dict(chat_info)
        self.dialog_id = int(chat_info.get("peer_id", 0) or 0)
        self.chat_id = self.dialog_id

    def getDialogId(self) -> int:
        return self.dialog_id

    def getCurrentAccount(self) -> int:
        return int(self._chat_info.get("account", 0) or 0)

    def getParentActivity(self):
        return None

    def getContext(self):
        from _java_bridge import ApplicationLoaderBridge

        return ApplicationLoaderBridge.applicationContext

    def getMessagesController(self):
        return get_messages_controller(self.getCurrentAccount())

    def getSendMessagesHelper(self):
        return get_send_messages_helper(self.getCurrentAccount())


def get_last_fragment():
    """Return active chat fragment shim if a chat is currently open, else None."""
    chat_info = _ayu_runtime_host.get_active_chat()
    if chat_info and int(chat_info.get("peer_id", 0) or 0) != 0:
        return _FragmentShim(chat_info)
    return None


def get_active_chat() -> dict[str, Any]:
    return _ayu_runtime_host.get_active_chat()


def copy_to_clipboard(text: str) -> bool:
    return _ayu_runtime_host.copy_to_clipboard(str(text or ""))


def open_url(url: str) -> bool:
    return _ayu_runtime_host.open_url(str(url or ""))


def get_current_fragment():
    return get_last_fragment()


def get_account_instance(_account: int = 0):
    return _AccountInstanceShim()


def get_messages_storage():
    return _GenericClientShim()


def get_media_controller():
    return _GenericClientShim()


def get_media_data_controller():
    return _GenericClientShim()


def get_file_loader():
    return _GenericClientShim()


def get_download_controller():
    return _GenericClientShim()


def get_contacts_controller():
    return _GenericClientShim()


def get_location_controller():
    return _GenericClientShim()


def get_notification_center():
    return _NotificationCenterShim()


def run_on_ui_thread(fn, delay: float = 0.0) -> None:
    import android_utils

    android_utils.run_on_ui_thread(fn, delay=delay)


__all__ = list(globals().get("__all__", [])) + [
    "GLOBAL_QUEUE",
    "PLUGINS_QUEUE",
    "STAGE_QUEUE",
    "get_account_instance",
    "get_contacts_controller",
    "get_current_fragment",
    "get_download_controller",
    "get_file_loader",
    "get_last_fragment",
    "get_location_controller",
    "get_media_controller",
    "get_media_data_controller",
    "get_messages_storage",
    "get_notification_center",
    "run_on_ui_thread",
]
