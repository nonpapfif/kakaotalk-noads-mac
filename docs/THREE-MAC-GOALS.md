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
| Exactly one Mac is Open, with no protected owner | Automatically select that Mac when peer state is known. |
| Another Mac opens or receives input while the owner remains Open | Keep the existing owner. Explicit Manual Reconnect changes the selection. |
| Owner's display turns off or its session locks | Put the previous owner on Hold and automatically hand off to an eligible Open Mac. |
| Two Open Macs can receive an Automatic Handoff | Prefer the Mac with the most recent keyboard or mouse use. |
| No Mac is Open | Put all Managed Macs on Hold. |
| A Mac opens after all were on Hold | Automatically acquire the session if it is the only Open Mac and peer state is known. |
| The Open owner temporarily loses Internet connectivity | Retain ownership and perform Owner Recovery on the same Mac. Other Macs remain on Hold. |
| Peer state is unknown | Defer automatic acquisition or handoff. Do not interpret missing contact as ownership release. |

Manual Reconnect is the previously agreed, intentional exception to protection of an Open
owner. The user has not yet decided its behavior during unknown peer state or concurrent
requests. Keeping an owner distinct from a working connection is essential to the priority
rule; see [ADR 0001](adr/0001-protect-the-open-session-owner.md).

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

Settled: user/scope -> Open definition -> owner protection -> automatic handoff -> candidate
selection -> Owner Recovery -> conservative behavior under Unknown Presence.

The next interview round covers these decisions independently:

1. Owner lifecycle: whether normal app quit releases ownership; how to treat crash, abrupt
   power loss, and missing contact without violating conservative Unknown Presence handling.
2. Startup: how to choose when multiple Macs are Open and no owner is established.
3. Manual Reconnect arbitration: simultaneous requests and requests during Unknown Presence.

Further decisions remain before implementation:

- Whether closed apps are started automatically or only running apps participate.
- Required operation across different networks, and acceptable coordination infrastructure.
- Actual display/lock behavior with external displays and remote sessions on these Macs.
- Delay tolerance for handoff and display/lock transitions; deterministic recency ties.
- Saved-authentication expiration, failed transfers, and useful user-facing failure states.
- Measurable completion criteria: all six directed transfers, three-Mac caffeinate/idle
  duration, network interruption/rejoin, restart, and concurrent request scenarios.

No coordinator, transport, credentials, deployment model, or implementation rewrite has
been selected. Architecture follows the remaining decisions and feasibility evidence.
