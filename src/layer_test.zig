const std = @import("std");
const config = @import("config.zig");
const remapper = @import("remapper.zig");

test "home-row modifier combines with space layer" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    // Hold S (home-row Option), then Space (layer), then press H.
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x01)); // S down
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    try std.testing.expect(state.space_layer_active);

    const action = try state.handleKeyDown(0x04); // H down
    switch (action) {
        .ReplaceWithKeyAndModifiers => |data| {
            try std.testing.expectEqual(config.Key.LeftArrow, data.key);
            try std.testing.expectEqual(@as(usize, 1), data.modifiers.len);
            try std.testing.expectEqual(config.Modifier.Option, data.modifiers[0]);
        },
        else => return error.WrongAction,
    }
}

test "space layer alone still emits plain arrow" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    const action = try state.handleKeyDown(0x04); // H down
    switch (action) {
        .ReplaceWithKeyAndModifiers => |data| {
            try std.testing.expectEqual(config.Key.LeftArrow, data.key);
            try std.testing.expectEqual(@as(usize, 0), data.modifiers.len);
        },
        else => return error.WrongAction,
    }
}

test "fast roll flushes home-row tap instead of firing modifier" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    // Type "so" fast: S down, O down a few ms later. S must come out as a
    // tap, not convert to Option.
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x01)); // S down
    const action = try state.handleKeyDown(0x1F); // O down immediately after

    try std.testing.expectEqual(remapper.RemapAction.PassThrough, action);
    const rolls = state.takePendingRolls();
    try std.testing.expectEqual(@as(usize, 1), rolls.len);
    try std.testing.expectEqual(config.Key.S, rolls[0]);
    try std.testing.expectEqual(@as(usize, 0), state.active_modifiers.items.len);
}

test "held home-row key past chord_ms still chords" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x01)); // S down
    // Busy-wait past default chord_ms (120); no std sleep without an Io in 0.16.
    const start = remapper.nanoTimestamp();
    while (remapper.nanoTimestamp() - start < 130 * std.time.ns_per_ms) {}
    const action = try state.handleKeyDown(0x1F); // O down

    switch (action) {
        .ApplyModifiers => |mods| {
            try std.testing.expectEqual(@as(usize, 1), mods.len);
            try std.testing.expectEqual(config.Modifier.Option, mods[0]);
        },
        else => return error.WrongAction,
    }
    try std.testing.expectEqual(@as(usize, 0), state.takePendingRolls().len);
}

test "two home-row modifiers stack onto space layer" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x01)); // S down (Option)
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x03)); // F down (Shift)
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    const action = try state.handleKeyDown(0x04); // H down
    switch (action) {
        .ReplaceWithKeyAndModifiers => |data| {
            try std.testing.expectEqual(config.Key.LeftArrow, data.key);
            try std.testing.expectEqual(@as(usize, 2), data.modifiers.len);
        },
        else => return error.WrongAction,
    }
}
