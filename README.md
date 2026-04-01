# Deft

A keyboard remapper for macOS implementing home row mods, written in Zig.

## Features

- **Home Row Modifiers**: Transform A, S, D, F (left) and J, K, L, ; (right) into modifiers when held:
  - A/; → Command
  - S/L → Option
  - D/K → Control
  - F/J → Shift

- **Extra Tap-Hold Keys**: Make any key tap-hold enabled!
  - Example: CapsLock → tap for Escape, hold for Control
  - Supports ~50 keys: letters, numbers, punctuation, special keys

- **Space Layer**: Hold Space to activate arrow keys on H, J, K, L

- **Chord Detection**: Press a home row key followed by another key quickly to activate the modifier

- **Menu Bar Integration**: Runs as a background app with menu bar icon (⌨︎)
  - No dock icon for minimal distraction
  - Easy access to quit and settings

- **Login Item Support**: Optional auto-start on login
  - Toggle via menu bar "Start at Login" option
  - Uses modern macOS SMAppService API

- **JSON Configuration**: Easy-to-edit config file, no recompilation needed

- **Tap-Hold Timing**:
  - Tap threshold: 150ms
  - Hold threshold: 200ms
  - Chord threshold: 120ms

## Building

Requires Zig 0.15.2 or later:

```bash
# Install Zig via Homebrew (macOS)
brew install zig

# Build the project
zig build

# Run the executable
./zig-out/bin/deft
```

### Building as Signed .app Bundle (Recommended)

To avoid security software flags (like CrowdStrike), create a proper signed macOS app:

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

The signed `.app` bundle includes:
- Proper Info.plist with bundle identifier
- Privacy usage descriptions for Accessibility and Input Monitoring
- Code signature to prove authenticity
- Menu bar integration with no dock icon

A keyboard icon (⌨︎) will appear in your menu bar when the app is running.

## Menu Bar Controls

- **⌨︎** - Click to access the menu
- **Start at Login** - Toggle to launch automatically at system startup
- **Quit** - Stop the application (⌘Q also works)

## Configuration

The program loads settings from `config.json` in the current directory. If the file doesn't exist or has errors, it uses built-in defaults.

Edit `config.json` to customize:
- **Timing thresholds** (tap_ms, hold_ms, chord_ms)
- **builtin_keyboard_only** - Set to `true` to only affect built-in MacBook keyboard (experimental, may not work perfectly)
- **Home row key mappings** (which keys become which modifiers)
- **Space layer mappings** (which keys become arrows when holding space)
- **Extra tap-hold keys** (like CapsLock → Escape/Control)

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
    { "from": "H", "to": "LeftArrow" }
  ],
  "extra_tap_holds": [
    {
      "key": "CapsLock",
      "tap": "Escape",
      "hold": "Control"
    }
  ]
}
```

### Extra Tap-Hold Keys

The `extra_tap_holds` field (optional) lets you make **any** key tap-hold enabled:

- **CapsLock**: Tap for Escape, hold for Control (most popular!)
- **Tab**: Tap for Tab, hold for Hyper
- **Enter**: Tap for Enter, hold for Control
- Any other key you want

See [config-example-capslockesc.json](config-example-capslockesc.json) for a complete example with CapsLock → Esc/Ctrl.

Available keys: `A`, `S`, `D`, `F`, `J`, `K`, `L`, `Semicolon`, `H`, `U`, `N`, `M`, `Space`, `Tab`, `Enter`, `Escape`, `Backspace`, `Delete`, `CapsLock`, `Key0`-`Key9`, `Minus`, `Equals`, `LeftBracket`, `RightBracket`, `Backslash`, `Quote`, `Comma`, `Period`, `Slash`, `Grave`, `LeftArrow`, `DownArrow`, `UpArrow`, `RightArrow`

Available modifiers: `Command`, `Option`, `Control`, `Shift`, `Hyper` (Cmd+Opt+Ctrl+Shift)

No recompilation needed - just edit the JSON and restart the program!

## Permissions Required

This app requires two macOS permissions:

1. **Accessibility** - To listen to keyboard events
2. **Input Monitoring** - To modify/suppress events

Grant these in:
- System Settings → Privacy & Security → Accessibility → Add Terminal (or your terminal app)
- System Settings → Privacy & Security → Input Monitoring → Add Terminal

**Important**: Restart your terminal completely after granting permissions.

## Why Zig?

- **Direct C API access**: No wrapper crates needed, directly calls Core Graphics/Core Foundation
- **Small binary**: ~1.4MB compiled size
- **Explicit memory management**: Clear control over allocations
- **Fast compilation**: Zig compiles very quickly
- **Simple cross-platform**: Easy to build on different systems

## Project Structure

```
├── build.zig          # Build configuration
└── src/
    ├── main.zig       # Event tap setup and callbacks
    ├── config.zig     # Configuration types and defaults
    ├── keycode.zig    # Key code mappings and modifiers
    └── remapper.zig   # Core remapping state machine
```

## Limitations

Modern macOS security restrictions may prevent event suppression even with proper permissions. If you see home row keys leaking through, consider using [Karabiner-Elements](https://karabiner-elements.pqrs.org/) which uses a DriverKit virtual HID device to work around these limitations.
