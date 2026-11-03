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
