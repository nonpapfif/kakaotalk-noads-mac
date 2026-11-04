# Three-Mac Session Goals

Status: first product-goal baseline agreed; implementation feasibility pending.
Updated: 2026-11-04.
This records agreed target behavior, not implemented or verified functionality.
Terminology is defined in [GLOSSARY.md](../GLOSSARY.md).

## Objective and priority

The owner normally rotates between three Macs at home and wants to avoid repeated manual
login. Stabilize that experience with Automatic Login and Owner Recovery. At home, protect
the Open Session Owner from unwanted automatic takeover. When the owner takes one MacBook
outside, that Open, Eligible Away MacBook has priority over the home Macs, even if a home
owner remains Open. Main-window ad removal remains a baseline feature.

The scope is the owner's three Macs first. Broader distribution and platform coverage are
not acceptance criteria for this goal reset. Coordination must work across different
networks. The owner takes at most one MacBook outside at a time. Home/external network
recognition and coordination technology are still unselected.

The spending budget is exactly zero. Operating a separate external coordination service
is outside the default scope because the owner wants to keep this project small. Prefer
existing capabilities and infrastructure; do not interpret a free service tier as approval
to expand operations or provision a service. Revisit the product scope with evidence if
the guarantees cannot be met within these constraints.

Selection priority is explicit Manual Reconnect, then Away MacBook preference, then
protection of the existing home owner. Automatic input-recency selection applies only when
selecting a replacement is allowed by those rules. An accepted manual selection must not
be immediately undone by automatic Away MacBook acquisition or stale automatic recovery.

## Agreed behavior

| Situation | Required behavior |
| --- | --- |
| Display on and user session unlocked | Treat the Managed Mac as Open. |
| Caffeinate is running | Apply the same display/lock definition of Open. |
| Home owner remains Open without recent input, with no higher-priority Away MacBook | Keep protecting the owner. |
| Exactly one Mac is Eligible, with no protected owner | Automatically select that Mac when peer state is known. |
| Another home Mac opens or receives input while the home owner remains Open | Keep the existing owner. Explicit Manual Reconnect changes the selection. |
| The sole Away MacBook is Open and Eligible on an external network | Give it priority over an Open home owner; home Macs must not automatically take the session back. |
| Home owner's display turns off or its session locks | Put the previous owner on Hold and automatically hand off to an Eligible Mac. |
| Away owner temporarily locks or turns its display off | Retain Away Reservation. Home Macs remain on Hold; the Away MacBook automatically recovers when Open again. |
| Two Eligible Macs can receive an Automatic Handoff | Prefer the Mac with the most recent keyboard or mouse use. |
| No Mac is Open | Put all Managed Macs on Hold. |
| A Mac opens after all were on Hold | Automatically acquire the session if it is the only Eligible Mac and peer state is known. |
| The Open owner temporarily loses Internet connectivity | Retain ownership and perform Automatic Login/Owner Recovery on the same Mac. Other Macs remain on Hold. |
| Home Mac cannot establish peer presence | Defer automatic acquisition or handoff. Do not interpret missing contact as ownership release. |
| Away MacBook cannot establish home-peer presence | Permit its automatic acquisition attempt as an explicit priority exception. Home Macs must not automatically take the session back. |
| User normally quits the owner's app | Release ownership and hand off to another Eligible Mac. Do not automatically relaunch the app that was quit. |
| App crashes or contact is abruptly lost | Do not infer normal ownership release from the missing contact. Apply Unknown Presence handling. |
| Multiple Eligible Macs start with no established owner | Choose the Mac with the most recent keyboard or mouse use. If ordering cannot be established, wait for Manual Reconnect. |
| Manual Reconnect is requested during Unknown Presence | Allow the explicit request; automatic takeover remains deferred. |
| Multiple Manual Reconnect requests arrive concurrently | Do not promise a globally first-accepted winner. Retain owner protection and prevent automatic takeover fights; concrete handling needs validation. |
| No valid shared ownership approval path is reachable | Preserve the existing connection and defer new automatic and manual transfers. |

Manual Reconnect is the previously agreed, intentional exception to protection of an Open
owner, including during Unknown Presence. Concurrent requests do not authorize competing
automatic retry loops. Strict global first-accepted ordering was explicitly removed from
scope; no shared arbitration service is selected or required solely to provide that order.
Other owner-protection and transfer-approval rules remain. See
[ADR 0004](adr/0004-drop-strict-global-request-ordering.md).
Keeping an owner distinct from a working connection is essential to the priority rule; see
[ADR 0001](adr/0001-protect-the-open-session-owner.md).
The Away MacBook is an accepted exception to home-owner protection; see
[ADR 0002](adr/0002-prioritize-the-away-macbook.md). Away Reservation preserves preference,
not a requirement to keep a live connection while the display is off or the session locked.
An explicit Manual Reconnect elsewhere can override the reservation. Ordinary home-side
automatic handoff must not reverse the Away MacBook preference during a temporary lock.

Unknown home-peer presence and an unreachable authoritative coordinator are different
failure cases. The user accepted an Away MacBook exception for the former. Arbitration and
failure behavior for the latter is now conservative: preserve existing connections and
defer new transfers, including Manual Reconnect. The Away MacBook presence exception does
not bypass this approval requirement or establish a shared order of concurrent requests.
See [ADR 0003](adr/0003-zero-cost-scope-and-approval-unavailability.md).

## Automatic Login goal and evidence

The user rejected routine manual sign-in as the response to authentication expiration.
Automatic Login and recovery are required goals. Do not equate a helper request timeout
with proof that saved authentication has expired, or silently replace this goal with a
manual-login default.

Static audit of `917b4bb` confirms an existing `autoLoginWithForce:YES` request path guarded
by `canAutoLogin`, login-in-progress checks, and a success-event hook. It uses saved native
authentication and currently runs only on explicit Manual Reconnect. The native method
internals and its complete eligibility conditions are not present in this repository.
The current Hold policy blocks unattended authentication rather than providing the newly
requested behavior.

Fully invalid saved authentication, additional user challenges, device re-verification,
and password-change recovery have not been tested. Feasibility research must distinguish
these cases from ordinary connection loss. No claim of universal unattended re-login or
indefinite session protection has been established, and no credential-handling design is
selected by recording the goal.

## Provisional completion criteria

The user accepted these initial measurable targets:

- On a healthy network, complete a session transfer within 10 seconds.
- Complete 10 successful transfers in each of the six directed Mac-to-Mac paths.
- With all three Macs running caffeinate, observe eight hours with zero unintended
  takeovers. Expected manual transfers and the agreed Away MacBook priority are intentional.

Indefinite protection from unwanted takeover is the desired long-term behavior; eight hours
is an initial observation window, not a guarantee. These checks have not been executed.
The target conditions, valid-authentication prerequisites, and failure/latency measurement
need a concrete test plan before an implementation is declared complete.

## Current-code comparison

Read-only audit baseline: commit `917b4bb` on the separate module-cleanup branch. That branch
also includes the unpublished Hold network-gate candidate. It is not merged into this
documentation branch or asserted to satisfy these goals.

- The current controller has local Hold/reconnect flags, with no shared Session Owner or
  peer-presence model. Application/window notifications refresh UI; they do not establish
  the agreed Open state or input-recency ordering.
- Current reconnect is manual. Screen/lock-driven acquisition and three-Mac handoff are
  missing, as are cross-network ownership and home/Away MacBook priority.
- Current disconnect handling can enter Hold and suppress automatic authentication. This
  conflicts with Owner Recovery after a temporary Internet outage.
- Hold is not retained across app restart. The agreed startup ownership policy is not
  implemented.
- The candidate's process-wide Internet gate also needs review before any coordination
  channel is placed in that process. Its tests are not proof of zero egress or server control.

Audit references in that commit: `reconnect/SessionReconnect.m:90`, `:185`, `:216`, `:291`,
`:405`, `:493`, `:588`; `reconnect/SessionNetworkGate.m:134`.
These are static source findings. No new application or multi-Mac test was run for this
goal interview. Preventing interference by these three clients is a target; protection
against every server-side revocation or unmanaged client has not been established.

## Coordination feasibility status

The [zero-cost coordination research](ZERO-COST-COORDINATION.md) records the evidence and
limitations of local discovery, native login events, and existing file synchronization.
Strict global first-accepted ordering is no longer required. Its removal does not prove
that those mechanisms enforce the remaining owner-protection and priority rules.

An existing Mac as sole authority with existing synchronization as transport was examined
as a candidate, not selected. A separate external service remains outside the default scope.
No coordination role, host dependency, account setup, or transport is adopted by these goals.

Continuing a working native connection differs from making a fresh saved-auth login request.
It is not yet proven that a previously selected owner's fresh login cannot replace a newer
owner after a communications partition. Preserve the accepted unavailable-approval policy
while investigating recovery; do not assume cached ownership authorizes a stale takeover.

## Decision tree and open questions

Settled: user/scope -> Open/Eligible definitions -> owner protection -> automatic handoff ->
candidate selection -> Owner Recovery -> conservative automatic behavior under Unknown
Presence -> normal app exit -> initial owner selection -> explicit request exceptions ->
cross-network operation -> Away MacBook priority -> provisional completion criteria.
Automatic Login is required; coverage of fully expired authentication remains unverified.
Also settled: Away Reservation across temporary lock, explicit manual selection above
Away MacBook preference, and Away MacBook acquisition despite unknown home-peer presence.
Budget is zero, separate external service operation is outside the default scope, and
unavailable shared ownership approval defers new automatic/manual transfers.

Scope decision accepted:

The user removed strict globally first-accepted manual-request ordering from this phase.
It had been proposed during the interview in addition to the primary purpose of avoiding
repeated login while rotating among three Macs. Prioritize a small, zero-spending design
and investigate existing capabilities before adding a coordination role or service.

The relaxation is limited to global first-accepted ordering; it does not remove
owner protection, manual/away precedence, automatic-login goals, or the accepted policy
of preserving existing connections and deferring transfers without valid approval.

Engineering work after the goal reset:

1. Identify what can be achieved with existing KakaoTalk authentication/session events,
   local coordination, or existing synchronization without a new external service.
2. Validate the remaining cross-network ownership/protection rules without requiring the
   removed first-accepted ordering guarantee. Any further reduction in an accepted rule
   returns to the user as a product decision.

Engineering checks and unresolved design details:

- Native saved-authentication cases that can recover without user action, established by
  source/binary investigation and controlled tests rather than user guesses.
- A minimal design that preserves explicit selections, prevents stale automatic takeovers,
  and handles concurrent requests without promising a global first-accepted order or
  conflating presence observations with ownership approval.
- Reliable home/external classification, return-home behavior, and uncertain location.
- Actual display/lock behavior with external displays and remote sessions on these Macs.
- Display/lock transition delay tolerance and stale observation handling. Unresolvable
  recent-input ordering already falls back to Manual Reconnect.
- Failed transfers and useful user-facing failure states without creating an automatic
  ownership fight or silently relaunching a deliberately closed app.
- Detailed acceptance coverage: all six directed transfers, caffeinate/idle duration,
  network interruption/rejoin, restart, concurrent requests, home/away changes, and the
  automatic-authentication cases supported by feasibility evidence.

No coordinator, transport, credentials, deployment model, or implementation rewrite has
been selected. Architecture follows the remaining decisions and feasibility evidence.
