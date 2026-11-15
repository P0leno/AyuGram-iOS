import json
import sys
import tempfile
import unittest
from pathlib import Path

SDK_DIR = Path(__file__).resolve().parents[2] / "Swiftgram" / "SGPlugins" / "PythonSDK"
sys.path.insert(0, str(SDK_DIR))

import _ayu_runtime_host  # noqa: E402
from markdown_utils import parse_markdown  # noqa: E402


class TestExteraCompatSDK(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = _ayu_runtime_host._DefaultFallbackNativeBackend()
        _ayu_runtime_host.set_native_backend(self.backend)
        _ayu_runtime_host.reset_host_state()

    def tearDown(self) -> None:
        _ayu_runtime_host.reset_host_state()
        _ayu_runtime_host.set_native_backend(None)

    def _write_plugin(self, tmp_dir: Path, filename: str, source: str) -> Path:
        path = tmp_dir / filename
        path.write_text(source, encoding="utf-8")
        return path

    def test_markdown_utf16_offsets_with_emoji(self) -> None:
        parsed = parse_markdown("👋 **hi** __you__ `c` [tap](https://example.com) ||secret||")
        self.assertEqual(parsed.text, "👋 hi you c tap secret")
        # 👋 is 2 UTF-16 code units + space = offset 3
        self.assertEqual(parsed.raw_entities[0], {"type": "bold", "offset": 3, "length": 2})
        self.assertEqual(parsed.raw_entities[1], {"type": "italic", "offset": 6, "length": 3})
        self.assertEqual(parsed.raw_entities[2], {"type": "code", "offset": 10, "length": 1})
        self.assertEqual(
            parsed.raw_entities[3],
            {"type": "text_url", "offset": 12, "length": 3, "url": "https://example.com"},
        )
        self.assertEqual(parsed.raw_entities[4], {"type": "spoiler", "offset": 16, "length": 6})

    def test_pure_python_plugin_lifecycle_settings_and_hooks(self) -> None:
        plugin_src = """
from base_plugin import BasePlugin, HookResult, HookStrategy
from ui.settings import Header, Switch, Input, Selector, Text, Divider
from ui.bulletin import BulletinHelper
from ui.alert import AlertDialogBuilder
import client_utils

__id__ = "echo_ext"
__name__ = "Echo Ex"
__author__ = "Tester"
__version__ = "2.1"
__description__ = "Rewrites .ping and uppercases with setting"

class EchoExPlugin(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook(priority=10)
        self.add_hook("receive_message")
        self.unloaded = False
        self.changed = []

    def on_plugin_unload(self):
        self.unloaded = True

    def _on_prefix_change(self, val):
        self.changed.append(("prefix", val))

    def _on_test_click(self, _view=None):
        BulletinHelper.show_success("Clicked!")
        AlertDialogBuilder().set_title("Info").set_message("Done").set_positive_button("OK", lambda: self.set_setting("acked", True)).show()

    def create_settings(self):
        return [
            Header("General"),
            Switch(key="enabled", text="Enable rewrite", default=True, subtext="Active in chats"),
            Input(key="prefix", text="Prefix", default="[bot] ", on_change=self._on_prefix_change),
            Selector(key="mode", text="Mode", items=["Normal", "Loud"], default=0),
            Text(text="Run Action", accent=True, on_click=self._on_test_click),
            Divider("Footer"),
        ]

    def on_setting_changed(self, key, value):
        self.changed.append((key, value))

    def on_send_message_hook(self, account, params):
        if not self.get_setting("enabled", True):
            return HookResult(strategy=HookStrategy.DEFAULT)
        msg = params.message or ""
        if msg == ".cancel":
            return HookResult(strategy=HookStrategy.CANCEL)
        if msg.startswith(".ping"):
            res = client_utils.send_request("help.getAppConfig", {"x": 1})
            self.log(f"ping config={res.get('ok')}")
            params.message = self.get_setting("prefix", "[bot] ") + "PONG!"
            return HookResult(strategy=HookStrategy.MODIFY_FINAL, params=params)
        return HookResult(strategy=HookStrategy.DEFAULT)

    def on_update_hook(self, update_name, account, update):
        if update.text == "auto":
            client_utils.send_message({"peer_id": update.peer_id, "message": "auto-reply"})
        return HookResult(strategy=HookStrategy.DEFAULT)
"""
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write_plugin(Path(tmp), "echo_ext.plugin", plugin_src)
            load_res = _ayu_runtime_host.load_plugin("echo_ext", str(p))
            self.assertTrue(load_res["ok"], load_res)
            self.assertFalse(load_res["incompatible"])
            self.assertTrue(load_res["has_settings"])
            self.assertEqual(load_res["metadata"]["name"], "Echo Ex")

            schema_resp = json.loads(
                _ayu_runtime_host.dispatch_json("export_settings_schema", json.dumps({"plugin_id": "echo_ext"}))
            )
            self.assertTrue(schema_resp["ok"])
            items = schema_resp["items"]
            self.assertEqual([i["type"] for i in items], ["header", "switch", "input", "selector", "text", "divider"])
            action_id = items[4]["action_id"]

            _ayu_runtime_host.apply_setting_change("echo_ext", "prefix", ">> ")
            self.assertEqual(
                _ayu_runtime_host.get_setting("echo_ext", "prefix"),
                ">> ",
            )

            _ayu_runtime_host.trigger_setting_action("echo_ext", action_id)
            self.assertEqual(self.backend.bulletins[-1], ("", "Clicked!", "success"))
            buttons = json.loads(self.backend.alerts[-1][2])
            self.assertTrue(_ayu_runtime_host.trigger_alert_callback(buttons[0]["id"]))
            self.assertTrue(_ayu_runtime_host.get_setting("echo_ext", "acked", False))

            hook_res = _ayu_runtime_host.dispatch_send_message_hook(
                0, {"message": ".ping", "peer_id": 12345}
            )
            self.assertEqual(hook_res["action"], "modify")
            self.assertEqual(hook_res["params"]["message"], ">> PONG!")
            self.assertEqual(self.backend.requests[-1], ("help.getAppConfig", {"x": 1}))

            cancel_res = _ayu_runtime_host.dispatch_send_message_hook(
                0, {"message": ".cancel", "peer_id": 12345}
            )
            self.assertEqual(cancel_res["action"], "cancel")

            _ayu_runtime_host.dispatch_update_hook("receive_message", 0, {"peer_id": 77, "text": "auto"})
            self.assertEqual(self.backend.sent_messages[-1], {"peer_id": 77, "message": "auto-reply"})

            unload_res = _ayu_runtime_host.unload_plugin("echo_ext")
            self.assertTrue(unload_res["ok"])
            self.assertTrue(unload_res["was_loaded"])

    def test_java_xposed_plugin_fails_cleanly_with_diagnostic(self) -> None:
        android_plugin = """
from base_plugin import BasePlugin
from hook_utils import find_class, hook_method

__id__ = "android_only"
__name__ = "Android Only Plugin"
__version__ = "1.0"

class AndroidOnlyPlugin(BasePlugin):
    def on_plugin_load(self):
        cls = find_class("org.telegram.ui.ChatActivity")
        hook_method(cls, "onResume", None)
"""
        jclass_plugin = """
from base_plugin import BasePlugin
from java import jclass

__id__ = "jclass_only"

class JClassPlugin(BasePlugin):
    def on_plugin_load(self):
        jclass("org.telegram.messenger.UserConfig")
"""
        with tempfile.TemporaryDirectory() as tmp:
            p1 = self._write_plugin(Path(tmp), "android_only.plugin", android_plugin)
            res1 = _ayu_runtime_host.load_plugin("android_only", str(p1))
            self.assertFalse(res1["ok"])
            self.assertTrue(res1["incompatible"])
            self.assertIn("unavailable on iOS", res1["error"])
            self.assertEqual(len(_ayu_runtime_host.list_loaded_plugins()), 0)

            p2 = self._write_plugin(Path(tmp), "jclass_only.plugin", jclass_plugin)
            res2 = _ayu_runtime_host.load_plugin("jclass_only", str(p2))
            self.assertFalse(res2["ok"])
            self.assertTrue(res2["incompatible"])
            self.assertIn("Android", res2["error"])

    def test_hook_utils_and_client_utils_extera_imports(self) -> None:
        plugin_src = """
from base_plugin import BasePlugin
from hook_utils import find_class, get_private_field, set_private_field, call_private_method, XposedHelpers
from client_utils import get_last_fragment, get_account_instance, get_messages_storage, get_notification_center

__id__ = "import_compat"
__name__ = "Import Compat"
__version__ = "1.0"

class ImportCompatPlugin(BasePlugin):
    def on_plugin_load(self):
        self.frag = get_last_fragment()
        self.acct = get_account_instance()
        self.storage = get_messages_storage()
        get_notification_center().addObserver(None, 0)
        self.saw_java_error = False
        try:
            get_private_field(object(), "mField")
        except Exception:
            self.saw_java_error = True
"""
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write_plugin(Path(tmp), "import_compat.plugin", plugin_src)
            res = _ayu_runtime_host.load_plugin("import_compat", str(p))
            self.assertTrue(res["ok"], res)
            self.assertFalse(res["incompatible"])


if __name__ == "__main__":
    unittest.main()
