# AI Error Fix Guardrails

Airstrip turns recognized runtime failures into structured repair requests, then
tries local deterministic fixes before asking an AI for help. The goal is a
durable project fix, not a one-off terminal cleanup.

## Address already in use

When output contains common bind-failure markers such as `Address already in use`,
`EADDRINUSE`, or `Errno 48`, Airstrip records a `RuntimeIssue` with:

- the failure kind and short summary
- the active web port Airstrip expected
- the next available fallback port, when one is found
- the command Airstrip ran
- a trimmed terminal excerpt

The Fix Error flow refreshes active ports and first shows Airstrip-controlled
options:

- explain which process is listening on the attempted port
- stop the confirmed listener and retry
- retry the project with the next suggested free port
- stop trying and leave the run as-is

AI escalation is available after these local controls. The chosen model receives
a bounded repair prompt with the project path, manifest web config, command,
port scan result, and the Airstrip controls that have already been offered.

## AI repair boundaries

The AI should prefer these fixes:

- make app code read `PORT` or `AIRSTRIP_PORT`
- make `airstrip.json` commands use `{PORT}`
- enable or explain manifest `allowPortFallback`
- use or explain Airstrip's existing controls: refresh ports, stop a confirmed
  listener, retry with a suggested port
- explain the active port owner and ask before stopping anything manually

The AI should not silently recommend destructive cleanup, broad process kills, or
changes outside the project folder. If a listener must be stopped, it should name
the exact process, pid, and port and ask the user to confirm.

## Port-control principle

Airstrip may detect and display port owners automatically. Stopping another
process remains an explicit user action because the occupied port may belong to a
different project, a browser preview, or a service the user intentionally started.
