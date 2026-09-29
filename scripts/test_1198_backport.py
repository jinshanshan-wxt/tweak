#!/usr/bin/env python3
"""Read-only base and regression checks, before any remote compilation."""
import hashlib
import plistlib
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
# File hashes from stable a220172; works with the CI shallow checkout as well.
stable_hashes = {
    'Tweak.x': 'bc4b8c8f3f6499ac974d1e5fc10b04fab9cd02ddf4b32804cf7983738e5b35b8',
    'IOS26Compatibility.x': '1516732042a974aee12227d045c678cef4c4b715f95ada2ee2c3f1fbb813f971',
    'BHDownloadInlineButton.m': '621fc1801175dea282b3e5cdd74a336f06a9a329d5dcbdf02170ce3e45725c8e',
    'keychainfix/Tweak.x': '83c4864bbfd1243135d5bae25a023d381c83bbaaef0a3fd13ec95e313c792bb1',
}
for filename, expected in stable_hashes.items():
    assert hashlib.sha256((root / filename).read_bytes()).hexdigest() == expected, f'Stable crash fix modified: {filename}'
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
