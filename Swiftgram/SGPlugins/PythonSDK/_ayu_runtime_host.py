"""Internal runtime host bridging embedded CPython, `_ayu_native` C module, and exteraCompat SDK."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import sys
import threading
import traceback
from pathlib import Path
from typing import Any, Callable


class HookParams(dict):
    """Dictionary with attribute access so plugins can use either `params.message` or `params['message']`."""

    def __getattr__(self, name: str) -> Any:
        try:
            return self[name]
        except KeyError:
            return None

    def __setattr__(self, name: str, value: Any) -> None:
        self[name] = value

    def __delattr__(self, name: str) -> None:
        self.pop(name, None)

    def to_serializable(self) -> dict[str, Any]:
        return _serialize_value(dict(self))


def _serialize_value(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if hasattr(value, "to_dict") and callable(value.to_dict):
        return _serialize_value(value.to_dict())
    if isinstance(value, dict):
        return {str(k): _serialize_value(v) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_serialize_value(v) for v in value]
    if hasattr(value, "__dict__"):
        return {
            str(k): _serialize_value(v)
            for k, v in vars(value).items()
            if not str(k).startswith("_")
        }
    return str(value)


class _DefaultFallbackNativeBackend:
    """In-memory backend used automatically during headless Python tests when `_ayu_native` C module is absent."""

    def __init__(self) -> None:
        self.logs: list[tuple[str, str, str]] = []
        self.settings: dict[tuple[str, str], str] = {}
        self.bulletins: list[tuple[str, str, str]] = []
        self.alerts: list[tuple[str, str, str]] = []
        self.sent_messages: list[dict[str, Any]] = []
        self.requests: list[tuple[str, dict[str, Any]]] = []
        self.account: dict[str, Any] = {
            "id": 0,
            "first_name": "AyuGram",
            "last_name": "",
            "username": "",
            "phone": "",
            "is_premium": False,
        }

    def log(self, level: str, plugin_id: str, message: str) -> None:
        self.logs.append((level, plugin_id, message))

    def get_setting(self, plugin_id: str, key: str, default_json: str) -> str:
        return self.settings.get((plugin_id, key), default_json)

    def set_setting(self, plugin_id: str, key: str, value_json: str) -> None:
        self.settings[(plugin_id, key)] = value_json

    def show_bulletin(self, title: str, subtitle: str, icon: str) -> None:
        self.bulletins.append((title, subtitle, icon))

    def show_alert(self, title: str, message: str, buttons_json: str) -> None:
        self.alerts.append((title, message, buttons_json))

    def send_message(self, params_json: str) -> str:
        payload = json.loads(params_json)
        self.sent_messages.append(payload)
        return json.dumps({"ok": True, "message_id": len(self.sent_messages)})

    def execute_request(self, method: str, params_json: str) -> str:
        payload = json.loads(params_json) if params_json else {}
        self.requests.append((method, payload))
        return json.dumps({"ok": True, "method": method, "result": {}})

    def get_current_account_json(self) -> str:
        return json.dumps(self.account)


def _detect_native_backend():
    try:
        import _ayu_native  # type: ignore

        return _ayu_native
    except ImportError:
        return _DefaultFallbackNativeBackend()


_LOCK = threading.RLock()
_NATIVE_BACKEND: Any = _detect_native_backend()
_PLUGINS: dict[str, dict[str, Any]] = {}
_ACTION_CALLBACKS: dict[str, dict[str, Callable[..., Any]]] = {}
_ALERT_CALLBACKS: dict[str, Callable[..., Any]] = {}
_LOADING_DIAGNOSTICS: dict[str, list[str]] = {}
_CURRENT_LOADING_ID: str | None = None


def set_native_backend(backend: Any | None) -> Any:
    """Replace active native backend (used by tests to inspect bridged native calls)."""
    global _NATIVE_BACKEND
    with _LOCK:
        _NATIVE_BACKEND = backend if backend is not None else _detect_native_backend()
        return _NATIVE_BACKEND


def reset_host_state() -> None:
    """Unload all active plugins and clear host runtime state cleanly."""
    with _LOCK:
        for pid in list(_PLUGINS.keys()):
            try:
                unload_plugin(pid)
            except Exception:
                pass
        _PLUGINS.clear()
        _ACTION_CALLBACKS.clear()
        _ALERT_CALLBACKS.clear()
        _LOADING_DIAGNOSTICS.clear()


def log(level: str, plugin_id: str, message: str) -> None:
    try:
        _NATIVE_BACKEND.log(str(level), str(plugin_id), str(message))
    except Exception:
        pass


def get_setting(plugin_id: str, key: str, default: Any = None) -> Any:
    default_json = json.dumps(_serialize_value(default))
    try:
        raw = _NATIVE_BACKEND.get_setting(str(plugin_id), str(key), default_json)
        return json.loads(raw) if raw else default
    except Exception:
        return default


def set_setting(plugin_id: str, key: str, value: Any) -> None:
    encoded = json.dumps(_serialize_value(value))
    _NATIVE_BACKEND.set_setting(str(plugin_id), str(key), encoded)


def show_bulletin(title: str, subtitle: str, icon: str = "info") -> None:
    _NATIVE_BACKEND.show_bulletin(str(title or ""), str(subtitle or ""), str(icon or "info"))


def show_alert(title: str, message: str, buttons: list[dict[str, Any]]) -> None:
    encoded_buttons = []
    for idx, btn in enumerate(buttons):
        cb_id = ""
        cb = btn.get("callback")
        if callable(cb):
            cb_id = f"alert_{idx}_{id(cb)}"
            with _LOCK:
                _ALERT_CALLBACKS[cb_id] = cb
        encoded_buttons.append({
            "id": cb_id,
            "style": str(btn.get("style", "default")),
            "text": str(btn.get("text", "OK")),
        })
    _NATIVE_BACKEND.show_alert(str(title or ""), str(message or ""), json.dumps(encoded_buttons))


def trigger_alert_callback(callback_id: str) -> bool:
    with _LOCK:
        cb = _ALERT_CALLBACKS.pop(callback_id, None)
    if cb is None:
        return False
    try:
        cb()
    except TypeError:
        cb(None, 0)
    return True


def send_message(params: dict[str, Any]) -> dict[str, Any]:
    raw = _NATIVE_BACKEND.send_message(json.dumps(_serialize_value(params)))
    return json.loads(raw) if raw else {"ok": True}


def execute_request(method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    raw = _NATIVE_BACKEND.execute_request(str(method), json.dumps(_serialize_value(params or {})))
    return json.loads(raw) if raw else {"ok": False, "error": "empty response"}


def get_current_account() -> dict[str, Any]:
    try:
        raw = _NATIVE_BACKEND.get_current_account_json()
        return json.loads(raw) if raw else {}
    except Exception:
        return {}


def record_current_incompatibility(message: str) -> None:
    with _LOCK:
        target = _CURRENT_LOADING_ID
        if target:
            _LOADING_DIAGNOSTICS.setdefault(target, []).append(message)


def _find_plugin_class(module: Any, base_cls: type) -> type | None:
    candidates = []
    for attr_name in dir(module):
        obj = getattr(module, attr_name)
        if isinstance(obj, type) and issubclass(obj, base_cls) and obj is not base_cls:
            if obj.__module__ == module.__name__:
                candidates.append(obj)
            elif not candidates:
                candidates.append(obj)
    return candidates[0] if candidates else None


def _extract_plugin_metadata(module: Any, plugin_instance: Any, fallback_id: str) -> dict[str, str]:
    def pick(attr: str, default: str = "") -> str:
        val = getattr(module, attr, None)
        if not val:
            val = getattr(plugin_instance, attr, None)
        return str(val).strip() if val else default

    pid = pick("__id__", fallback_id)
    return {
        "id": pid,
        "name": pick("__name__", pid),
        "description": pick("__description__", ""),
        "author": pick("__author__", "Unknown"),
        "version": pick("__version__", "1.0"),
        "min_version": pick("__min_version__", ""),
        "icon": pick("__icon__", ""),
    }


def load_plugin(plugin_id: str, file_path: str, module_name: str | None = None) -> dict[str, Any]:
    """Import and initialize a Python `.plugin` script, isolating incompatibility/runtime failures."""
    global _CURRENT_LOADING_ID
    import base_plugin
    from java import JavaNotSupportedError

    mod_name = module_name or f"ayu_plugin_{plugin_id}"
    path_obj = Path(file_path)

    with _LOCK:
        if plugin_id in _PLUGINS:
            unload_plugin(plugin_id)
        _LOADING_DIAGNOSTICS[plugin_id] = []
        _CURRENT_LOADING_ID = plugin_id

    try:
        # `.plugin` files lack a `.py` extension, so bind SourceFileLoader explicitly.
        loader = importlib.machinery.SourceFileLoader(mod_name, str(path_obj))
        spec = importlib.util.spec_from_loader(mod_name, loader, origin=str(path_obj))
        if spec is None or spec.loader is None:
            raise ImportError(f"Cannot create module spec for {path_obj}")
        module = importlib.util.module_from_spec(spec)
        module.__file__ = str(path_obj)
        sys.modules[mod_name] = module
        spec.loader.exec_module(module)

        plugin_cls = _find_plugin_class(module, base_plugin.BasePlugin)
        if plugin_cls is None:
            raise ValueError(
                "No BasePlugin subclass found. Expected a class inheriting from `base_plugin.BasePlugin`."
            )

        instance = plugin_cls()
        meta = _extract_plugin_metadata(module, instance, plugin_id)
        instance._ayu_bind_runtime(plugin_id=plugin_id, metadata=meta)

        instance.on_plugin_load()

        with _LOCK:
            warnings = list(_LOADING_DIAGNOSTICS.get(plugin_id, []))
            entry = {
                "id": plugin_id,
                "module_name": mod_name,
                "file_path": str(path_obj),
                "instance": instance,
                "metadata": meta,
                "warnings": warnings,
                "incompatible": False,
                "error": "",
            }
            _PLUGINS[plugin_id] = entry

        log("info", plugin_id, f"Loaded plugin `{meta['name']}` v{meta['version']}")
        return {
            "ok": True,
            "incompatible": False,
            "error": "",
            "warnings": warnings,
            "metadata": meta,
            "has_settings": _safe_has_settings(instance),
        }

    except JavaNotSupportedError as exc:
        err_msg = str(exc)
        with _LOCK:
            warnings = list(_LOADING_DIAGNOSTICS.get(plugin_id, []))
        sys.modules.pop(mod_name, None)
        log("error", plugin_id, err_msg)
        return {
            "ok": False,
            "incompatible": True,
            "error": err_msg,
            "warnings": warnings,
            "metadata": {"id": plugin_id, "name": plugin_id},
            "has_settings": False,
        }
    except Exception as exc:
        tb = traceback.format_exc()
        err_msg = f"{type(exc).__name__}: {exc}"
        with _LOCK:
            warnings = list(_LOADING_DIAGNOSTICS.get(plugin_id, []))
        sys.modules.pop(mod_name, None)
        log("error", plugin_id, f"{err_msg}\n{tb}")
        return {
            "ok": False,
            "incompatible": False,
            "error": err_msg,
            "warnings": warnings,
            "traceback": tb,
            "metadata": {"id": plugin_id, "name": plugin_id},
            "has_settings": False,
        }
    finally:
        with _LOCK:
            _CURRENT_LOADING_ID = None


def _safe_has_settings(instance: Any) -> bool:
    try:
        items = instance.create_settings()
        return bool(items)
    except Exception:
        return False


def unload_plugin(plugin_id: str) -> dict[str, Any]:
    """Call `on_plugin_unload` and tear down module/callback references for `plugin_id`."""
    with _LOCK:
        entry = _PLUGINS.pop(plugin_id, None)
        _ACTION_CALLBACKS.pop(plugin_id, None)
    if entry is None:
        return {"ok": True, "was_loaded": False}

    error_msg = ""
    try:
        entry["instance"].on_plugin_unload()
    except Exception as exc:
        error_msg = f"{type(exc).__name__}: {exc}"
        log("error", plugin_id, f"Unload error: {error_msg}")

    sys.modules.pop(entry["module_name"], None)
    log("info", plugin_id, "Unloaded plugin")
    return {"ok": error_msg == "", "was_loaded": True, "error": error_msg}


def _iter_active_entries() -> list[dict[str, Any]]:
    with _LOCK:
        return list(_PLUGINS.values())


def dispatch_send_message_hook(account: int, params_dict: dict[str, Any]) -> dict[str, Any]:
    """Execute registered `on_send_message_hook` callbacks in priority order."""
    import base_plugin

    current_params = HookParams(params_dict)
    modified = False

    entries = [
        e for e in _iter_active_entries() if e["instance"]._ayu_send_hook_active
    ]
    entries.sort(key=lambda e: (-e["instance"]._ayu_send_hook_priority, e["id"]))

    for entry in entries:
        plugin_id = entry["id"]
        instance = entry["instance"]
        try:
            result = instance.on_send_message_hook(account, current_params)
        except Exception as exc:
            log("error", plugin_id, f"on_send_message_hook failed: {exc}\n{traceback.format_exc()}")
            continue

        if not isinstance(result, base_plugin.HookResult):
            continue

        strategy = result.strategy
        if strategy == base_plugin.HookStrategy.CANCEL:
            return {"action": "cancel", "plugin_id": plugin_id, "params": current_params.to_serializable()}
        if strategy in (base_plugin.HookStrategy.MODIFY, base_plugin.HookStrategy.MODIFY_FINAL):
            modified = True
            if isinstance(result.params, dict):
                current_params = HookParams(result.params)
            if strategy == base_plugin.HookStrategy.MODIFY_FINAL:
                return {"action": "modify", "plugin_id": plugin_id, "params": current_params.to_serializable()}

    return {
        "action": "modify" if modified else "default",
        "params": current_params.to_serializable(),
    }


def dispatch_update_hook(update_name: str, account: int, update_payload: dict[str, Any]) -> dict[str, Any]:
    """Deliver incoming update/message payload to plugins subscribed to update/receive hooks."""
    import base_plugin

    current = HookParams(update_payload)
    for entry in _iter_active_entries():
        instance = entry["instance"]
        if not instance._ayu_wants_update(update_name):
            continue
        try:
            res = instance.on_update_hook(update_name, account, current)
            if isinstance(res, base_plugin.HookResult):
                if res.strategy == base_plugin.HookStrategy.CANCEL:
                    return {"action": "cancel", "update": current.to_serializable()}
                if res.strategy in (base_plugin.HookStrategy.MODIFY, base_plugin.HookStrategy.MODIFY_FINAL):
                    if isinstance(res.update, dict):
                        current = HookParams(res.update)
                    elif isinstance(res.params, dict):
                        current = HookParams(res.params)
                    if res.strategy == base_plugin.HookStrategy.MODIFY_FINAL:
                        return {"action": "modify", "update": current.to_serializable()}
        except Exception as exc:
            log("error", entry["id"], f"on_update_hook failed: {exc}\n{traceback.format_exc()}")
    return {"action": "default", "update": current.to_serializable()}


def export_settings_schema(plugin_id: str) -> list[dict[str, Any]]:
    """Serialize `create_settings()` into JSON schemas and retain key/click callbacks."""
    with _LOCK:
        entry = _PLUGINS.get(plugin_id)
    if entry is None:
        return []

    instance = entry["instance"]
    try:
        items = instance.create_settings() or []
    except Exception as exc:
        log("error", plugin_id, f"create_settings() failed: {exc}")
        return [{"type": "divider", "text": f"Failed to build settings: {exc}"}]

    callbacks: dict[str, Callable[..., Any]] = {}
    exported: list[dict[str, Any]] = []
    for index, item in enumerate(items):
        if hasattr(item, "to_dict"):
            row = item.to_dict()
        elif isinstance(item, dict):
            row = dict(item)
        else:
            continue

        key = row.get("key")
        if key and hasattr(item, "on_change") and callable(getattr(item, "on_change")):
            callbacks[f"change:{key}"] = item.on_change

        if row.get("type") == "text" and hasattr(item, "on_click") and callable(getattr(item, "on_click")):
            action_id = f"action_{index}"
            row["action_id"] = action_id
            callbacks[f"click:{action_id}"] = item.on_click

        if key:
            row["value"] = instance.get_setting(key, row.get("default"))

        exported.append(row)

    with _LOCK:
        _ACTION_CALLBACKS[plugin_id] = callbacks
    return exported


def apply_setting_change(plugin_id: str, key: str, value: Any) -> dict[str, Any]:
    """Persist setting update and invoke both per-item `on_change` and `on_setting_changed`."""
    with _LOCK:
        entry = _PLUGINS.get(plugin_id)
        cb = _ACTION_CALLBACKS.get(plugin_id, {}).get(f"change:{key}")
    set_setting(plugin_id, key, value)

    if entry is None:
        return {"ok": True}

    instance = entry["instance"]
    try:
        if cb is not None:
            cb(value)
        if hasattr(instance, "on_setting_changed"):
            instance.on_setting_changed(key, value)
        return {"ok": True}
    except Exception as exc:
        log("error", plugin_id, f"Setting callback `{key}` failed: {exc}")
        return {"ok": False, "error": str(exc)}


def trigger_setting_action(plugin_id: str, action_id: str) -> dict[str, Any]:
    """Invoke registered button `on_click` callback from plugin settings screen."""
    with _LOCK:
        cb = _ACTION_CALLBACKS.get(plugin_id, {}).get(f"click:{action_id}")
    if cb is None:
        return {"ok": False, "error": f"Unknown action_id: {action_id}"}
    try:
        try:
            cb(None)
        except TypeError:
            cb()
        return {"ok": True}
    except Exception as exc:
        log("error", plugin_id, f"Settings action `{action_id}` failed: {exc}")
        return {"ok": False, "error": str(exc)}


def list_loaded_plugins() -> list[dict[str, Any]]:
    with _LOCK:
        return [
            {
                "id": entry["id"],
                "metadata": entry["metadata"],
                "warnings": entry["warnings"],
            }
            for entry in _PLUGINS.values()
        ]


def dispatch_json(command: str, payload_json: str) -> str:
    """Single JSON-in/JSON-out entrypoint invoked from C/ObjC bridge."""
    try:
        payload = json.loads(payload_json) if payload_json else {}
        if command == "load_plugin":
            res = load_plugin(
                plugin_id=payload["plugin_id"],
                file_path=payload["file_path"],
                module_name=payload.get("module_name"),
            )
        elif command == "unload_plugin":
            res = unload_plugin(payload["plugin_id"])
        elif command == "dispatch_send_message_hook":
            res = dispatch_send_message_hook(
                int(payload.get("account", 0)),
                dict(payload.get("params", {})),
            )
        elif command == "dispatch_update_hook":
            res = dispatch_update_hook(
                str(payload.get("update_name", "receive_message")),
                int(payload.get("account", 0)),
                dict(payload.get("update", {})),
            )
        elif command == "export_settings_schema":
            res = {"ok": True, "items": export_settings_schema(payload["plugin_id"])}
        elif command == "apply_setting_change":
            res = apply_setting_change(payload["plugin_id"], payload["key"], payload.get("value"))
        elif command == "trigger_setting_action":
            res = trigger_setting_action(payload["plugin_id"], payload["action_id"])
        elif command == "trigger_alert_callback":
            res = {"ok": trigger_alert_callback(payload["callback_id"])}
        elif command == "list_loaded_plugins":
            res = {"ok": True, "plugins": list_loaded_plugins()}
        else:
            res = {"ok": False, "error": f"Unknown command: {command}"}
    except Exception as exc:
        res = {"ok": False, "error": f"{type(exc).__name__}: {exc}", "traceback": traceback.format_exc()}
    return json.dumps(_serialize_value(res))
