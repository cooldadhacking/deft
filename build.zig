const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.addModule("root", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "deft",
        .root_module = root_module,
    });

    // Link to macOS frameworks
    root_module.linkFramework("CoreFoundation", .{});
    root_module.linkFramework("CoreGraphics", .{});
    root_module.linkFramework("AppKit", .{});
    root_module.linkFramework("ServiceManagement", .{});
    root_module.linkFramework("IOKit", .{});
    root_module.linkSystemLibrary("objc", .{});
    root_module.linkSystemLibrary("c", .{});

    b.installArtifact(exe);

    // Create .app bundle
    const app_bundle_step = b.step("bundle", "Create macOS .app bundle");
    const bundle_cmd = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "mkdir -p zig-out/Deft.app/Contents/MacOS && " ++
        "mkdir -p zig-out/Deft.app/Contents/Resources && " ++
        "cp zig-out/bin/deft zig-out/Deft.app/Contents/MacOS/ && " ++
        "cp Info.plist zig-out/Deft.app/Contents/ && " ++
        "cp resources/AppIcon.icns zig-out/Deft.app/Contents/Resources/ && " ++
        "cp resources/menubar_icon.png zig-out/Deft.app/Contents/Resources/ && " ++
        "cp 'resources/menubar_icon@2x.png' zig-out/Deft.app/Contents/Resources/ && " ++
        "codesign --force --deep --sign - --identifier com.rayou.deft --entitlements entitlements.plist zig-out/Deft.app && " ++
        "echo 'Created Deft.app bundle'",
    });
    bundle_cmd.step.dependOn(b.getInstallStep());
    app_bundle_step.dependOn(&bundle_cmd.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

