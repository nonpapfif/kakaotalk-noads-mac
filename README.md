# KakaoTalk NoAds for Mac

A version-locked Python tool that creates a separate KakaoTalk copy without main-window banners.
Git contains the patcher and installation instructions. A prebuilt experimental app is available
as a separate GitHub Release asset. This is an unofficial modified client, not a release from Kakao.

## Download

This README is the single installation and handoff entry point for users and coding agents.
Download the [app ZIP](https://github.com/nonpapfif/kakaotalk-noads-mac/releases/download/v26.9.0-patch.1/KakaoTalk-NoAds-Mac-26.9.0.zip)
and [SHA-256 file](https://github.com/nonpapfif/kakaotalk-noads-mac/releases/download/v26.9.0-patch.1/KakaoTalk-NoAds-Mac-26.9.0.sha256)
from the [experimental release](https://github.com/nonpapfif/kakaotalk-noads-mac/releases/tag/v26.9.0-patch.1).
Follow the complete procedure below. Building from source is optional, not an installation step.
The archive contains `KakaoTalk.app`, without chat history, login sessions, or the original
App Store receipt. Sign in on the destination Mac. First launch on another Mac is unverified.

## Supported source

- KakaoTalk 26.9.0, build 2006.
- Original executable SHA-256: `456e1a3ed7a87168888bdb8c6e4894764a028e62c0af68562a760d9909d2bb65`.
- The source must be an unmodified application supplied separately by the user.
- A newer version or an already patched application is rejected.

## Build

Requires macOS, Python 3.9 or later, and the `codesign` command.
No third-party Python packages are required.

```sh
python3 patch_kakaotalk.py \
  --source /path/to/original/KakaoTalk.app \
  --output /path/to/output/KakaoTalk.app
```

The output path must not exist. The source is never overwritten.
The app keeps the display name `KakaoTalk` but uses bundle identifier
`local.elsholtzia.KakaoTalkNoAds` and a separate sandbox container.
The output is signed ad hoc, not signed by Kakao or notarized by Apple.
The original app-group entitlement is removed. Library validation is disabled for the copy;
App Sandbox and Hardened Runtime remain enabled.
The builder copies application files only. It does not copy login sessions or chat databases.
Unlike the separately prepared portable package, the builder does not remove the source app's
App Store receipt. Do not confuse a local build with the receipt-free portable package.

## Verification and limits

The initial patch was tested on Apple Silicon with macOS 26.6.2.
Main-window banners and their reserved space were absent in Friends, Chats, and More.
Window resizing was also checked. The patch introduces no monitoring process or polling timer.
Intel machine code is patched, but Intel hardware has not been tested.
Lock mode, calls, file transfer, sharing extensions, login items, and long-term compatibility
remain unverified. Features relying on the original app group may be affected.
Channel advertisements delivered as chat messages are outside the scope of this patch.
This is not a verified block of all advertising network requests.
There is no automatic update detection or automatic support for future versions.

## Install and replace the official app

The goal is to use the patched app as `/Applications/KakaoTalk.app`, with the display name
`KakaoTalk`, and make it the Dock and KakaoTalk URL-scheme target on the destination Mac.
This procedure requires local access to that Mac. A GitHub link does not install anything by itself.

### Identify the apps

| App | Bundle identifier |
| --- | --- |
| Official app | `com.kakao.KakaoTalkMac` |
| Patched app | `local.elsholtzia.KakaoTalkNoAds` |

Read `Contents/Info.plist`; do not identify the removal target by its name alone.
Do not change the patched identifier to the official identifier. Storage depends on this identity.

### Installation procedure

1. Download both release assets linked above. In their download directory, run
   `shasum -a 256 -c KakaoTalk-NoAds-Mac-26.9.0.sha256` and require an `OK` result.
2. Extract the ZIP using a macOS-compatible archive utility that preserves app symlinks.
   Verify the extracted app identity, version 26.9.0 / build 2006, and signature before removal.
3. Check whether the existing app contains local history that the user needs. Preserve it;
   separate patched storage does not automatically inherit official local history.
4. Quit both apps without logging out. If the installed app is the official app, move only
   that application to Trash through Finder. Keep it recoverable for rollback. The user must
   handle any administrator prompt directly. Do not empty Trash or remove related user data.
5. Move the extracted `KakaoTalk.app` to `/Applications/KakaoTalk.app`.
   If an app with the patched identifier is already installed, treat this as a patched-app update
   rather than blindly applying the official-app removal step.
6. Verify the final path and bundle identifier. Run
   `codesign --verify --deep --strict /Applications/KakaoTalk.app` and check its exit status.
   A successful check is not proof of notarization, compatibility, or safety.
7. Launch that exact installed path. Let the user sign in directly on the destination Mac.
   Never request a password or QR authentication secret in chat.
8. Replace stale Dock entries with the app at the final installed path, keeping the name `KakaoTalk`.
9. Configure and verify the four default URL handlers described below.
10. Verify Friends, Chats, More, and window resizing. Confirm that the main-window banner and
    reserved space are absent. Do not send a message or click an advertisement as a test.

If installation fails, retain the original app for restoration. Do not delete chat data to fix
an installation or authorization failure.

### Default URL handlers

The app declares `kakaotalk`, `kakaoopen`, `kakaoplus`, and `kakaoshare`.
Installing or renaming it does not prove that these default handlers changed.
Use the public `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:completion:)` API
for each scheme with application URL `/Applications/KakaoTalk.app`.
Wait for each asynchronous result and let the user handle any system consent prompt.
Use `NSWorkspace.urlForApplication(toOpen:)` to query the resulting handler without opening
an advertising or message-sending link. Verify both the returned path and bundle identifier.
Report failures instead of assuming success. The downloaded app and patcher do not configure
these defaults automatically; the installer or coding agent must do this on the destination Mac.

### Preserve data and security settings

Do not remove Library containers, group containers, Keychain items, attachments, or backups.
Do not use an app cleaner that also deletes related data. Use KakaoTalk's supported backup and
restore process separately if history migration is needed. Never copy another Mac's session
or chat database as part of application packaging.

The ad-hoc app may be blocked on another Mac. Follow Apple's app-specific opening guidance
and let the user handle security decisions. Do not disable Gatekeeper or SIP, or strip quarantine
attributes in bulk. A managed Mac may prohibit installation. Record the actual blocker if so.

### Completion report

Report the final path, bundle identifier, version, original-app Trash status, signature check,
login and banner results, Dock target, and the resolved path and identifier for each URL scheme.
List unverified features separately. Do not report completion before checking these results.

No application binaries are tracked in Git. No user data, credentials, or local diagnostic reports
are included in Git or in the release package. No redistribution license for the original
KakaoTalk application is granted by this repository.

## References

- [Apple: Open apps safely](https://support.apple.com/en-gb/102445)
- [Apple: Default app for URL schemes](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))
