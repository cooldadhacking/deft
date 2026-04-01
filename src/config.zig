const std = @import("std");

pub const Key = enum {
    // Letters
    A,
    S,
    D,
    F,
    J,
    K,
    L,
    Semicolon,
    H,
    I,
    O,
    Y,
    U,
    N,
    M,
    
    // Numbers
    Key0,
    Key1,
    Key2,
    Key3,
    Key4,
    Key5,
    Key6,
    Key7,
    Key8,
    Key9,
    
    // Special keys
    Space,
    Tab,
    Enter,
    Escape,
    Backspace,
    Delete,
    CapsLock,
    
    // Punctuation
    Minus,
    Equals,
    LeftBracket,
    RightBracket,
    Backslash,
    Quote,
    Comma,
    Period,
    Slash,
    Grave,
    
    // Arrows
    LeftArrow,
    DownArrow,
    UpArrow,
    RightArrow,

    // Mouse actions (for space layer / simple remaps)
    MouseLeftClick,
    MouseRightClick,
    MouseMoveUp,
    MouseMoveDown,
    MouseMoveLeft,
    MouseMoveRight,

    // Modifier keys (for simple remaps)
    RightShift,
    LeftShift,
    RightCommand,
    LeftCommand,
    RightOption,
    LeftOption,
    RightControl,
    LeftControl,
};

pub const Modifier = enum {
    Command,
    Option,
    Control,
    Shift,
    Hyper, // Cmd+Opt+Ctrl+Shift
};

pub const HomeRowKey = struct {
    tap: Key,
    hold: Modifier,
};

pub const TapHoldKey = struct {
    key: Key,
    tap: Key,
    hold: Modifier,
};

pub const LayerMapping = struct {
    from: Key,
    to: Key,
};

pub const ComboKey = struct {
    key1: Key,
    key2: Key,
    output: Key,
};

pub const SimpleRemap = struct {
    from: Key,
    to: Key,
};

pub const Profile = struct {
    tap_hold: bool = true,
    combos: bool = true,
    space_layer: bool = true,
};

pub const ProfileEntry = struct {
    name: []const u8,
    profile: Profile,
};

pub const AppProfileEntry = struct {
    bundle_id: []const u8,
    profile_name: []const u8,
};

pub const TimingConfig = struct {
    tap_ms: u64,
    hold_ms: u64,
    chord_ms: u64,
};

pub const Config = struct {
    timing: TimingConfig,
    left_home_row: []const HomeRowKey,
    right_home_row: []const HomeRowKey,
    space_layer: []const LayerMapping,
    extra_tap_holds: []const TapHoldKey,
    combos: []const ComboKey,
    simple_remaps: []const SimpleRemap,
    builtin_keyboard_only: bool,
    profiles: []const ProfileEntry,
    app_profiles: []const AppProfileEntry,

    pub const DEFAULT_LEFT_HOME_ROW = [_]HomeRowKey{
        .{ .tap = .A, .hold = .Command },
        .{ .tap = .S, .hold = .Option },
        .{ .tap = .D, .hold = .Control },
        .{ .tap = .F, .hold = .Shift },
    };

    pub const DEFAULT_RIGHT_HOME_ROW = [_]HomeRowKey{
        .{ .tap = .J, .hold = .Shift },
        .{ .tap = .K, .hold = .Control },
        .{ .tap = .L, .hold = .Option },
        .{ .tap = .Semicolon, .hold = .Command },
    };

    pub const DEFAULT_SPACE_LAYER = [_]LayerMapping{
        .{ .from = .H, .to = .LeftArrow },
        .{ .from = .J, .to = .DownArrow },
        .{ .from = .K, .to = .UpArrow },
        .{ .from = .L, .to = .RightArrow },
    };

    pub const DEFAULT_EXTRA_TAP_HOLDS = [_]TapHoldKey{};

    pub const DEFAULT_COMBOS = [_]ComboKey{};

    pub const DEFAULT_SIMPLE_REMAPS = [_]SimpleRemap{};

    pub const DEFAULT_PROFILES = [_]ProfileEntry{};
    pub const DEFAULT_APP_PROFILES = [_]AppProfileEntry{};

    pub fn getProfile(self: *const Config, name: []const u8) Profile {
        for (self.profiles) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.profile;
        }
        return .{}; // default: all true
    }

    pub fn default() Config {
        return .{
            .timing = .{
                .tap_ms = 150,
                .hold_ms = 200,
                .chord_ms = 120,
            },
            .left_home_row = &DEFAULT_LEFT_HOME_ROW,
            .right_home_row = &DEFAULT_RIGHT_HOME_ROW,
            .space_layer = &DEFAULT_SPACE_LAYER,
            .extra_tap_holds = &DEFAULT_EXTRA_TAP_HOLDS,
            .combos = &DEFAULT_COMBOS,
            .simple_remaps = &DEFAULT_SIMPLE_REMAPS,
            .builtin_keyboard_only = false,
            .profiles = &DEFAULT_PROFILES,
            .app_profiles = &DEFAULT_APP_PROFILES,
        };
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.debug.print("Could not open config file '{s}': {}, using defaults\n", .{ path, err });
            return default();
        };
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            std.debug.print("Could not read config file: {}, using defaults\n", .{err});
            return default();
        };
        defer allocator.free(content);

        const parsed = std.json.parseFromSlice(JsonConfig, allocator, content, .{}) catch |err| {
            std.debug.print("Could not parse config file: {}, using defaults\n", .{err});
            return default();
        };
        defer parsed.deinit();

        const json = parsed.value;

        // Allocate arrays for the config
        const left_home_row = try allocator.alloc(HomeRowKey, json.left_home_row.len);
        for (json.left_home_row, 0..) |item, i| {
            left_home_row[i] = .{
                .tap = std.meta.stringToEnum(Key, item.key) orelse .A,
                .hold = std.meta.stringToEnum(Modifier, item.modifier) orelse .Command,
            };
        }

        const right_home_row = try allocator.alloc(HomeRowKey, json.right_home_row.len);
        for (json.right_home_row, 0..) |item, i| {
            right_home_row[i] = .{
                .tap = std.meta.stringToEnum(Key, item.key) orelse .J,
                .hold = std.meta.stringToEnum(Modifier, item.modifier) orelse .Shift,
            };
        }

        const space_layer = try allocator.alloc(LayerMapping, json.space_layer.len);
        for (json.space_layer, 0..) |item, i| {
            space_layer[i] = .{
                .from = std.meta.stringToEnum(Key, item.from) orelse .H,
                .to = std.meta.stringToEnum(Key, item.to) orelse .LeftArrow,
            };
        }

        // Parse extra_tap_holds (optional)
        const extra_tap_holds = if (json.extra_tap_holds) |eth| blk: {
            const arr = try allocator.alloc(TapHoldKey, eth.len);
            for (eth, 0..) |item, i| {
                arr[i] = .{
                    .key = std.meta.stringToEnum(Key, item.key) orelse .CapsLock,
                    .tap = std.meta.stringToEnum(Key, item.tap) orelse .Escape,
                    .hold = std.meta.stringToEnum(Modifier, item.hold) orelse .Control,
                };
            }
            break :blk arr;
        } else &DEFAULT_EXTRA_TAP_HOLDS;

        // Parse combos (optional)
        const combos = if (json.combos) |cb| blk: {
            const arr = try allocator.alloc(ComboKey, cb.len);
            for (cb, 0..) |item, i| {
                arr[i] = .{
                    .key1 = std.meta.stringToEnum(Key, item.key1) orelse .J,
                    .key2 = std.meta.stringToEnum(Key, item.key2) orelse .K,
                    .output = std.meta.stringToEnum(Key, item.output) orelse .Escape,
                };
            }
            break :blk arr;
        } else &DEFAULT_COMBOS;

        // Parse simple_remaps (optional)
        const simple_remaps = if (json.simple_remaps) |sr| blk: {
            const arr = try allocator.alloc(SimpleRemap, sr.len);
            for (sr, 0..) |item, i| {
                const from_key = std.meta.stringToEnum(Key, item.from) orelse .RightShift;
                const to_key = std.meta.stringToEnum(Key, item.to) orelse .Space;
                arr[i] = .{
                    .from = from_key,
                    .to = to_key,
                };
            }
            break :blk arr;
        } else &DEFAULT_SIMPLE_REMAPS;

        // Parse profiles (optional map of name -> settings)
        const profiles = if (json.profiles) |prof_map| blk: {
            const keys = prof_map.map.keys();
            const vals = prof_map.map.values();
            const arr = try allocator.alloc(ProfileEntry, keys.len);
            for (keys, vals, 0..) |key, val, i| {
                arr[i] = .{
                    .name = try allocator.dupe(u8, key),
                    .profile = .{
                        .tap_hold = if (val.tap_hold) |v| v else true,
                        .combos = if (val.combos) |v| v else true,
                        .space_layer = if (val.space_layer) |v| v else true,
                    },
                };
            }
            break :blk arr;
        } else &DEFAULT_PROFILES;

        // Parse app_profiles (optional map of bundle_id -> profile_name)
        const app_profiles = if (json.app_profiles) |ap_map| blk: {
            const keys = ap_map.map.keys();
            const vals = ap_map.map.values();
            const arr = try allocator.alloc(AppProfileEntry, keys.len);
            for (keys, vals, 0..) |key, val, i| {
                arr[i] = .{
                    .bundle_id = try allocator.dupe(u8, key),
                    .profile_name = try allocator.dupe(u8, val),
                };
            }
            break :blk arr;
        } else &DEFAULT_APP_PROFILES;

        return .{
            .timing = .{
                .tap_ms = json.timing.tap_ms,
                .hold_ms = json.timing.hold_ms,
                .chord_ms = json.timing.chord_ms,
            },
            .left_home_row = left_home_row,
            .right_home_row = right_home_row,
            .space_layer = space_layer,
            .extra_tap_holds = extra_tap_holds,
            .combos = combos,
            .simple_remaps = simple_remaps,
            .builtin_keyboard_only = json.builtin_keyboard_only orelse false,
            .profiles = profiles,
            .app_profiles = app_profiles,
        };
    }

    pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        // Only free if not using default static arrays
        if (self.left_home_row.ptr != &DEFAULT_LEFT_HOME_ROW) {
            allocator.free(self.left_home_row);
        }
        if (self.right_home_row.ptr != &DEFAULT_RIGHT_HOME_ROW) {
            allocator.free(self.right_home_row);
        }
        if (self.space_layer.ptr != &DEFAULT_SPACE_LAYER) {
            allocator.free(self.space_layer);
        }
        if (self.extra_tap_holds.ptr != &DEFAULT_EXTRA_TAP_HOLDS) {
            allocator.free(self.extra_tap_holds);
        }
        if (self.combos.ptr != &DEFAULT_COMBOS) {
            allocator.free(self.combos);
        }
        if (self.simple_remaps.ptr != &DEFAULT_SIMPLE_REMAPS) {
            allocator.free(self.simple_remaps);
        }
        if (self.profiles.ptr != &DEFAULT_PROFILES) {
            for (self.profiles) |entry| {
                allocator.free(entry.name);
            }
            allocator.free(self.profiles);
        }
        if (self.app_profiles.ptr != &DEFAULT_APP_PROFILES) {
            for (self.app_profiles) |entry| {
                allocator.free(entry.bundle_id);
                allocator.free(entry.profile_name);
            }
            allocator.free(self.app_profiles);
        }
    }
};

const JsonProfileSettings = struct {
    tap_hold: ?bool = null,
    combos: ?bool = null,
    space_layer: ?bool = null,
};

const JsonConfig = struct {
    timing: struct {
        tap_ms: u64,
        hold_ms: u64,
        chord_ms: u64,
    },
    left_home_row: []struct {
        key: []const u8,
        modifier: []const u8,
    },
    right_home_row: []struct {
        key: []const u8,
        modifier: []const u8,
    },
    space_layer: []struct {
        from: []const u8,
        to: []const u8,
    },
    extra_tap_holds: ?[]struct {
        key: []const u8,
        tap: []const u8,
        hold: []const u8,
    } = null,
    combos: ?[]struct {
        key1: []const u8,
        key2: []const u8,
        output: []const u8,
    } = null,
    simple_remaps: ?[]struct {
        from: []const u8,
        to: []const u8,
    } = null,
    builtin_keyboard_only: ?bool = null,
    profiles: ?std.json.ArrayHashMap(JsonProfileSettings) = null,
    app_profiles: ?std.json.ArrayHashMap([]const u8) = null,
};
