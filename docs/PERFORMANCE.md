# Resource use and verification

## Design constraints

- No clipboard observer, idle animation, translation polling loop, or permanent
  keyboard event monitor. The global shortcut uses the macOS event dispatcher.
- Context observers are installed only for an in-flight editable-selection
  translation and removed on every completion, error, or termination path.
- The progress ring runs at 15 FPS only while working. Streaming preview updates
  are coalesced to at most 10 per second with one-shot timers; idle drawing is static.
- The configuration window's SwiftUI view tree is released after closing.
- A shared ephemeral URLSession reuses connections without disk cache, cookies,
  or stored HTTP credentials. Its redirect delegate does not form a retain cycle.
- Requests do not retry automatically, and overlapping shortcuts are ignored.
- Source text is limited to 30,000 UTF-16 code units; streamed output is capped at
  120,000. A pull-based response sequence applies backpressure without an unbounded
  producer queue; network tasks are cancelled on every response exit path.
  Replacement snapshots
  retain at most 1,000,000 code units of full field text; larger fields use copy
  delivery. Only the latest preview is retained in memory until the next request
  or process exit; no text is written to a history file.
- Full clipboard representations are materialized only for the Copy fallback.
  Image/file/PDF payloads skip this probe, and retained representations are bounded
  to 4 MiB. A newer clipboard write is never overwritten during probe restoration.
- Sparkle uses a static release-asset feed once per day by default, rather than
  frequent GitHub API polling. Automatic downloads/installation are disabled.

## Local sample — 2026-10-25

An earlier production arm64 build, before bidirectional streaming, was launched
on this Mac and sampled four times with
`top -l 4 -s 2 -pid <pid> -stats pid,command,cpu,mem,threads,power` while no
translation was active. Desktop automation was not approved for the new app, so
the configuration window's actual visible state was not inspected.

| Metric | Observed value |
| --- | --- |
| CPU | 0.0% in all four samples |
| top memory footprint | approximately 42 MiB |
| Threads | 3–4 |
| top POWER score | 0.0 in all four samples |
| ps resident memory (different accounting) | 118,512 KiB |

These are short observations for the then-current build, not resource ceilings
or evidence of long-term battery impact. The `top` POWER score is not a wattmeter.
The window-close release, bounded clipboard, and streaming changes were made
after this sample and must not be described as independently measured improvements.

## Verification limits

Automated checks cover API request/response handling, credential scope, profile
deletion, output routing, target changes, and release/workflow rules. Build and
packaging verify native and universal binaries and app signatures. They do not
substitute for a desktop acceptance run in TextEdit, browser inputs, and PDF apps.

Actual LLM translation and cross-app replacement have not been tested with a real
user API key or granted Accessibility permission in this session. No older
released build existed to test an actual Sparkle download/install/relaunch cycle.
Long-duration memory growth, active-request energy use, and Intel runtime behavior
remain separate verification tasks. The Intel slice is cross-compiled locally.
