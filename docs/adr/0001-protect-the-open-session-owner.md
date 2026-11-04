---
status: accepted
---

# Protect the Open Session Owner before automatic availability

Across the owner's three Macs, retain the Open Session Owner through temporary Internet
loss and defer automatic takeover when peer presence is unknown. A working connection and
session ownership are separate concepts: automatic recovery belongs to the existing owner,
while screen-off or lock can trigger handoff. This deliberately favors avoiding session
fights over immediate failover; explicit Manual Reconnect remains the agreed intentional
transfer mechanism when multiple Macs are Open.

The later [Away MacBook priority decision](0002-prioritize-the-away-macbook.md) is an explicit
exception: an Open, Eligible Away MacBook can automatically supersede a home owner. Home
Macs must not use ordinary automatic recovery to reverse that intentional transfer.
