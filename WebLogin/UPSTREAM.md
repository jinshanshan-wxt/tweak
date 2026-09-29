# Selective Twitter 11.98 backport

WebLoginViewController, WebSession (originally WebCreateTweet.x), WebXTID.js,
and the branding scripts derive from orionblur/NeoFreeBird at
1b24ee11908c9b3a1ec53938a4b5b085a56379f2 (AGPL-3.0, LICENSE in this directory).
The classic resource pack is the upstream p63f20.zip, pinned by SHA-256 in CI.

Application base: the user's stable release 1.0, Twitter 11.98, SHA-256
030bb98e1eb79b66884c83196ed9dd5ddae92719635fad5ba3e9f915a6767a8b.
All original application/framework Mach-O files and launch NIB/storyboard UI
are preserved byte-for-byte. Only the existing BHTwitter dylib is replaced;
there is no new binary injection and no 12.x executable.

The existing iOS 26 prefetch and inline-action crash fixes remain unchanged.
Web login is optional, uses an isolated WKWebView and the official X login site.
Request rewriting applies only to accounts explicitly logged in through this
flow, and only to enumerated HTTPS X/Twitter hosts. Sessions use device-local
Keychain storage. Existing accounts are not migrated automatically.

Settings: General -> Web login; Branding -> Classic Twitter bird.
Passkeys and some native account features may not work with cookie login.
CI compilation and archive verification do not replace testing on a device.
