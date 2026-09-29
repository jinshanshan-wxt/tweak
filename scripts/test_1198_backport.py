#!/usr/bin/env python3
"""Regression checks for the v7 settings/core port without changing the 11.98 app."""
import hashlib
import plistlib
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
assert hashlib.sha256((root / 'keychainfix/Tweak.x').read_bytes()).hexdigest() == '83c4864bbfd1243135d5bae25a023d381c83bbaaef0a3fd13ec95e313c792bb1'
assert hashlib.sha256((root / 'IOS26Compatibility.x').read_bytes()).hexdigest() == '1516732042a974aee12227d045c678cef4c4b715f95ada2ee2c3f1fbb813f971'
makefile = (root / 'Makefile').read_text()
sources = next(line for line in makefile.splitlines() if line.startswith('BHTwitter_FILES'))
assert 'find src' in sources and 'IOS26Compatibility.x' in sources
assert all(f not in sources for f in ('ClassicLogin.x', 'ModernSettingsViewController.m', 'BHDownloadInlineButton.m', ' Tweak.x'))

with zipfile.ZipFile(root / 'packages/base-11.98-stable.ipa') as archive:
    info = plistlib.loads(archive.read('Payload/Twitter.app/Info.plist'))
    assert info['CFBundleShortVersionString'] == '11.98'
    binary = archive.read('Payload/Twitter.app/Frameworks/T1Twitter.framework/T1Twitter')
    for selector in ('initWithUsername:userID:', 'updateUserInfoAndCredentialsWithToken:secret:username:',
                     'private_startLoginFlowWithSender:', 'makeOnboardingViewControllerWithOCFFallback:completion:',
                     'viewAccount:animated:', 'addAccount:', 'saveSharedTwitter', 'animateRevealWithCompletion:'):
        assert selector.encode() + b'\0' in binary, f'Missing 11.98 selector: {selector}'

session = (root / 'src/Hooks/WebCreateTweet.x').read_text()
assert 'postingUserID = userIDFromTwid(WebTwid)' not in session
assert '[hosts containsObject:url.host.lowercaseString]' in session
assert 'isCreateTweet && nativeCreateTweetInterceptEnabled() && cookieReplication' in session
assert 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in session
assert '[authorization containsString:marker]' in session
login = (root / 'src/Hooks/LoginCompatibility.x').read_text()
assert 'makeOnboardingViewControllerWithOCFFallback:' in login
assert 'makeOnboardingViewControllerWithCompletion:' not in login

# Every subclass receives the common switch handler; this specifically prevents
# the previous TweetsSettingsViewController unrecognized-selector regression.
page = (root / 'src/Settings/ModernSettingsPageViewController.m').read_text()
assert re.search(r'-\s*\(void\)\s*switchChanged:\s*\(UISwitch\s*\*\)', page)
tweets_header = (root / 'src/Settings/Pages/TweetsSettingsViewController.h').read_text()
assert ': ModernSettingsPageViewController' in tweets_header
cells = (root / 'src/Settings/ModernSettingsCells.m').read_text()
assert 'removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents' in cells
assert '[target respondsToSelector:action]' in cells
settings_sources = list((root / 'src/Settings').rglob('*.m'))
available_actions = set()
for source in settings_sources:
    text = source.read_text()
    for signature in re.findall(r'^[-+]\s*\([^)]*\)\s*([^;{]+)\{', text, re.M):
        parts = re.findall(r'(\w+)\s*:', signature)
        available_actions.add(''.join(p + ':' for p in parts) if parts else signature.strip().split()[0])
registry = (root / 'src/Core/BHTSettings.m').read_text()
navigation = (root / 'src/Settings/ModernSettingsViewController.m').read_text()
for action in re.findall(r'@"action":\s*@"([^"]+)"', registry + navigation):
    assert action in available_actions, f'Settings action has no implementation: {action}'
for key in ('general', 'appearance', 'grok', 'timelines', 'media_downloads', 'profiles', 'tweets', 'chat',
            'search', 'web', 'branding', 'presets', 'experimental', 'debug'):
    assert '@"' + key + '": @{' in registry, f'Missing v7 page: {key}'
for key in ('hide_grok_analyze', 'hide_grok_sidebar', 'hide_grok_create', 'disable_auto_translate'):
    assert key in registry and any(key in p.read_text() for p in (root / 'src/Hooks').glob('*.x'))
assert 'TAEStandardFontGroup' in (root / 'src/Core/BHTManager.m').read_text()
assert 'NFBHookExistingMessage' in (root / 'src/Hooks/HookHelpers.h').read_text() + (root / 'src/Core/RuntimeCompatibility.h').read_text()
assert '@interface DownloadInlineButton : NSObject' in (root / 'src/Download/DownloadInlineButton.h').read_text()
launch = (root / 'src/Hooks/Launch.x').read_text()
assert 'layoutSubviews' not in launch and 'dispatch_once' in launch
assert '0.28' in launch and 'UIAccessibilityIsReduceMotionEnabled' in launch
assert 'animateRevealWithCompletion' not in (root / 'src/Hooks/AppLifecycle.x').read_text()
assert '[BHTManager cleanCache]' not in (root / 'src/Hooks/AppLifecycle.x').read_text()
assert 'tfn_vectorImageNamed' not in (root / 'src/Hooks/Theme.x').read_text()

# .strings are UTF-8 by platform requirement. Verify the Simplified Chinese
# text remains GBK-representable, and validate every locale as an Apple plist.
bundle = root / 'layout/Library/Application Support/BHT/BHTwitter.bundle'
for source in bundle.rglob('*.strings'):
    subprocess.run(['plutil', '-lint', str(source)], check=True, stdout=subprocess.DEVNULL)
zh = (bundle / 'zh_CN.lproj/Localizable.strings').read_text('utf-8')
''.join(c for c in zh if '\u3400' <= c <= '\u9fff' or '\u3000' <= c <= '\u303f').encode('gbk', errors='strict')
for title in ('使用网页登录', '搜索与发现', '时间线', '外观', '实验室', 'Grok'):
    assert title in zh
for source in (root / 'src/WebLogin').glob('*.m'):
    source.read_text('utf-8').encode('gbk', errors='strict')

# Execute the actual hook-installation guard against the macOS ObjC runtime.
with tempfile.TemporaryDirectory(prefix='nfb-runtime-test-') as temp:
    executable = str(Path(temp) / 'guard-test')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
                    '-I' + str(root / 'tests/stubs'), '-I' + str(root / 'src'),
                    str(root / 'src/Core/RuntimeCompatibility.m'),
                    str(root / 'tests/runtime_compatibility.m'), '-o', executable], check=True)
    subprocess.run([executable], check=True)
print('PASS: 11.98 base, inherited switch actions, all v7 pages, launch and scoped login regression checks')
