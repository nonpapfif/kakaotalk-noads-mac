---
status: accepted
---

# Give the Away MacBook priority over home clients

The owner normally rotates among three home Macs but carries at most one MacBook outside.
An Open, Eligible Away MacBook has priority over an Open home Session Owner. This explicitly
qualifies the usual owner-protection rule: home clients can remain awake or apparently Open
under caffeinate while the user is physically using the MacBook elsewhere, and should not
automatically take its session back. Away reservation during screen-off or lock, manual
override precedence, and unknown home-peer presence are resolved as follows: retain Away
Reservation through temporary lock/display-off, allow the Away MacBook to attempt automatic
acquisition despite unknown home-peer presence, and honor an explicit Manual Reconnect
ahead of automatic Away MacBook preference without automatically taking the session back.
The method of recognizing home versus external networks and behavior during an unreachable
ownership coordinator remain undecided.
