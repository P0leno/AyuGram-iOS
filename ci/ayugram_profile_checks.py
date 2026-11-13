from pathlib import Path
import re
import subprocess


def check_shared_profiles(source: Path, ci: Path):
    output = source / 'build-input/ayu-profile-checks'
    output.mkdir(parents=True, exist_ok=True)
    badges = source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramClientBadges.swift'
    text = badges.read_text()
    for token in ['URLSession', 'URLRequest', 'URL(', 'http']:
        assert token not in text, 'Badges are decided on the device and never use the network: ' + token
    tests = ci / 'tests/AyuGramClientBadgesTests.swift'
    binary = output / 'badge-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', badges, tests, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=40)
    minimum = re.search(r'^minimum_os_version\s*=\s*"([0-9.]+)"', (source / 'Telegram/BUILD').read_text(), re.M).group(1)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios' + minimum, '-sdk', sdk,
                    '-parse-as-library', '-typecheck', badges], check=True)
    print('Local badges checked with real Foundation and the minimum iOS SDK', flush=True)

    updates = source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramUpdates.swift'
    updates_text = updates.read_text()
    for token in ['URLSession', 'URLRequest', 'update.json', 'mapix3', 'workers.dev']:
        assert token not in updates_text, 'Updates must not perform remote fetches: ' + token
    update_tests = ci / 'tests/AyuGramUpdatesTests.swift'
    update_binary = output / 'update-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', updates, update_tests, '-o', update_binary], check=True)
    subprocess.run([update_binary], check=True, timeout=40)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios' + minimum, '-sdk', sdk,
                    '-parse-as-library', '-typecheck', updates], check=True)
    print('Offline update metadata checked', flush=True)

    security = source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramSecurity.swift'
    security_text = security.read_text()
    for token in ['URLSession', 'URLRequest', 'workers.dev', 'mapix3', 'tamperMessage', 'ayuGramSeal', 'SecItem']:
        assert token not in security_text, 'Security module must stay local-only without telemetry or remote blocks: ' + token
    security_tests = ci / 'tests/AyuGramSecurityTests.swift'
    security_binary = output / 'security-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0', security, security_tests, '-o', security_binary], check=True)
    subprocess.run([security_binary], check=True, timeout=40)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios' + minimum, '-sdk', sdk,
                    '-parse-as-library', '-typecheck', security], check=True)

    for rel_path in [
        'Swiftgram/SGSettingsUI/Sources/AyuGramUpdatePrompt.swift',
        'Swiftgram/SGSettingsUI/Sources/AyuGramSettingsScreen.swift',
    ]:
        ui_text = (source / rel_path).read_text()
        for token in ['ayuGramStartSecurity', 'ayuGramArmTamperWatchdog', 'update.json', 'workers.dev']:
            assert token not in ui_text, f'{rel_path} must not contain removed hook or remote endpoint: {token}'

    print('Local-only security checks verified', flush=True)
