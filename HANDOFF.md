# Installation handoff

## Goal

Use the patched app as `/Applications/KakaoTalk.app`, replace the official app, and make the
patched app the Dock and URL-scheme target. Run this procedure on the destination Mac.
This document does not mean installation or default-handler configuration has already occurred.

## Identify both apps

- Official bundle identifier: `com.kakao.KakaoTalkMac`.
- Patched bundle identifier: `local.elsholtzia.KakaoTalkNoAds`.
- Patched display name: `KakaoTalk`.
- Supported patched version: 26.9.0, build 2006.

Read `Contents/Info.plist`; never identify the removal target by its display name alone.
Do not change the patched bundle identifier to the official identifier.

## Procedure

1. Verify the supplied archive checksum, if installing the separately prepared portable package.
2. Extract the package and verify the app identity and signature before removing anything.
3. Quit both apps without logging out.
4. If the installed app is the official app, move only that app to Trash through Finder.
   Keep Trash available for rollback. Let the user approve administrator prompts directly.
5. Install the patched app at `/Applications/KakaoTalk.app`.
6. Verify the signature and bundle identifier at the final path. Launch that exact path.
7. Let the user sign in directly. Never request a password or QR authentication secret in chat.
8. Replace stale Dock entries with the final installed app.
9. Configure and verify all four URL schemes listed below.
10. Verify the authenticated Friends, Chats, and More tabs and resize the window.

If the installed app already has the patched identifier, treat it as a patched-app update;
do not apply the official-app removal step blindly.

## Default URL handlers

The patched app declares `kakaotalk`, `kakaoopen`, `kakaoplus`, and `kakaoshare`.
Installing or renaming the app does not prove these defaults were changed.
Use the public `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:completion:)` API
for each scheme and wait for each completion. Let the user handle any system consent prompt.
Use `NSWorkspace.urlForApplication(toOpen:)` to query the resulting handler without sending a
message or opening an advertising link. Verify both the final path and bundle identifier.
Report a failure rather than assuming success. This repository does not apply these settings
automatically.

## Preserve data and security settings

Do not remove Library containers, group containers, Keychain items, attachments, or backups.
Do not use an app cleaner that also removes related user data.
The patched app uses separate storage. Official local history and settings are not automatically
migrated. Use the application's supported backup and restore process if needed.
Never copy another machine's login session or chat database as part of application packaging.

The ad-hoc app may be blocked on another Mac. Follow Apple's app-specific opening guidance
and let the user handle security decisions. Do not disable Gatekeeper or SIP, or strip quarantine
attributes in bulk. A managed Mac may prohibit installation.

## Completion report

Report the final app path, identifier, version, signature check, login and banner results,
Dock target, and the resolved path and identifier for each URL scheme.
List untested features and preserve the original app in Trash until rollback is no longer needed.
Do not report completion before verification.
