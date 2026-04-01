# Flexibility Roadmap

## Issues with Current Design

### 1. Limited Key Coverage
```zig
// Current: Only 20 keys
pub const Key = enum {
    A, S, D, F, J, K, L, Semicolon, Space, H, U, N, M,
    LeftArrow, DownArrow, UpArrow, RightArrow,
};

// Needed: ~100+ keys for full keyboard
// Missing: 0-9, F1-F12, Tab, Enter, Escape, Caps, `, -, =, [, ], \, ', ,, ., /, etc.
```

### 2. Hardcoded Home Row Logic
```zig
// Current: remapper.zig has hardcoded isHomeRowKey() check
fn isHomeRowKey(self: *const RemapperState, key: Key) bool {
    // Only checks against config's home_row arrays
}

// Needed: Generic tap-hold for ANY key
// Config should look like:
{
  "tap_hold_keys": [
    { "key": "A", "tap": "A", "hold": "Command" },
    { "key": "CapsLock", "tap": "Escape", "hold": "Control" },
    { "key": "Tab", "tap": "Tab", "hold": "Hyper" }
  ]
}
```

### 3. Hardcoded Space Layer
```zig
// Current: Only supports Space as layer trigger
if (key == .Space) {
    self.space_layer_active = true;
}

// Needed: Multiple layers with any trigger key
{
  "layers": [
    {
      "trigger": "Space",
      "mappings": [
        { "from": "H", "to": "LeftArrow" }
      ]
    },
    {
      "trigger": "CapsLock", 
      "mappings": [
        { "from": "HJKL", "to": "Arrows" },
        { "from": "ASDF", "to": "MediaKeys" }
      ]
    }
  ]
}
```

### 4. Rigid Config Structure
```zig
// Current: Forces specific field names
pub const Config = struct {
    timing: TimingConfig,
    left_home_row: []const HomeRowKey,   // Hardcoded
    right_home_row: []const HomeRowKey,  // Hardcoded
    space_layer: []const LayerMapping,   // Hardcoded
};

// Needed: Flexible structure
pub const Config = struct {
    timing: TimingConfig,
    tap_hold_keys: []const TapHoldKey,  // Any key can be tap-hold
    layers: []const Layer,               // Multiple layers with any trigger
    simple_remaps: []const SimpleRemap, // One-to-one key remaps
};
```

## Required Changes

### Phase 1: Expand Key Enum
- [ ] Add numbers 0-9
- [ ] Add function keys F1-F12
- [ ] Add punctuation: `, -, =, [, ], \, ', ,, ., /
- [ ] Add special keys: Tab, Enter, Escape, Backspace, Delete, CapsLock
- [ ] Add modifier keys themselves: LeftCommand, RightCommand, etc.

### Phase 2: Generalize Tap-Hold
- [ ] Remove `isHomeRowKey()` hardcoded logic
- [ ] Create generic `TapHoldKey` type
- [ ] Rewrite handleKeyDown/Up to check against tap_hold_keys config
- [ ] Support tap producing different key than base (e.g., CapsLock → Escape on tap)

### Phase 3: Generalize Layers
- [ ] Remove hardcoded `space_layer_active` boolean
- [ ] Support multiple active layers simultaneously
- [ ] Support any key as layer trigger (not just Space)
- [ ] Implement layer priority system

### Phase 4: Add Simple Remaps
- [ ] Support one-to-one key remapping (e.g., CapsLock → Control always)
- [ ] These are simpler than tap-hold, useful for permanent swaps

## Config Example (Future)

```json
{
  "timing": {
    "tap_ms": 150,
    "hold_ms": 200,
    "chord_ms": 120
  },
  "tap_hold_keys": [
    { "key": "A", "tap": "A", "hold": "Command" },
    { "key": "S", "tap": "S", "hold": "Option" },
    { "key": "CapsLock", "tap": "Escape", "hold": "Control" },
    { "key": "Tab", "tap": "Tab", "hold": "Hyper" }
  ],
  "layers": [
    {
      "name": "nav",
      "trigger": "Space",
      "mappings": [
        { "from": "H", "to": "LeftArrow" },
        { "from": "J", "to": "DownArrow" },
        { "from": "K", "to": "UpArrow" },
        { "from": "L", "to": "RightArrow" }
      ]
    },
    {
      "name": "numbers",
      "trigger": "CapsLock",
      "mappings": [
        { "from": "A", "to": "1" },
        { "from": "S", "to": "2" },
        { "from": "D", "to": "3" }
      ]
    }
  ],
  "simple_remaps": [
    { "from": "CapsLock", "to": "Control" }
  ]
}
```

## Compatibility Note

This would be a **breaking change** to the config format. Consider:
- Version field in config.json
- Migration tool from v1 → v2 config
- Keep v1 parser for backward compatibility
