# Development guide

## Source and release status

The published installer is reconnect.7. Source also contains the local Hold transport and
network-gate candidate preserved before the module cleanup on 2026-11-04. The candidate has
automated coverage, but its effect on long-idle session ownership across two Macs is unverified.
The module cleanup does not install an app or publish a release.

The candidate still embeds the existing reconnect.7 profile tag. A matching tag alone does
not prove that a local helper matches the published binary. Compare helper hashes. Before a
future release, assign a new reviewed patch tag and complete the acceptance checklist in
[UPDATES.md](UPDATES.md). Do not replace published reconnect.7 assets with this candidate.

## Module responsibilities

| Module | Responsibility |
| --- | --- |
| `compatibility/` | Validate reviewed profiles, stable app identity, and official source hashes. |
| `reconnect/SessionReconnect.m` | Own session hooks, Hold/reconnect transitions, and chat-model refresh. |
| `reconnect/SessionDisconnectPolicy.h` | Decide which native disconnects preserve the authenticated UI. |
| `reconnect/SessionNetworkGate.{h,m}` | Gate the tested socket and URLSession paths during Hold. |
| `reconnect/SessionReconnectViews.{h,m}` | Draw the sidebar button and lay out feedback text/spinner. |
| `reconnect/AppUpdater.{h,m}` | Own the in-app update window, downloads, and helper launch. |
| `tools/build_support.py` | Compile arm64/x86_64 Swift executables with the existing macOS 13 target. |
| `tools/build_reconnect.py` | Validate the official source, patch a copy, and build/sign its helpers. |
| `tools/build_updater.py` | Assemble and sign the external updater app. |
| `tools/build_installer.py` | Validate a patched payload and package installer/update artifacts. |
| `installer/` | Present installation UI and perform backed-up app replacement. |
| `updater/` | Validate staged payloads and apply them after the parent app exits. |

The session controller owns request timing, Hold state, and feedback dismissal. The views
own drawing, hover tracking, spinner creation, and feedback layout. Their interface exposes
only the button's busy/Hold state and the feedback view's message-display operation.

Installer and updater builds share one Swift compilation function. The updater retains its
warnings-as-errors setting. App identity, source guards, manifest fields, patch bytes,
signing order, and command-line entry points stay unchanged.

## Local checks

Development requires macOS, Command Line Tools, and Python 3.9+. No third-party Python
packages are required by the build tools or test suite. Run commands from the repository root.

```sh
python3 -m unittest discover -s tests -v
KAKAO_TEST_APP=/path/to/signed/KakaoTalk.app python3 -m unittest discover -s tests -v
```

Without `KAKAO_TEST_APP`, the installer and staged-update fixture tests are skipped. With a
signed updater-enabled reconnect app, all 24 tests run. They treat that app as a read-only
fixture, copy it to disposable directories, and never replace `/Applications/KakaoTalk.app`
or read chat/login data. Network-gate checks use a loopback HTTP server and native test clients.

Build commands are in the [README](../README.md#build-from-source). Reconnect builds require
the exact unmodified official app; the installed patched app is not a valid source.
Installer builds package an already signed reconnect app and do not install it.

## Remaining validation

The in-process network gate is not a kernel firewall or proof of zero egress. Direct
syscalls, unhooked networking paths, submitted requests, background services, and other
processes are outside the existing test evidence. Hold can also pause update downloads.

Keep automated checks separate from real two-Mac session testing, Intel runtime, and visual
QA. Compile/signature success does not establish message delivery or prevent delayed
server-side disconnects. Record measured results in [VALIDATION.md](VALIDATION.md).
