const std = @import("std");
const config = @import("config.zig");
const remapper = @import("remapper.zig");

// Busy-wait; no std sleep without an Io in Zig 0.16.
fn wait(ms: i128) void {
    const start = remapper.nanoTimestamp();
    while (remapper.nanoTimestamp() - start < ms * std.time.ns_per_ms) {}
}

test "home-row modifier combines with space layer" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    // Hold S (home-row Option), then Space (layer), then press H.
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x01)); // S down
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    try std.testing.expect(state.space_layer_active);
    wait(130); // hold space past chord_ms so it's a layer, not a rolled tap

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
    wait(130);
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
    wait(130); // past default chord_ms (120)
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
    wait(130);
    const action = try state.handleKeyDown(0x04); // H down
    switch (action) {
        .ReplaceWithKeyAndModifiers => |data| {
            try std.testing.expectEqual(config.Key.LeftArrow, data.key);
            try std.testing.expectEqual(@as(usize, 2), data.modifiers.len);
        },
        else => return error.WrongAction,
    }
}

test "space rolled into a layer key types space + letter" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    // Typing "a h": space down, H down a few ms later. H is a layer key but
    // this is typing, not navigation — space must flush and H pass through.
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    const action = try state.handleKeyDown(0x04); // H down immediately

    try std.testing.expectEqual(remapper.RemapAction.PassThrough, action);
    try std.testing.expect(!state.space_layer_active);
    const rolls = state.takePendingRolls();
    try std.testing.expectEqual(@as(usize, 1), rolls.len);
    try std.testing.expectEqual(config.Key.Space, rolls[0]);

    // Space release after the roll must not emit a second space.
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyUp(0x31));
}

test "long space hold without layer use still emits space" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    wait(160); // past default tap_ms (150)
    const action = try state.handleKeyUp(0x31);
    switch (action) {
        .ReplaceWithKey => |key| try std.testing.expectEqual(config.Key.Space, key),
        else => return error.WrongAction,
    }
}

test "space hold with layer use is suppressed on release" {
    var state = try remapper.RemapperState.init(std.testing.allocator, config.Config.default());
    defer state.deinit();

    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyDown(0x31)); // Space down
    wait(160);
    _ = try state.handleKeyDown(0x04); // H -> LeftArrow (layer used)
    try std.testing.expectEqual(remapper.RemapAction.Suppress, try state.handleKeyUp(0x31));
}
