"""Smart Java-to-iOS class registry mapping popular Android/Telegram classes to iOS shims."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import _ayu_runtime_host


class _SharedPreferencesEditor:
    def __init__(self, prefs: "_SharedPreferencesShim") -> None:
        self._prefs = prefs
        self._updates: dict[str, Any] = {}
        self._removals: set[str] = set()
        self._clear = False

    def putString(self, key: str, value: str | None) -> "_SharedPreferencesEditor":
        self._updates[str(key)] = value
        self._removals.discard(str(key))
        return self

    def putInt(self, key: str, value: int) -> "_SharedPreferencesEditor":
        self._updates[str(key)] = int(value)
        return self

    def putLong(self, key: str, value: int) -> "_SharedPreferencesEditor":
        self._updates[str(key)] = int(value)
        return self

    def putFloat(self, key: str, value: float) -> "_SharedPreferencesEditor":
        self._updates[str(key)] = float(value)
        return self

    def putBoolean(self, key: str, value: bool) -> "_SharedPreferencesEditor":
        self._updates[str(key)] = bool(value)
        return self

    def remove(self, key: str) -> "_SharedPreferencesEditor":
        k = str(key)
        self._updates.pop(k, None)
        self._removals.add(k)
        return self

    def clear(self) -> "_SharedPreferencesEditor":
        self._updates.clear()
        self._removals.clear()
        self._clear = True
        return self

    def commit(self) -> bool:
        self.apply()
        return True

    def apply(self) -> None:
        self._prefs._commit(self._updates, self._removals, self._clear)


class _SharedPreferencesShim:
    _ayu_bridged = True

    def __init__(self, plugin_id: str, name: str) -> None:
        self._plugin_id = plugin_id or "shared_prefs"
        self._storage_key = f"__android_prefs_{name}"

    def _load(self) -> dict[str, Any]:
        raw = _ayu_runtime_host.get_setting(self._plugin_id, self._storage_key, {})
        return dict(raw) if isinstance(raw, dict) else {}

    def _commit(self, updates: dict[str, Any], removals: set[str], clear: bool) -> None:
        data = {} if clear else self._load()
        for key in removals:
            data.pop(key, None)
        data.update(updates)
        _ayu_runtime_host.set_setting(self._plugin_id, self._storage_key, data)

    def edit(self) -> _SharedPreferencesEditor:
        return _SharedPreferencesEditor(self)

    def contains(self, key: str) -> bool:
        return str(key) in self._load()

    def getAll(self) -> dict[str, Any]:
        return self._load()

    def getString(self, key: str, default: str | None = None) -> str | None:
        val = self._load().get(str(key), default)
        return None if val is None else str(val)

    def getInt(self, key: str, default: int = 0) -> int:
        try:
            return int(self._load().get(str(key), default))
        except Exception:
            return int(default)

    def getLong(self, key: str, default: int = 0) -> int:
        return self.getInt(key, default)

    def getFloat(self, key: str, default: float = 0.0) -> float:
        try:
            return float(self._load().get(str(key), default))
        except Exception:
            return float(default)

    def getBoolean(self, key: str, default: bool = False) -> bool:
        return bool(self._load().get(str(key), default))


class _JavaFileShim:
    _ayu_bridged = True

    def __init__(self, path: str | Path, child: str | None = None) -> None:
        p = Path(str(path))
        if child is not None:
            p = p / str(child)
        self._path = p

    def getAbsolutePath(self) -> str:
        return str(self._path.resolve())

    def getPath(self) -> str:
        return str(self._path)

    def getName(self) -> str:
        return self._path.name

    def exists(self) -> bool:
        return self._path.exists()

    def mkdirs(self) -> bool:
        self._path.mkdir(parents=True, exist_ok=True)
        return True

    def mkdir(self) -> bool:
        return self.mkdirs()

    def isDirectory(self) -> bool:
        return self._path.is_dir()

    def isFile(self) -> bool:
        return self._path.is_file()

    def length(self) -> int:
        return self._path.stat().st_size if self._path.is_file() else 0

    def delete(self) -> bool:
        try:
            if self._path.is_file():
                self._path.unlink()
                return True
        except Exception:
            pass
        return False

    def __str__(self) -> str:
        return str(self._path)


class _AndroidContextShim:
    _ayu_bridged = True

    def getSharedPreferences(self, name: str = "mainconfig", _mode: int = 0) -> _SharedPreferencesShim:
        pid = _ayu_runtime_host.get_current_plugin_id() or "android_compat"
        return _SharedPreferencesShim(pid, name)

    def getFilesDir(self) -> _JavaFileShim:
        return _JavaFileShim(_ayu_runtime_host.get_plugin_data_dir())

    def getCacheDir(self) -> _JavaFileShim:
        return _JavaFileShim(Path(_ayu_runtime_host.get_plugin_data_dir()) / "cache")

    def getPackageName(self) -> str:
        return "org.telegram.messenger"

    def getSystemService(self, service: str) -> Any:
        if "clipboard" in str(service).lower():
            return ClipboardManagerBridge()
        return None


class ApplicationLoaderBridge:
    _ayu_bridged = True
    applicationContext = _AndroidContextShim()

    @staticmethod
    def getFilesDirFixed() -> _JavaFileShim:
        return _AndroidContextShim().getFilesDir()


class UserConfigBridge:
    _ayu_bridged = True
    selectedAccount = 0

    @staticmethod
    def getInstance(account: int = 0):
        import client_utils

        return client_utils.get_user_config(account)


class MessagesControllerBridge:
    _ayu_bridged = True

    @staticmethod
    def getInstance(account: int = 0):
        import client_utils

        return client_utils.get_messages_controller(account)


class SendMessagesHelperBridge:
    _ayu_bridged = True

    @staticmethod
    def getInstance(account: int = 0):
        import client_utils

        return client_utils.get_send_messages_helper(account)


class ConnectionsManagerBridge:
    _ayu_bridged = True

    @staticmethod
    def getInstance(account: int = 0):
        import client_utils

        return client_utils.get_connections_manager(account)


class NotificationCenterBridge:
    _ayu_bridged = True

    @staticmethod
    def getInstance(_account: int = 0):
        import client_utils

        return client_utils.get_notification_center()

    @staticmethod
    def getGlobalInstance():
        import client_utils

        return client_utils.get_notification_center()


class LocaleControllerBridge:
    _ayu_bridged = True
    isRTL = False

    @staticmethod
    def getInstance() -> type["LocaleControllerBridge"]:
        return LocaleControllerBridge

    @staticmethod
    def getString(key: Any, res_id: Any = None) -> str:
        if isinstance(res_id, str) and res_id:
            return res_id
        return str(key)

    @staticmethod
    def getLocaleString(_res_id: Any) -> str:
        return ""

    @staticmethod
    def formatString(key: str, *args: Any) -> str:
        if args:
            return f"{key} " + " ".join(str(a) for a in args)
        return str(key)


class _DisplayPoint:
    _ayu_bridged = True

    def __init__(self, x: int = 390, y: int = 844) -> None:
        self.x = x
        self.y = y


class AndroidUtilitiesBridge:
    _ayu_bridged = True
    density = 3.0
    statusBarHeight = 47
    navigationBarHeight = 44
    displaySize = _DisplayPoint(390, 844)

    @staticmethod
    def runOnUIThread(fn: Any, delay: int | float = 0) -> None:
        import android_utils

        seconds = float(delay) / 1000.0 if isinstance(delay, (int, float)) and delay > 10 else float(delay or 0)
        android_utils.run_on_ui_thread(fn, delay=seconds)

    @staticmethod
    def addToClipboard(text: Any) -> bool:
        return _ayu_runtime_host.copy_to_clipboard(str(text or ""))

    @staticmethod
    def copyToClipboard(text: Any) -> bool:
        return AndroidUtilitiesBridge.addToClipboard(text)

    @staticmethod
    def showToast(message: Any) -> None:
        _ayu_runtime_host.show_bulletin("", str(message or ""), "info")

    @staticmethod
    def dp(value: float) -> int:
        return int(round(float(value) * 3.0))

    @staticmethod
    def dpf2(value: float) -> float:
        return float(value) * 3.0

    @staticmethod
    def openUrl(_context: Any, url: str) -> bool:
        return _ayu_runtime_host.open_url(str(url or ""))


class _BulletinHandle:
    _ayu_bridged = True

    def __init__(self, message: str, icon: str = "info") -> None:
        self._message = message
        self._icon = icon

    def show(self) -> "_BulletinHandle":
        _ayu_runtime_host.show_bulletin("", self._message, self._icon)
        return self


class _BulletinFactoryInstance:
    _ayu_bridged = True

    def createSimpleBulletin(self, _icon: Any, title: str, subtitle: str = "") -> _BulletinHandle:
        text = f"{title}: {subtitle}" if subtitle else str(title)
        return _BulletinHandle(text, "info")

    def createSuccessBulletin(self, message: str) -> _BulletinHandle:
        return _BulletinHandle(str(message), "success")

    def createErrorBulletin(self, message: str) -> _BulletinHandle:
        return _BulletinHandle(str(message), "error")

    def createCopyBulletin(self, message: str = "Copied to clipboard") -> _BulletinHandle:
        return _BulletinHandle(str(message), "success")

    def createCopyLinkBulletin(self, message: str = "Link copied") -> _BulletinHandle:
        return _BulletinHandle(str(message), "success")


class BulletinFactoryBridge:
    _ayu_bridged = True

    @staticmethod
    def of(*_args: Any, **_kwargs: Any) -> _BulletinFactoryInstance:
        return _BulletinFactoryInstance()

    @staticmethod
    def global_() -> _BulletinFactoryInstance:
        return _BulletinFactoryInstance()


setattr(BulletinFactoryBridge, "global", staticmethod(BulletinFactoryBridge.global_))


class AlertDialogBuilderBridge:
    _ayu_bridged = True

    def __init__(self, context: Any = None) -> None:
        from ui.alert import AlertDialogBuilder

        self._inner = AlertDialogBuilder(context)

    def setTitle(self, title: Any) -> "AlertDialogBuilderBridge":
        self._inner.set_title(str(title))
        return self

    def setMessage(self, message: Any) -> "AlertDialogBuilderBridge":
        self._inner.set_message(str(message))
        return self

    def setPositiveButton(self, text: Any, listener: Any = None) -> "AlertDialogBuilderBridge":
        self._inner.set_positive_button(str(text), listener)
        return self

    def setNegativeButton(self, text: Any, listener: Any = None) -> "AlertDialogBuilderBridge":
        self._inner.set_negative_button(str(text), listener)
        return self

    def setNeutralButton(self, text: Any, listener: Any = None) -> "AlertDialogBuilderBridge":
        self._inner.set_neutral_button(str(text), listener)
        return self

    def create(self) -> "AlertDialogBuilderBridge":
        return self

    def show(self) -> "AlertDialogBuilderBridge":
        self._inner.show()
        return self


class ToastBridge:
    _ayu_bridged = True
    LENGTH_SHORT = 0
    LENGTH_LONG = 1

    def __init__(self, text: str) -> None:
        self._text = text

    @staticmethod
    def makeText(_context: Any, text: Any, _duration: int = 0) -> "ToastBridge":
        return ToastBridge(str(text or ""))

    def show(self) -> None:
        _ayu_runtime_host.show_bulletin("", self._text, "info")


class ClipDataBridge:
    _ayu_bridged = True

    def __init__(self, text: str) -> None:
        self.text = text

    @staticmethod
    def newPlainText(_label: Any, text: Any) -> "ClipDataBridge":
        return ClipDataBridge(str(text or ""))


class ClipboardManagerBridge:
    _ayu_bridged = True

    def setPrimaryClip(self, clip: Any) -> None:
        text = getattr(clip, "text", str(clip or ""))
        _ayu_runtime_host.copy_to_clipboard(str(text))

    def setText(self, text: Any) -> None:
        _ayu_runtime_host.copy_to_clipboard(str(text or ""))


class UriBridge:
    _ayu_bridged = True

    @staticmethod
    def parse(url: str) -> str:
        return str(url or "")


class IntentBridge:
    _ayu_bridged = True
    ACTION_VIEW = "android.intent.action.VIEW"

    def __init__(self, action: str = "", uri: Any = None) -> None:
        self.action = action
        self.data = str(uri) if uri is not None else ""

    def setData(self, uri: Any) -> "IntentBridge":
        self.data = str(uri or "")
        return self

    def addFlags(self, _flags: int) -> "IntentBridge":
        return self


class LaunchActivityBridge:
    _ayu_bridged = True

    @staticmethod
    def getLastFragment():
        import client_utils

        return client_utils.get_last_fragment()


class SharedConfigBridge:
    _ayu_bridged = True
    bubbleRadius = 16
    fontSize = 16
    distanceSystemType = 0


class ThemeBridge:
    _ayu_bridged = True

    @staticmethod
    def getColor(_key: Any) -> int:
        return 0xFF2AABEE


class BuildVersionBridge:
    _ayu_bridged = True
    SDK_INT = 34
    RELEASE = "14"


class BuildBridge:
    _ayu_bridged = True
    MODEL = "iPhone"
    MANUFACTURER = "Apple"
    BRAND = "Apple"
    VERSION = BuildVersionBridge


class _StringBuilderShim:
    _ayu_bridged = True

    def __init__(self, initial: str = "") -> None:
        self._buf = [str(initial)]

    def append(self, value: Any) -> "_StringBuilderShim":
        self._buf.append(str(value))
        return self

    def toString(self) -> str:
        return "".join(self._buf)

    def __str__(self) -> str:
        return self.toString()


class _ArrayListShim(list):
    _ayu_bridged = True

    def add(self, item: Any) -> bool:
        self.append(item)
        return True

    def size(self) -> int:
        return len(self)

    def get(self, index: int) -> Any:
        return self[index]


class _HashMapShim(dict):
    _ayu_bridged = True

    def put(self, key: Any, value: Any) -> Any:
        old = super().get(key)
        self[key] = value
        return old

    def get(self, key: Any, default: Any = None) -> Any:
        return super().get(key, default)

    def containsKey(self, key: Any) -> bool:
        return key in self

    def size(self) -> int:
        return len(self)


def _make_tl_class(tl_name: str):
    short_name = tl_name.rsplit("$", 1)[-1]
    method_guess = short_name
    if method_guess.startswith("TL_"):
        method_guess = method_guess[3:].replace("_", ".", 1)

    class _DynamicTLObject(_ayu_runtime_host.HookParams):
        _ayu_bridged = True
        CONSTRUCTOR_NAME = method_guess
        METHOD_NAME = method_guess

    _DynamicTLObject.__name__ = short_name
    return _DynamicTLObject


class _TLRPCNamespace:
    _ayu_bridged = True

    def __getattr__(self, name: str):
        return _make_tl_class(f"org.telegram.tgnet.TLRPC${name}")


_BRIDGED_CLASSES: dict[str, Any] = {
    "org.telegram.messenger.UserConfig": UserConfigBridge,
    "org.telegram.messenger.MessagesController": MessagesControllerBridge,
    "org.telegram.messenger.SendMessagesHelper": SendMessagesHelperBridge,
    "org.telegram.messenger.ConnectionsManager": ConnectionsManagerBridge,
    "org.telegram.messenger.NotificationCenter": NotificationCenterBridge,
    "org.telegram.messenger.LocaleController": LocaleControllerBridge,
    "org.telegram.messenger.ApplicationLoader": ApplicationLoaderBridge,
    "org.telegram.messenger.AndroidUtilities": AndroidUtilitiesBridge,
    "org.telegram.messenger.SharedConfig": SharedConfigBridge,
    "org.telegram.ui.Components.BulletinFactory": BulletinFactoryBridge,
    "org.telegram.ui.ActionBar.AlertDialog": AlertDialogBuilderBridge,
    "org.telegram.ui.ActionBar.AlertDialog$Builder": AlertDialogBuilderBridge,
    "org.telegram.ui.ActionBar.Theme": ThemeBridge,
    "org.telegram.ui.LaunchActivity": LaunchActivityBridge,
    "org.telegram.tgnet.TLRPC": _TLRPCNamespace,
    "android.widget.Toast": ToastBridge,
    "android.content.ClipboardManager": ClipboardManagerBridge,
    "android.content.ClipData": ClipDataBridge,
    "android.content.Intent": IntentBridge,
    "android.net.Uri": UriBridge,
    "android.os.Build": BuildBridge,
    "android.os.Build$VERSION": BuildVersionBridge,
    "java.lang.String": str,
    "java.lang.Integer": int,
    "java.lang.Long": int,
    "java.lang.Float": float,
    "java.lang.Double": float,
    "java.lang.Boolean": bool,
    "java.lang.StringBuilder": _StringBuilderShim,
    "java.util.ArrayList": _ArrayListShim,
    "java.util.HashMap": _HashMapShim,
    "java.io.File": _JavaFileShim,
}


def resolve_bridged_class(class_name: str) -> Any | None:
    """Return a native iOS-backed Python proxy for known Android/Telegram Java classes, else None."""
    name = str(class_name or "").strip()
    if name in _BRIDGED_CLASSES:
        return _BRIDGED_CLASSES[name]
    if name.startswith("org.telegram.tgnet.TLRPC$"):
        return _make_tl_class(name)
    return None
