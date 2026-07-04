# Deft

A keyboard remapper for macOS implementing home row mods, written in Zig.

## Features

- **Home Row Modifiers**: Transform A, S, D, F (left) and J, K, L, ; (right) into modifiers when held:
  - A/; → Command
  - S/L → Option
  - D/K → Control
  - F/J → Shift

- **Fast-Roll Detection**: Typing fast never swallows taps. If a home row key
  has been down for less than `chord_ms` when the next key arrives, it's
  treated as a rolled tap and emitted in press order; held longer, it chords
  into its modifier.

- **Extra Tap-Hold Keys**: Make any key tap-hold enabled!
  - Example: CapsLock → tap for Escape, hold for Control
  - Supports ~50 keys: letters, numbers, punctuation, special keys

- **Space Layer**: Hold Space for navigation — arrows on H/J/K/L, plus
  optional mouse movement and clicks on other keys. Modifiers stack with the
  layer: hold Option (or home-row S) + Space + H emits Option+Left for
  word-wise navigation. Cmd+Space and Ctrl+Space pass through untouched
  (Spotlight, input source switching).

- **Combos**: Press two keys together for a third (e.g. J+K → Escape)

- **Simple Remaps**: Unconditional key swaps (e.g. RightShift → Space)

- **Per-App Profiles**: Disable tap-hold/combos/layer per app bundle ID
  (e.g. turn everything off in games), switchable from the menu bar

- **Menu Bar Integration**: Runs as a background app with a keycap "d" icon
  - No dock icon for minimal distraction
  - On/off toggle, profile switcher, config reload, permission status

- **Self-Healing Permissions**: Prompts for Accessibility on first launch and
  retries automatically every few seconds — remapping starts the moment you
  grant access, no restart or manual toggle needed. Recovers if macOS
  disables the event tap under load.

- **Login Item Support**: Optional auto-start on login via SMAppService

- **JSON Configuration**: Easy-to-edit config file, no recompilation needed

## Building

Requires Zig 0.16:

```bash
# Install Zig via Homebrew (macOS)
brew install zig

# Build the project
zig build

# Run remapper logic tests
zig test src/layer_test.zig
```

### Building as a Signed .app Bundle (Required for stable permissions)

```bash
# 1. Build and create .app bundle
zig build bundle

# 2. Find your signing identity
security find-identity -v -p codesigning

# 3. Sign the app (replace with your identity)
./sign.sh "Developer ID Application: Your Name (TEAM123)"

# 4. Run the signed app
open zig-out/Deft.app

# 5. (Optional) Install to Applications folder
cp -r zig-out/Deft.app /Applications/
```

**Sign after every rebuild.** `zig build bundle` ad-hoc signs the app, and
macOS TCC identifies ad-hoc apps by a per-build code hash — an unsigned
rebuild silently invalidates your Accessibility and Input Monitoring grants
(the checkboxes still show ON while the event tap fails). A stable signing
identity makes permissions survive rebuilds. See [CODESIGNING.md](CODESIGNING.md).

If permissions ever get stuck: `tccutil reset Accessibility com.rayou.deft`,
`tccutil reset ListenEvent com.rayou.deft`, relaunch, re-grant.

## Menu Bar Controls

- **d** (keycap icon) — click to access the menu
- **On/Off** — toggle remapping
- **Profile** — cycle between Auto (per-app) and manual profiles
- **Open Config… / Reload Config** — edit and apply settings live
- **Accessibility / Input Monitoring** — live permission status; click to open
  System Settings
- **Start at Login** — launch automatically at system startup
- **Quit** — stop the application

## Configuration

Config is loaded from `~/.config/deft/config.json` if it exists, otherwise
from `config.json` in the working directory. Missing or invalid files fall
back to built-in defaults.

Timing semantics (defaults in parentheses):

- `tap_ms` (150) — max hold for Space and combo keys to still count as a tap
- `hold_ms` (200) — a home row key held this long becomes its modifier
- `chord_ms` (120) — the roll-vs-chord window: below it a home row key
  rolls (tap), above it it chords (modifier). Raise it if fast typing still
  triggers modifiers; lower it if chords feel sluggish.

Example `config.json`:
```json
{
  "timing": {
    "tap_ms": 150,
    "hold_ms": 200,
    "chord_ms": 120
  },
  "builtin_keyboard_only": false,
  "left_home_row": [
    { "key": "A", "modifier": "Command" }
  ],
  "space_layer": [
    { "from": "H", "to": "LeftArrow" },
    { "from": "Y", "to": "MouseMoveLeft" },
    { "from": "N", "to": "MouseLeftClick" }
  ],
  "extra_tap_holds": [
    { "key": "CapsLock", "tap": "Escape", "hold": "Control" }
  ],
  "combos": [
    { "key1": "J", "key2": "K", "output": "Escape" }
  ],
  "simple_remaps": [
    { "from": "RightShift", "to": "Space" }
  ],
  "profiles": {
    "fps": { "tap_hold": false, "combos": false, "space_layer": false }
  },
  "app_profiles": {
    "com.riotgames.LeagueOfLegends.GameClient": "fps"
  }
}
```

Other options:
- **builtin_keyboard_only** — only remap the built-in MacBook keyboard,
  external keyboards pass through untouched
- **space_layer** targets can be keys, `MouseMoveUp/Down/Left/Right`
  (accelerating cursor), or `MouseLeftClick`/`MouseRightClick`
- **profiles / app_profiles** — named feature toggles applied automatically
  when the matching app is frontmost, or manually via the menu bar

### Extra Tap-Hold Keys

The `extra_tap_holds` field (optional) lets you make **any** key tap-hold enabled:

- **CapsLock**: Tap for Escape, hold for Control (most popular!)
- **Tab**: Tap for Tab, hold for Hyper
- **Enter**: Tap for Enter, hold for Control

See [config-example-capslockesc.json](config-example-capslockesc.json) for a
complete example with CapsLock → Esc/Ctrl.

Available keys: `A`, `S`, `D`, `F`, `J`, `K`, `L`, `Semicolon`, `H`, `U`, `N`, `M`, `Space`, `Tab`, `Enter`, `Escape`, `Backspace`, `Delete`, `CapsLock`, `Key0`-`Key9`, `Minus`, `Equals`, `LeftBracket`, `RightBracket`, `Backslash`, `Quote`, `Comma`, `Period`, `Slash`, `Grave`, `LeftArrow`, `DownArrow`, `UpArrow`, `RightArrow`

Available modifiers: `Command`, `Option`, `Control`, `Shift`, `Hyper` (Cmd+Opt+Ctrl+Shift)

No recompilation needed — edit the JSON and click Reload Config in the menu bar.

## Permissions Required

This app requires two macOS permissions:

1. **Accessibility** — to create the event tap
2. **Input Monitoring** — to read and modify keyboard events

On first launch Deft prompts for Accessibility and appears in both permission
lists in System Settings → Privacy & Security. Grant them and remapping
starts within a few seconds — no restart needed. The menu bar shows the live
status of both permissions.

Only run one Deft instance at a time — multiple instances intercept each
other's synthetic events.

## Why Zig?

- **Direct C API access**: No wrapper crates needed, directly calls Core Graphics/Core Foundation
- **Small binary**: ~1.4MB compiled size
- **Explicit memory management**: Clear control over allocations
- **Fast compilation**: Zig compiles very quickly

## Project Structure

```
├── build.zig            # Build configuration and .app bundle step
├── generate_icons.py    # App + menu bar icon generator (stdlib only)
└── src/
    ├── main.zig         # Event tap, synthetic events, menu bar, permissions
    ├── config.zig       # Configuration types and defaults
    ├── keycode.zig      # Key code mappings and modifiers
    ├── remapper.zig     # Core remapping state machine (pure, testable)
    └── layer_test.zig   # Tests for layers, rolls, and chords
```

## Limitations

Modern macOS security restrictions may prevent event suppression even with proper permissions. If you see home row keys leaking through, consider using [Karabiner-Elements](https://karabiner-elements.pqrs.org/) which uses a DriverKit virtual HID device to work around these limitations.
