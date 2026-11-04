# Three-Mac Session Goals

Status: goal interview in progress. Updated: 2026-11-04.
This records agreed target behavior, not implemented or verified functionality.
Terminology is defined in [GLOSSARY.md](../GLOSSARY.md).

## Objective and priority

Stabilize session use across the owner's three Macs. Protect the Open Session Owner from
automatic session takeover by the other Managed Macs. This takes priority over automatic
handoff speed and availability. Main-window ad removal remains a baseline feature.

The scope is the owner's three Macs first. Broader distribution and platform coverage are
not acceptance criteria for this goal reset. Cross-network requirements remain undecided.

## Agreed behavior

| Situation | Required behavior |
| --- | --- |
| Display on and user session unlocked | Treat the Managed Mac as Open. |
| Caffeinate is running | Apply the same display/lock definition of Open. |
| Owner remains Open without recent input | Keep protecting the owner. |
| Exactly one Mac is Eligible, with no protected owner | Automatically select that Mac when peer state is known. |
| Another Mac opens or receives input while the owner remains Open | Keep the existing owner. Explicit Manual Reconnect changes the selection. |
| Owner's display turns off or its session locks | Put the previous owner on Hold and automatically hand off to an Eligible Mac. |
| Two Eligible Macs can receive an Automatic Handoff | Prefer the Mac with the most recent keyboard or mouse use. |
| No Mac is Open | Put all Managed Macs on Hold. |
| A Mac opens after all were on Hold | Automatically acquire the session if it is the only Eligible Mac and peer state is known. |
| The Open owner temporarily loses Internet connectivity | Retain ownership and perform Owner Recovery on the same Mac. Other Macs remain on Hold. |
| Peer state is unknown | Defer automatic acquisition or handoff. Do not interpret missing contact as ownership release. |
| User normally quits the owner's app | Release ownership and hand off to another Eligible Mac. Do not automatically relaunch the app that was quit. |
| App crashes or contact is abruptly lost | Do not infer normal ownership release from the missing contact. Apply Unknown Presence handling. |
| Multiple Eligible Macs start with no established owner | Choose the Mac with the most recent keyboard or mouse use. If ordering cannot be established, wait for Manual Reconnect. |
| Manual Reconnect is requested during Unknown Presence | Allow the explicit request; automatic takeover remains deferred. |
| Multiple Manual Reconnect requests arrive concurrently | Process only the first accepted request; report a conflict to the other requesters. |

Manual Reconnect is the previously agreed, intentional exception to protection of an Open
owner, including during Unknown Presence. Concurrent requests do not authorize competing
reconnect attempts. The meaning and feasibility of a shared request order still need design
evidence; no coordinator is selected by this policy. Keeping an owner distinct from a working
connection is essential to the priority rule; see
[ADR 0001](adr/0001-protect-the-open-session-owner.md).

## Current-code comparison

Read-only audit baseline: commit `917b4bb` on the separate module-cleanup branch. That branch
also includes the unpublished Hold network-gate candidate. It is not merged into this
documentation branch or asserted to satisfy these goals.

- The current controller has local Hold/reconnect flags, with no shared Session Owner or
  peer-presence model. Application/window notifications refresh UI; they do not establish
  the agreed Open state or input-recency ordering.
- Current reconnect is manual. Screen/lock-driven acquisition and three-Mac handoff are
  missing.
- Current disconnect handling can enter Hold and suppress automatic authentication. This
  conflicts with Owner Recovery after a temporary Internet outage.
- Hold is not retained across app restart. Startup ownership selection is unresolved.
- The candidate's process-wide Internet gate also needs review before any coordination
  channel is placed in that process. Its tests are not proof of zero egress or server control.

Audit references in that commit: `reconnect/SessionReconnect.m:90`, `:185`, `:216`, `:291`,
`:405`, `:493`, `:588`; `reconnect/SessionNetworkGate.m:134`.
These are static source findings. No new application or multi-Mac test was run for this
goal interview. Preventing interference by these three clients is a target; protection
against every server-side revocation or unmanaged client has not been established.

## Decision tree and open questions

Settled: user/scope -> Open/Eligible definitions -> owner protection -> automatic handoff ->
candidate selection -> Owner Recovery -> conservative automatic behavior under Unknown
Presence -> normal app exit -> initial owner selection -> explicit request exceptions.

The next interview round covers these decisions:

1. Required operation across different networks. The choice of coordination infrastructure
   follows this requirement and feasibility research.
2. Measurable completion criteria, including transfer latency and three-Mac stability duration.
3. Authentication expiration: when to stop unattended recovery and request manual sign-in.

Further decisions remain before implementation:

- Acceptable coordination infrastructure after network scope is settled, and handling an
  unavailable coordinator during an explicit Manual Reconnect or request arbitration.
- Actual display/lock behavior with external displays and remote sessions on these Macs.
- Display/lock transition delay tolerance and stale observation handling. Unresolvable
  recent-input ordering already falls back to Manual Reconnect.
- Failed transfers and useful user-facing failure states without creating an automatic
  ownership fight or silently relaunching a deliberately closed app.
- Detailed acceptance coverage: all six directed transfers, caffeinate/idle duration,
  network interruption/rejoin, restart, and concurrent request scenarios.

No coordinator, transport, credentials, deployment model, or implementation rewrite has
been selected. Architecture follows the remaining decisions and feasibility evidence.
