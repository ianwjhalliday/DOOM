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

    const zig_objects = .{
        b.addObject(.{
            .name = "z_zone",
            .root_source_file = .{ .path = "z_zone.zig" },
            .optimize = optimize,
            .target = target,
        }),
    };

    inline for (zig_objects) |o| {
        o.addIncludePath(".");
    }

    const source_files = [_][]const u8{
        "i_main.c",
        "doomdef.c",
        "doomstat.c",
        "dstrings.c",
        "i_system.c",
        "i_sound.c",
        "i_video.c",
        "i_net.c",
        "tables.c",
        "f_finale.c",
        "f_wipe.c",
        "d_main.c",
        "d_net.c",
        "d_items.c",
        "g_game.c",
        "m_menu.c",
        "m_misc.c",
        "m_argv.c",
        "m_bbox.c",
        "m_fixed.c",
        "m_swap.c",
        "m_cheat.c",
        "m_random.c",
        "am_map.c",
        "p_ceilng.c",
        "p_doors.c",
        "p_enemy.c",
        "p_floor.c",
        "p_inter.c",
        "p_lights.c",
        "p_map.c",
        "p_maputl.c",
        "p_plats.c",
        "p_pspr.c",
        "p_setup.c",
        "p_sight.c",
        "p_spec.c",
        "p_switch.c",
        "p_mobj.c",
        "p_telept.c",
        "p_tick.c",
        "p_saveg.c",
        "p_user.c",
        "r_bsp.c",
        "r_data.c",
        "r_draw.c",
        "r_main.c",
        "r_plane.c",
        "r_segs.c",
        "r_sky.c",
        "r_things.c",
        "w_wad.c",
        "wi_stuff.c",
        "v_video.c",
        "st_lib.c",
        "st_stuff.c",
        "hu_stuff.c",
        "hu_lib.c",
        "s_sound.c",
        "z_zone.c",
        "info.c",
        "sounds.c",
    };

    const cflags = [_][]const u8{
        "-fno-sanitize=undefined", // TODO: Re-enable UBSan?
        "-g", // TODO: Can remove? "default debug information"
        "-Wall", // TODO: What is zig's default on C warnings?
    };

    const exe = b.addExecutable(.{
        .name = "doomzig",
        .target = target,
        .optimize = optimize,
    });

    exe.defineCMacro("NORMALUNIX", null);
    exe.defineCMacro("LINUX", null);
    exe.addCSourceFiles(&source_files, &cflags);
    inline for (zig_objects) |o| {
        exe.addObject(o);
    }
    exe.linkLibC();
    exe.linkSystemLibrary("glfw3");
    // TODO: MacOS only frameworks
    exe.linkFramework("Cocoa");
    exe.linkFramework("IOKit");
    exe.linkFramework("CoreFoundation");
    exe.linkFramework("OpenGL");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run doomzig");
    run_step.dependOn(&run_cmd.step);
}
