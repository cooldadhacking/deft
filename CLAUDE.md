# deft — macOS keyboard remapper (Zig)

Menu-bar app that remaps keys via a CGEventTap: home-row tap-hold modifiers,
a space-held navigation layer, combos, and per-app profiles.

## Build & run

Requires Zig 0.16.

```bash
zig build                    # binary at zig-out/bin/deft
zig build bundle             # Deft.app at zig-out/Deft.app (ad-hoc signed!)
./sign.sh "Developer ID Application: RAMBO ANDERSON-YOU (S22F3UYNLS)"
zig test src/layer_test.zig  # remapper logic tests (not part of zig build)
```

**IMPORTANT: always run `sign.sh` after `zig build bundle`.** The bundle step
ad-hoc signs the app, and macOS TCC identifies ad-hoc apps by per-build code
hash — an unsigned rebuild silently invalidates the Accessibility and Input
Monitoring grants (the checkboxes in System Settings still show ON while the
event tap fails). A stable Developer ID signature makes grants survive rebuilds.

If permissions get stuck anyway: `tccutil reset Accessibility com.rayou.deft`
and `tccutil reset ListenEvent com.rayou.deft`, relaunch, re-grant. The app
retries the event tap every 3s, so grants take effect without a restart or
clicking "On". Only ever run ONE deft instance — multiple instances intercept
each other's synthetic events.

## Config

Loaded from `~/.config/deft/config.json` if present, else `./config.json`.
Timing semantics:
- `tap_ms` — max hold for Space (and combo keys) to still count as a tap
- `hold_ms` — a home-row key held this long becomes its modifier
- `chord_ms` — roll-vs-chord window: if a home-row key has been down less
  than this when the next key arrives, it's a fast typing roll and its tap is
  flushed; past it, it chords into a modifier

## Architecture

- `src/main.zig` — event tap, synthetic event emission, menu bar (raw objc),
  IOHID keyboard detection, permission retry timer. CoreGraphics/IOKit symbols
  are declared by hand in the `cg` struct because recent SDK headers use
  blocks and array-nullability syntax that Zig's translate-c cannot parse —
  don't add those frameworks back to `@cImport`.
- `src/remapper.zig` — pure key-state machine (`handleKeyDown`/`handleKeyUp`
  return `RemapAction`s; no OS calls, which is what makes it testable).
  Fast-roll taps are buffered and drained via `takePendingRolls()`.
- `src/config.zig` — JSON config, defaults, profiles.
- `src/keycode.zig` — macOS virtual keycode <-> `Key` enum, CGEventFlags masks.
