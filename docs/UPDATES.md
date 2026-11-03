# Maintaining features across KakaoTalk updates

This repository now separates reviewed app compatibility from the reconnect helper and
installer. Only 26.9.0 build 2006 is currently approved. No future version is supported
merely because this infrastructure exists.

## Two different update problems

1. **Porting the modifications:** check the new official binary, native classes/selectors,
   ABI, UI, data-store lifecycle, ad code and session behavior. Some releases may require
   changes to both the patch profile and `SessionReconnect.m`.
2. **Delivering a verified build:** package the resulting app in the self-contained installer.
   Keep the same bundle identity, preserve user data, back up the previous app, and configure
   the Dock/URL defaults as before.

The new tooling handles version selection, source guards, packaging metadata and repeatable
checks. It cannot infer correct semantics of an arbitrary new binary, guarantee future
server authentication behavior, or replace real login/send/receive tests.

The app now downloads reviewed GitHub release payloads on demand and applies them after
normal app termination. It does not patch App Store updates, watch for updates in the
background, or infer compatibility. HTTPS and GitHub release asset digests form the update
trust boundary; ad-hoc signing does not provide an independent publisher signature.

## Current layout

- `compatibility/profiles/<version>-<build>.json`: official source identity/hash,
  architectures, original/replacement bytes, required selector names, stable output identity,
  approval for building, and the actual scope of functional validation.
- `tools/inspect_update.py`: read-only source/signature/architecture and known-profile inspection.
- `tools/build_reconnect.py`: selects the exact profile and refuses unknown versions/hashes,
  overlapping patches, missing selectors, unexpected architectures and changed original bytes.
- `tools/build_installer.py`: reads the reviewed app version and produces versioned installer
  filenames and a payload manifest. It contains no fixed 26.9 payload version.
- `installer/Installer.swift` and `install-app.sh`: verify the payload version/build from that
  signed manifest. The GUI refuses a version/build downgrade before quitting the installed app.

`approved_for_build` means a maintainer reviewed static patch prerequisites. It is not proof
that every feature works. New candidates can be approved for an isolated test build after
static review; functional verification and release approval still happen separately.
Never set it merely to bypass an unsupported-version error.

## Procedure for the next official version

1. Obtain an official app copy separately. Keep the working installation untouched.
   Do not update `/Applications/KakaoTalk.app` through the App Store to test this project.
2. Inspect the copy on a development Mac:

   ```sh
   python3 -m tools.inspect_update --app /path/to/new/official/KakaoTalk.app --output /tmp/candidate.json
   ```

   An unknown version/hash must report `build_allowed: false`. The tool reads app files,
   not Library, chat databases, Keychain, credentials or live network traffic.
3. Review the new binary and helper interfaces. Set the profile's `patch_release` to the
   intended reconnect release tag before building. Add a new profile with the exact source
   hash and independently verified code locations. Do not carry offsets forward based
   only on matching version strings or a coincidental byte pattern. Selector-name presence
   is advisory: it does not prove class ownership, method signature or runtime behavior.
4. After static review approves an isolated build, build the candidate:

   ```sh
   python3 -m tools.build_reconnect --source /path/to/new/official/KakaoTalk.app --output /tmp/KakaoTalk.app
   ```

   The current Mach-O injector and entitlement reader expect the supported universal format.
   If Apple/Kakao changes the format or architectures, stop and adapt those readers explicitly.
5. Test on a spare Mac or separate macOS account. The production bundle identity is retained;
   do not launch a test candidate against your only copy of important chat data.
   Use a supported chat backup/restore process before upgrading important data.
6. Run the acceptance checklist below and record what actually passed. Fix helper code if
   native APIs or data-store/observer lifecycles changed. Commit profile and source changes
   together with their validation notes.
7. Build the installer, run its transaction tests and inspect the resulting artifacts:

   ```sh
   KAKAO_TEST_APP=/tmp/KakaoTalk.app python3 -m unittest discover -s tests -v
   python3 -m tools.build_installer --app /tmp/KakaoTalk.app --output /tmp/new-kakao-installer
   ```

8. Set the profile's `patch_release` to the new reconnect release tag. The source builder
   embeds it as `KakaoTalkPatchRelease`. Publish only after functional review. Upload the
   DMG, installer/app ZIPs, `Update.json`, update ZIP and checksums. The update manifest
   must match the release tag and its GitHub asset digests. Point the README to that release. Do not replace old release
   assets silently. Keep the previous version available for recovery.

## Functional acceptance checklist

Record each result separately, including platform/architecture and any limits:

- Friends, Chats and More have no main-window banner or unused banner space after resize.
- Manual login and saved-authentication reconnect succeed without exporting credentials.
- Takeover does not trigger a repeated automatic login fight with the other Mac.
- Existing multiple chat windows can send and receive live updates after takeover.
- Unsent text/attachments remain intact during reconnect; failed requests are not duplicated.
- Sidebar placement, active/inactive, hover and appearance transitions still work.
- Login expiration, temporary network loss, app restart and manual recovery behave clearly.
- The app retains its expected sandbox/data identity and passes signature checks.
- Installer backup/replacement, repeat install, Dock/URL defaults and app launch pass.
- Before claiming full compatibility, test auxiliary windows, calls and file transfer too.

## Recovery limits

The installer preserves app bundles and leaves Library/Keychain data in place. That does
not undo a database migration performed by a newer KakaoTalk after launch. Restoring an
older `.app` alone is not a verified chat-data rollback. Keep a supported backup and test
new versions away from the only production data copy. A failed or unknown compatibility
check should leave users on the previous working release.
