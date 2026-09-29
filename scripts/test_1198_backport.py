#!/usr/bin/env python3
"""Read-only base and regression checks, before any remote compilation."""
import hashlib
import plistlib
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
stable = 'a2201724a9584482cd2cf7c66baaf18ee5df12c8'
for filename in ('Tweak.x', 'IOS26Compatibility.x', 'BHDownloadInlineButton.m', 'keychainfix/Tweak.x'):
    original = subprocess.check_output(['git', 'show', f'{stable}:{filename}'], cwd=root)
    assert (root / filename).read_bytes() == original, f'Stable crash fix modified: {filename}'
with zipfile.ZipFile(root / 'packages/base-11.98-stable.ipa') as archive:
    info = plistlib.loads(archive.read('Payload/Twitter.app/Info.plist'))
    assert info['CFBundleShortVersionString'] == '11.98'
    binary = archive.read('Payload/Twitter.app/Frameworks/T1Twitter.framework/T1Twitter')
    for selector in ('initWithUsername:userID:', 'updateUserInfoAndCredentialsWithToken:secret:username:',
                     'private_startLoginFlowWithSender:', 'makeOnboardingViewControllerWithOCFFallback:completion:',
                     'viewAccount:animated:', 'addAccount:', 'saveSharedTwitter'):
        assert selector.encode() + b'\0' in binary, f'Missing 11.98 selector: {selector}'
session = (root / 'WebLogin/WebSession.x').read_text()
assert 'postingUserID = userIDFromTwid(WebTwid)' not in session
assert '[hosts containsObject:url.host.lowercaseString]' in session
assert 'isCreateTweet && nativeCreateTweetInterceptEnabled() && cookieReplication' in session
assert 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in session
assert 'BHTSettings' not in session
for path in (root / 'WebLogin').glob('*.m'):
    # Format-required UTF-8 source, but all Simplified Chinese added by this patch
    # must also be representable in GBK (the user's document preference).
    path.read_text('utf-8').encode('gbk', errors='strict')
for locale in ('en', 'zh_CN', 'zh-Hant'):
    source = root / f'layout/Library/Application Support/BHT/BHTwitter.bundle/{locale}.lproj/Localizable.strings'
    subprocess.run(['plutil', '-lint', str(source)], check=True)
print('PASS: verified stable 11.98 base, retained crash fixes, guarded login and scoped credentials')
