# Release validation: 26.9.0-reconnect.1

Validation date: 2026-11-03. Host: Apple Silicon macOS.

## Verified

- The owner tested manual desktop-session takeover using saved native authentication.
- Existing chat windows can send and update after their models and data-store observer
  subscriptions are rebound. One open chat model was explicitly confirmed.
- The 36-point custom sidebar button shares the Notifications button's `BDView` parent.
  Settings, Notifications, and Reconnect have 40-point vertical spacing and the same center.
- The inner vector is scaled to 90%; active and inactive appearance were observed.
- The universal installer compiles for arm64 and x86_64 and passes code-signature verification.
- Three install-helper tests passed against disposable directories with spaces and apostrophes:
  backup/replacement plus idempotence, wrong-payload-hash rejection, and unexpected-target rejection.
  The old app sentinel and separate chat-data sentinel were preserved.
- The real installer UI completed its matching-version reinstall path on the owner's Mac.
  The app-file replacement was skipped because it already matched the payload.
  Graceful termination, payload validation, Dock update/verification, all four URL handler
  settings/verifications, local report generation, and app relaunch completed successfully.
- Installer UI layout was inspected before running installation.
- The standalone app archive was extracted again and its signature and executable hash verified.
- The DMG passed its checksum check and was mounted read-only. The embedded installer
  signature and executable hash matched the local build; the volume was then detached.

## Not yet verified

- A clean destination Mac installation and its Gatekeeper/user-consent flow.
- Actual administrator elevation on a protected `/Applications` destination.
- A simulated failure after the old bundle has moved; rollback is implemented and reviewed,
  but that failure point was not injected in testing.
- Intel runtime, all auxiliary windows, calls, file transfer, sharing extensions, startup
  items, complete dark-mode visual matching, and long-term stability.
- A fresh end-to-end source rebuild from the original official app for this release.
  Prebuilt payloads use the owner-tested app. Source build tools check the official version/hash.

## Reproduce installer transaction checks

These tests do not replace `/Applications/KakaoTalk.app` or read user chat databases.
They use the signed app as a read-only installation source and create temporary destinations.

```sh
KAKAO_TEST_APP=/Applications/KakaoTalk.app python3 -m unittest discover -s tests -v
```

Do not mistake preserved old data containers for automatic chat-history migration.
This release intentionally retains the reconnect bundle identity. It supports session
switching, not simultaneous desktop sessions, and disables automatic recovery.

## Version-profile maintenance tooling

The follow-up maintenance change adds an approved 26.9.0/build 2006 profile, a read-only
candidate inspector, version-independent installer payload metadata and downgrade refusal.
Eleven checks passed, including unknown-version/hash rejection, unapproved-profile rejection,
output-identity preservation, overlapping-patch rejection, path validation and installer
backup/idempotence/incorrect-payload safeguards.
The modified installed app was correctly rejected as a source for repatching.
No newer official app was patched or functionally validated. This is maintenance
infrastructure, not a declaration of support for a future release or an in-app updater.


## Inactive-window hover fix: 26.9.0-reconnect.2

The owner reported that the reconnect button did not show its hover background while
KakaoTalk was inactive. The tracking area incorrectly used `NSTrackingActiveInActiveApp`.
It now uses `NSTrackingActiveAlways`; drawing still uses the existing inactive-hover colors.
The helper compiled for both architectures and the installed main app passed signature checks.
The owner confirmed that hovering the reconnect icon now shows its background while the
KakaoTalk window is behind another app. Reconnect behavior and data identity were unchanged.
The updated installer also includes the version-profile-aware payload metadata introduced
by the maintenance tooling. Older release assets remain unchanged.

## Reconnect progress and visual feedback

The owner confirmed both already-connected feedback and session takeover feedback.
The native `BCLocoClient.loggedIn` state avoids waiting for a new login event when the
client is already connected. Request-scoped callbacks ignore stale requests, and a
60-second deadline ends the progress indicator without retrying.

The owner approved the centered overlay text/spinner, 1.4-point icon stroke, 0.3-point
optical adjustment, and matching popup tone. The overlay uses a custom translucent view
with sRGB (81, 81, 81), alpha 224/255, sampled from the original mute popup image.
The helper compiled for both architectures, and the installed app passed code-signature
verification. These source changes are newer than the published reconnect.2 assets.

## Hide reconnect controls on the login screen

The helper now attaches the sidebar button only when the native Notifications and Settings
buttons exist under the same parent. Otherwise it removes the custom button and feedback
overlay instead of attaching them directly to the window content. The owner confirmed the
installed fix. Friend-list duplication remains under investigation; temporary diagnostics
are not included in repository source.

## Installer refresh: 26.9.0-reconnect.3

The release payload is rebuilt from the current native helper source, without temporary
friend-list diagnostics. The app retains the existing reconnect bundle identity.
The installer detects an existing reconnect app and labels the action Update KakaoTalk.
Replacement still depends on executable/helper hashes, including at the same app version.

Twelve automated checks passed against the signed release payload. The added upgrade check
uses a separately signed, different helper at the same application version and verifies
replacement, the previous helper in the app backup, and a preserved separate data sentinel.
This is a disposable transaction test, not a clean second-Mac GUI upgrade validation.

The installer GUI was opened on the owner's Mac. It displayed Update KakaoTalk and
explained reuse of existing reconnect login/chat data. Installation was not run through
this refreshed GUI. Both payload archives matched the release executable/helper hashes.
The standalone archive was extracted and its app signature verified; the installer
signature and DMG checksum also passed verification.

## Staged in-app updates: 26.9.0-reconnect.4

The Settings menu now checks GitHub releases and downloads an update only after user action.
GitHub asset digests authenticate the downloaded manifest/archive within the HTTPS GitHub
repository trust boundary. This is not an independent publisher-signature scheme.
The main app verifies checksums, identity, version and signature before persisting a pending
update. It stays open until the user restarts or normally quits. A separate helper waits on
a kernel process-exit event, revalidates the payload, and uses the installer transaction.

Twenty-one automated checks cover compatibility, same-version patch replacement, data
sentinel preservation, rejection of corrupt/missing/older/incorrect-identity payloads,
and the app/helper sandbox signing policy. A fault-injected final signature check verified
that the transaction restores the previous app after replacement and removes staging.
The external helper is separately signed without sandbox entitlements; the main app retains
its sandbox and existing data identity. Both helpers compile for arm64 and x86_64.

A real in-app download and restart on the owner's Mac is pending at publication.
Administrator elevation, app-data access consent on other Macs, OS logout/shutdown timing,
Intel runtime, and clean second-Mac end-to-end updating remain unverified.

## Sandbox launch-document fix: 26.9.0-reconnect.5

The owner's real download of reconnect.4 reached the verified pending-update state.
Its restart helper then received no command-line arguments through the sandboxed
NSWorkspace launch path and stopped before changing the app. The old app was reopened.

The helper now receives a Launch.plist document through NSWorkspace.openURLs and the
NSApplicationDelegate document-open callback. A native launch probe delivered the document
and reached staged-app validation; the intentionally missing app was rejected before
replacement. Twenty-one automated checks also pass against the reconnect.5 payload.
The owner's retry completed the real sandboxed download and restart flow. The installed
app reports reconnect.5 and matches the published executable/helper SHA-256 values. Its
deep strict signature check passed, the /Applications process relaunched, the pending
pointer was removed, and the updater report records the previous-app backup and no
failures for any of the four default URL handlers. No chat or login data was copied or
deleted by the updater. Clean second-Mac and administrator-elevation coverage remain pending.

## Continuous update window: 26.9.0-reconnect.6

A single retained native panel now displays checking, availability, downloading, readiness
and errors. Only the text, progress indicator and button action change. A separate
sandboxed UI preview used the production updater code to download a real GitHub payload.
The native accessibility window and button remained the same between Download Update
and Restart Now, and the ready layout was inspected visually. Both architectures compile.
The owner's main app received the UI change and passed signature verification. The
previously verified download/validation/replacement protocol is unchanged.
