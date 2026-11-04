# Offline session policy supervisor

The first finite run validates the three-Mac decision rules in
[the agreed goals](THREE-MAC-GOALS.md). Its acceptance evidence is a pure native policy,
observable fixture cases, a passing offline regression suite, an arm64/x86_64 fixture,
and independent review tied to the tested source digest. The fixture models observations
and authorization that a future adapter would supply.

Python runs commands, persists each child exit, and waits for results. Luna low selects
the next necessary test, Sol medium proposes a diff, and Astra medium reviews the
recorded source and evidence. For a repair, Astra records the required change and the
observable test separately. Sol receives both instructions directly, and Python reruns
the suite on the changed source before returning the results to Astra. This cycle ends
at the accepted milestone or an established blocker. Model workers can read the scoped
worktree. The controller checks the diff allowlist before applying it in a dedicated
worktree. Generated tests run in a macOS sandbox that denies network access and restricts
writes to the worktree and scratch directory.

Use the existing ChatGPT login. The controller checks authentication type, ordinary plan
usage, and exact model efforts before every model call. It stops when that evidence is
unavailable. The subprocess environment is limited to the local runtime variables required
for execution. See [Codex App Server](https://learn.chatgpt.com/docs/app-server).

## Run and inspect

Use a clean dedicated worktree at the approved revision and a private run directory outside
that checkout. Copy the controller into the run directory before handing it to launchd.
Use one service and one supervisor lock per run. A revision with the policy fixture already
present starts at verification and returns its fresh evidence to Astra.

```sh
python3 tools/test_supervisor.py check --codex /absolute/path/to/codex
python3 /private/run/controller.py run --run /private/run \
  --worktree /private/checkout --codex /absolute/path/to/codex
```

For an unattended run, point the user LaunchAgent at the second command and use
`caffeinate -i` while it runs. Inspect `status.json`, the current job's `worker.json` and
`child.json`, and its independent `exit.json`. The controller detects ambiguous or missing
child identity and preserves the run for reconciliation. It also stops when it reaches a
previous stage with the same source and no new test evidence. A planner's proposed blocker
goes to independent review.

The controller applies offline diffs and records evidence. Publication is a separate review
of the actual tested worktree and any draft pull request. Keep private run artifacts outside
Git. Candidate application assembly requires the matching official source bundle and
validated production adapters. This run validates policy and buildability of its fixture.
Real screen and lock observation, account login, installation, and three-Mac behavior are
subsequent milestones.
