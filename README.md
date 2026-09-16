# Tars

A full-screen native iOS companion: two pixel eyes, four states, no account or pairing screen.

## Open on iPhone

Open `Tars.xcodeproj` in Xcode, select your personal development team under Signing & Capabilities, select your phone, and run. Allow Local Network access. Keep the phone and Mac on the same local network. The app connects automatically to the first discovered `_tars._tcp` server. Bonjour discovers network reachability, not physical distance.

Tap the face to show or hide state and connection information. Waiting and working use true black; approval uses orange; completion uses dark green for five seconds. The app respects Reduce Motion. Static states have no animation loop. It leaves system auto-lock enabled.

## Communication

Native `NWBrowser` → Bonjour → `NWConnection` → newline-delimited JSON. Each connection receives a complete snapshot. Subsequent state changes are pushed immediately. Packets carry a server-session UUID and monotonic sequence number. Heartbeats repeat the existing sequence so they do not replay completion. Active heartbeat: 20 seconds; idle heartbeat: 120 seconds. The client disconnects in the background, reconnects when active, rejects malformed/oversized input, and uses bounded reconnect backoff.

Only aggregate state and source availability travel over the network. No prompts, project paths, session identifiers from agents, commands, or approval actions are exposed.

This development prototype intentionally omits pairing and uses unauthenticated local TCP. Use it on a trusted local network. Four-digit pairing with authenticated encryption, direct agent adapters, BLE, and remote notifications are future work; there are no placeholder pairing screens. An app in the background is not a live status monitor.

## Build

The generated Xcode project is included; XcodeGen is only needed after changing `project.yml`.

```zsh
xcodebuild -project Tars.xcodeproj -scheme Tars \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/iOS CODE_SIGNING_ALLOWED=NO build
```

For visual inspection, Debug builds accept `--preview-state waiting`, `working`, `approval`, or `completed`. Preview is explicit and does not connect to the live source. Normal launches always discover a server.

## Agent hooks

Tars uses the agents' own lifecycle hooks as the source of truth, the same approach as [codestatus](https://github.com/henriquegpb/codestatus). No Vibe Island or other bridge is required.

In the Mac app, Settings → Agents toggles Claude Code and Codex. That stages `~/.tars/bin/tars-hook` (and `tars-hook-codex`) and registers it in `~/.claude/settings.json` and `~/.codex/hooks.json`; the config file is backed up alongside first. Only entries whose command is exactly our hook path are ever touched. Codex requires you to trust the entries once via `/hooks`. From the CLI:

```zsh
/usr/bin/python3 Mac/install-hooks.py install   # or: install claude | remove codex | status
```

The hook (`Mac/hook.py`) reads one payload from stdin, projects it to a hashed session key, a normalized state and one clipped detail line (current tool, question, or last assistant message, ≤160 chars), and pushes that to a **loopback-only** listener on 17894 with a 50 ms budget. It always exits 0 and is registered `async` for Claude Code. Events: SessionStart, UserPromptSubmit, Pre/PostToolUse, PostToolUseFailure, PermissionRequest/Denied, Notification (permission_prompt, idle_prompt), Elicitation, Stop, StopFailure, SessionEnd. Questions (`AskUserQuestion`, `ExitPlanMode`) show as approval. Priority: approval → working → completed → waiting. A silent session expires after 30 minutes because hooks provide no liveness query; a turn you interrupt keeps its last state until you type again.

## Checks

```zsh
/usr/bin/python3 Tests/test_hook.py
xcrun swiftc Mac/Server.swift Mac/main.swift -o /tmp/tars-server
python3 Tests/test_server.py /tmp/tars-server
```

The integration test uses separate ports 27893/27894 and does not inject into Vibe Island. It checks fresh snapshots, fragmented input, priority, sequence increments, five-second completion, reconnect, and input limits.

## Verified on this Mac

- Xcode 27.0 simulator build succeeded; app installed and launched on iPhone 17 Pro / iOS 26.5.
- Four displays inspected from actual simulator screenshots (`waiting.png`, `working.png`, `approval.png`, `completed.png`).
- Bonjour discovery and automatic reconnection after server restart verified with established app/server connections.
- Mirror → native Mac push → iOS approval display verified with an explicit fixture sent through a no-op original launcher; no synthetic event was injected into Vibe Island. One local mirror-to-push check took 49 ms including Python startup; this is not a physical-phone latency benchmark.
- Seven mirror checks and the isolated server integration check passed.
- The reversible mirror was installed, and its `--help` preserved the original helper behavior. The Mac server remains running for future events.

Still unverified: a real post-install agent event, physical iPhone discovery/permission behavior, battery consumption, and hardware display refresh rate. This Xcode installation exposes the simulator runtime through `simctl` but has no discoverable Simulator.app GUI; simulator launch and screenshots work.
