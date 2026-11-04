# Coordination with zero spending and no new external service

Status: feasibility research, not an architecture decision. Reviewed: 2026-11-04.

Scope update: after this investigation, the user removed strict globally first-accepted
request ordering from the current phase. Findings about that ordering explain the earlier
scope trade-off, not a current requirement to build a shared arbiter. Remaining owner
protection, manual/away priority, automatic-login goals, and approval-unavailability policy
remain in force. See [ADR 0004](adr/0004-drop-strict-global-request-ordering.md).

## Conclusion

LAN discovery plus native KakaoTalk login/kickout does not currently demonstrate the
agreed cross-network ownership policy. Existing iCloud Drive could transport messages,
but ordinary file synchronization does not itself establish globally first-accepted
manual requests. A protocol using an existing Mac as the sole approval authority is
a possible research candidate, not an implemented or proven solution.

This is a gap in the examined mechanisms, not proof that every zero-cost design is
impossible. The user has since removed strict first-accepted ordering. If no valid shared approval
path is reachable, preserve the existing connection and defer new automatic and manual
transfers, as agreed. Unknown home-peer presence alone does not block Away acquisition
when that approval path remains available.

## Constraints and evidence boundaries

- Total additional spending must be zero. Do not depend on paid membership, a paid tier,
  or a free quota that could produce a bill. Operating a separate external service is
  excluded by default; reuse of already-existing infrastructure remains investigable.
- Scope is three personal Macs, normally at home, with at most one Away MacBook.
  Manual selection outranks Away preference. Away Reservation survives temporary lock.
- Open means display on and user session unlocked. This note does not verify those
  observations, home/Away classification, native authentication, or device provisioning.
- Investigation used official documentation, repository commit `917b4bb`, and existing
  static disassembly. No real-device discovery, authentication requests, account changes,
  service deployment, app changes, chat access, or Keychain access occurred.

## Confirmed findings

| Mechanism | Confirmed evidence | What it does not establish |
| --- | --- | --- |
| LAN Bonjour/mDNS | Standard mDNS operates on the local link without a conventional DNS server. Apple distinguishes local Bonjour from separately configured wide-area discovery. | A route from the Away MacBook to home, a shared owner order, or proof that a missing peer released ownership. |
| Existing KakaoTalk paths | The helper checks `canAutoLogin` and invokes `autoLoginWithForce:YES`. Native disassembly forwards a kickout notice to a delegate and reads reason/error information. | Which managed Mac initiated a replacement, whether it was manual, a durable manual override, Away Reservation, or a globally accepted request order. |
| Existing iCloud Drive | Apple documents access across devices using the same Apple Account and enabled Drive synchronization. | That these three Macs already meet those conditions or have usable existing capacity. |
| iCloud document synchronization | Apple documents local writes followed by daemon transfer, and possible conflicts between different devices. `NSFileCoordinator` coordinates app/daemon file access. | A distributed compare-and-set, global mutex, or ten-second propagation guarantee. |

Sources: [RFC 6762](https://www.rfc-editor.org/rfc/rfc6762),
[Apple Bonjour domains](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/NetServices/Articles/domainnames.html),
[Apple Drive setup](https://support.apple.com/en-us/118443),
[Apple iCloud file management](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/iCloud/iCloud.html).

Local static evidence, inspected read-only:

- `git show 917b4bb:reconnect/SessionReconnect.m`, lines 493–553: local request guards,
  saved-authentication eligibility, forced login, and local timeout. Lines 180–191:
  kickout-triggered Hold and authentication guards. These are not shared approval operations.
- Sibling analysis folder `kakaotalk-session-analysis`, file
  `verified-kickout-disassembly-x86_64.txt`: `0x1018d4ad0`–`0x1018d4b0d` obtains the
  delegate and forwards the notice; `0x10179fa3a`–`0x10179faa8` reads reason/error fields.
  These extracts do not establish a source-device identity or server ordering contract.
- `autologin-logout-request-disassembly.txt`, around `0x101713873`–`0x1017138ff`:
  native eligibility processing reads preferences and device-related data. The supplied
  dump has unresolved string references. It does not establish full credential-expiry
  recovery. No credential values were inspected.

Symbol names, local notifications, and generic kickout events are insufficient evidence
for the missing identity and ordering properties. The inspected extracts do not prove
that the entire native protocol lacks them.

## Inferences and a bounded candidate

**LAN only.** Discovery can find a home peer that runs the coordination protocol.
The protocol must still decide ownership and persist manual overrides/reservations.
The absence of a discovery response cannot distinguish sleep, a crash, packet loss,
permission failure, or departure. Treat it as missing observation, not release.

**Native login outside.** A successful forced login may establish a working connection.
It cannot substitute for prior ownership approval on current evidence. Even if the
server eventually retains one connection, competing login attempts could successively
replace each other. Final connection state does not prove the formerly requested
first-accepted ordering, nor the remaining persistent priority/protection requirements.

**One synchronized owner file.** Independent Macs can read old copies and each write a
different winner. Resolving the file conflict later cannot undo an already executed
login. Modification timestamps do not establish the shared first-accepted order.
This follows from Apple's documented delayed synchronization and conflict model.

**Existing-Mac authority, optional iCloud mailbox.** An existing home Mac could be the
only process allowed to approve requests. LAN would carry local requests; an already
usable iCloud folder could carry uniquely identified requests and responses from outside.
The authority, not file arrival order or timestamps on the clients, would serialize
acceptance and reject other requests in the same competing decision. Its persistent
state would include the manual selection and Away Reservation independently of Open.
No new externally operated service is inherent in this candidate.

This candidate still adds a coordination role on an existing Mac. It is not selected.
It requires a protocol for fresh approvals, acknowledgments, crash recovery, stale
responses, and in-flight native logins. A single writer alone does not solve delayed
execution: an old approval must not execute after a newer manual selection. Native
server fencing support has not been established. The authority must not be replaced
independently during loss of contact without a proven agreement mechanism.

An iCloud file merely existing locally is not proof that the approval process is alive.
An absent response means approval is unavailable or unconfirmed; it does not diagnose
whether the home peer, synchronization transport, or authority failed. A fresh protocol
response could establish usable approval while some peer presence remains unknown.
During unavailable approval, keep the agreed defer policy.

## Exact unresolved guarantees

1. **Ten-second cross-network transfer:** no cited iCloud specification supplies this
   bound. If this transport is selected, retain ten seconds as an unverified acceptance
   target or revisit it explicitly; do not silently promise it.
2. **First-accepted manual winner (removed from scope):** it would need one demonstrated
   acceptance point and conflict boundary, with stale requests/responses and restarts
   covered. It was not proved by LAN, synchronization, or kickout handling; it is no longer
   an acceptance requirement for the current phase.
3. **Persistent manual override and Away Reservation:** need authoritative durable state,
   explicit release rules, and clients that cannot act on obsolete ownership. Neither
   a live connection nor a generic disconnect identifies these intentions.
4. **Owner Recovery during partition:** continuing a working native connection is different
   from issuing a new saved-authentication login. A cached owner might have been superseded
   by a newer manual choice elsewhere. Recovery must be investigated with authority and
   stale-action prevention; this concern is not a newly accepted product restriction.
5. **Fully expired authentication:** saved-login calls exist, but recovery after invalidated
   credentials, device re-verification, or additional challenges remains unverified.
6. **Zero spending and usable infrastructure:** existing shared Drive access/capacity,
   authority-host availability, and whether its operation fits the intended small scope
   remain unverified. No new account, subscription, CloudKit setup, or capacity upgrade
   is part of this candidate.

Next evidence should establish those prerequisites and stale-action handling before an
architecture is selected. All-six-direction transfers, concurrent requests, lock/resume,
partition/rejoin, restart, and the eight-hour protection window remain unexecuted.
