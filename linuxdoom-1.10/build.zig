const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Homebrew installs to /opt/homebrew on Apple Silicon and /usr/local on Intel.
    const homebrew = if (target.result.cpu.arch == .aarch64) "/opt/homebrew" else "/usr/local";

    const c_files = [_][]const u8{
        "dstrings.c",
        "i_sound.c",
        "tables.c",
        "m_swap.c",
        "p_ceilng.c",
        "p_doors.c",
        "p_enemy.c",
        "p_floor.c",
        "p_lights.c",
        "p_plats.c",
        "p_pspr.c",
        "p_spec.c",
        "p_switch.c",
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

    const cflags = [_][]const u8{
        "-fno-sanitize=undefined", // TODO: Re-enable UBSan?
        "-g", // TODO: Can remove? "default debug information"
        "-Wall", // TODO: What is zig's default on C warnings?
    };

    // C headers are translated to Zig modules by the build, which the Zig
    // files @import. (This replaces @cImport, removed in Zig 0.17.)
    const c_doom = b.addTranslateC(.{
        .root_source_file = b.path("cimport/doom.h"),
        .target = target,
        .optimize = optimize,
    });
    c_doom.addIncludePath(b.path("."));
    c_doom.defineCMacro("NORMALUNIX", null);
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

    const c_glfw = b.addTranslateC(.{
        .root_source_file = b.path("cimport/glfw.h"),
        .target = target,
        .optimize = optimize,
    });
    c_glfw.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ homebrew, "include" }) });

    // One module holds both the Zig code (rooted at i_main.zig, which reaches
    // the rest through @import) and the C files that haven't been converted yet.
    const mod = b.createModule(.{
        .root_source_file = b.path("i_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "c", .module = c_doom.createModule() },
            .{ .name = "c_system", .module = c_system.createModule() },
            .{ .name = "c_net", .module = c_net.createModule() },
            .{ .name = "c_glfw", .module = c_glfw.createModule() },
        },
    });
    mod.addCMacro("NORMALUNIX", "");
    mod.addCMacro("LINUX", "");
    mod.addCSourceFiles(.{ .files = &c_files, .flags = &cflags });
    mod.addIncludePath(b.path("."));
    mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ homebrew, "lib" }) });
    mod.linkSystemLibrary("glfw3", .{});
    // TODO: MacOS only frameworks
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
