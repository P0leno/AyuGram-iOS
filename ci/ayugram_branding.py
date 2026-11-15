"""Produce native Apple icon and display-name assets from repo config or CI inputs."""
import base64
import json
import os
import plistlib
import re
import struct
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


# Official Telegram icons shipped next to the AyuGram and Swiftgram ones.
OFFICIAL_ICONS = [
    'BlueIcon', 'New2', 'New1', 'BlackIcon', 'BlueClassicIcon', 'BlackClassicIcon',
    'BlueFilledIcon', 'BlackFilledIcon', 'WhiteFilledIcon', 'Premium', 'PremiumBlack',
    'PremiumTurbo',
]
DEFAULT_AYU_ICONS = ['AyuClassic', 'AyuPurple', 'AyuRed']
MAX_ICON_BYTES = 8 * 1024 * 1024
_ICON_ID_RE = re.compile(r'^[A-Za-z][A-Za-z0-9_]{0,31}$')


def _is_valid_image_bytes(contents: bytes) -> bool:
    if not contents or len(contents) > MAX_ICON_BYTES:
        return False
    return contents.startswith(b'\xff\xd8') or contents.startswith(b'\x89PNG\r\n\x1a\n')


def _image_extension(contents: bytes) -> str:
    return '.png' if contents.startswith(b'\x89PNG\r\n\x1a\n') else '.jpg'


def _download_icon(url: str) -> bytes:
    parsed = urllib.request.urlparse(url)
    if parsed.scheme not in ('https', 'http'):
        raise ValueError('Custom icon URL must use http or https')
    req = urllib.request.Request(url, headers={'User-Agent': 'AyuGram-iOS-Branding/1.0'})
    with urllib.request.urlopen(req, timeout=30) as response:
        data = response.read(MAX_ICON_BYTES + 1)
    if not _is_valid_image_bytes(data):
        raise ValueError('Downloaded custom icon is invalid PNG/JPEG or exceeds size limit')
    return data


def _sanitize_icon_id(value: str, fallback: str = 'CustomPrimary') -> str:
    cleaned = re.sub(r'[^A-Za-z0-9_]', '', (value or '').strip())
    if not cleaned or not cleaned[0].isalpha():
        return fallback
    return cleaned[:32]


def _render_png(image_path: Path, target_path: Path, size: int) -> None:
    target_path.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == 'darwin':
        subprocess.run(
            ['sips', '-s', 'format', 'png', '-z', str(size), str(size), str(image_path), '--out', str(target_path)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        return
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError('Rendering PNG icons outside macOS requires Pillow') from exc
    with Image.open(image_path) as img:
        resized = img.convert('RGBA').resize((size, size), Image.Resampling.LANCZOS)
        resized.save(target_path, format='PNG')


def _load_legacy_icons_json(source: Path) -> dict[str, bytes]:
    icons_path = source / 'Swiftgram/AyuBranding/icons.json'
    data = json.loads(icons_path.read_text(encoding='utf-8'))
    if not {'AyuClassic', 'AyuPurple', 'AyuRed'}.issubset(data):
        raise ValueError('Unexpected icon manifest')
    decoded: dict[str, bytes] = {}
    for name, encoded in data.items():
        contents = base64.b64decode(encoded, validate=True)
        if not _is_valid_image_bytes(contents):
            raise ValueError('Invalid source icon: ' + name)
        decoded[name] = contents
    return decoded


def load_branding_config(source: Path, env: dict | None = None) -> dict:
    """Resolve effective branding config from Swiftgram/AyuBranding/branding.json and CI env."""
    source = source.resolve()
    env = env if env is not None else os.environ
    branding_path = source / 'Swiftgram/AyuBranding/branding.json'
    if branding_path.is_file():
        config = json.loads(branding_path.read_text(encoding='utf-8'))
    else:
        config = {
            'display_name': 'AyuGram',
            'badge_title': '',
            'hide_client_branding': False,
            'default_icon': 'AyuClassic',
            'icons': [
                {'id': name, 'title': name, 'source': f'icons.json:{name}'}
                for name in DEFAULT_AYU_ICONS
            ],
        }

    app_name_override = (env.get('AYUGRAM_APP_NAME') or '').strip()
    if app_name_override:
        if len(app_name_override) > 64 or any(ord(ch) < 32 for ch in app_name_override):
            raise ValueError('Invalid AYUGRAM_APP_NAME')
        config['display_name'] = app_name_override

    display_name = (config.get('display_name') or 'AyuGram').strip()
    if not display_name or len(display_name) > 64:
        raise ValueError('Invalid display_name in branding config')
    config['display_name'] = display_name

    badge_override = env.get('AYUGRAM_BADGE_TITLE')
    if badge_override is not None and badge_override.strip():
        config['badge_title'] = badge_override.strip()[:24]
    else:
        config['badge_title'] = str(config.get('badge_title') or '')[:24]

    hide_override = (env.get('AYUGRAM_HIDE_BRANDING') or '').strip().lower()
    if hide_override in ('1', 'true', 'yes'):
        config['hide_client_branding'] = True
    elif hide_override in ('0', 'false', 'no'):
        config['hide_client_branding'] = False
    else:
        config['hide_client_branding'] = bool(config.get('hide_client_branding', False))

    icons = list(config.get('icons') or [])
    if not icons:
        icons = [
            {'id': name, 'title': name, 'source': f'icons.json:{name}'}
            for name in DEFAULT_AYU_ICONS
        ]

    # Allow CI / workflow_dispatch custom icon URL, path, or base64 override.
    custom_url = (env.get('AYUGRAM_CUSTOM_ICON_URL') or '').strip()
    custom_path = (env.get('AYUGRAM_CUSTOM_ICON_PATH') or '').strip()
    custom_b64 = (env.get('AYUGRAM_CUSTOM_ICON_B64') or '').strip()
    custom_title = (env.get('AYUGRAM_CUSTOM_ICON_NAME') or '').strip() or 'Custom'
    if custom_url or custom_path or custom_b64:
        custom_id = _sanitize_icon_id(env.get('AYUGRAM_CUSTOM_ICON_ID') or 'CustomPrimary')
        source_ref = ''
        if custom_url:
            source_ref = f'url:{custom_url}'
        elif custom_path:
            source_ref = custom_path
        elif custom_b64:
            source_ref = f'base64:{custom_b64}'
        icons = [entry for entry in icons if entry.get('id') != custom_id]
        icons.insert(0, {'id': custom_id, 'title': custom_title, 'source': source_ref})
        config['default_icon'] = custom_id

    seen_ids = set()
    normalized_icons = []
    for entry in icons:
        icon_id = str(entry.get('id') or '').strip()
        if not _ICON_ID_RE.fullmatch(icon_id):
            raise ValueError('Invalid custom icon id: ' + icon_id)
        if icon_id in seen_ids:
            continue
        seen_ids.add(icon_id)
        normalized_icons.append({
            'id': icon_id,
            'title': str(entry.get('title') or icon_id),
            'source': str(entry.get('source') or f'icons.json:{icon_id}'),
        })

    config['icons'] = normalized_icons
    default_icon = str(config.get('default_icon') or '').strip()
    if default_icon not in seen_ids:
        default_icon = normalized_icons[0]['id']
    config['default_icon'] = default_icon
    return config


def _resolve_icon_bytes(source: Path, entry_source: str, legacy_icons: dict[str, bytes]) -> bytes:
    if entry_source.startswith('icons.json:'):
        key = entry_source.split(':', 1)[1]
        if key not in legacy_icons:
            raise ValueError('Missing key in icons.json: ' + key)
        return legacy_icons[key]
    if entry_source.startswith('base64:'):
        data = base64.b64decode(entry_source.split(':', 1)[1], validate=True)
        if not _is_valid_image_bytes(data):
            raise ValueError('Invalid base64 custom icon')
        return data
    if entry_source.startswith('url:'):
        return _download_icon(entry_source.split(':', 1)[1])

    candidate = Path(entry_source)
    if not candidate.is_absolute():
        candidate = (source / 'Swiftgram/AyuBranding' / candidate).resolve()
        branding_root = (source / 'Swiftgram/AyuBranding').resolve()
        if branding_root not in candidate.parents and candidate != branding_root:
            raise ValueError('Custom icon path escapes AyuBranding directory')
    data = candidate.read_bytes()
    if not _is_valid_image_bytes(data):
        raise ValueError('Invalid custom icon file: ' + str(candidate))
    return data


def _update_build_and_plists(source: Path, display_name: str, icon_ids: list[str]) -> None:
    build_path = source / 'Telegram/BUILD'
    build_text = build_path.read_text(encoding='utf-8')
    escaped_xml_name = xml_escape(display_name)
    escaped_open_name = xml_escape('Open in ' + display_name)

    # Update alternate_icon_folders if any custom icon IDs were added beyond repo defaults.
    folder_block_match = re.search(
        r'(alternate_icon_folders\s*=\s*\[)(.*?)(\n\])',
        build_text,
        flags=re.DOTALL,
    )
    if folder_block_match:
        existing_block = folder_block_match.group(2)
        existing_names = re.findall(r'"([^"]+)"', existing_block)
        missing = [icon_id for icon_id in icon_ids if icon_id not in existing_names]
        if missing:
            addition = ''.join(f'\n    "{icon_id}",' for icon_id in missing)
            new_block = folder_block_match.group(1) + addition + existing_block + folder_block_match.group(3)
            build_text = (
                build_text[:folder_block_match.start()]
                + new_block
                + build_text[folder_block_match.end():]
            )

    if display_name != 'AyuGram':
        build_text = re.sub(
            r'(<key>CFBundleDisplayName</key>\s*<string>)AyuGram(</string>)',
            rf'\g<1>{escaped_xml_name}\g<2>',
            build_text,
        )
        build_text = re.sub(
            r'(<key>CFBundleName</key>\s*<string>)AyuGram(</string>)',
            rf'\g<1>{escaped_xml_name}\g<2>',
            build_text,
        )
        build_text = re.sub(
            r'(<key>CFBundleDisplayName</key>\s*<string>)Open in AyuGram(</string>)',
            rf'\g<1>{escaped_open_name}\g<2>',
            build_text,
        )

        # Update localized InfoPlist.strings when custom display name is set.
        escaped_strings_name = display_name.replace('\\', '\\\\').replace('"', '\\"')
        for strings_path in sorted((source / 'Telegram/Telegram-iOS').glob('*.lproj/InfoPlist.strings')):
            content = strings_path.read_text(encoding='utf-8')
            updated = re.sub(
                r'("CFBundleDisplayName"\s*=\s*")[^"]*(";)',
                rf'\g<1>{escaped_strings_name}\g<2>',
                content,
            )
            if '"CFBundleDisplayName"' not in updated:
                updated = updated.rstrip() + f'\n"CFBundleDisplayName" = "{escaped_strings_name}";\n'
            if updated != content:
                strings_path.write_text(updated, encoding='utf-8')

    build_path.write_text(build_text, encoding='utf-8')


def prepare_branding(source: Path, env: dict | None = None, renderer=None) -> dict:
    """Prepare native icons, Assets.xcassets marks, Info.plist display name, and runtime manifest."""
    source = source.resolve()
    render_fn = renderer or _render_png
    legacy_icons = _load_legacy_icons_json(source)
    config = load_branding_config(source, env=env)

    temporary = source / 'build-input/ayugram-icons'
    temporary.mkdir(parents=True, exist_ok=True)

    resolved_sources: dict[str, bytes] = {}
    for icon in config['icons']:
        resolved_sources[icon['id']] = _resolve_icon_bytes(source, icon['source'], legacy_icons)

    # Also keep built-in Ayu icons rendered if omitted from custom icon list so BASE TARGETS never break.
    for name in DEFAULT_AYU_ICONS:
        if name not in resolved_sources and name in legacy_icons:
            resolved_sources[name] = legacy_icons[name]

    rendered_temp_files: dict[str, Path] = {}
    for name, contents in resolved_sources.items():
        ext = _image_extension(contents)
        image = temporary / (name + ext)
        image.write_bytes(contents)
        rendered_temp_files[name] = image

        alternate = source / 'Telegram/Telegram-iOS' / (name + '.alticon')
        for scale, size in [(2, 120), (3, 180)]:
            render_fn(image, alternate / f'{name}@{scale}x.png', size)

        preview = source / 'Swiftgram/SGAppBadgeAssets/Images.xcassets' / (name + 'Mark.imageset')
        entries = []
        for scale in [2, 3]:
            filename = f'{name}@{scale}x.png'
            render_fn(image, preview / filename, 30 * scale)
            entries.append({'idiom': 'universal', 'filename': filename, 'scale': f'{scale}x'})
        preview.mkdir(parents=True, exist_ok=True)
        (preview / 'Contents.json').write_text(
            json.dumps({'images': entries, 'info': {'version': 1, 'author': 'xcode'}}, indent=2),
            encoding='utf-8',
        )

    primary_id = config['default_icon']
    primary_src = rendered_temp_files[primary_id]
    composer = source / 'Telegram/Telegram-iOS/AyuGram.icon'
    template = json.loads((source / 'Telegram/Telegram-iOS/Swiftgram.icon/icon.json').read_text(encoding='utf-8'))
    template['fill']['linear-gradient'] = ['srgb:0.19,0.15,0.28,1.0', 'srgb:0.19,0.15,0.28,1.0']
    primary_layer_filename = f'{primary_id}.png'
    for group in template['groups']:
        for layer in group['layers']:
            layer['image-name'] = primary_layer_filename
            layer['name'] = config['display_name']
            layer['glass'] = False
            layer['opacity-specializations'] = [{'value': 1}]
        group['translucency'] = {'enabled': False, 'value': 0}
    render_fn(primary_src, composer / 'Assets' / primary_layer_filename, 1024)
    (composer / 'icon.json').write_text(json.dumps(template, indent=2), encoding='utf-8')

    all_icon_ids = list(resolved_sources.keys())
    _update_build_and_plists(source, config['display_name'], all_icon_ids)

    # Persist sanitized runtime branding manifest (without inline base64/url secrets).
    runtime_manifest = {
        'display_name': config['display_name'],
        'badge_title': config['badge_title'],
        'hide_client_branding': config['hide_client_branding'],
        'default_icon': config['default_icon'],
        'icons': [{'id': item['id'], 'title': item['title']} for item in config['icons']],
    }
    (source / 'Swiftgram/AyuBranding/branding.json').write_text(
        json.dumps(runtime_manifest, indent=2) + '\n',
        encoding='utf-8',
    )
    return runtime_manifest


def verify_branding_ipa(path, branding: dict | None = None, source: Path | None = None, env: dict | None = None):
    if branding is None and source is not None:
        branding = load_branding_config(source, env=env)
    expected_name = branding['display_name'] if branding else 'AyuGram'
    custom_ids = [item['id'] for item in branding['icons']] if branding else list(DEFAULT_AYU_ICONS)
    required_icons = list(dict.fromkeys(custom_ids + DEFAULT_AYU_ICONS + OFFICIAL_ICONS))

    with zipfile.ZipFile(path) as archive:
        mains = [
            name for name in archive.namelist()
            if name.startswith('Payload/') and name.endswith('.app/Info.plist') and name.count('/') == 2
        ]
        if len(mains) != 1:
            raise ValueError('Missing main app plist')
        info = plistlib.loads(archive.read(mains[0]))
        if info.get('CFBundleDisplayName') != expected_name:
            raise ValueError(f"Unexpected app display name: {info.get('CFBundleDisplayName')!r} != {expected_name!r}")
        alternates = info.get('CFBundleIcons', {}).get('CFBundleAlternateIcons', {})
        expected_custom_set = set(custom_ids + DEFAULT_AYU_ICONS)
        if not expected_custom_set.issubset(alternates):
            raise ValueError('AyuGram alternate icons were not included')
        missing = [name for name in OFFICIAL_ICONS if name not in alternates]
        if missing:
            raise ValueError('Telegram alternate icons were not included: ' + ', '.join(missing))
        bundle = mains[0].removesuffix('Info.plist')
        for name in required_icons:
            files = alternates[name].get('CFBundleIconFiles') or []
            expected = (files == [name]) if (name.startswith('Ayu') or name in custom_ids) else (name in files)
            if not expected:
                raise ValueError('Unexpected alternate icon file reference: ' + name)
            for scale, pixels in [(2, 120), (3, 180)]:
                icon_path = bundle + name + '@' + str(scale) + 'x.png'
                if icon_path not in archive.namelist():
                    raise ValueError('Missing alternate icon image: ' + icon_path)
                image = archive.read(icon_path)
                if png_dimensions(image) != (pixels, pixels):
                    raise ValueError('Invalid alternate icon image: ' + icon_path)


def png_dimensions(image):
    if image[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    offset = 8
    while offset + 12 <= len(image):
        length = struct.unpack('>I', image[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(image):
            return None
        if image[offset + 4:offset + 8] == b'IHDR':
            return struct.unpack('>II', image[offset + 8:offset + 16]) if length == 13 else None
        offset = end
    return None
