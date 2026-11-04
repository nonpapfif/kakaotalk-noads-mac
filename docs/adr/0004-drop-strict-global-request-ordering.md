---
status: accepted
---

# Drop strict global first-accepted ordering from the current scope

The user accepted removing the requirement that simultaneous Manual Reconnect requests
have exactly the globally first-accepted winner. That interview-added guarantee was
driving extra arbitration infrastructure beyond the primary goal of convenient, stable
use across three Macs under a zero-spending budget and small-project scope.

This removes a strict ordering guarantee, not protection of the working Mac. Explicit
manual selection still outranks Away MacBook preference and home automatic selection;
stale automatic recovery must not take the session back. Automatic Login remains a goal,
and unavailable valid ownership approval still preserves existing connections and defers
new automatic/manual transfers. No architecture or native-login behavior is established
by accepting this scope reduction.
