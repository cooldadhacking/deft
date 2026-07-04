const std = @import("std");
const config = @import("config.zig");
const keycode = @import("keycode.zig");

const Config = config.Config;
const Key = config.Key;
const Modifier = config.Modifier;

/// Monotonic clock in nanoseconds (std.time.nanoTimestamp was removed in Zig 0.16).
pub fn nanoTimestamp() i128 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

const KeyState = union(enum) {
    Idle,
    Down: i128, // Timestamp in nanoseconds
    Tapped,
    Held,
    ComboFired,
};

pub const RemapAction = union(enum) {
    PassThrough,
    Suppress,
    ReplaceWithKey: Key,
    ApplyModifiers: []const Modifier,
    ReplaceWithKeyAndModifiers: struct { key: Key, modifiers: []const Modifier },
};

const TapHoldInfo = struct {
    tap: Key,
    hold: Modifier,
};

pub const RemapperState = struct {
    config: Config,
    key_states: std.AutoHashMap(Key, KeyState),
    space_layer_active: bool,
    active_modifiers: std.ArrayList(Modifier),
    allocator: std.mem.Allocator,
    active_profile: config.Profile,
    // Taps flushed by fast-roll detection, waiting to be emitted before the
    // key event that triggered the flush. Drained via takePendingRolls().
    roll_buf: [8]Key,
    roll_len: usize,

    pub fn init(allocator: std.mem.Allocator, cfg: Config) !RemapperState {
        return .{
            .config = cfg,
            .key_states = std.AutoHashMap(Key, KeyState).init(allocator),
            .space_layer_active = false,
            .active_modifiers = .empty,
            .allocator = allocator,
            .active_profile = .{},
            .roll_buf = undefined,
            .roll_len = 0,
        };
    }

    /// Returns taps buffered by roll detection and clears the buffer.
    /// The caller must emit these before acting on the current key event.
    pub fn takePendingRolls(self: *RemapperState) []const Key {
        const n = self.roll_len;
        self.roll_len = 0;
        return self.roll_buf[0..n];
    }

    pub fn deinit(self: *RemapperState) void {
        self.key_states.deinit();
        self.active_modifiers.deinit(self.allocator);
    }

    fn getTapHoldInfo(self: *const RemapperState, key: Key) ?TapHoldInfo {
        // Check home row keys
        for (self.config.left_home_row) |hrk| {
            if (hrk.tap == key) return .{ .tap = hrk.tap, .hold = hrk.hold };
        }
        for (self.config.right_home_row) |hrk| {
            if (hrk.tap == key) return .{ .tap = hrk.tap, .hold = hrk.hold };
        }
        // Check extra tap-hold keys
        for (self.config.extra_tap_holds) |eth| {
            if (eth.key == key) return .{ .tap = eth.tap, .hold = eth.hold };
        }
        return null;
    }

    fn isHomeRowKey(self: *const RemapperState, key: Key) bool {
        return self.getTapHoldInfo(key) != null;
    }

    fn isComboKey(self: *const RemapperState, key: Key) bool {
        for (self.config.combos) |combo| {
            if (combo.key1 == key or combo.key2 == key) return true;
        }
        return false;
    }

    /// Check if the incoming key + any currently-Down key forms a combo within chord_ms.
    /// Returns the combo output key if a match is found.
    fn checkCombos(self: *RemapperState, incoming_key: Key, incoming_time: i128) ?Key {
        for (self.config.combos) |combo| {
            const partner: ?Key = if (combo.key1 == incoming_key)
                combo.key2
            else if (combo.key2 == incoming_key)
                combo.key1
            else
                null;

            if (partner) |p| {
                if (self.key_states.get(p)) |state| {
                    switch (state) {
                        .Down => |down_time| {
                            const elapsed_ns = incoming_time - down_time;
                            const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                            if (elapsed_ms <= self.config.timing.chord_ms) {
                                return combo.output;
                            }
                        },
                        else => {},
                    }
                }
            }
        }
        return null;
    }

    pub fn handleKeyDown(self: *RemapperState, keycode_val: i64) !RemapAction {
        std.debug.print("Key down: keycode={d}, space_layer_active: {}, active_modifiers: {any}\n", .{ keycode_val, self.space_layer_active, self.active_modifiers.items });

        const key_opt = keycode.keycodeToKey(keycode_val);
        const profile = self.active_profile;

        // --- Combo check (only when combos enabled) ---
        if (profile.combos) {
            if (key_opt) |k| {
                const now = nanoTimestamp();
                if (self.checkCombos(k, now)) |combo_output| {
                    std.debug.print("Combo fired! {s} + another key -> {s}\n", .{ @tagName(k), @tagName(combo_output) });
                    for (self.config.combos) |combo| {
                        if ((combo.key1 == k or combo.key2 == k) and combo.output == combo_output) {
                            try self.key_states.put(combo.key1, .ComboFired);
                            try self.key_states.put(combo.key2, .ComboFired);
                            break;
                        }
                    }
                    return .{ .ReplaceWithKey = combo_output };
                }

                // Suppress key repeats for ComboFired keys
                if (self.key_states.get(k)) |state| {
                    if (state == .ComboFired) {
                        return .Suppress;
                    }
                }
            }
        }

        // --- Chord detection and modifier updates (only when tap_hold enabled) ---
        if (profile.tap_hold) {
            const is_incoming_home_row = if (key_opt) |k|
                self.isHomeRowKey(k) or k == .Space
            else
                false;

            if (!is_incoming_home_row) {
                _ = try self.checkAndActivateChords();
            }

            try self.updateHeldModifiers();
        }

        if (key_opt) |k| {
            // --- Space layer (only when space_layer enabled) ---
            if (profile.space_layer) {
                if (k == .Space) {
                    if (self.key_states.get(.Space)) |state| {
                        switch (state) {
                            .Down, .Held => {
                                std.debug.print("Suppressing space key repeat\n", .{});
                                return .Suppress;
                            },
                            else => {},
                        }
                    }

                    try self.key_states.put(.Space, .{ .Down = nanoTimestamp() });
                    self.space_layer_active = true;
                    std.debug.print("Space layer activated\n", .{});
                    return .Suppress;
                }

                if (self.space_layer_active) {
                    for (self.config.space_layer) |mapping| {
                        if (k == mapping.from) {
                            std.debug.print("Space layer mapping: {s} -> {s} (modifiers: {any})\n", .{ @tagName(k), @tagName(mapping.to), self.active_modifiers.items });
                            return .{ .ReplaceWithKeyAndModifiers = .{ .key = mapping.to, .modifiers = self.active_modifiers.items } };
                        }
                    }
                }
            }

            // --- Tap-hold / home-row key handling ---
            const is_home_row = self.isHomeRowKey(k);

            if (is_home_row) {
                if (!profile.tap_hold) {
                    // tap_hold OFF: check if this key is also a combo key and combos are ON
                    if (profile.combos and self.isComboKey(k)) {
                        // Still suppress for combo detection window
                        if (self.key_states.get(k)) |state| {
                            if (state == .Down) {
                                std.debug.print("Suppressing combo-key repeat for {s}\n", .{@tagName(k)});
                                return .Suppress;
                            }
                        }
                        std.debug.print("Combo key (tap_hold off): {s}, marking as down\n", .{@tagName(k)});
                        try self.key_states.put(k, .{ .Down = nanoTimestamp() });
                        return .Suppress;
                    }
                    // Pass through instantly — no modifier, no suppression
                    std.debug.print("Tap-hold off, passing through home-row key {s}\n", .{@tagName(k)});
                    return .PassThrough;
                }

                // tap_hold ON: normal behavior
                if (self.key_states.get(k)) |state| {
                    switch (state) {
                        .Down, .Held => {
                            std.debug.print("Suppressing home-row key repeat for {s}\n", .{@tagName(k)});
                            return .Suppress;
                        },
                        else => {},
                    }
                }

                if (self.active_modifiers.items.len > 0) {
                    std.debug.print("Home row key {s} pressed with active modifiers: {any}\n", .{ @tagName(k), self.active_modifiers.items });
                    return .{ .ApplyModifiers = self.active_modifiers.items };
                }

                std.debug.print("Home row key detected: {s}, marking as down\n", .{@tagName(k)});
                try self.key_states.put(k, .{ .Down = nanoTimestamp() });
                return .Suppress;
            }

            // --- Combo-only key handling ---
            if (self.isComboKey(k)) {
                if (!profile.combos) {
                    // combos OFF: pass through instantly
                    std.debug.print("Combos off, passing through combo key {s}\n", .{@tagName(k)});
                    return .PassThrough;
                }

                if (self.key_states.get(k)) |state| {
                    switch (state) {
                        .Down => {
                            std.debug.print("Suppressing combo-key repeat for {s}\n", .{@tagName(k)});
                            return .Suppress;
                        },
                        else => {},
                    }
                }

                std.debug.print("Combo key detected: {s}, marking as down\n", .{@tagName(k)});
                try self.key_states.put(k, .{ .Down = nanoTimestamp() });
                return .Suppress;
            }
        }

        // For all other keys, apply active modifiers if any
        if (self.active_modifiers.items.len > 0) {
            if (key_opt) |k| {
                std.debug.print("Applying modifiers {any} to mapped key {s}\n", .{ self.active_modifiers.items, @tagName(k) });
            } else {
                std.debug.print("Applying modifiers {any} to unmapped keycode {d}\n", .{ self.active_modifiers.items, keycode_val });
            }
            return .{ .ApplyModifiers = self.active_modifiers.items };
        } else {
            std.debug.print("Passing through keycode {d} with no modifiers\n", .{keycode_val});
            return .PassThrough;
        }
    }

    pub fn handleKeyUp(self: *RemapperState, keycode_val: i64) !RemapAction {
        const key = keycode.keycodeToKey(keycode_val) orelse return .PassThrough;
        const profile = self.active_profile;

        std.debug.print("Key up: {s}\n", .{@tagName(key)});

        // Handle space layer deactivation (only when space_layer enabled)
        if (key == .Space and profile.space_layer) {
            self.space_layer_active = false;
            std.debug.print("Space layer deactivated\n", .{});

            if (self.key_states.get(key)) |state| {
                if (state == .Down) {
                    const elapsed_ns = nanoTimestamp() - state.Down;
                    const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                    std.debug.print("Space held for {d}ms\n", .{elapsed_ms});

                    if (elapsed_ms < self.config.timing.tap_ms) {
                        try self.key_states.put(key, .Tapped);
                        return .{ .ReplaceWithKey = .Space };
                    }
                }
                try self.key_states.put(key, .Idle);
                return .Suppress;
            }

            // Space wasn't tracked (passed through with real modifiers), pass through keyup too
            return .PassThrough;
        }

        // Handle ComboFired state (only when combos enabled)
        if (profile.combos) {
            if (self.key_states.get(key)) |state| {
                if (state == .ComboFired) {
                    std.debug.print("Combo key {s} released, suppressing\n", .{@tagName(key)});
                    try self.key_states.put(key, .Idle);
                    return .Suppress;
                }
            }
        }

        // Check home-row modifier keys (only process tap/hold release when tap_hold enabled)
        if (self.getModifierForKey(key)) |modifier| {
            if (!profile.tap_hold) {
                // tap_hold OFF: check if this was suppressed for combo detection
                if (profile.combos and self.isComboKey(key)) {
                    if (self.key_states.get(key)) |state| {
                        if (state == .Down) {
                            // Was buffered for combo, emit as tap
                            std.debug.print("Combo-buffered home-row key {s} released (tap_hold off)\n", .{@tagName(key)});
                            try self.key_states.put(key, .Tapped);
                            if (self.getTapHoldInfo(key)) |info| {
                                return .{ .ReplaceWithKey = info.tap };
                            }
                            return .{ .ReplaceWithKey = key };
                        }
                    }
                }
                // Otherwise pass through (key was never suppressed)
                return .PassThrough;
            }

            // tap_hold ON: normal release handling
            var i: usize = 0;
            while (i < self.active_modifiers.items.len) {
                if (self.active_modifiers.items[i] == modifier) {
                    _ = self.active_modifiers.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
            std.debug.print("Key up for home-row key {s}, removed modifier {s}\n", .{ @tagName(key), @tagName(modifier) });

            if (self.key_states.get(key)) |state| {
                switch (state) {
                    .Held => {
                        std.debug.print("Home row key {s} was used as modifier, suppressing release\n", .{@tagName(key)});
                        try self.key_states.put(key, .Idle);
                        return .Suppress;
                    },
                    .Down => |down_time| {
                        const elapsed_ns = nanoTimestamp() - down_time;
                        const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                        std.debug.print("Home row key {s} was held for {d}ms\n", .{ @tagName(key), elapsed_ms });

                        if (elapsed_ms < self.config.timing.hold_ms) {
                            std.debug.print("Tap detected for {s}, emitting it\n", .{@tagName(key)});
                            try self.key_states.put(key, .Tapped);
                            if (self.getTapHoldInfo(key)) |info| {
                                return .{ .ReplaceWithKey = info.tap };
                            }
                            return .{ .ReplaceWithKey = key };
                        } else {
                            try self.key_states.put(key, .Idle);
                            return .Suppress;
                        }
                    },
                    else => {
                        try self.key_states.put(key, .Idle);
                    },
                }
            }
        }

        // Handle combo-only keys (in a combo but not a home-row key)
        if (!self.isHomeRowKey(key) and self.isComboKey(key)) {
            if (!profile.combos) return .PassThrough;

            if (self.key_states.get(key)) |state| {
                if (state == .Down) {
                    const elapsed_ns = nanoTimestamp() - state.Down;
                    const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                    std.debug.print("Combo-only key {s} released after {d}ms\n", .{ @tagName(key), elapsed_ms });

                    if (elapsed_ms < self.config.timing.tap_ms) {
                        try self.key_states.put(key, .Tapped);
                        return .{ .ReplaceWithKey = key };
                    } else {
                        try self.key_states.put(key, .Idle);
                        return .Suppress;
                    }
                }
            }
        }

        return .PassThrough;
    }

    const RollEntry = struct { key: Key, time: i128 };

    /// Decide what a currently-down tap-hold key means now that another key
    /// has been pressed: held at least chord_ms -> it's a chord, activate the
    /// modifier; younger than that -> it's a fast typing roll, flush its tap.
    /// With the space layer active a chord is always intended, so no roll check.
    fn considerChordKey(self: *RemapperState, state_key: Key, tap_out: Key, hold: Modifier, now: i128, rolls: *[8]RollEntry, roll_len: *usize, activated: *usize) !void {
        const state = self.key_states.get(state_key) orelse return;
        if (state != .Down) return;
        const down_time = state.Down;
        const elapsed_ms = @divTrunc(now - down_time, std.time.ns_per_ms);

        if (elapsed_ms < self.config.timing.chord_ms and !self.space_layer_active and roll_len.* < rolls.len) {
            std.debug.print("Roll detected: {s} down only {d}ms, flushing as tap\n", .{ @tagName(state_key), elapsed_ms });
            try self.key_states.put(state_key, .Tapped);
            rolls[roll_len.*] = .{ .key = tap_out, .time = down_time };
            roll_len.* += 1;
            return;
        }

        std.debug.print("Chord detected! Activating {s} as modifier after {d}ms\n", .{ @tagName(state_key), elapsed_ms });
        try self.key_states.put(state_key, .Held);
        activated.* += 1;
        for (self.active_modifiers.items) |m| {
            if (m == hold) return;
        }
        try self.active_modifiers.append(self.allocator, hold);
    }

    fn checkAndActivateChords(self: *RemapperState) !usize {
        var activated_count: usize = 0;
        var rolls: [8]RollEntry = undefined;
        var roll_len: usize = 0;

        const now = nanoTimestamp();

        for (self.config.left_home_row) |hrk| {
            try self.considerChordKey(hrk.tap, hrk.tap, hrk.hold, now, &rolls, &roll_len, &activated_count);
        }
        for (self.config.right_home_row) |hrk| {
            try self.considerChordKey(hrk.tap, hrk.tap, hrk.hold, now, &rolls, &roll_len, &activated_count);
        }
        for (self.config.extra_tap_holds) |eth| {
            try self.considerChordKey(eth.key, eth.tap, eth.hold, now, &rolls, &roll_len, &activated_count);
        }

        // Buffer rolled taps in press order for the caller to emit.
        std.mem.sort(RollEntry, rolls[0..roll_len], {}, struct {
            fn lessThan(_: void, a: RollEntry, b: RollEntry) bool {
                return a.time < b.time;
            }
        }.lessThan);
        for (rolls[0..roll_len], 0..) |entry, i| {
            self.roll_buf[i] = entry.key;
        }
        self.roll_len = roll_len;

        return activated_count;
    }

    fn updateHeldModifiers(self: *RemapperState) !void {
        self.active_modifiers.clearRetainingCapacity();

        std.debug.print("updateHeldModifiers called, checking key states...\n", .{});

        const now = nanoTimestamp();

        for (self.config.left_home_row) |hrk| {
            if (self.key_states.get(hrk.tap)) |state| {
                switch (state) {
                    .Down => |down_time| {
                        const elapsed_ns = now - down_time;
                        const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                        if (elapsed_ms >= self.config.timing.hold_ms) {
                            std.debug.print("Activating modifier {s} for {s} after {d}ms\n", .{ @tagName(hrk.hold), @tagName(hrk.tap), elapsed_ms });
                            try self.active_modifiers.append(self.allocator, hrk.hold);
                            try self.key_states.put(hrk.tap, .Held);
                        } else {
                            std.debug.print("Key {s} down for {d}ms, not yet at threshold\n", .{ @tagName(hrk.tap), elapsed_ms });
                        }
                    },
                    .Held => {
                        std.debug.print("Keeping modifier {s} active for held key {s}\n", .{ @tagName(hrk.hold), @tagName(hrk.tap) });
                        try self.active_modifiers.append(self.allocator, hrk.hold);
                    },
                    else => {},
                }
            }
        }

        for (self.config.right_home_row) |hrk| {
            if (self.key_states.get(hrk.tap)) |state| {
                switch (state) {
                    .Down => |down_time| {
                        const elapsed_ns = now - down_time;
                        const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                        if (elapsed_ms >= self.config.timing.hold_ms) {
                            std.debug.print("Activating modifier {s} for {s} after {d}ms\n", .{ @tagName(hrk.hold), @tagName(hrk.tap), elapsed_ms });
                            try self.active_modifiers.append(self.allocator, hrk.hold);
                            try self.key_states.put(hrk.tap, .Held);
                        } else {
                            std.debug.print("Key {s} down for {d}ms, not yet at threshold\n", .{ @tagName(hrk.tap), elapsed_ms });
                        }
                    },
                    .Held => {
                        std.debug.print("Keeping modifier {s} active for held key {s}\n", .{ @tagName(hrk.hold), @tagName(hrk.tap) });
                        try self.active_modifiers.append(self.allocator, hrk.hold);
                    },
                    else => {},
                }
            }
        }

        // Check extra tap-hold keys
        for (self.config.extra_tap_holds) |eth| {
            if (self.key_states.get(eth.key)) |state| {
                switch (state) {
                    .Down => |down_time| {
                        const elapsed_ns = now - down_time;
                        const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
                        if (elapsed_ms >= self.config.timing.hold_ms) {
                            std.debug.print("Activating modifier {s} for {s} after {d}ms\n", .{ @tagName(eth.hold), @tagName(eth.key), elapsed_ms });
                            try self.active_modifiers.append(self.allocator, eth.hold);
                            try self.key_states.put(eth.key, .Held);
                        } else {
                            std.debug.print("Key {s} down for {d}ms, not yet at threshold\n", .{ @tagName(eth.key), elapsed_ms });
                        }
                    },
                    .Held => {
                        std.debug.print("Keeping modifier {s} active for held key {s}\n", .{ @tagName(eth.hold), @tagName(eth.key) });
                        try self.active_modifiers.append(self.allocator, eth.hold);
                    },
                    else => {},
                }
            }
        }

        std.debug.print("After update: active_modifiers = {any}\n", .{self.active_modifiers.items});
    }

    fn getModifierForKey(self: *const RemapperState, key: Key) ?Modifier {
        if (self.getTapHoldInfo(key)) |info| {
            return info.hold;
        }
        return null;
    }
};
