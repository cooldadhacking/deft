const std = @import("std");
const config = @import("config.zig");
const keycode = @import("keycode.zig");
const remapper = @import("remapper.zig");

// Import Core Foundation and Objective-C runtime C APIs
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

// CoreGraphics event-tap and IOKit HID APIs, declared by hand: recent SDK
// headers for these frameworks use blocks (`^`) and nullability annotations
// on array parameters, which Zig 0.16's translate-c cannot parse.
const cg = struct {
    pub const CGEvent = opaque {};
    pub const CGEventRef = ?*CGEvent;
    pub const CGEventSource = opaque {};
    pub const CGEventSourceRef = ?*CGEventSource;
    pub const CGEventTapProxy = ?*anyopaque;
    pub const CGEventType = u32;
    pub const CGEventMask = u64;
    pub const CGEventFlags = u64;
    pub const CGKeyCode = u16;
    pub const CGEventField = u32;
    pub const CGEventSourceStateID = i32;
    pub const CGPoint = extern struct { x: f64, y: f64 };
    pub const CGEventTapCallBack = *const fn (CGEventTapProxy, CGEventType, CGEventRef, ?*anyopaque) callconv(.c) CGEventRef;

    // CGEventTypes.h (values shared with IOLLEvent.h NX_* constants)
    pub const kCGEventLeftMouseDown: CGEventType = 1;
    pub const kCGEventLeftMouseUp: CGEventType = 2;
    pub const kCGEventRightMouseDown: CGEventType = 3;
    pub const kCGEventRightMouseUp: CGEventType = 4;
    pub const kCGEventMouseMoved: CGEventType = 5;
    pub const kCGEventKeyDown: CGEventType = 10;
    pub const kCGEventKeyUp: CGEventType = 11;
    pub const kCGEventFlagsChanged: CGEventType = 12;
    pub const kCGEventTapDisabledByTimeout: CGEventType = 0xFFFFFFFE;
    pub const kCGEventTapDisabledByUserInput: CGEventType = 0xFFFFFFFF;

    pub const kCGKeyboardEventKeycode: CGEventField = 9;
    pub const kCGKeyboardEventKeyboardType: CGEventField = 10;

    pub const kCGHIDEventTap: u32 = 0; // CGEventTapLocation
    pub const kCGSessionEventTap: u32 = 1;
    pub const kCGHeadInsertEventTap: u32 = 0; // CGEventTapPlacement
    pub const kCGEventTapOptionDefault: u32 = 0; // CGEventTapOptions
    pub const kCGMouseButtonLeft: u32 = 0;
    pub const kCGMouseButtonRight: u32 = 1;
    pub const kCGEventSourceStateHIDSystemState: CGEventSourceStateID = 1;

    pub extern "c" fn CGEventTapCreate(tap: u32, place: u32, options: u32, events_of_interest: CGEventMask, callback: CGEventTapCallBack, user_info: ?*anyopaque) c.CFMachPortRef;
    pub extern "c" fn CGEventTapEnable(tap: c.CFMachPortRef, enable: bool) void;
    pub extern "c" fn CGEventGetIntegerValueField(event: CGEventRef, field: CGEventField) i64;
    pub extern "c" fn CGEventSetIntegerValueField(event: CGEventRef, field: CGEventField, value: i64) void;
    pub extern "c" fn CGEventGetFlags(event: CGEventRef) CGEventFlags;
    pub extern "c" fn CGEventSetFlags(event: CGEventRef, flags: CGEventFlags) void;
    pub extern "c" fn CGEventCreate(source: CGEventSourceRef) CGEventRef;
    pub extern "c" fn CGEventCreateKeyboardEvent(source: CGEventSourceRef, virtual_key: CGKeyCode, key_down: bool) CGEventRef;
    pub extern "c" fn CGEventCreateMouseEvent(source: CGEventSourceRef, mouse_type: CGEventType, position: CGPoint, button: u32) CGEventRef;
    pub extern "c" fn CGEventGetLocation(event: CGEventRef) CGPoint;
    pub extern "c" fn CGEventPost(tap: u32, event: CGEventRef) void;
    pub extern "c" fn CGEventSourceCreate(state_id: CGEventSourceStateID) CGEventSourceRef;

    // IOKit/hid (IOHIDManager.h, IOHIDDeviceKeys.h)
    pub const IOHIDManager = opaque {};
    pub const IOHIDManagerRef = ?*IOHIDManager;
    pub const IOHIDDevice = opaque {};
    pub const IOHIDDeviceRef = ?*IOHIDDevice;
    pub const IOReturn = c_int;
    pub const kIOReturnSuccess: IOReturn = 0;
    pub const kIOHIDOptionsTypeNone: u32 = 0;
    pub const kIOHIDTransportKey = "Transport";
    pub const kIOHIDVendorIDKey = "VendorID";
    pub const kIOHIDProductKey = "Product";
    pub const kIOHIDDeviceUsageKey = "DeviceUsage";
    pub const kIOHIDDeviceUsagePageKey = "DeviceUsagePage";

    pub extern "c" fn IOHIDManagerCreate(allocator: c.CFAllocatorRef, options: u32) IOHIDManagerRef;
    pub extern "c" fn IOHIDManagerSetDeviceMatching(manager: IOHIDManagerRef, matching: c.CFDictionaryRef) void;
    pub extern "c" fn IOHIDManagerOpen(manager: IOHIDManagerRef, options: u32) IOReturn;
    pub extern "c" fn IOHIDManagerClose(manager: IOHIDManagerRef, options: u32) IOReturn;
    pub extern "c" fn IOHIDManagerCopyDevices(manager: IOHIDManagerRef) c.CFSetRef;
    pub extern "c" fn IOHIDDeviceGetProperty(device: IOHIDDeviceRef, key: c.CFStringRef) c.CFTypeRef;
};

const Config = config.Config;
const Key = config.Key;
const RemapperState = remapper.RemapperState;
const RemapAction = remapper.RemapAction;

const KEYCODE_DELETE: cg.CGKeyCode = 51; // Backspace/Delete key

// Declare AppKit / ApplicationServices functions
extern "c" fn NSApplicationLoad() c_int;
extern "c" fn AXIsProcessTrusted() bool;
extern "c" fn AXIsProcessTrustedWithOptions(options: ?*const anyopaque) bool;

// Properly typed objc_msgSend wrappers for ARM64
// On ARM64, objc_msgSend is not a normal variadic function - it's a trampoline
// We need to cast it to the exact signature for each use case

fn msgSend_ptr(target: *anyopaque, sel: ?*c.struct_objc_selector) callconv(.c) *anyopaque {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector) callconv(.c) *anyopaque, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel);
}

fn msgSend_ptr_ptr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: *anyopaque) callconv(.c) *anyopaque {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, *anyopaque) callconv(.c) *anyopaque, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel, arg1);
}

fn msgSend_void(target: *anyopaque, sel: ?*c.struct_objc_selector) callconv(.c) void {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector) callconv(.c) void, .{ .name = "objc_msgSend" });
    objc_msgSend(target, sel);
}

fn msgSend_void_ptr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: *anyopaque) callconv(.c) void {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, *anyopaque) callconv(.c) void, .{ .name = "objc_msgSend" });
    objc_msgSend(target, sel, arg1);
}

fn msgSend_void_long(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: c_long) callconv(.c) void {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, c_long) callconv(.c) void, .{ .name = "objc_msgSend" });
    objc_msgSend(target, sel, arg1);
}

fn msgSend_ptr_f64(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: f64) callconv(.c) *anyopaque {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, f64) callconv(.c) *anyopaque, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel, arg1);
}

fn msgSend_ptr_cstr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: [*:0]const u8) callconv(.c) *anyopaque {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, [*:0]const u8) callconv(.c) *anyopaque, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel, arg1);
}

fn msgSend_ptr_ptr_sel_ptr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: *anyopaque, arg2: ?*c.struct_objc_selector, arg3: *anyopaque) callconv(.c) *anyopaque {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, *anyopaque, ?*c.struct_objc_selector, *anyopaque) callconv(.c) *anyopaque, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel, arg1, arg2, arg3);
}

fn msgSend_long(target: *anyopaque, sel: ?*c.struct_objc_selector) callconv(.c) c_long {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector) callconv(.c) c_long, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel);
}

fn msgSend_bool_ptrptr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: *?*anyopaque) callconv(.c) bool {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, *?*anyopaque) callconv(.c) bool, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel, arg1);
}

fn msgSend_void_bool(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: bool) callconv(.c) void {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, bool) callconv(.c) void, .{ .name = "objc_msgSend" });
    objc_msgSend(target, sel, arg1);
}

fn msgSend_bool_ptr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: *anyopaque) callconv(.c) bool {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, *anyopaque) callconv(.c) bool, .{ .name = "objc_msgSend" });
    return objc_msgSend(target, sel, arg1);
}

fn msgSend_void_ptr_sel_ptr_ptr(target: *anyopaque, sel: ?*c.struct_objc_selector, arg1: *anyopaque, arg2: ?*c.struct_objc_selector, arg3: ?*anyopaque, arg4: ?*anyopaque) callconv(.c) void {
    const objc_msgSend = @extern(*const fn (*anyopaque, ?*c.struct_objc_selector, *anyopaque, ?*c.struct_objc_selector, ?*anyopaque, ?*anyopaque) callconv(.c) void, .{ .name = "objc_msgSend" });
    objc_msgSend(target, sel, arg1, arg2, arg3, arg4);
}

// Global state for the event callback
var global_remapper: *RemapperState = undefined;
var global_allocator: std.mem.Allocator = undefined;
var global_io: std.Io = undefined;
var global_app: ?*anyopaque = null;
var global_status_item: ?*anyopaque = null;
var global_delegate: ?*anyopaque = null;
var global_builtin_keyboard_only: bool = false;
var global_builtin_kb_type: ?i64 = null;
var global_enabled: bool = true;
var global_enabled_item: ?*anyopaque = null;
var global_config: ?*Config = null;
var global_event_tap_active: bool = false;
var global_event_tap: c.CFMachPortRef = null;
var global_permission_timer: c.CFRunLoopTimerRef = null;
var global_accessibility_item: ?*anyopaque = null;
var global_input_monitoring_item: ?*anyopaque = null;
var global_config_path_buf: [std.fs.max_path_bytes]u8 = undefined;
var global_config_path: ?[]const u8 = null;
var global_profile_item: ?*anyopaque = null;
var global_active_profile_name_buf: [64]u8 = undefined;
var global_active_profile_name: []const u8 = "default";
var global_profile_override: bool = false; // true = manual override active

// Mouse movement state
const MouseMoveState = struct {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    start_time: i128 = 0,
    timer: c.CFRunLoopTimerRef = null,

    fn anyActive(self: *const MouseMoveState) bool {
        return self.up or self.down or self.left or self.right;
    }

    fn isActive(self: *const MouseMoveState, key: Key) bool {
        return switch (key) {
            .MouseMoveUp => self.up,
            .MouseMoveDown => self.down,
            .MouseMoveLeft => self.left,
            .MouseMoveRight => self.right,
            else => false,
        };
    }
};
var mouse_move_state = MouseMoveState{};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    global_allocator = allocator;
    global_io = init.io;

    const cfg = try allocator.create(Config);

    // Resolve config path: ~/.config/deft/config.json first, then ./config.json
    const config_file = blk: {
        if (std.c.getenv("HOME")) |home_z| {
            const home = std.mem.sliceTo(home_z, 0);
            const xdg_path = std.fmt.bufPrint(&global_config_path_buf, "{s}/.config/deft/config.json", .{home}) catch break :blk "config.json";
            if (std.Io.Dir.cwd().access(global_io, xdg_path, .{})) |_| {
                global_config_path = xdg_path;
                break :blk xdg_path;
            } else |_| {}
        }
        // Fall back to ./config.json
        global_config_path = if (std.c.realpath("config.json", &global_config_path_buf)) |p|
            std.mem.sliceTo(p, 0)
        else
            null;
        break :blk global_config_path orelse "config.json";
    };

    cfg.* = try Config.loadFromFile(allocator, global_io, config_file);
    global_config = cfg;

    global_builtin_keyboard_only = cfg.builtin_keyboard_only;
    detectBuiltinKeyboardType();

    std.debug.print("deft starting with config:\n", .{});
    std.debug.print("  Tap threshold: {d}ms\n", .{cfg.timing.tap_ms});
    std.debug.print("  Hold threshold: {d}ms\n", .{cfg.timing.hold_ms});
    std.debug.print("  Chord threshold: {d}ms\n", .{cfg.timing.chord_ms});
    std.debug.print("  Combos: {d}\n", .{cfg.combos.len});
    std.debug.print("  Built-in keyboard only: {}\n", .{cfg.builtin_keyboard_only});
    std.debug.print("  Profiles: {d}\n", .{cfg.profiles.len});
    std.debug.print("  App profiles: {d}\n", .{cfg.app_profiles.len});

    const remap = try allocator.create(RemapperState);
    remap.* = try RemapperState.init(allocator, cfg.*);
    global_remapper = remap;

    // Check for --headless flag
    const headless = blk: {
        for (init.minimal.args.vector[1..]) |arg_z| {
            if (std.mem.eql(u8, std.mem.sliceTo(arg_z, 0), "--headless")) break :blk true;
        }
        break :blk false;
    };

    if (headless) {
        std.debug.print("Running in headless mode (no menu bar)\n", .{});
        startEventTap();
        c.CFRunLoopRun();
        return;
    }

    // Initialize AppKit for menu bar
    if (NSApplicationLoad() == 0) {
        std.debug.print("Warning: Failed to load NSApplication\n", .{});
    }

    const NSApp_class = c.objc_getClass("NSApplication") orelse {
        std.debug.print("Warning: NSApplication class not found, continuing without menu bar\n", .{});
        startEventTap();
        c.CFRunLoopRun();
        return;
    };

    const app = msgSend_ptr(NSApp_class, c.sel_registerName("sharedApplication"));
    global_app = app;

    // Set activation policy to accessory (no dock icon): NSApplicationActivationPolicyAccessory = 1
    msgSend_void_long(app, c.sel_registerName("setActivationPolicy:"), 1);

    // Create menu bar item
    createMenuBar();

    // Prompt for accessibility permission if not granted
    if (!AXIsProcessTrusted()) {
        // Create options dict with kAXTrustedCheckOptionPrompt = true to show system dialog
        const key = c.CFStringCreateWithCString(null, "AXTrustedCheckOptionPrompt", c.kCFStringEncodingUTF8);
        const value = c.kCFBooleanTrue;
        var keys = [_]?*const anyopaque{@ptrCast(key)};
        var values = [_]?*const anyopaque{@ptrCast(value)};
        const options = c.CFDictionaryCreate(null, &keys, &values, 1, &c.kCFTypeDictionaryKeyCallBacks, &c.kCFTypeDictionaryValueCallBacks);
        _ = AXIsProcessTrustedWithOptions(options);
        c.CFRelease(options);
        c.CFRelease(key);
    }

    // Try to start event tap (may fail if permissions not yet granted)
    startEventTap();
    if (!global_event_tap_active) {
        global_enabled = false;
    }
    updateEnabledItemTitle();

    // Set up workspace observer for app-based profile switching
    setupWorkspaceObserver();

    // Run the NSApplication event loop — required for menu bar click handling
    std.debug.print("Starting event loop...\n", .{});
    msgSend_void(app, c.sel_registerName("run"));
}

fn createMenuBar() void {
    // Create delegate first - it handles menu action callbacks
    setupMenuHandlers();

    const NSStatusBar = c.objc_getClass("NSStatusBar") orelse return;
    const systemBar = msgSend_ptr(NSStatusBar, c.sel_registerName("systemStatusBar"));

    // Create status item with variable length (-1.0 = NSVariableStatusItemLength)
    const statusItem = msgSend_ptr_f64(systemBar, c.sel_registerName("statusItemWithLength:"), -1.0);
    _ = msgSend_ptr(statusItem, c.sel_registerName("retain"));
    global_status_item = statusItem;

    // Get button and set icon (or fallback to text)
    const button = msgSend_ptr(statusItem, c.sel_registerName("button"));
    const NSString_class = c.objc_getClass("NSString") orelse return;

    const icon_set = blk: {
        const NSImage_class = c.objc_getClass("NSImage") orelse break :blk false;
        const icon_name_cstr: [*:0]const u8 = "menubar_icon";
        const icon_name = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), icon_name_cstr);
        const image = msgSend_ptr_ptr(NSImage_class, c.sel_registerName("imageNamed:"), icon_name);
        if (@intFromPtr(image) == 0) break :blk false;
        msgSend_void_bool(image, c.sel_registerName("setTemplate:"), true);
        msgSend_void_ptr(button, c.sel_registerName("setImage:"), image);
        break :blk true;
    };

    if (!icon_set) {
        const title_cstr: [*:0]const u8 = "d";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        msgSend_void_ptr(button, c.sel_registerName("setTitle:"), title);
    }

    // Create menu
    const NSMenu_class = c.objc_getClass("NSMenu") orelse return;
    const menu_alloc = msgSend_ptr(NSMenu_class, c.sel_registerName("alloc"));
    const menu = msgSend_ptr(menu_alloc, c.sel_registerName("init"));
    const NSMenuItem_class = c.objc_getClass("NSMenuItem") orelse return;
    const emptyKey_cstr: [*:0]const u8 = "";
    const emptyKey = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), emptyKey_cstr);
    const delegate = global_delegate.?;

    // --- On/Off toggle item ---
    {
        const title_cstr: [*:0]const u8 = "\xe2\x97\x8b Off"; // ○ Off
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("toggleEnabled:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        global_enabled_item = item;
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- Profile item ---
    {
        const title_cstr: [*:0]const u8 = "Profile: Auto";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("toggleProfile:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        global_profile_item = item;
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- Separator ---
    msgSend_void_ptr(menu, c.sel_registerName("addItem:"),
        msgSend_ptr(NSMenuItem_class, c.sel_registerName("separatorItem")));

    // --- "Open Config..." item ---
    {
        const title_cstr: [*:0]const u8 = "Open Config\xe2\x80\xa6"; // ellipsis character
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("openConfig:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- "Reload Config" item ---
    {
        const title_cstr: [*:0]const u8 = "Reload Config";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("reloadConfig:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- Separator ---
    msgSend_void_ptr(menu, c.sel_registerName("addItem:"),
        msgSend_ptr(NSMenuItem_class, c.sel_registerName("separatorItem")));

    // --- Accessibility status item (click opens settings) ---
    {
        const title_cstr: [*:0]const u8 = "Accessibility";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("openAccessibilitySettings:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        global_accessibility_item = item;
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- Input Monitoring status item (click opens settings) ---
    {
        const title_cstr: [*:0]const u8 = "Input Monitoring";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("openInputMonitoringSettings:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        global_input_monitoring_item = item;
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- Separator ---
    msgSend_void_ptr(menu, c.sel_registerName("addItem:"),
        msgSend_ptr(NSMenuItem_class, c.sel_registerName("separatorItem")));

    // --- "Start at Login" item ---
    {
        const title_cstr: [*:0]const u8 = "Start at Login";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("toggleLoginItem:"), emptyKey);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), delegate);
        if (isLoginItem()) {
            msgSend_void_long(item, c.sel_registerName("setState:"), 1);
        }
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // --- Separator ---
    msgSend_void_ptr(menu, c.sel_registerName("addItem:"),
        msgSend_ptr(NSMenuItem_class, c.sel_registerName("separatorItem")));

    // --- "Quit" item ---
    {
        const title_cstr: [*:0]const u8 = "Quit";
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), title_cstr);
        const item_alloc = msgSend_ptr(NSMenuItem_class, c.sel_registerName("alloc"));
        const key_cstr: [*:0]const u8 = "q";
        const key = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), key_cstr);
        const item = msgSend_ptr_ptr_sel_ptr(item_alloc,
            c.sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, c.sel_registerName("terminate:"), key);
        msgSend_void_ptr(item, c.sel_registerName("setTarget:"), global_app.?);
        msgSend_void_ptr(menu, c.sel_registerName("addItem:"), item);
    }

    // Set menu delegate (for menuWillOpen: to refresh permission status)
    msgSend_void_ptr(menu, c.sel_registerName("setDelegate:"), delegate);

    // Set menu on status item
    msgSend_void_ptr(statusItem, c.sel_registerName("setMenu:"), menu);

    std.debug.print("Menu bar created successfully\n", .{});
}

fn setupMenuHandlers() void {
    const NSObject = c.objc_getClass("NSObject") orelse return;
    const DelegateClass = c.objc_allocateClassPair(NSObject, "MenuDelegate", 0);
    if (DelegateClass) |cls| {
        const method_type = "v@:@";
        _ = c.class_addMethod(cls, c.sel_registerName("toggleLoginItem:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&toggleLoginItemHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("toggleEnabled:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&toggleEnabledHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("openConfig:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&openConfigHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("reloadConfig:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&reloadConfigHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("openAccessibilitySettings:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&openAccessibilitySettingsHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("openInputMonitoringSettings:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&openInputMonitoringSettingsHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("menuWillOpen:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&menuWillOpenHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("toggleProfile:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&toggleProfileHandler))), method_type);
        _ = c.class_addMethod(cls, c.sel_registerName("appDidActivate:"),
            @ptrCast(@as(*const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void, @ptrCast(&appDidActivateHandler))), method_type);
        c.objc_registerClassPair(cls);

        const delegate = msgSend_ptr(cls, c.sel_registerName("alloc"));
        _ = msgSend_ptr(delegate, c.sel_registerName("init"));
        global_delegate = delegate;
    }
}

fn toggleLoginItemHandler(self: *anyopaque, _: *anyopaque, sender: *anyopaque) callconv(.c) void {
    _ = self;
    
    std.debug.print("Toggle login item clicked\n", .{});
    
    const currentState = msgSend_long(sender, c.sel_registerName("state"));
    const isEnabled = currentState != 0;
    
    if (isEnabled) {
        std.debug.print("Removing from login items...\n", .{});
        removeLoginItem();
        msgSend_void_long(sender, c.sel_registerName("setState:"), 0);
    } else {
        std.debug.print("Adding to login items...\n", .{});
        addLoginItem();
        msgSend_void_long(sender, c.sel_registerName("setState:"), 1);
    }
}

fn toggleEnabledHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    global_enabled = !global_enabled;

    // If enabling but event tap isn't running, try to start it
    if (global_enabled and !global_event_tap_active) {
        startEventTap();
        if (!global_event_tap_active) {
            global_enabled = false;
            std.debug.print("Cannot enable: event tap failed. Grant Accessibility and Input Monitoring permissions, then try again.\n", .{});
        }
    }

    std.debug.print("Remapping {s}\n", .{if (global_enabled) "enabled" else "disabled"});

    updateEnabledItemTitle();
}

fn updateEnabledItemTitle() void {
    const item = global_enabled_item orelse return;
    const NSString_class = c.objc_getClass("NSString") orelse return;
    const label: [*:0]const u8 = if (global_enabled)
        "\xe2\x97\x89 On" // ◉ On
    else
        "\xe2\x97\x8b Off"; // ○ Off
    const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), label);
    msgSend_void_ptr(item, c.sel_registerName("setTitle:"), title);
}

fn menuWillOpenHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    const NSString_class = c.objc_getClass("NSString") orelse return;
    const ax_trusted = AXIsProcessTrusted();

    if (global_accessibility_item) |item| {
        const label: [*:0]const u8 = if (ax_trusted)
            "\xe2\x9c\x93  Accessibility" // ✓  Accessibility
        else
            "\xe2\x9c\x97  Accessibility \xe2\x80\x94 Open Settings\xe2\x80\xa6"; // ✗  Accessibility — Open Settings…
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), label);
        msgSend_void_ptr(item, c.sel_registerName("setTitle:"), title);
    }

    if (global_input_monitoring_item) |item| {
        const has_input = global_event_tap_active;
        const label: [*:0]const u8 = if (has_input)
            "\xe2\x9c\x93  Input Monitoring" // ✓  Input Monitoring
        else if (ax_trusted)
            "\xe2\x9c\x97  Input Monitoring \xe2\x80\x94 Open Settings\xe2\x80\xa6" // ✗  Input Monitoring — Open Settings…
        else
            "?  Input Monitoring \xe2\x80\x94 Open Settings\xe2\x80\xa6"; // ?  Input Monitoring — Open Settings…
        const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), label);
        msgSend_void_ptr(item, c.sel_registerName("setTitle:"), title);
    }
}

fn openConfigHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    std.debug.print("Opening config file...\n", .{});

    const abs_path = global_config_path orelse {
        std.debug.print("Config path not resolved at startup\n", .{});
        return;
    };

    const NSString_class = c.objc_getClass("NSString") orelse return;
    const NSWorkspace = c.objc_getClass("NSWorkspace") orelse return;
    const workspace = msgSend_ptr(NSWorkspace, c.sel_registerName("sharedWorkspace"));

    // Build a null-terminated path string for ObjC
    var cpath_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    @memcpy(cpath_buf[0..abs_path.len], abs_path);
    cpath_buf[abs_path.len] = 0;
    const cpath: [*:0]const u8 = cpath_buf[0..abs_path.len :0];

    const ns_path = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), cpath);
    _ = msgSend_bool_ptr(workspace, c.sel_registerName("openFile:"), ns_path);
}

fn reloadConfigHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    std.debug.print("Reloading config...\n", .{});

    const allocator = global_allocator;

    const new_cfg = allocator.create(Config) catch |err| {
        std.debug.print("Failed to allocate config: {}\n", .{err});
        return;
    };
    const config_file = global_config_path orelse "config.json";
    new_cfg.* = Config.loadFromFile(allocator, global_io, config_file) catch |err| {
        std.debug.print("Failed to load config: {}\n", .{err});
        allocator.destroy(new_cfg);
        return;
    };

    const new_remap = allocator.create(RemapperState) catch |err| {
        std.debug.print("Failed to allocate remapper: {}\n", .{err});
        new_cfg.deinit(allocator);
        allocator.destroy(new_cfg);
        return;
    };
    new_remap.* = RemapperState.init(allocator, new_cfg.*) catch |err| {
        std.debug.print("Failed to init remapper: {}\n", .{err});
        allocator.destroy(new_remap);
        new_cfg.deinit(allocator);
        allocator.destroy(new_cfg);
        return;
    };

    // Swap out old state
    const old_remap = global_remapper;
    const old_cfg = global_config;
    global_remapper = new_remap;
    global_config = new_cfg;
    global_builtin_keyboard_only = new_cfg.builtin_keyboard_only;
    detectBuiltinKeyboardType();

    // Clean up old state
    old_remap.deinit();
    allocator.destroy(old_remap);
    if (old_cfg) |oc| {
        oc.deinit(allocator);
        allocator.destroy(oc);
    }

    std.debug.print("Config reloaded successfully\n", .{});
    std.debug.print("  Tap threshold: {d}ms\n", .{new_cfg.timing.tap_ms});
    std.debug.print("  Hold threshold: {d}ms\n", .{new_cfg.timing.hold_ms});
    std.debug.print("  Chord threshold: {d}ms\n", .{new_cfg.timing.chord_ms});
    std.debug.print("  Combos: {d}\n", .{new_cfg.combos.len});
    std.debug.print("  Built-in keyboard only: {}\n", .{new_cfg.builtin_keyboard_only});
    std.debug.print("  Profiles: {d}\n", .{new_cfg.profiles.len});
    std.debug.print("  App profiles: {d}\n", .{new_cfg.app_profiles.len});

    // Re-evaluate active profile with new config
    if (global_profile_override) {
        // Re-apply the manual override profile from new config
        const profile = new_cfg.getProfile(global_active_profile_name);
        global_remapper.active_profile = profile;
    } else {
        reevaluateProfile();
    }
}

fn openAccessibilitySettingsHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    openSystemURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
}

fn openInputMonitoringSettingsHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    openSystemURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent");
}

fn openSystemURL(url_cstr: [*:0]const u8) void {
    const NSString_class = c.objc_getClass("NSString") orelse return;
    const NSURL_class = c.objc_getClass("NSURL") orelse return;
    const NSWorkspace_class = c.objc_getClass("NSWorkspace") orelse return;

    const ns_string = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), url_cstr);
    const ns_url = msgSend_ptr_ptr(NSURL_class, c.sel_registerName("URLWithString:"), ns_string);
    const workspace = msgSend_ptr(NSWorkspace_class, c.sel_registerName("sharedWorkspace"));
    _ = msgSend_bool_ptr(workspace, c.sel_registerName("openURL:"), ns_url);
}

fn isLoginItem() bool {
    const SMAppService = c.objc_getClass("SMAppService") orelse return false;
    const service = msgSend_ptr(SMAppService, c.sel_registerName("mainAppService"));
    const status = msgSend_long(service, c.sel_registerName("status"));
    return status == 1; // SMAppServiceStatusEnabled
}

fn addLoginItem() void {
    const SMAppService = c.objc_getClass("SMAppService") orelse {
        std.debug.print("SMAppService not available\n", .{});
        return;
    };
    
    const service = msgSend_ptr(SMAppService, c.sel_registerName("mainAppService"));
    var err: ?*anyopaque = null;
    _ = msgSend_bool_ptrptr(service, c.sel_registerName("registerAndReturnError:"), &err);
    
    if (err != null) {
        std.debug.print("Failed to add login item\n", .{});
    } else {
        std.debug.print("Added to login items\n", .{});
    }
}

fn removeLoginItem() void {
    const SMAppService = c.objc_getClass("SMAppService") orelse return;
    
    const service = msgSend_ptr(SMAppService, c.sel_registerName("mainAppService"));
    var err: ?*anyopaque = null;
    _ = msgSend_bool_ptrptr(service, c.sel_registerName("unregisterAndReturnError:"), &err);
    
    if (err != null) {
        std.debug.print("Failed to remove login item\n", .{});
    } else {
        std.debug.print("Removed from login items\n", .{});
    }
}

fn toggleProfileHandler(_: *anyopaque, _: *anyopaque, _: *anyopaque) callconv(.c) void {
    const cfg = global_config orelse return;

    if (global_profile_override) {
        // Currently on a manual profile — find it in the list and go to the next one, or wrap to Auto
        var found_idx: ?usize = null;
        for (cfg.profiles, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, global_active_profile_name)) {
                found_idx = i;
                break;
            }
        }

        if (found_idx) |idx| {
            if (idx + 1 < cfg.profiles.len) {
                // Next profile in list
                applyProfile(cfg.profiles[idx + 1].name);
                return;
            }
        }
        // Wrap back to Auto
        global_profile_override = false;
        reevaluateProfile();
    } else {
        // Currently Auto — go to first profile
        if (cfg.profiles.len > 0) {
            applyProfile(cfg.profiles[0].name);
        }
    }
}

fn applyProfile(name: []const u8) void {
    const cfg = global_config orelse return;
    const profile = cfg.getProfile(name);
    global_remapper.active_profile = profile;
    global_profile_override = true;

    // Copy name into buffer
    const len = @min(name.len, global_active_profile_name_buf.len);
    @memcpy(global_active_profile_name_buf[0..len], name[0..len]);
    global_active_profile_name = global_active_profile_name_buf[0..len];

    std.debug.print("Profile set to: {s} (tap_hold={}, combos={}, space_layer={})\n", .{ name, profile.tap_hold, profile.combos, profile.space_layer });
    updateProfileItemTitle();
}

fn reevaluateProfile() void {
    if (global_profile_override) return;

    const cfg = global_config orelse return;

    // Get frontmost app's bundle ID via NSWorkspace
    const bundle_id = getFrontmostBundleId() orelse {
        setActiveProfileName("default");
        global_remapper.active_profile = .{};
        updateProfileItemTitle();
        return;
    };

    // Look up in app_profiles
    for (cfg.app_profiles) |entry| {
        if (std.mem.eql(u8, entry.bundle_id, bundle_id)) {
            const profile = cfg.getProfile(entry.profile_name);
            global_remapper.active_profile = profile;
            setActiveProfileName(entry.profile_name);
            std.debug.print("Auto-profile: {s} -> {s}\n", .{ bundle_id, entry.profile_name });
            updateProfileItemTitle();
            return;
        }
    }

    // No match — default profile
    setActiveProfileName("default");
    global_remapper.active_profile = .{};
    updateProfileItemTitle();
}

fn setActiveProfileName(name: []const u8) void {
    const len = @min(name.len, global_active_profile_name_buf.len);
    @memcpy(global_active_profile_name_buf[0..len], name[0..len]);
    global_active_profile_name = global_active_profile_name_buf[0..len];
}

fn getFrontmostBundleId() ?[]const u8 {
    const NSWorkspace_class = c.objc_getClass("NSWorkspace") orelse return null;
    const workspace = msgSend_ptr(NSWorkspace_class, c.sel_registerName("sharedWorkspace"));
    const front_app = msgSend_ptr(workspace, c.sel_registerName("frontmostApplication"));
    if (@intFromPtr(front_app) == 0) return null;
    const bundle_nsstring = msgSend_ptr(front_app, c.sel_registerName("bundleIdentifier"));
    if (@intFromPtr(bundle_nsstring) == 0) return null;
    const cstr: ?[*:0]const u8 = @ptrCast(msgSend_ptr(bundle_nsstring, c.sel_registerName("UTF8String")));
    if (cstr) |s| {
        return std.mem.sliceTo(s, 0);
    }
    return null;
}

fn updateProfileItemTitle() void {
    const item = global_profile_item orelse return;
    const NSString_class = c.objc_getClass("NSString") orelse return;

    // Build "Profile: <name>" or "Profile: Auto (<name>)"
    var buf: [128]u8 = undefined;
    const label = if (global_profile_override) blk: {
        break :blk std.fmt.bufPrint(&buf, "Profile: {s}", .{global_active_profile_name}) catch "Profile: ???";
    } else blk: {
        if (std.mem.eql(u8, global_active_profile_name, "default")) {
            break :blk std.fmt.bufPrint(&buf, "Profile: Auto", .{}) catch "Profile: Auto";
        } else {
            break :blk std.fmt.bufPrint(&buf, "Profile: Auto ({s})", .{global_active_profile_name}) catch "Profile: Auto";
        }
    };

    // Null-terminate for ObjC
    var cstr_buf: [129]u8 = undefined;
    @memcpy(cstr_buf[0..label.len], label);
    cstr_buf[label.len] = 0;
    const cstr: [*:0]const u8 = cstr_buf[0..label.len :0];

    const title = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), cstr);
    msgSend_void_ptr(item, c.sel_registerName("setTitle:"), title);
}

fn appDidActivateHandler(_: *anyopaque, _: *anyopaque, notification: *anyopaque) callconv(.c) void {
    if (global_profile_override) return;

    const cfg = global_config orelse return;
    if (cfg.app_profiles.len == 0) return;

    // Extract bundle ID from the notification's userInfo
    const user_info = msgSend_ptr(notification, c.sel_registerName("userInfo"));
    if (@intFromPtr(user_info) == 0) return;

    const NSString_class = c.objc_getClass("NSString") orelse return;
    const key_cstr: [*:0]const u8 = "NSWorkspaceApplicationKey";
    const key = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), key_cstr);
    const app_obj = msgSend_ptr_ptr(user_info, c.sel_registerName("objectForKey:"), key);
    if (@intFromPtr(app_obj) == 0) return;

    const bundle_nsstring = msgSend_ptr(app_obj, c.sel_registerName("bundleIdentifier"));
    if (@intFromPtr(bundle_nsstring) == 0) return;

    const cstr: ?[*:0]const u8 = @ptrCast(msgSend_ptr(bundle_nsstring, c.sel_registerName("UTF8String")));
    const bundle_id = if (cstr) |s| std.mem.sliceTo(s, 0) else return;

    std.debug.print("App activated: {s}\n", .{bundle_id});

    // Look up in app_profiles
    for (cfg.app_profiles) |entry| {
        if (std.mem.eql(u8, entry.bundle_id, bundle_id)) {
            const profile = cfg.getProfile(entry.profile_name);
            global_remapper.active_profile = profile;
            setActiveProfileName(entry.profile_name);
            std.debug.print("Auto-profile switched to: {s}\n", .{entry.profile_name});
            updateProfileItemTitle();
            return;
        }
    }

    // No match — default
    setActiveProfileName("default");
    global_remapper.active_profile = .{};
    updateProfileItemTitle();
}

fn setupWorkspaceObserver() void {
    const delegate = global_delegate orelse return;
    const NSString_class = c.objc_getClass("NSString") orelse return;
    const NSWorkspace_class = c.objc_getClass("NSWorkspace") orelse return;
    const workspace = msgSend_ptr(NSWorkspace_class, c.sel_registerName("sharedWorkspace"));
    const nc = msgSend_ptr(workspace, c.sel_registerName("notificationCenter"));

    // Create the notification name string manually
    const notif_cstr: [*:0]const u8 = "NSWorkspaceDidActivateApplicationNotification";
    const notif_name = msgSend_ptr_cstr(NSString_class, c.sel_registerName("stringWithUTF8String:"), notif_cstr);

    // [nc addObserver:delegate selector:@selector(appDidActivate:) name:notifName object:nil]
    msgSend_void_ptr_sel_ptr_ptr(nc, c.sel_registerName("addObserver:selector:name:object:"), delegate, c.sel_registerName("appDidActivate:"), notif_name, null);

    std.debug.print("Workspace observer registered for app activation\n", .{});
}

fn cfStr(comptime s: []const u8) c.CFStringRef {
    return c.CFStringCreateWithCStringNoCopy(
        null,
        s.ptr,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull, // don't free the static string
    );
}

fn detectBuiltinKeyboardType() void {
    const manager = cg.IOHIDManagerCreate(c.kCFAllocatorDefault, cg.kIOHIDOptionsTypeNone);
    if (manager == null) {
        std.debug.print("Could not create IOHIDManager, processing all keyboards\n", .{});
        global_builtin_kb_type = null;
        return;
    }
    defer c.CFRelease(manager);

    // Build matching dictionary: UsagePage=1 (Generic Desktop), Usage=6 (Keyboard)
    const usage_page_key = cfStr(cg.kIOHIDDeviceUsagePageKey);
    defer c.CFRelease(usage_page_key);
    const usage_key = cfStr(cg.kIOHIDDeviceUsageKey);
    defer c.CFRelease(usage_key);

    var page_val: c_int = 1; // kHIDPage_GenericDesktop
    var usage_val: c_int = 6; // kHIDUsage_GD_Keyboard
    const cf_page = c.CFNumberCreate(null, c.kCFNumberIntType, &page_val);
    defer c.CFRelease(cf_page);
    const cf_usage = c.CFNumberCreate(null, c.kCFNumberIntType, &usage_val);
    defer c.CFRelease(cf_usage);

    var match_keys = [_]?*const anyopaque{ @ptrCast(usage_page_key), @ptrCast(usage_key) };
    var match_vals = [_]?*const anyopaque{ @ptrCast(cf_page), @ptrCast(cf_usage) };
    const match_dict = c.CFDictionaryCreate(
        null,
        @ptrCast(&match_keys),
        @ptrCast(&match_vals),
        2,
        &c.kCFTypeDictionaryKeyCallBacks,
        &c.kCFTypeDictionaryValueCallBacks,
    );
    defer c.CFRelease(match_dict);

    cg.IOHIDManagerSetDeviceMatching(manager, match_dict);

    if (cg.IOHIDManagerOpen(manager, cg.kIOHIDOptionsTypeNone) != cg.kIOReturnSuccess) {
        std.debug.print("Could not open IOHIDManager, processing all keyboards\n", .{});
        global_builtin_kb_type = null;
        return;
    }
    defer _ = cg.IOHIDManagerClose(manager, cg.kIOHIDOptionsTypeNone);

    const device_set = cg.IOHIDManagerCopyDevices(manager);
    if (device_set == null) {
        std.debug.print("No HID keyboard devices found, processing all keyboards\n", .{});
        global_builtin_kb_type = null;
        return;
    }
    defer c.CFRelease(device_set);

    const count = c.CFSetGetCount(device_set);
    if (count == 0) {
        std.debug.print("No HID keyboard devices found, processing all keyboards\n", .{});
        global_builtin_kb_type = null;
        return;
    }

    // Get all devices from the set
    var devices_buf: [64]?*const anyopaque = undefined;
    const actual_count: usize = @intCast(@min(count, 64));
    c.CFSetGetValues(device_set, &devices_buf);

    const vendor_key = cfStr(cg.kIOHIDVendorIDKey);
    defer c.CFRelease(vendor_key);
    const transport_key = cfStr(cg.kIOHIDTransportKey);
    defer c.CFRelease(transport_key);
    const product_key = cfStr(cg.kIOHIDProductKey);
    defer c.CFRelease(product_key);
    const kb_type_key = cfStr("KeyboardType");
    defer c.CFRelease(kb_type_key);

    for (devices_buf[0..actual_count]) |dev_ptr| {
        const device: cg.IOHIDDeviceRef = @ptrCast(@constCast(dev_ptr));

        // Check vendor ID == 0x05AC (Apple)
        const vendor_ref = cg.IOHIDDeviceGetProperty(device, vendor_key);
        if (vendor_ref == null) continue;
        var vendor_id: c_int = 0;
        if (c.CFNumberGetValue(@ptrCast(vendor_ref), c.kCFNumberIntType, &vendor_id) == 0) continue;
        if (vendor_id != 0x05AC) continue;

        // Check transport == "SPI" (Apple Silicon built-in bus)
        var is_builtin = false;
        const transport_ref = cg.IOHIDDeviceGetProperty(device, transport_key);
        if (transport_ref != null) {
            const transport_cfstr: c.CFStringRef = @ptrCast(transport_ref);
            const spi_str = cfStr("SPI");
            defer c.CFRelease(spi_str);
            if (c.CFStringCompare(transport_cfstr, spi_str, 0) == c.kCFCompareEqualTo) {
                is_builtin = true;
            }
        }

        // Fallback: check product name contains "Internal" (Intel Macs)
        if (!is_builtin) {
            const product_ref = cg.IOHIDDeviceGetProperty(device, product_key);
            if (product_ref != null) {
                const product_cfstr: c.CFStringRef = @ptrCast(product_ref);
                const internal_str = cfStr("Internal");
                defer c.CFRelease(internal_str);
                const range = c.CFStringFind(product_cfstr, internal_str, c.kCFCompareCaseInsensitive);
                if (range.location != c.kCFNotFound) {
                    is_builtin = true;
                }
            }
        }

        if (!is_builtin) continue;

        // Read KeyboardType property
        const kb_type_ref = cg.IOHIDDeviceGetProperty(device, kb_type_key);
        if (kb_type_ref == null) continue;
        var kb_type_val: i64 = 0;
        if (c.CFNumberGetValue(@ptrCast(kb_type_ref), c.kCFNumberSInt64Type, &kb_type_val) == 0) continue;

        global_builtin_kb_type = kb_type_val;
        std.debug.print("Built-in keyboard type: {d}\n", .{kb_type_val});
        return;
    }

    std.debug.print("Could not detect built-in keyboard, processing all keyboards\n", .{});
    global_builtin_kb_type = null;
}

fn startEventTap() void {
    if (global_event_tap_active) return;

    std.debug.print("Creating event tap...\n", .{});

    const event_mask: cg.CGEventMask = (1 << cg.kCGEventKeyDown) | (1 << cg.kCGEventKeyUp) | (1 << cg.kCGEventFlagsChanged);

    const tap = cg.CGEventTapCreate(
        cg.kCGHIDEventTap,
        cg.kCGHeadInsertEventTap,
        cg.kCGEventTapOptionDefault,
        event_mask,
        eventCallback,
        null,
    );

    if (tap == null) {
        std.debug.print("Event tap failed — waiting for Accessibility and Input Monitoring permissions...\n", .{});
        startPermissionRetryTimer();
        return;
    }

    const run_loop_source = c.CFMachPortCreateRunLoopSource(c.kCFAllocatorDefault, tap, 0);
    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), run_loop_source, c.kCFRunLoopCommonModes);
    cg.CGEventTapEnable(tap, true);
    // Release the source — the run loop retains it. Keep the tap so we can
    // re-enable it when the system disables it (see eventCallbackInternal).
    c.CFRelease(run_loop_source);
    global_event_tap = tap;

    global_event_tap_active = true;
    std.debug.print("Event tap created successfully!\n", .{});
}

/// While permissions are missing, retry the event tap every few seconds so
/// deft starts working the moment the user grants them — no manual toggle.
fn startPermissionRetryTimer() void {
    if (global_permission_timer != null) return;

    const timer = c.CFRunLoopTimerCreate(
        c.kCFAllocatorDefault,
        c.CFAbsoluteTimeGetCurrent() + 3.0,
        3.0,
        0,
        0,
        permissionRetryCallback,
        null,
    );
    if (timer != null) {
        c.CFRunLoopAddTimer(c.CFRunLoopGetCurrent(), timer, c.kCFRunLoopCommonModes);
        global_permission_timer = timer;
        std.debug.print("Watching for permission grant...\n", .{});
    }
}

fn stopPermissionRetryTimer() void {
    if (global_permission_timer) |timer| {
        c.CFRunLoopTimerInvalidate(timer);
        c.CFRelease(timer);
        global_permission_timer = null;
    }
}

fn permissionRetryCallback(_: c.CFRunLoopTimerRef, _: ?*anyopaque) callconv(.c) void {
    if (global_event_tap_active) {
        stopPermissionRetryTimer();
        return;
    }

    startEventTap();
    if (global_event_tap_active) {
        global_enabled = true;
        updateEnabledItemTitle();
        std.debug.print("Permissions granted — remapping is now active\n", .{});
        stopPermissionRetryTimer();
    }
}

fn eventCallback(
    _: cg.CGEventTapProxy,
    event_type: cg.CGEventType,
    event: cg.CGEventRef,
    _: ?*anyopaque,
) callconv(.c) cg.CGEventRef {
    const result = eventCallbackInternal(event_type, event);
    return result orelse @ptrFromInt(0);
}

fn eventCallbackInternal(event_type: cg.CGEventType, event: cg.CGEventRef) ?cg.CGEventRef {
    // The system disables taps it considers unresponsive (heavy load, debugger
    // pause, login window). Re-enable ours or remapping dies until restart.
    if (event_type == cg.kCGEventTapDisabledByTimeout or event_type == cg.kCGEventTapDisabledByUserInput) {
        std.debug.print("Event tap disabled by system, re-enabling\n", .{});
        if (global_event_tap != null) cg.CGEventTapEnable(global_event_tap, true);
        return event;
    }

    // Pass through everything when remapping is disabled
    if (!global_enabled) return event;

    // Filter: only process events from built-in keyboard if enabled in config
    if (global_builtin_keyboard_only) {
        if (global_builtin_kb_type) |kb_type| {
            const event_kb_type = cg.CGEventGetIntegerValueField(event, cg.kCGKeyboardEventKeyboardType);
            if (event_kb_type != kb_type) return event; // external keyboard, pass through
        }
        // if detection failed (null), fall through and process all keyboards
    }
    
    const kcode: cg.CGKeyCode = @intCast(cg.CGEventGetIntegerValueField(event, cg.kCGKeyboardEventKeycode));
    const kcode_i64: i64 = @intCast(kcode);

    // Pass through Space when Cmd/Ctrl are held (e.g., Cmd+Space for Spotlight,
    // Ctrl+Space for input source switching). Option and Shift do NOT bypass the
    // space layer, so e.g. Alt+Space+H emits Option+LeftArrow.
    if (kcode == 49) { // Space keycode
        const flags: u64 = @intCast(cg.CGEventGetFlags(event));
        const real_mod_mask = keycode.kCGEventFlagMaskCommand | keycode.kCGEventFlagMaskControl;
        if (flags & real_mod_mask != 0) {
            return event;
        }
    }

    // --- Simple remaps: check before any other processing ---
    if (global_remapper.config.simple_remaps.len > 0) {
        const key_opt = keycode.keycodeToKey(kcode_i64);
        if (key_opt) |from_key| {
            for (global_remapper.config.simple_remaps) |sr| {
                if (sr.from == from_key) {
                    if (event_type == cg.kCGEventFlagsChanged) {
                        // Modifier key remap: detect press/release via device-specific flags
                        const flags: u64 = @intCast(cg.CGEventGetFlags(event));
                        const is_pressed = keycode.isModifierPressed(kcode, flags);
                        if (is_pressed) {
                            std.debug.print("Simple remap: {s} pressed -> emitting {s} down\n", .{ @tagName(from_key), @tagName(sr.to) });
                            if (keycode.isModifierKey(sr.to)) {
                                // Remap modifier to modifier: pass through with modified keycode
                                const target_kcode = keycode.keyToKeycode(sr.to);
                                cg.CGEventSetIntegerValueField(event, cg.kCGKeyboardEventKeycode, @intCast(target_kcode));
                                return event;
                            } else {
                                emitSyntheticKeyDown(sr.to, 0);
                            }
                        } else {
                            std.debug.print("Simple remap: {s} released -> emitting {s} up\n", .{ @tagName(from_key), @tagName(sr.to) });
                            if (keycode.isModifierKey(sr.to)) {
                                const target_kcode = keycode.keyToKeycode(sr.to);
                                cg.CGEventSetIntegerValueField(event, cg.kCGKeyboardEventKeycode, @intCast(target_kcode));
                                return event;
                            } else {
                                emitSyntheticKeyUp(sr.to, 0);
                            }
                        }
                        return null; // suppress original modifier event
                    } else if (event_type == cg.kCGEventKeyDown) {
                        // Regular key remap
                        std.debug.print("Simple remap: {s} -> {s}\n", .{ @tagName(from_key), @tagName(sr.to) });
                        if (keycode.isModifierKey(sr.to)) {
                            // Remap regular key to modifier: would need flags changed event
                            // For now, just change the keycode
                            const target_kcode = keycode.keyToKeycode(sr.to);
                            cg.CGEventSetIntegerValueField(event, cg.kCGKeyboardEventKeycode, @intCast(target_kcode));
                            return event;
                        } else {
                            const target_kcode = keycode.keyToKeycode(sr.to);
                            cg.CGEventSetIntegerValueField(event, cg.kCGKeyboardEventKeycode, @intCast(target_kcode));
                            return event;
                        }
                    } else if (event_type == cg.kCGEventKeyUp) {
                        const target_kcode = keycode.keyToKeycode(sr.to);
                        cg.CGEventSetIntegerValueField(event, cg.kCGKeyboardEventKeycode, @intCast(target_kcode));
                        return event;
                    }
                }
            }
        }
    }

    if (event_type == cg.kCGEventKeyDown) {
        const action = global_remapper.handleKeyDown(kcode_i64) catch |err| {
            std.debug.print("Error handling key down: {}\n", .{err});
            return event;
        };
        // Fast-roll taps must come out before the key that ended the roll.
        for (global_remapper.takePendingRolls()) |roll_key| {
            emitKeyOrMouse(roll_key, realModifierFlags(event));
        }
        switch (action) {
            .Suppress => return null,
            .PassThrough => return event,
            .ReplaceWithKey => |key| {
                emitKeyOrMouse(key, realModifierFlags(event));
                return null;
            },
            .ReplaceWithKeyAndModifiers => |data| {
                emitKeyOrMouse(data.key, modifiersToFlags(data.modifiers) | realModifierFlags(event));
                return null;
            },
            .ApplyModifiers => |mods| {
                const flags = modifiersToFlags(mods);
                cg.CGEventSetFlags(event, flags);
                return event;
            },
        }
    } else if (event_type == cg.kCGEventKeyUp) {
        // Deactivate all mouse movement when space is released
        if (kcode == 0x31 and mouse_move_state.anyActive()) {
            deactivateAllMouseDirections();
        }

        // Check for mouse movement key release (before remapper)
        if (mouse_move_state.anyActive()) {
            const mouse_key_opt = keycode.keycodeToKey(kcode_i64);
            if (mouse_key_opt) |mk| {
                for (global_remapper.config.space_layer) |mapping| {
                    if (mk == mapping.from and isMouseMoveKey(mapping.to) and mouse_move_state.isActive(mapping.to)) {
                        deactivateMouseDirection(mapping.to);
                        return null; // suppress
                    }
                }
            }
        }

        const action = global_remapper.handleKeyUp(kcode_i64) catch |err| {
            std.debug.print("Error handling key up: {}\n", .{err});
            return event;
        };
        switch (action) {
            .Suppress => return null,
            .PassThrough => return event,
            .ReplaceWithKey => |key| {
                emitKeyOrMouse(key, realModifierFlags(event));
                return null;
            },
            .ReplaceWithKeyAndModifiers => |data| {
                emitKeyOrMouse(data.key, modifiersToFlags(data.modifiers) | realModifierFlags(event));
                return null;
            },
            .ApplyModifiers => |mods| {
                const flags = modifiersToFlags(mods);
                cg.CGEventSetFlags(event, flags);
                return event;
            },
        }
    }

    return event;
}

/// The real (physically held) modifier flags on an incoming event, masked to
/// just Cmd/Opt/Ctrl/Shift so device-specific bits don't leak into synthetic events.
fn realModifierFlags(event: cg.CGEventRef) keycode.CGEventFlags {
    const flags: u64 = @intCast(cg.CGEventGetFlags(event));
    const mask = keycode.kCGEventFlagMaskCommand | keycode.kCGEventFlagMaskAlternate | keycode.kCGEventFlagMaskControl | keycode.kCGEventFlagMaskShift;
    return flags & mask;
}

fn modifiersToFlags(mods: []const config.Modifier) keycode.CGEventFlags {
    var flags: keycode.CGEventFlags = 0;
    for (mods) |mod| {
        flags |= switch (mod) {
            .Control => keycode.kCGEventFlagMaskControl,
            .Shift => keycode.kCGEventFlagMaskShift,
            .Option => keycode.kCGEventFlagMaskAlternate,
            .Command => keycode.kCGEventFlagMaskCommand,
            .Hyper => keycode.kCGEventFlagMaskCommand | keycode.kCGEventFlagMaskAlternate | keycode.kCGEventFlagMaskControl | keycode.kCGEventFlagMaskShift,
        };
    }
    return flags;
}

fn isMouseMoveKey(key: Key) bool {
    return switch (key) {
        .MouseMoveUp, .MouseMoveDown, .MouseMoveLeft, .MouseMoveRight => true,
        else => false,
    };
}

fn activateMouseDirection(key: Key) void {
    std.debug.print("Mouse direction activated: {s}\n", .{@tagName(key)});
    switch (key) {
        .MouseMoveUp => mouse_move_state.up = true,
        .MouseMoveDown => mouse_move_state.down = true,
        .MouseMoveLeft => mouse_move_state.left = true,
        .MouseMoveRight => mouse_move_state.right = true,
        else => return,
    }
    if (mouse_move_state.timer == null) {
        mouse_move_state.start_time = remapper.nanoTimestamp();
        startMouseMoveTimer();
        std.debug.print("Mouse move timer started\n", .{});
    }
}

fn deactivateMouseDirection(key: Key) void {
    switch (key) {
        .MouseMoveUp => mouse_move_state.up = false,
        .MouseMoveDown => mouse_move_state.down = false,
        .MouseMoveLeft => mouse_move_state.left = false,
        .MouseMoveRight => mouse_move_state.right = false,
        else => return,
    }
    if (!mouse_move_state.anyActive()) {
        stopMouseMoveTimer();
    }
}

fn deactivateAllMouseDirections() void {
    mouse_move_state.up = false;
    mouse_move_state.down = false;
    mouse_move_state.left = false;
    mouse_move_state.right = false;
    stopMouseMoveTimer();
}

fn mouseTimerCallback(_: c.CFRunLoopTimerRef, _: ?*anyopaque) callconv(.c) void {
    if (!mouse_move_state.anyActive()) return;

    const now = remapper.nanoTimestamp();
    const elapsed_ms: i64 = @intCast(@divTrunc(now - mouse_move_state.start_time, std.time.ns_per_ms));

    // Acceleration curve
    const speed: f64 = if (elapsed_ms < 100) 2.0
        else if (elapsed_ms < 300) 6.0
        else if (elapsed_ms < 600) 14.0
        else 24.0;

    var dx: f64 = 0;
    var dy: f64 = 0;
    if (mouse_move_state.left) dx -= speed;
    if (mouse_move_state.right) dx += speed;
    if (mouse_move_state.up) dy -= speed;
    if (mouse_move_state.down) dy += speed;

    if (dx == 0 and dy == 0) return;

    // Get current cursor position
    const dummy = cg.CGEventCreate(null);
    if (dummy == null) return;
    const pos = cg.CGEventGetLocation(dummy);
    c.CFRelease(dummy);

    const new_pos = cg.CGPoint{ .x = pos.x + dx, .y = pos.y + dy };

    const source = cg.CGEventSourceCreate(cg.kCGEventSourceStateHIDSystemState);
    if (source == null) return;

    const move_event = cg.CGEventCreateMouseEvent(source, cg.kCGEventMouseMoved, new_pos, cg.kCGMouseButtonLeft);
    if (move_event != null) {
        cg.CGEventPost(cg.kCGSessionEventTap, move_event);
        c.CFRelease(move_event);
    }
    c.CFRelease(source);
}

fn startMouseMoveTimer() void {
    const timer = c.CFRunLoopTimerCreate(
        c.kCFAllocatorDefault,
        c.CFAbsoluteTimeGetCurrent(),
        0.016, // 16ms ≈ 60fps
        0,
        0,
        mouseTimerCallback,
        null,
    );
    if (timer != null) {
        c.CFRunLoopAddTimer(c.CFRunLoopGetCurrent(), timer, c.kCFRunLoopCommonModes);
        mouse_move_state.timer = timer;
    }
}

fn stopMouseMoveTimer() void {
    if (mouse_move_state.timer) |timer| {
        c.CFRunLoopTimerInvalidate(timer);
        c.CFRelease(timer);
        mouse_move_state.timer = null;
    }
    mouse_move_state.start_time = 0;
}

fn emitMouseClick(comptime button: enum { left, right }) void {
    // Get current mouse position
    const dummy_event = cg.CGEventCreate(null);
    if (dummy_event == null) return;
    const pos = cg.CGEventGetLocation(dummy_event);
    c.CFRelease(dummy_event);

    const source = cg.CGEventSourceCreate(cg.kCGEventSourceStateHIDSystemState);
    if (source == null) return;

    const down_type = if (button == .left) cg.kCGEventLeftMouseDown else cg.kCGEventRightMouseDown;
    const up_type = if (button == .left) cg.kCGEventLeftMouseUp else cg.kCGEventRightMouseUp;
    const cg_button = if (button == .left) cg.kCGMouseButtonLeft else cg.kCGMouseButtonRight;

    const down = cg.CGEventCreateMouseEvent(source, down_type, pos, cg_button);
    if (down != null) {
        cg.CGEventPost(cg.kCGSessionEventTap, down);
        c.CFRelease(down);
    }
    const up = cg.CGEventCreateMouseEvent(source, up_type, pos, cg_button);
    if (up != null) {
        cg.CGEventPost(cg.kCGSessionEventTap, up);
        c.CFRelease(up);
    }

    c.CFRelease(source);
}

fn emitKeyOrMouse(key: Key, modifiers: keycode.CGEventFlags) void {
    switch (key) {
        .MouseLeftClick => emitMouseClick(.left),
        .MouseRightClick => emitMouseClick(.right),
        .MouseMoveUp, .MouseMoveDown, .MouseMoveLeft, .MouseMoveRight => activateMouseDirection(key),
        else => emitSyntheticKey(key, modifiers),
    }
}

fn emitSyntheticKey(key: Key, modifiers: keycode.CGEventFlags) void {
    emitSyntheticKeyDown(key, modifiers);
    emitSyntheticKeyUp(key, modifiers);
}

fn emitSyntheticKeyDown(key: Key, modifiers: keycode.CGEventFlags) void {
    const kcode = keycode.keyToKeycode(key);

    const source = cg.CGEventSourceCreate(cg.kCGEventSourceStateHIDSystemState);
    if (source == null) return;

    const keydown = cg.CGEventCreateKeyboardEvent(source, kcode, true);
    if (keydown == null) {
        c.CFRelease(source);
        return;
    }
    cg.CGEventSetFlags(keydown, modifiers);
    cg.CGEventPost(cg.kCGSessionEventTap, keydown);
    c.CFRelease(keydown);

    c.CFRelease(source);
}

fn emitSyntheticKeyUp(key: Key, modifiers: keycode.CGEventFlags) void {
    const kcode = keycode.keyToKeycode(key);

    const source = cg.CGEventSourceCreate(cg.kCGEventSourceStateHIDSystemState);
    if (source == null) return;

    const keyup = cg.CGEventCreateKeyboardEvent(source, kcode, false);
    if (keyup == null) {
        c.CFRelease(source);
        return;
    }
    cg.CGEventSetFlags(keyup, modifiers);
    cg.CGEventPost(cg.kCGSessionEventTap, keyup);
    c.CFRelease(keyup);

    c.CFRelease(source);
}
