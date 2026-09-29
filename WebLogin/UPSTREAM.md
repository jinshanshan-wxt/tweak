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
RuntimeCompatibility checks method existence before every v7 Logos hook install.
The 11.98 font group and initial-login factory have explicit compatibility paths.
Settings switches have one valid target; all pages share an implemented handler.
The classic launch uses one cached glyph and a bounded 0.28s zoom/fade; it does
not mutate all subview backgrounds during layout or run the original X mask.
The native 11.98 launch NIB is intentionally retained, not replaced by a 12.x NIB.
Startup no longer synchronously scans Documents/tmp or deletes arbitrary media.
Web login is optional, uses an isolated WKWebView and the official X login site.
Request rewriting applies only to accounts explicitly logged in through this
flow, and only to enumerated HTTPS X/Twitter hosts. Sessions use device-local
Keychain storage. Existing accounts are not migrated automatically.

Settings: General -> Web login; Branding -> Blue launch screen.
All 14 v7 categories are included, including Appearance, Grok, Timelines, Chat,
Presets, Experimental and Debug. Controls for APIs absent from 11.98 cannot add
native 12.x-only capabilities (such as XChat or newer Grok creation surfaces).
Passkeys and some native account features may not work with cookie login.
CI compilation, actual macOS ObjC hook-guard tests, settings callback regression
checks and archive verification do not replace testing on an iOS 27 device.
