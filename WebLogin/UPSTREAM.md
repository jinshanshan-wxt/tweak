# Twitter 11.98 full v7 settings and compatibility port

The complete src/ core, settings and feature hooks, WebXTID.js, localizations
and branding scripts derive from orionblur/NeoFreeBird at
1b24ee11908c9b3a1ec53938a4b5b085a56379f2 (AGPL-3.0, LICENSE in this directory).
The classic resource pack is the upstream p63f20.zip, pinned by SHA-256 in CI.
Unlike upstream's default packaging, all existing 11.98 alternate icons are
retained, including icons absent from the new classic pack.

Application base: the user's stable release 1.0, Twitter 11.98, SHA-256
030bb98e1eb79b66884c83196ed9dd5ddae92719635fad5ba3e9f915a6767a8b.
All original application/framework Mach-O files and launch NIB/storyboard UI
are preserved byte-for-byte. Only the existing BHTwitter dylib is replaced;
there is no new binary injection and no 12.x executable.

The existing iOS 26+ (including 27) table prefetch workaround remains unchanged.
The old inline-action download class is not linked: v7 downloads from the media
overflow menu instead, avoiding its private inline-layout metrics entirely.
Legacy root-level tweak/settings sources are retained for history but not built.
RuntimeCompatibility checks method existence AND argument/return ABI before
every v7 Logos hook install, against a manifest generated from the declarations.
The 11.98 font group and initial-login factory have explicit compatibility paths.
Settings switches have one valid target; all pages share an implemented handler.
The user rejected the substitute fade/zoom, which was not the classic Twitter
bird-mask reveal. All custom launch overlays, bitmaps and transition code have
been removed. The animated-launch feature gate is disabled unconditionally,
regardless of preferences saved by prior builds. The operating system's static
launch screen remains unchanged; an animated view created from cached native
state finishes its host callback immediately, without running the X reveal.
The pinned 11.98 native thunk was checked to accept a void(void) block.
The native 11.98 launch NIB is intentionally retained, not replaced by a 12.x NIB.
Startup no longer synchronously scans Documents/tmp or deletes arbitrary media.
Web login is optional, uses an isolated WKWebView and the official X login site.
Request rewriting applies only to accounts explicitly logged in through this
flow, and only to enumerated HTTPS X/Twitter hosts. Sessions use device-local
Keychain storage. Existing accounts are not migrated automatically.

Settings: General -> Web login. The removed custom launch has no settings toggle.
General also hides Money, News and Jobs by default, with individual toggles.
Their feature gates are no longer forced on when hidden, and the sidebar's
visible-panel snapshot claims the pinned 11.98 IDs (18/19/22), without changing the
actual tab array. Queries outside the drawer retain their original results.
The newer upstream's IDs must NOT be used: 11.98 uses 14 for Community Notes,
15 for Grok, 16 for Media, 17 for Premium, 18 for Jobs, 19 for Payments, 22 for
News. These were verified against +[T1PanelIdentity stringForPanelID:] in the
base framework, and regression checks audit its native string table directly.
All 14 v7 categories are included, including Appearance, Grok, Timelines, Chat,
Presets, Experimental and Debug. Controls for APIs absent from 11.98 cannot add
native 12.x-only capabilities (such as XChat or newer Grok creation surfaces).
Passkeys and some native account features may not work with cookie login.
CI compilation, actual macOS ObjC hook-guard tests, settings callback regression
checks and archive verification do not replace testing on an iOS 27 device.
