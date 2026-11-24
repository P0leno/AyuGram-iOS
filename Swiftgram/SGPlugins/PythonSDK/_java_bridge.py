"""Smart Java-to-iOS class registry mapping popular Android/Telegram classes to iOS shims."""

from __future__ import annotations

import importlib.abc
import importlib.util
import json
import os
import sys
import threading
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


class FileLogBridge:
    _ayu_bridged = True

    @staticmethod
    def d(msg: Any) -> None:
        _ayu_runtime_host.log("info", _ayu_runtime_host.get_current_plugin_id() or "FileLog", str(msg))

    @staticmethod
    def i(msg: Any) -> None:
        FileLogBridge.d(msg)

    @staticmethod
    def w(msg: Any) -> None:
        _ayu_runtime_host.log("warn", _ayu_runtime_host.get_current_plugin_id() or "FileLog", str(msg))

    @staticmethod
    def e(msg: Any, exc: Any = None) -> None:
        text = f"{msg}: {exc}" if exc is not None else str(msg)
        _ayu_runtime_host.log("error", _ayu_runtime_host.get_current_plugin_id() or "FileLog", text)


class AndroidLogBridge:
    _ayu_bridged = True

    @staticmethod
    def d(tag: str, msg: Any) -> int:
        _ayu_runtime_host.log("info", str(tag), str(msg))
        return 0

    @staticmethod
    def i(tag: str, msg: Any) -> int:
        _ayu_runtime_host.log("info", str(tag), str(msg))
        return 0

    @staticmethod
    def w(tag: str, msg: Any) -> int:
        _ayu_runtime_host.log("warn", str(tag), str(msg))
        return 0

    @staticmethod
    def e(tag: str, msg: Any, exc: Any = None) -> int:
        text = f"{msg}: {exc}" if exc is not None else str(msg)
        _ayu_runtime_host.log("error", str(tag), text)
        return 0


class ColorBridge:
    _ayu_bridged = True
    BLACK = 0xFF000000
    DKGRAY = 0xFF444444
    GRAY = 0xFF888888
    LTGRAY = 0xFFCCCCCC
    WHITE = 0xFFFFFFFF
    RED = 0xFFFF0000
    GREEN = 0xFF00FF00
    BLUE = 0xFF0000FF
    YELLOW = 0xFFFFFF00
    CYAN = 0xFF00FFFF
    MAGENTA = 0xFFFF00FF
    TRANSPARENT = 0x00000000

    @staticmethod
    def argb(a: int, r: int, g: int, b: int) -> int:
        return ((int(a) & 0xFF) << 24) | ((int(r) & 0xFF) << 16) | ((int(g) & 0xFF) << 8) | (int(b) & 0xFF)

    @staticmethod
    def rgb(r: int, g: int, b: int) -> int:
        return ColorBridge.argb(255, r, g, b)

    @staticmethod
    def alpha(color: int) -> int:
        return (int(color) >> 24) & 0xFF

    @staticmethod
    def red(color: int) -> int:
        return (int(color) >> 16) & 0xFF

    @staticmethod
    def green(color: int) -> int:
        return (int(color) >> 8) & 0xFF

    @staticmethod
    def blue(color: int) -> int:
        return int(color) & 0xFF

    @staticmethod
    def parseColor(color_str: str) -> int:
        s = str(color_str or "").strip()
        if s.startswith("#"):
            raw = s[1:]
            if len(raw) == 6:
                return int("FF" + raw, 16)
            if len(raw) == 8:
                return int(raw, 16)
        return ColorBridge.WHITE


class LooperBridge:
    _ayu_bridged = True

    @staticmethod
    def getMainLooper() -> "LooperBridge":
        return LooperBridge()


class HandlerBridge:
    _ayu_bridged = True

    def __init__(self, _looper: Any = None) -> None:
        pass

    def post(self, fn: Any) -> bool:
        if callable(fn):
            fn()
        return True

    def postDelayed(self, fn: Any, delay_ms: int | float = 0) -> bool:
        if callable(fn):
            delay_s = max(0.0, float(delay_ms) / 1000.0)
            if delay_s > 0:
                t = threading.Timer(delay_s, fn)
                t.daemon = True
                t.start()
            else:
                fn()
        return True


class ChatObjectBridge:
    _ayu_bridged = True

    @staticmethod
    def isChannel(chat: Any) -> bool:
        if isinstance(chat, dict):
            return bool(chat.get("broadcast") or chat.get("is_channel") or int(chat.get("id", 0) or 0) < -1_000_000_000_000)
        return False

    @staticmethod
    def isMegagroup(chat: Any) -> bool:
        return bool(isinstance(chat, dict) and chat.get("megagroup"))

    @staticmethod
    def canSendMessages(_chat: Any) -> bool:
        return True


class UserObjectBridge:
    _ayu_bridged = True

    @staticmethod
    def getUserName(user: Any) -> str:
        if isinstance(user, dict):
            first = str(user.get("first_name", "") or "")
            last = str(user.get("last_name", "") or "")
            return (first + " " + last).strip() or str(user.get("username", "") or "")
        first = str(getattr(user, "first_name", "") or "")
        last = str(getattr(user, "last_name", "") or "")
        return (first + " " + last).strip() or str(getattr(user, "username", "") or "")

    @staticmethod
    def isUserSelf(user: Any) -> bool:
        uid = user.get("id") if isinstance(user, dict) else getattr(user, "id", None)
        return int(uid or -1) == int(_ayu_runtime_host.get_current_account().get("id", 0) or -2)


class SendMessageParamsBridge(_ayu_runtime_host.HookParams):
    _ayu_bridged = True

    @staticmethod
    def of(*args: Any, **kwargs: Any) -> _ayu_runtime_host.HookParams:
        payload = _ayu_runtime_host.HookParams(kwargs)
        if args and "message" not in payload:
            payload["message"] = str(args[0])
        if len(args) > 1 and "peer_id" not in payload:
            payload["peer_id"] = args[1]
        return payload


class JSONObjectBridge(dict):
    _ayu_bridged = True

    def __init__(self, source: Any = None) -> None:
        if isinstance(source, str):
            super().__init__(json.loads(source) if source.strip() else {})
        elif isinstance(source, dict):
            super().__init__(source)
        else:
            super().__init__()

    def getString(self, key: str) -> str:
        return str(self[key])

    def optString(self, key: str, default: str = "") -> str:
        return str(self.get(key, default))

    def getInt(self, key: str) -> int:
        return int(self[key])

    def optInt(self, key: str, default: int = 0) -> int:
        return int(self.get(key, default))

    def getBoolean(self, key: str) -> bool:
        return bool(self[key])

    def optBoolean(self, key: str, default: bool = False) -> bool:
        return bool(self.get(key, default))

    def put(self, key: str, val: Any) -> "JSONObjectBridge":
        self[key] = val
        return self

    def has(self, key: str) -> bool:
        return key in self

    def toString(self) -> str:
        return json.dumps(self)


class JSONArrayBridge(list):
    _ayu_bridged = True

    def __init__(self, source: Any = None) -> None:
        if isinstance(source, str):
            super().__init__(json.loads(source) if source.strip() else [])
        elif isinstance(source, (list, tuple)):
            super().__init__(source)
        else:
            super().__init__()

    def length(self) -> int:
        return len(self)

    def get(self, index: int) -> Any:
        return self[index]

    def put(self, val: Any) -> "JSONArrayBridge":
        self.append(val)
        return self

    def toString(self) -> str:
        return json.dumps(self)


class RunnableBridge:
    _ayu_bridged = True

    def __init__(self, fn: Any = None) -> None:
        self._fn = fn

    def run(self) -> None:
        if callable(self._fn):
            self._fn()


_BRIDGED_CLASSES: dict[str, Any] = {
    "org.telegram.messenger.UserConfig": UserConfigBridge,
    "org.telegram.messenger.MessagesController": MessagesControllerBridge,
    "org.telegram.messenger.SendMessagesHelper": SendMessagesHelperBridge,
    "org.telegram.messenger.SendMessagesHelper$SendMessageParams": SendMessageParamsBridge,
    "org.telegram.messenger.ConnectionsManager": ConnectionsManagerBridge,
    "org.telegram.messenger.NotificationCenter": NotificationCenterBridge,
    "org.telegram.messenger.LocaleController": LocaleControllerBridge,
    "org.telegram.messenger.ApplicationLoader": ApplicationLoaderBridge,
    "org.telegram.messenger.AndroidUtilities": AndroidUtilitiesBridge,
    "org.telegram.messenger.SharedConfig": SharedConfigBridge,
    "org.telegram.messenger.FileLog": FileLogBridge,
    "org.telegram.messenger.ChatObject": ChatObjectBridge,
    "org.telegram.messenger.UserObject": UserObjectBridge,
    "org.telegram.ui.Components.BulletinFactory": BulletinFactoryBridge,
    "org.telegram.ui.ActionBar.AlertDialog": AlertDialogBuilderBridge,
    "org.telegram.ui.ActionBar.AlertDialog$Builder": AlertDialogBuilderBridge,
    "org.telegram.ui.ActionBar.Theme": ThemeBridge,
    "org.telegram.ui.ActionBar.BaseFragment": LaunchActivityBridge,
    "org.telegram.ui.LaunchActivity": LaunchActivityBridge,
    "org.telegram.tgnet.TLRPC": _TLRPCNamespace,
    "org.json.JSONObject": JSONObjectBridge,
    "org.json.JSONArray": JSONArrayBridge,
    "android.widget.Toast": ToastBridge,
    "android.content.ClipboardManager": ClipboardManagerBridge,
    "android.content.ClipData": ClipDataBridge,
    "android.content.Intent": IntentBridge,
    "android.net.Uri": UriBridge,
    "android.os.Build": BuildBridge,
    "android.os.Build$VERSION": BuildVersionBridge,
    "android.os.Handler": HandlerBridge,
    "android.os.Looper": LooperBridge,
    "android.graphics.Color": ColorBridge,
    "android.util.Log": AndroidLogBridge,
    "java.lang.Runnable": RunnableBridge,
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


_JAVA_IMPORT_ROOTS = frozenset({
    "org",
    "android",
    "androidx",
    "com",
    "java",
    "javax",
    "kotlin",
    "kotlinx",
    "dalvik",
    "de",
})


class _JavaPackageModule:
    def __init__(self, fullname: str) -> None:
        self.__name__ = fullname
        self.__package__ = fullname
        self.__path__ = []
        self.__all__: list[str] = []

    def __getattr__(self, item: str) -> Any:
        if item.startswith("__"):
            raise AttributeError(item)
        full = f"{self.__name__}.{item}"
        resolved = resolve_bridged_class(full)
        if resolved is not None:
            return resolved
        # Also allow nested TL classes `from org.telegram.tgnet.TLRPC import TL_users_getFullUser`.
        dollar = f"{self.__name__}${item}"
        resolved_dollar = resolve_bridged_class(dollar)
        if resolved_dollar is not None:
            return resolved_dollar
        sub = _JavaPackageModule(full)
        sys.modules.setdefault(full, sub)
        return sub


class _JavaPackageLoader(importlib.abc.Loader):
    def create_module(self, spec):
        if spec.name in sys.modules:
            return sys.modules[spec.name]
        mod = _JavaPackageModule(spec.name)
        mod.__spec__ = spec
        return mod

    def exec_module(self, module) -> None:
        pass


class _JavaPackageFinder(importlib.abc.MetaPathFinder):
    _loader = _JavaPackageLoader()

    def find_spec(self, fullname: str, path=None, target=None):
        root = fullname.split(".", 1)[0]
        if root not in _JAVA_IMPORT_ROOTS:
            return None
        if fullname == "java" or fullname.startswith("java."):
            # Let our real `PythonSDK/java/__init__.py` package handle `from java import jclass`.
            if fullname == "java":
                return None
        return importlib.util.spec_from_loader(fullname, self._loader, is_package=True)


_FINDER_INSTALLED = False


def install_java_import_hook() -> None:
    global _FINDER_INSTALLED
    if _FINDER_INSTALLED:
        return
    _FINDER_INSTALLED = True
    sys.meta_path.append(_JavaPackageFinder())

