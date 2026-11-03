# KakaoTalk NoAds for Mac

A version-locked Python tool that creates a separate KakaoTalk copy without main-window banners.
Git contains the patcher and installation instructions. A prebuilt experimental app is available
as a separate GitHub Release asset. This is an unofficial modified client, not a release from Kakao.

## Download

Download the app ZIP and its SHA-256 file from
[Releases](https://github.com/nonpapfif/kakaotalk-noads-mac/releases).
Extract the ZIP, read `INSTALL.md`, and follow [HANDOFF.md](HANDOFF.md).
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

Follow [HANDOFF.md](HANDOFF.md). Preserve chat data and keep a reversible rollback path.
A successful signature check is not proof of notarization, functional compatibility, or safety.
No application binaries are tracked in Git. No user data, credentials, or local diagnostic reports
are included in Git or in the release package.
No redistribution license for the original KakaoTalk application is granted by this repository.

## References

- [Apple: Open apps safely](https://support.apple.com/en-gb/102445)
- [Apple: Default app for URL schemes](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))
