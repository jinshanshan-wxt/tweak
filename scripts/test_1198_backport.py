#!/usr/bin/env python3
"""Regression checks for the v7 settings/core port without changing the 11.98 app."""
import hashlib
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from hook_abi import render as render_abi

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'branding'))
import ipa_branding
from launch_asset import build_launch_asset
assert (root / 'src/Core/HookABI.h').read_text() == render_abi(), 'Hook ABI manifest is stale'
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
    # Pinned base's +[T1PanelIdentity stringForPanelID:] indexes this CFString
    # table. Catch accidental use of the newer upstream's different panel IDs.
    for panel_id, panel_name in {14: '__PANEL_BIRDWATCH', 15: '__PANEL_GROK',
                                 16: '__PANEL_Media', 17: '__PANEL_PREMIUMHUB',
                                 18: '__PANEL_JOBS', 19: '__PANEL_PAYMENTS',
                                 22: '__PANEL_NEWS'}.items():
        cfstring = struct.unpack_from('<Q', binary, 0x18ac3b0 + (panel_id - 1) * 8)[0] & 0xffffffff
        string_addr = struct.unpack_from('<Q', binary, cfstring + 16)[0] & 0xffffffff
        assert binary[string_addr:binary.index(b'\0', string_addr)].decode() == panel_name
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
media_downloads = (root / 'src/Hooks/MediaDownloads.x').read_text()
assert 'objc_allocateClassPair(baseClass, "NFBVideoDownloadActionItem", 0)' in media_downloads
assert 'class_addMethod(itemClass, @selector(enabled)' in media_downloads
assert 'return !((BOOL (*)(id, SEL))implementation)(item, isDisabled)' in media_downloads
assert '![item isKindOfClass:%c(TFNActionItem)]' in media_downloads
assert '+ (BOOL)enabled { return YES; }' in media_downloads
assert '- (BOOL)enabled { return [super isEnabled]; }' in media_downloads
launch = (root / 'src/Hooks/Launch.x').read_text()
assert launch.count('%hook') == 1 and launch.count('- (void)') == 3
assert '((UIView *)self).hidden = YES' in launch
assert 'if (completion) ((void (^)(void))completion)()' in launch
assert '%orig' not in launch.split('- (void)animateRevealWithCompletion:', 1)[1]
assert 'NFBLaunchMask.png' in launch and 'UIAccessibilityIsReduceMotionEnabled()' in launch
assert '![BHTSettings boolForKey:@"padlock"]' in launch, 'Do not snapshot private content behind the app lock'
composition = (root / 'src/Launch/NFBLaunchComposition.m').read_text()
assert 'masked.mask = _maskLayer' in composition
assert 'masked.backgroundColor = white' in composition and 'root.backgroundColor = blue' in composition
assert 'CAKeyframeAnimation' in composition and 'NFBLaunchProgress(t)' in composition
assert 'CAFrameRateRangeMake' in composition
assert all(token not in composition for token in ('CADisplayLink', 'NSTimer', 'animateWithDuration'))
session = (root / 'src/Launch/NFBClassicLaunchSession.m').read_text()
assert 'maximumFramesPerSecond' in session
assert session.count('snapshotViewAfterScreenUpdates:YES') == 1
assert '[_window addSubview:_cover]' in session
assert 'root.layer.mask =' not in session and 'root.transform =' not in session
assert 'UIApplicationWillResignActiveNotification' in session
assert 'UIAccessibilityReduceMotionStatusDidChangeNotification' in session
assert '_finishing = YES' in session and '[weakSelf finish]' in session
assert session.index('[_cover removeFromSuperview]') < session.index('[_completion finish]')
assert re.search(r'@"key": @"classic_launch_animation",\s*@"default": @YES', registry)
assert 'blue_launch_screen' not in registry and 'disable_launch_transition' not in registry
switches = (root / 'src/Hooks/FeatureSwitches.x').read_text()
assert re.search(r'if \(\[key isEqualToString:@"app_launch_animated_launch_screen_enabled"\]\) \{\s*return @\(\[BHTSettings boolForKey:@"classic_launch_animation"\]\);', switches)
packager = (root / 'scripts/rebuild_1198.py').read_text()
assert 'build_launch_asset' in packager and 'classic-bird-mask-reveal-three-layers' in packager
assert switches.index('NFBSidebarPreferenceForFeature(key)') < switches.index('@"ai_trends_ios_enable_news_tab"')
assert 'return ![BHTSettings boolForKey:@"hide_money_sidebar"]' in switches
assert 'return NFBSidebarClaimPanels(panelIDs, hidden)' in switches
assert 'DashPanelIDQuery = saved' in switches and '@finally' in switches
for key in ('hide_money_sidebar', 'hide_news_sidebar', 'hide_jobs_sidebar'):
    assert re.search(r'@"key": @"' + key + r'", @"default": @YES', registry)
assert 'animateRevealWithCompletion' not in (root / 'src/Hooks/AppLifecycle.x').read_text()
assert '[BHTManager cleanCache]' not in (root / 'src/Hooks/AppLifecycle.x').read_text()
assert 'tfn_vectorImageNamed' not in (root / 'src/Hooks/Theme.x').read_text()

# .strings are UTF-8 by platform requirement. Verify the Simplified Chinese
# text remains GBK-representable, and validate every locale as an Apple plist.
bundle = root / 'layout/Library/Application Support/BHT/BHTwitter.bundle'
for source in bundle.rglob('*.strings'):
    subprocess.run(['plutil', '-lint', str(source)], check=True, stdout=subprocess.DEVNULL)
zh = (bundle / 'zh_CN.lproj/Localizable.strings').read_text('utf-8')
localized_keys = set(re.findall(r'^"([^"]+)"\s*=', zh, re.M))
for setting in re.findall(r'@\{([^{}]+)\}', registry, re.S):
    pref = re.search(r'@"key":\s*@"([^"]+)"', setting)
    if not pref:
        continue
    explicit = re.search(r'@"titleKey":\s*@"([^"]+)"', setting)
    title_key = explicit[1] if explicit else pref[1].upper() + '_TITLE'
    assert title_key in localized_keys, f'Untranslated setting: {title_key}'
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
    sidebar_executable = str(Path(temp) / 'sidebar-test')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
                    '-I' + str(root / 'src'), str(root / 'src/Core/NFBSidebarPolicy.m'),
                    str(root / 'tests/sidebar_policy.m'), '-o', sidebar_executable], check=True)
    subprocess.run([sidebar_executable], check=True)
    mask = build_launch_asset(root / 'packages/classic-resource-pack.zip', Path(temp),
                              ipa_branding._ensure_resvg(Path(temp)))
    launch_executable = str(Path(temp) / 'launch-test')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
                    '-framework', 'QuartzCore', '-framework', 'CoreGraphics', '-framework', 'ImageIO',
                    '-I' + str(root / 'src'), str(root / 'src/Launch/NFBLaunchComposition.m'),
                    str(root / 'tests/launch_composition.m'),
                    '-o', launch_executable], check=True)
    subprocess.run([launch_executable, str(mask)], check=True)
print('PASS: 11.98 base, inherited switch actions, all v7 pages, launch and scoped login regression checks')
