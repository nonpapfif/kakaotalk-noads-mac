# Three-Mac Session Coordination

The owner's three Macs share one desktop-session role. These terms describe the target
domain; the goal document tracks implementation gaps separately.

## Language

**Managed Mac**:
One of the owner's three Macs participating in session coordination.
_Avoid_: Any desktop, every installed client

**Open Mac**:
A Managed Mac whose display is on and whose user session is unlocked. Recent input is not
required for this status.
_Avoid_: Awake Mac, running app, recently used Mac

**Eligible Mac**:
An Open Mac with KakaoTalk already running that can be selected for an automatic session
acquisition or handoff. A Mac whose app was deliberately quit is not eligible.
_Avoid_: Any Open Mac, automatically launched app

**Session Owner**:
The single Managed Mac entitled to maintain or recover the desktop connection. Ownership
does not imply that its connection is currently working.
_Avoid_: Connected Mac, frontmost app

**Connected Mac**:
A Managed Mac with a working native KakaoTalk desktop connection.
_Avoid_: Session Owner, Open Mac

**Hold**:
A waiting state that retains the app's existing windows without attempting to acquire the
desktop session automatically.
_Avoid_: Connected, logged out, offline Session Owner

**Automatic Handoff**:
A transfer of session ownership prompted by the current owner's confirmed screen-off,
locked state, or normal app exit, with an Eligible Mac available to receive it.
_Avoid_: Automatic takeover of an Open Session Owner

**Manual Reconnect**:
An explicit user request to connect on a chosen Managed Mac, including a deliberate
transfer away from another Open Session Owner.
_Avoid_: Background recovery, automatic handoff

**Owner Recovery**:
Restoration of the current Session Owner's interrupted connection without transferring
ownership to a different Managed Mac.
_Avoid_: Handoff, Manual Reconnect

**Unknown Presence**:
A Managed Mac's screen or lock state cannot be established reliably.
_Avoid_: Closed, locked, owner relinquished
