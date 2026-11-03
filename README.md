# KakaoTalk NoAds + Reconnect for Mac

An unofficial, version-locked KakaoTalk 26.9.0 build with no main-window banners and a
sidebar button that brings the desktop session back to this Mac. It does not enable
simultaneous desktop sessions.

## Download and install

Download **one file**:

[Download the self-contained installer DMG](https://github.com/nonpapfif/kakaotalk-noads-reconnect/releases/download/v26.9.0-reconnect.6/KakaoTalk-NoAds-Reconnect-Installer-26.9.0.dmg)

1. Open the DMG and double-click **Install KakaoTalk**.
2. Finish drafts, then click **Update KakaoTalk** for an existing reconnect build,
   or **Install and Replace KakaoTalk** for a first installation.
3. Approve administrator or default-link prompts if macOS asks.
4. The installer opens `/Applications/KakaoTalk.app`. Sign in directly with
   **Keep me logged in** enabled if needed.

No Python, Xcode, Terminal commands, separate app ZIP, or additional network download is
required on the destination Mac. A [ZIP of the same installer](https://github.com/nonpapfif/kakaotalk-noads-reconnect/releases/download/v26.9.0-reconnect.6/KakaoTalk-NoAds-Reconnect-Installer-26.9.0.zip)
is also available. Extract it before opening the installer.

**First-launch approval:** these builds are ad-hoc signed, not Kakao-signed or
Apple-notarized. macOS may block the installer until you explicitly allow it in
System Settings > Privacy & Security > Open Anyway. Approval may also be required for
KakaoTalk itself. The installer does not disable Gatekeeper or remove quarantine attributes.
An organization-managed Mac may enforce additional restrictions.

Checksums and the standalone app ZIP are on the
[release page](https://github.com/nonpapfif/kakaotalk-noads-reconnect/releases/tag/v26.9.0-reconnect.6).

## What the installer does

- Verifies its bundled payload checksum, app identity, version, executable/helper hashes,
  and code signature before touching the installed application.
- Asks running official/NoAds/reconnect clients to quit. If they remain open, installation
  stops without replacing the app. It does not force-quit or discard drafts.
- Backs up the existing app to `/Applications/KakaoTalk Backups/` before replacement.
- Installs the bundled `KakaoTalk.app` at `/Applications/KakaoTalk.app`.
- Restores the previous app if the replacement transaction fails.
- Replaces stale KakaoTalk Dock entries and verifies the new target.
- Sets and verifies `kakaotalk`, `kakaoopen`, `kakaoplus`, and `kakaoshare` defaults.
- Opens the app and saves a local installation report and Dock backup under
  `~/Library/Application Support/KakaoTalk NoAds Installer/`.

If link approval is declined, the app remains installed and the installer reports which
links were not configured. It does not silently claim full success.
The bundled app is fixed at 26.9.0/build 2006; the GUI refuses a newer installed version.
The installer refuses an unexpected application identity at the destination.

## Updating an existing patched app

Run the new installer over the existing reconnect app. It detects the same application
identity and offers **Update KakaoTalk**. No uninstall or data migration is needed.
Even when the KakaoTalk version/build is unchanged, a different executable or helper hash
triggers a backed-up replacement. An identical payload is left in place.
Existing reconnect data and saved login remain in the same container; expired authentication
can still require manual sign-in. The installer does not launch a background update watcher.

### In-app updates

This release adds **Settings > Check for Updates...**. Earlier releases need this installer
once to gain in-app downloads. Checking and downloading happen only when requested.
If a newer reconnect release is available, choose **Download Update**. The app verifies
GitHub asset SHA-256 digests, the update manifest, app identity/version, and code signature
before showing **Update ready**. Choose **Restart Now** or **Later**. The menu changes to
**Restart to Update...** while an update is staged. Checking, download, errors and restart
readiness share one persistent window; its text and buttons change without replacing it.

A staged update is applied after a normal app quit, including when you choose Later and
quit afterward. A separate helper waits for the parent process exit using a kernel event;
it does not poll or force-quit KakaoTalk. It backs up and replaces the app using the same
transaction as the installer, then relaunches it. Existing data containers and Keychain
entries are untouched. Administrator approval may be requested by macOS.

Update trust relies on HTTPS and this GitHub repository's release/asset metadata. These
apps remain ad-hoc signed; checksums are not an independent publisher signature. There is
no background update checking, restart-free code replacement, or downgrade support.
Forced termination, crashes, logout/shutdown, and interrupted network access may leave an
update staged for a later normal quit. Failed replacement retains/restores the previous
app; its backup is under `/Applications/KakaoTalk Backups/`.

## Chat data and login

The installer never deletes Library containers, group containers, Keychain entries,
attachments, or chat backups. **Keeping data files does not automatically migrate history
between application identities.**

| App | Bundle identity | Data behavior |
| --- | --- | --- |
| Official KakaoTalk | `com.kakao.KakaoTalkMac` | Its data is retained separately. |
| Older NoAds build | `local.elsholtzia.KakaoTalkNoAds` | Its data is retained separately. |
| This reconnect build | `local.elsholtzia.KakaoTalkReconnectExperiment` | Existing reconnect data is reused. |

The reconnect identity is retained intentionally, despite its historical name, so existing
users keep the data container they tested. Only the app's visible name is `KakaoTalk`.
For history migration from another identity, use KakaoTalk's supported backup/restore
separately. Do not use an app cleaner. Do not copy another Mac's login/session databases.
No credentials, sessions, or chat data are distributed in the installer or app archive.
Never send your password to an agent or put it in this repository.

## Reconnect on this Mac

Click the circular-arrow button above Notifications in the left sidebar, or choose
**Session > Reconnect on This Mac**. The app requests the desktop session once using its
native saved-authentication flow. It then rebinds existing chat models to the current data
store and refreshes open chats after a successful native connection event.

The sidebar button shares the original sidebar parent, 36-point hit area, center alignment,
and 40-point spacing. Its custom vector is scaled to 90% inside that area. Normal, hover,
pressed, active/inactive, and light/dark colors follow the original sidebar asset values.
A spinner and inline status overlay show request progress. An already-connected client
shows **Already connected** without starting another login. The overlay uses the original
mute popup's sRGB gray (81, 81, 81) and alpha (224/255). The icon uses a 1.4-point stroke
and a 0.3-point optical shift to the right.
No background polling or automatic takeover is added.

Another desktop may be logged out. Its unmodified auto-recovery can take the session back.
Using this build on both Macs avoids that specific automatic-recovery path; two-Mac use of
the final installer remains unverified. If saved authentication expires, sign in manually.
**Automatic recovery is disabled**, including after ordinary network interruptions, so the
button may also be needed when a network connection returns. While another Mac owns the
session, old chat content can remain visible without being connected.

## Verification and limits

The owner verified on Apple Silicon: main-window ad removal; manual session takeover;
sending from a previously opened chat; live chat-content updates after model rebinding;
sidebar appearance; and local replacement as the main application with Dock/URL defaults.

The universal installer was compiled for arm64 and x86_64 with macOS 13 as its minimum.
Intel runtime, a clean second-Mac installer run, all auxiliary windows, calls, file transfer,
sharing extensions, startup items, and long-term behavior have not been fully verified.
Dark-mode colors were derived from original assets; complete dark-mode visual QA is pending.
This is not a block of all advertising traffic. Channel ads delivered as messages are outside
scope. There is no automatic compatibility with future KakaoTalk versions or App Store updates.
The app retains sandbox and hardened runtime, removes the original App Group entitlement,
and disables library validation for the added helper. Official signing cannot be retained.

## Build from source

Run the commands below from the repository root.
Building is optional. Development requires macOS, Command Line Tools, and Python 3.9+.
The destination user only needs the prebuilt installer.

```sh
python3 -m tools.build_reconnect --source /path/to/official/KakaoTalk.app --output /tmp/KakaoTalk.app
python3 -m tools.build_installer --app /tmp/KakaoTalk.app --output /tmp/kakao-installer
```

The source must be the unmodified official **26.9.0 build 2006** executable with SHA-256
`456e1a3ed7a87168888bdb8c6e4894764a028e62c0af68562a760d9909d2bb65`.
The builder checks the hash and original bytes at every patch site. It copies no user data
and removes the copied App Store receipt. Do not reuse offsets on another version.

`tools/patch_kakaotalk.py` remains available for the historical ad-only build. Its output uses
the older NoAds identity and does not include reconnect. The prebuilt installer uses the
owner-tested reconnect binary; a fresh end-to-end build from the official source has not
been revalidated for this release.

## Restore the previous app

Quit the current KakaoTalk. Move `/Applications/KakaoTalk.app` aside, then copy the desired
backup from `/Applications/KakaoTalk Backups/` to `/Applications/KakaoTalk.app`.
Keep all Library data. Update the Dock and default URL handlers to the restored identity.

## Updating to future KakaoTalk versions

See [update maintenance guide](docs/UPDATES.md) for the version-profile maintenance workflow and acceptance
checklist. Only the reviewed 26.9.0/build 2006 source is currently approved. Future versions
must get their own reviewed profile and functional validation before release.
The tools refuse unknown versions and hashes. The next installer can use its own payload
version, keep the same data identity, and refuse downgrades. In-app delivery still requires
a reviewed release and does not guarantee compatibility with an untested official version.

## Repository layout

- `docs/`: installation handoff, validation records, and update maintenance.
- `tools/`: Python build and read-only inspection commands; run with `python3 -m tools.<name>`.
- `reconnect/`: native reconnect helper, vector assets, and Mach-O load-command injection.
- `installer/`: native installer UI and application replacement transaction.
- `updater/`: external helper and staged-payload validation for updates after exit.
- `compatibility/`: source validation and reviewed version profiles.
- `tests/`: compatibility and disposable installer transaction checks.

See the [installation handoff](docs/HANDOFF.md) and [validation record](docs/VALIDATION.md).
The default development branch is `master`.
