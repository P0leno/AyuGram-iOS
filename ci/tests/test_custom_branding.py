"""Unit tests for flexible custom app name and PNG/JPG icon branding."""
import base64
import io
import json
import plistlib
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
import zipfile

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ayugram_branding


def _minimal_png(width: int, height: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    raw = b'\x00' + (b'\x00\x00\x00\xff' * width)
    idat = zlib.compress(raw * height)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')


def _fake_renderer(src: Path, dst: Path, size: int) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(_minimal_png(size, size))


def _make_fake_source(root: Path) -> None:
    (root / 'Swiftgram/AyuBranding/custom_icons').mkdir(parents=True)
    (root / 'Swiftgram/SGAppBadgeAssets/Images.xcassets').mkdir(parents=True)
    (root / 'Telegram/Telegram-iOS/Swiftgram.icon').mkdir(parents=True)
    (root / 'Telegram/Telegram-iOS/en.lproj').mkdir(parents=True)
    (root / 'Telegram/Telegram-iOS/ko.lproj').mkdir(parents=True)

    tiny_jpg = b'\xff\xd8\xff\xe0dummy'
    encoded = base64.b64encode(tiny_jpg).decode('ascii')
    (root / 'Swiftgram/AyuBranding/icons.json').write_text(
        json.dumps({'AyuClassic': encoded, 'AyuPurple': encoded, 'AyuRed': encoded}),
        encoding='utf-8',
    )
    (root / 'Telegram/Telegram-iOS/Swiftgram.icon/icon.json').write_text(
        json.dumps({'fill': {}, 'groups': [{'layers': [{'image-name': 'x.png', 'name': 'x'}]}]}),
        encoding='utf-8',
    )
    (root / 'Telegram/BUILD').write_text(
        'alternate_icon_folders = [\n    "AyuClassic",\n    "AyuPurple",\n    "AyuRed",\n]\n'
        '<key>CFBundleDisplayName</key>\n<string>AyuGram</string>\n'
        '<key>CFBundleName</key>\n<string>AyuGram</string>\n'
        '<key>CFBundleDisplayName</key>\n<string>Open in AyuGram</string>\n',
        encoding='utf-8',
    )
    (root / 'Telegram/Telegram-iOS/en.lproj/InfoPlist.strings').write_text('"NSCameraUsageDescription" = "x";\n', encoding='utf-8')
    (root / 'Telegram/Telegram-iOS/ko.lproj/InfoPlist.strings').write_text('"CFBundleDisplayName" = "AyuGram";\n', encoding='utf-8')


def _make_fake_ipa(path: Path, display_name: str, extra_icons: list[str] | None = None) -> None:
    icons = list(ayugram_branding.DEFAULT_AYU_ICONS) + list(ayugram_branding.OFFICIAL_ICONS) + list(extra_icons or [])
    alternate_dict = {name: {'CFBundleIconFiles': [name]} for name in icons}
    info_plist = plistlib.dumps({
        'CFBundleDisplayName': display_name,
        'CFBundleIcons': {'CFBundleAlternateIcons': alternate_dict},
    })
    with zipfile.ZipFile(path, 'w') as zf:
        zf.writestr('Payload/Swiftgram.app/Info.plist', info_plist)
        for name in icons:
            zf.writestr(f'Payload/Swiftgram.app/{name}@2x.png', _minimal_png(120, 120))
            zf.writestr(f'Payload/Swiftgram.app/{name}@3x.png', _minimal_png(180, 180))


class CustomBrandingTests(unittest.TestCase):
    def test_custom_name_and_png_icon_prepared_and_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_fake_source(root)
            custom_png = root / 'Swiftgram/AyuBranding/custom_icons/MyLogo.png'
            custom_png.write_bytes(_minimal_png(64, 64))
            manifest = {
                'display_name': 'MyCustomGram',
                'badge_title': 'MY',
                'hide_client_branding': True,
                'default_icon': 'MyCustomIcon',
                'icons': [
                    {'id': 'MyCustomIcon', 'title': 'My Custom', 'source': 'custom_icons/MyLogo.png'},
                    {'id': 'AyuClassic', 'title': 'AyuClassic', 'source': 'icons.json:AyuClassic'},
                ],
            }
            (root / 'Swiftgram/AyuBranding/branding.json').write_text(json.dumps(manifest), encoding='utf-8')

            result = ayugram_branding.prepare_branding(root, env={}, renderer=_fake_renderer)
            self.assertEqual(result['display_name'], 'MyCustomGram')
            self.assertEqual(result['default_icon'], 'MyCustomIcon')
            self.assertTrue((root / 'Telegram/Telegram-iOS/MyCustomIcon.alticon/MyCustomIcon@3x.png').is_file())
            self.assertTrue((root / 'Telegram/Telegram-iOS/AyuGram.icon/Assets/MyCustomIcon.png').is_file())

            build_text = (root / 'Telegram/BUILD').read_text(encoding='utf-8')
            self.assertIn('"MyCustomIcon"', build_text)
            self.assertIn('<string>MyCustomGram</string>', build_text)
            self.assertIn('<string>Open in MyCustomGram</string>', build_text)
            self.assertIn('"CFBundleDisplayName" = "MyCustomGram";',
                          (root / 'Telegram/Telegram-iOS/ko.lproj/InfoPlist.strings').read_text(encoding='utf-8'))

            ipa_path = root / 'out.ipa'
            _make_fake_ipa(ipa_path, 'MyCustomGram', extra_icons=['MyCustomIcon'])
            ayugram_branding.verify_branding_ipa(ipa_path, branding=result)

            with self.assertRaises(ValueError):
                ayugram_branding.verify_branding_ipa(ipa_path)  # Default expects AyuGram

    def test_ci_env_overrides_base64_and_app_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_fake_source(root)
            b64_png = base64.b64encode(_minimal_png(32, 32)).decode('ascii')
            env = {
                'AYUGRAM_APP_NAME': 'NovaGram',
                'AYUGRAM_CUSTOM_ICON_B64': b64_png,
                'AYUGRAM_CUSTOM_ICON_NAME': 'Nova',
                'AYUGRAM_HIDE_BRANDING': 'true',
            }
            result = ayugram_branding.prepare_branding(root, env=env, renderer=_fake_renderer)
            self.assertEqual(result['display_name'], 'NovaGram')
            self.assertTrue(result['hide_client_branding'])
            self.assertEqual(result['default_icon'], 'CustomPrimary')
            self.assertEqual(result['icons'][0]['title'], 'Nova')

    def test_repo_branding_manifest_defaults_to_telegram(self):
        repo_root = Path(__file__).resolve().parents[2]
        config = ayugram_branding.load_branding_config(repo_root, env={})
        self.assertEqual(config['display_name'], 'Telegram')


if __name__ == '__main__':
    unittest.main()
