const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_files = [_][]const u8{
        "dstrings.c",
        "i_sound.c",
        "tables.c",
        "p_saveg.c",
        "r_bsp.c",
        "r_data.c",
        "r_draw.c",
        "r_main.c",
        "r_plane.c",
        "r_segs.c",
        "r_things.c",
        "info.c",
    };

    // Zig passes only clang's default warnings, so ask for more.
    const cflags = [_][]const u8{"-Wall"};

    // C headers are translated to Zig modules by the build, which the Zig
    // files @import. (This replaces @cImport, removed in Zig 0.17.)
    const c_doom = b.addTranslateC(.{
        .root_source_file = b.path("cimport/doom.h"),
        .target = target,
        .optimize = optimize,
    });
    c_doom.addIncludePath(b.path("."));
    c_doom.defineCMacro("LINUX", null);

    const c_system = b.addTranslateC(.{
        .root_source_file = b.path("cimport/system.h"),
        .target = target,
        .optimize = optimize,
    });

    const c_net = b.addTranslateC(.{
        .root_source_file = b.path("cimport/net.h"),
        .target = target,
        .optimize = optimize,
    });

    // pkg-config supplies GLFW's include path here and its link flags below.
    const c_glfw = b.addTranslateC(.{
        .root_source_file = b.path("cimport/glfw.h"),
        .target = target,
        .optimize = optimize,
    });
    c_glfw.linkSystemLibrary("glfw3", .{});

    // One module holds both the Zig code (rooted at i_main.zig, which reaches
    // the rest through @import) and the C files that haven't been converted yet.
    const mod = b.createModule(.{
        .root_source_file = b.path("i_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // UBSan traps in R_InitTextures, which reads structs out of WAD lumps
        // at unaligned addresses. Revisit once r_data.c is converted.
        .sanitize_c = .off,
        .imports = &.{
            .{ .name = "c", .module = c_doom.createModule() },
            .{ .name = "c_system", .module = c_system.createModule() },
            .{ .name = "c_net", .module = c_net.createModule() },
            .{ .name = "c_glfw", .module = c_glfw.createModule() },
        },
    });
    // r_data.c and tables.h test LINUX for <alloca.h> and <math.h>.
    mod.addCMacro("LINUX", "");
    mod.addCSourceFiles(.{ .files = &c_files, .flags = &cflags });
    mod.addIncludePath(b.path("."));
    mod.linkSystemLibrary("glfw3", .{});
    if (target.result.os.tag == .macos) {
        mod.linkFramework("Cocoa", .{});
        mod.linkFramework("IOKit", .{});
        mod.linkFramework("CoreFoundation", .{});
        mod.linkFramework("OpenGL", .{});
        // miniaudio's default runtime linking dlopens "CoreFoundation.framework/CoreFoundation"
        // by relative path, which newer macOS no longer resolves, so it silently falls back
        // to the Null backend (no sound). Link the audio frameworks directly instead.
        mod.addCMacro("MA_NO_RUNTIME_LINKING", "");
        mod.linkFramework("CoreAudio", .{});
        mod.linkFramework("AudioToolbox", .{});
    }

    const exe = b.addExecutable(.{
        .name = "doomzig",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run doomzig");
    run_step.dependOn(&run_cmd.step);

    // Compiles without installing. zls build-on-save runs this step to report
    // compile errors as diagnostics.
    const check = b.step("check", "Compile without installing, for zls build-on-save");
    check.dependOn(&exe.step);
}
