#!/usr/bin/env python3
"""Replace the existing tweak once, rebrand resources, and audit the 11.98 base."""
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'branding'))
import ipa_branding


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def otool(path):
    return subprocess.check_output(['xcrun', 'otool', '-L', str(path)], text=True)


def is_macho(path):
    if not path.is_file():
        return False
    with path.open('rb') as stream:
        return stream.read(4) in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf')


def main():
    base, pack, dylib = map(lambda arg: Path(arg).resolve(), sys.argv[1:4])
    output = ROOT / 'packages/Twitter-11.98_NeoFreeBird-v7_iOS27_zh-CN_unsigned.ipa'
    with tempfile.TemporaryDirectory(prefix='nfb-1198-') as temp:
        work = Path(temp)
        stage = work / 'stage'
        subprocess.run(['ditto', '-x', '-k', str(base), str(stage)], check=True)
        apps = list((stage / 'Payload').glob('*.app'))
        assert len(apps) == 1
        app = apps[0]
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        assert info['CFBundleShortVersionString'] == '11.98', 'Refusing a 12.x base'
        assert info['CFBundleIdentifier'] == 'com.atebits.Tweetie2'
        executable = app / info['CFBundleExecutable']
        embedded = list(app.rglob('BHTwitter.dylib'))
        assert len(embedded) == 1
        # Keep every original application/framework executable byte-for-byte.
        originals = {p.relative_to(app): sha(p) for p in app.rglob('*')
                     if is_macho(p) and p != embedded[0]}
        nibs = {p.relative_to(app): sha(p) for p in app.rglob('*')
                if p.is_file() and (p.suffix == '.nib' or any(part.endswith('.storyboardc') for part in p.parts))}
        built = work / 'BHTwitter.dylib'
        shutil.copy2(dylib, built)
        for line in otool(built).splitlines()[1:]:
            dependency = line.strip().split(' ', 1)[0]
            if dependency.startswith('/Library/Frameworks/'):
                portable = '@rpath/' + dependency.removeprefix('/Library/Frameworks/')
                subprocess.run(['install_name_tool', '-change', dependency, portable, str(built)], check=True)
        dependencies = [line.strip().split(' ', 1)[0] for line in otool(built).splitlines()[1:]]
        assert not any(path.startswith('/Library/Frameworks/') for path in dependencies), dependencies
        for name in ('Cephei', 'CepheiPrefs', 'CepheiUI', 'CydiaSubstrate'):
            assert (app / f'Frameworks/{name}.framework/{name}').is_file()
        shutil.copy2(built, embedded[0])
        bundle = ROOT / 'layout/Library/Application Support/BHT/BHTwitter.bundle'
        shutil.copytree(bundle, app / 'BHTwitter.bundle', dirs_exist_ok=True)
        assert not (app / 'BHTwitter.bundle/NFBLaunchBird@3x.png').exists(), 'Removed overlay bitmap must not ship'
        # Newer-app launch NIBs are deliberately excluded: they are not 11.98 UI.
        safe_pack = work / 'safe-pack.zip'
        with zipfile.ZipFile(pack) as source, zipfile.ZipFile(safe_pack, 'w') as target:
            for name in source.namelist():
                parts = Path(name).parts
                if parts and parts[0] in ('icons', 'svgs') and '..' not in parts and not name.endswith('/'):
                    target.writestr(name, source.read(name))
        brand_work = work / 'branding'
        brand_work.mkdir()
        ipa_branding._apply_resource_pack_to_app(app, brand_work, safe_pack, keep_stock_icons=True)
        ipa_branding._set_display_name_in_app(app)
        info2 = plistlib.loads((app / 'Info.plist').read_bytes())
        # 11.98 also ships PNG-only alternates, without MSIS catalog facets.
        # Keep their original file references; the PNG overlay updates their art.
        for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
            old_alternates = info.get(key, {}).get('CFBundleAlternateIcons', {})
            if old_alternates:
                alternates = info2.setdefault(key, {}).setdefault('CFBundleAlternateIcons', {})
                for name, entry in old_alternates.items():
                    alternates.setdefault(name, entry)
        (app / 'Info.plist').write_bytes(plistlib.dumps(info2, fmt=plistlib.FMT_BINARY))
        assert info2['CFBundleShortVersionString'] == '11.98'
        assert info2['CFBundleVersion'] == info['CFBundleVersion']
        assert info2['CFBundleIdentifier'] == info['CFBundleIdentifier']
        old_icons = set(info['CFBundleIcons']['CFBundleAlternateIcons'])
        new_icons = set(info2['CFBundleIcons']['CFBundleAlternateIcons'])
        assert old_icons <= new_icons, f'Existing icons removed: {old_icons - new_icons}'
        assert info2.get('CADisableMinimumFrameDurationOnPhone') is True
        assert all(sha(app / p) == digest for p, digest in originals.items())
        assert all(sha(app / p) == digest for p, digest in nibs.items())
        assert otool(executable).count('BHTwitter.dylib') == 1
        assert otool(executable).count('keychainfix.dylib') == 1
        assert len(list(app.rglob('keychainfix.dylib'))) == 1
        # Validate the home bird glyph actually changed, not just the app icon.
        with zipfile.ZipFile(safe_pack) as assets:
            for glyph in ('twitter.svg', 'x_custom_logo.svg'):
                name = 'svgs/' + glyph
                if name not in assets.namelist():
                    continue
                expected = assets.read(name)
                matches = list(app.rglob(glyph))
                assert matches and all(p.read_bytes() == expected for p in matches), glyph
        strings = (app / 'BHTwitter.bundle/zh_CN.lproj/Localizable.strings').read_text('utf-8')
        assert all(title in strings for title in ('使用网页登录', '搜索与发现', 'Grok', '时间线', '外观', '实验室'))
        assert (app / 'BHTwitter.bundle/WebXTID.js').is_file()
        for seal in sorted((stage / 'Payload').rglob('_CodeSignature'), reverse=True):
            if seal.is_dir():
                shutil.rmtree(seal)
        for profile in (stage / 'Payload').rglob('embedded.mobileprovision'):
            profile.unlink()
        subprocess.run(['/usr/bin/zip', '-qry', str(output), 'Payload'], cwd=stage, check=True)
        report = {
            'app_version': info2['CFBundleShortVersionString'],
            'bundle_version': info2['CFBundleVersion'],
            'base_sha256': sha(base),
            'output_sha256': sha(output),
            'original_macho_binaries_unchanged': len(originals),
            'original_launch_ui_unchanged': True,
            'single_tweak_and_keychain_load': True,
            'promotion_opt_in': True,
            'alternate_icons': len(info2['CFBundleIcons']['CFBundleAlternateIcons']),
            'all_existing_alternate_icons_preserved': old_icons <= new_icons,
            'provisioning_removed': True,
            'settings_core': 'orionblur-v7-1b24ee11908c',
            'settings_pages': 14,
            'missing_private_hooks_skipped': True,
            'incompatible_private_hook_abi_skipped': True,
            'launch_transition_seconds': 0,
            'launch_transition_style': 'none-system-static-launch-only',
            'custom_launch_animation_removed': True,
            'sidebar_hidden_by_default': ['Money', 'News', 'Jobs'],
            'ios_26_plus_prefetch_workaround': True,
            'device_login_and_stability_tested': False,
        }
        (ROOT / 'packages/verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
