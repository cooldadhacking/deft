const config = @import("config.zig");
const Key = config.Key;
const Modifier = config.Modifier;

// CGKeyCode constants - Arrows
pub const LEFT_ARROW: u16 = 0x7B;
pub const DOWN_ARROW: u16 = 0x7D;
pub const UP_ARROW: u16 = 0x7E;
pub const RIGHT_ARROW: u16 = 0x7C;

pub fn keycodeToKey(keycode: i64) ?Key {
    return switch (@as(u16, @intCast(keycode))) {
        // Letters
        0x00 => .A,
        0x01 => .S,
        0x02 => .D,
        0x03 => .F,
        0x04 => .H,
        0x22 => .I,
        0x1F => .O,
        0x10 => .Y,
        0x26 => .J,
        0x28 => .K,
        0x25 => .L,
        0x29 => .Semicolon,
        0x20 => .U,
        0x2D => .N,
        0x2E => .M,
        
        // Numbers
        0x1D => .Key0,
        0x12 => .Key1,
        0x13 => .Key2,
        0x14 => .Key3,
        0x15 => .Key4,
        0x17 => .Key5,
        0x16 => .Key6,
        0x1A => .Key7,
        0x1C => .Key8,
        0x19 => .Key9,
        
        // Special keys
        0x31 => .Space,
        0x30 => .Tab,
        0x24 => .Enter,
        0x35 => .Escape,
        0x33 => .Backspace,
        0x75 => .Delete,
        0x39 => .CapsLock,
        
        // Punctuation
        0x1B => .Minus,
        0x18 => .Equals,
        0x21 => .LeftBracket,
        0x1E => .RightBracket,
        0x2A => .Backslash,
        0x27 => .Quote,
        0x2B => .Comma,
        0x2F => .Period,
        0x2C => .Slash,
        0x32 => .Grave,
        
        // Arrows
        LEFT_ARROW => .LeftArrow,
        DOWN_ARROW => .DownArrow,
        UP_ARROW => .UpArrow,
        RIGHT_ARROW => .RightArrow,

        // Modifier keys
        0x3C => .RightShift,
        0x38 => .LeftShift,
        0x36 => .RightCommand,
        0x37 => .LeftCommand,
        0x3D => .RightOption,
        0x3A => .LeftOption,
        0x3E => .RightControl,
        0x3B => .LeftControl,

        else => null,
    };
}

pub fn keyToKeycode(key: Key) u16 {
    return switch (key) {
        // Letters
        .A => 0x00,
        .S => 0x01,
        .D => 0x02,
        .F => 0x03,
        .H => 0x04,
        .I => 0x22,
        .O => 0x1F,
        .Y => 0x10,
        .J => 0x26,
        .K => 0x28,
        .L => 0x25,
        .Semicolon => 0x29,
        .U => 0x20,
        .N => 0x2D,
        .M => 0x2E,
        
        // Numbers
        .Key0 => 0x1D,
        .Key1 => 0x12,
        .Key2 => 0x13,
        .Key3 => 0x14,
        .Key4 => 0x15,
        .Key5 => 0x17,
        .Key6 => 0x16,
        .Key7 => 0x1A,
        .Key8 => 0x1C,
        .Key9 => 0x19,
        
        // Special keys
        .Space => 0x31,
        .Tab => 0x30,
        .Enter => 0x24,
        .Escape => 0x35,
        .Backspace => 0x33,
        .Delete => 0x75,
        .CapsLock => 0x39,
        
        // Punctuation
        .Minus => 0x1B,
        .Equals => 0x18,
        .LeftBracket => 0x21,
        .RightBracket => 0x1E,
        .Backslash => 0x2A,
        .Quote => 0x27,
        .Comma => 0x2B,
        .Period => 0x2F,
        .Slash => 0x2C,
        .Grave => 0x32,
        
        // Arrows
        .LeftArrow => LEFT_ARROW,
        .DownArrow => DOWN_ARROW,
        .UpArrow => UP_ARROW,
        .RightArrow => RIGHT_ARROW,

        // Mouse actions (pseudo-keycodes, never used as real keycodes)
        .MouseLeftClick => 0xFFFC,
        .MouseRightClick => 0xFFFD,
        .MouseMoveUp => 0xFFF8,
        .MouseMoveDown => 0xFFF9,
        .MouseMoveLeft => 0xFFFA,
        .MouseMoveRight => 0xFFFB,

        // Modifier keys
        .RightShift => 0x3C,
        .LeftShift => 0x38,
        .RightCommand => 0x36,
        .LeftCommand => 0x37,
        .RightOption => 0x3D,
        .LeftOption => 0x3A,
        .RightControl => 0x3E,
        .LeftControl => 0x3B,
    };
}

// CGEventFlags  type and constants
pub const CGEventFlags = u64;
pub const kCGEventFlagMaskAlphaShift: u64 = 0x00010000;
pub const kCGEventFlagMaskShift: u64 = 0x00020000;
pub const kCGEventFlagMaskControl: u64 = 0x00040000;
pub const kCGEventFlagMaskAlternate: u64 = 0x00080000;
pub const kCGEventFlagMaskCommand: u64 = 0x00100000;
pub const kCGEventFlagMaskHelp: u64 = 0x00400000;
pub const kCGEventFlagMaskSecondaryFn: u64 = 0x00800000;
pub const kCGEventFlagMaskNumericPad: u64 = 0x00200000;

// Device-specific modifier key flags (low bits of CGEventFlags)
pub const NX_DEVICELCTLKEYMASK: u64 = 0x00000001;
pub const NX_DEVICELSHIFTKEYMASK: u64 = 0x00000002;
pub const NX_DEVICERSHIFTKEYMASK: u64 = 0x00000004;
pub const NX_DEVICELCMDKEYMASK: u64 = 0x00000008;
pub const NX_DEVICERCMDKEYMASK: u64 = 0x00000010;
pub const NX_DEVICELALTKEYMASK: u64 = 0x00000020;
pub const NX_DEVICERALTKEYMASK: u64 = 0x00000040;
pub const NX_DEVICERCTLKEYMASK: u64 = 0x00002000;

/// Returns true if the given modifier keycode is pressed based on device-specific flags.
pub fn isModifierPressed(kcode: u16, flags: u64) bool {
    return switch (kcode) {
        0x3C => (flags & NX_DEVICERSHIFTKEYMASK) != 0, // Right Shift
        0x38 => (flags & NX_DEVICELSHIFTKEYMASK) != 0, // Left Shift
        0x36 => (flags & NX_DEVICERCMDKEYMASK) != 0, // Right Command
        0x37 => (flags & NX_DEVICELCMDKEYMASK) != 0, // Left Command
        0x3D => (flags & NX_DEVICERALTKEYMASK) != 0, // Right Option
        0x3A => (flags & NX_DEVICELALTKEYMASK) != 0, // Left Option
        0x3E => (flags & NX_DEVICERCTLKEYMASK) != 0, // Right Control
        0x3B => (flags & NX_DEVICELCTLKEYMASK) != 0, // Left Control
        else => false,
    };
}

/// Returns true if the given Key is a modifier key (generates kCGEventFlagsChanged).
pub fn isModifierKey(key: Key) bool {
    return switch (key) {
        .RightShift, .LeftShift, .RightCommand, .LeftCommand, .RightOption, .LeftOption, .RightControl, .LeftControl => true,
        else => false,
    };
}
