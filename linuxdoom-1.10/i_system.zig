const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
    @cInclude("sys/time.h");
    @cInclude("doomdef.h");
    @cInclude("doomtype.h");
});

extern fn I_InitSound() void;
extern fn D_QuitNetGame() void;
extern fn I_ShutdownSound() void;
extern fn I_ShutdownMusic() void;

const std = @import("std");
const I_ShutdownGraphics = @import("i_video.zig").I_ShutdownGraphics;
const M_SaveDefaults = @import("m_misc.zig").M_SaveDefaults;
const G_CheckDemoStatus = @import("g_game.zig").G_CheckDemoStatus;

const TicCmd = @import("d_ticcmd.zig").TicCmd;

const mb_used: c_int = 6;

pub export fn I_Tactile(on: c_int, off: c_int, total: c_int) void {
    // UNUSED
    // NOTE: It appears this is intended for player input feedback
    // like controller vibration. On and off referring to intensity
    // and total referring to duration prob in milliseconds.
    _ = total;
    _ = off;
    _ = on;
}

const emptycmd = TicCmd{
    .forwardmove = 0,
    .sidemove = 0,
    .angleturn = 0,
    .consistancy = 0,
    .chatchar = 0,
    .buttons = 0,
};
pub export fn I_BaseTiccmd() *const TicCmd {
    return &emptycmd;
}

pub fn I_ZoneBase(size: *c_int) [*]u8 {
    size.* = mb_used*1024*1024;
    if (std.heap.raw_c_allocator.alloc(u8, @intCast(size.*))) |p| {
        return p.ptr;
    } else |_| {
        I_Error("I_ZoneBase: Failed to allocate zone memory\n");
    }
}

var basetime: c_long = 0;
pub export fn I_GetTime() c_int {
    var tp: c.struct_timeval = undefined;
    var tzp: c.struct_timezone = undefined;
    _ = c.gettimeofday(&tp, &tzp);
    if (basetime == 0) {
        basetime = tp.tv_sec;
    }
    const newtics: c_int = @truncate((tp.tv_sec-basetime)*c.TICRATE + @divTrunc(tp.tv_usec*c.TICRATE, 1000000));
    return newtics;
}

pub fn I_Init() void {
    I_InitSound();
}

pub export fn I_Quit() void {
    D_QuitNetGame();
    I_ShutdownSound();
    I_ShutdownMusic();
    M_SaveDefaults();
    I_ShutdownGraphics();
    std.process.exit(0);
}

/// Wait for vertical retrace or pause a bit.
pub export fn I_WaitVBL(count: c_int) void {
    _ = c.usleep(@intCast(count * (1000000/70)));
}

// Allocates from low memory under dos,
// just mallocs under unix
pub export fn I_AllocLow(length: c_int) ?[*]u8 {
    if (std.heap.raw_c_allocator.alloc(u8, @intCast(length))) |p| {
        @memset(p, 0);
        return p.ptr;
    } else |_| {
        return null;
    }
}

extern var demorecording: c.boolean;

pub export fn I_Error(errormsg: [*:0]const u8, ...) noreturn {
    // NOTE: zig translate-c fails to parse stdio.h's `stderr` so
    // open it manually here (and also can't case `2` to `*FILE`
    // due to debug build alignment checks).
    const stderr = c.fdopen(2, "w");
    var argptr = @cVaStart();
    _ = c.fprintf(stderr, "Error: ");
    _ = c.vfprintf(stderr, errormsg, argptr);
    _ = c.fprintf(stderr, "\n");
    @cVaEnd(&argptr);

    _ = c.fflush(stderr);
    _ = c.fclose(stderr);

    // Shutdown. Here might be other errors.
    if (demorecording == c.true) {
        _ = G_CheckDemoStatus();
    }

    D_QuitNetGame();
    I_ShutdownGraphics();

    std.process.exit(@bitCast(@as(i8, -1)));
}
