const c = @import("c_system");

extern fn I_InitSound() void;
extern fn I_ShutdownSound() void;
extern fn I_ShutdownMusic() void;

const std = @import("std");
const I_ShutdownGraphics = @import("i_video.zig").I_ShutdownGraphics;
const D_QuitNetGame = @import("d_net.zig").D_QuitNetGame;
const M_SaveDefaults = @import("m_misc.zig").M_SaveDefaults;
const g_game = @import("g_game.zig");
const G_CheckDemoStatus = g_game.G_CheckDemoStatus;

const TicCmd = @import("d_ticcmd.zig").TicCmd;

const TICRATE = @import("doomdef.zig").TICRATE;

// The std.Io implementation that all file and console I/O goes through.
// Set by main() before anything else runs.
pub var io: std.Io = undefined;

// The process environment variables. Set by main().
pub var environ_map: *const std.process.Environ.Map = undefined;

// std.io.cWriter was removed in Zig 0.15. This is a minimal unbuffered
// std.Io.Writer over a C FILE, used for the console and the -debugfile
// output. The FILE does the buffering.
pub const CFileWriter = struct {
    file: *std.c.FILE,
    interface: std.Io.Writer,

    pub fn init(file: *std.c.FILE) CFileWriter {
        return .{
            .file = file,
            .interface = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} },
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *CFileWriter = @alignCast(@fieldParentPtr("interface", w));
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.writeAll(bytes);
            n += bytes.len;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| try self.writeAll(pattern);
        return n + pattern.len * splat;
    }

    fn writeAll(self: *CFileWriter, bytes: []const u8) std.Io.Writer.Error!void {
        if (std.c.fwrite(bytes.ptr, 1, bytes.len, self.file) != bytes.len) return error.WriteFailed;
    }
};

// Console output. Writes go through C's stdout and stderr streams, which the
// C files print to as well, so output from both languages shares one buffer
// and comes out in order. Set up by initConsole() at startup.
var stdout_writer: CFileWriter = undefined;
var stderr_writer: CFileWriter = undefined;

pub fn initConsole() void {
    // Line buffer stdout even when it isn't a terminal, so a redirected log
    // interleaves it in order with the unbuffered stderr.
    _ = c.setvbuf(c.stdout(), null, c._IOLBF, 0);
    stdout_writer = .init(@ptrCast(c.stdout()));
    stderr_writer = .init(@ptrCast(c.stderr()));
}

pub fn stdout() *std.Io.Writer {
    return &stdout_writer.interface;
}

pub fn stderr() *std.Io.Writer {
    return &stderr_writer.interface;
}

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
    if (std.heap.c_allocator.alloc(u8, @intCast(size.*))) |p| {
        return p.ptr;
    } else |_| {
        I_Error("I_ZoneBase: Failed to allocate zone memory\n");
    }
}

var basetime: c_long = 0;
pub fn I_GetTime() c_int {
    var tp: c.struct_timeval = undefined;
    var tzp: c.struct_timezone = undefined;
    _ = c.gettimeofday(&tp, &tzp);
    if (basetime == 0) {
        basetime = tp.tv_sec;
    }
    const newtics: c_int = @truncate((tp.tv_sec-basetime)*TICRATE + @divTrunc(tp.tv_usec*TICRATE, 1000000));
    return newtics;
}

pub fn I_Init() void {
    I_InitSound();
}

pub fn I_Quit() void {
    D_QuitNetGame();
    I_ShutdownSound();
    I_ShutdownMusic();
    M_SaveDefaults();
    I_ShutdownGraphics();
    std.process.exit(0);
}

/// Wait for vertical retrace or pause a bit.
pub fn I_WaitVBL(count: c_int) void {
    _ = c.usleep(@intCast(count * (1000000/70)));
}

// Allocates from low memory under dos,
// just mallocs under unix
pub fn I_AllocLow(length: c_int) ?[*]u8 {
    if (std.heap.c_allocator.alloc(u8, @intCast(length))) |p| {
        @memset(p, 0);
        return p.ptr;
    } else |_| {
        return null;
    }
}

pub export fn I_Error(errormsg: [*:0]const u8, ...) noreturn {
    // Flush pending stdout first so the error comes after it.
    _ = c.fflush(c.stdout());
    var argptr = @cVaStart();
    _ = c.fprintf(c.stderr(), "Error: ");
    _ = c.vfprintf(c.stderr(), errormsg, argptr);
    _ = c.fprintf(c.stderr(), "\n");
    @cVaEnd(&argptr);

    // Shutdown. Here might be other errors.
    if (g_game.demorecording) {
        _ = G_CheckDemoStatus();
    }

    D_QuitNetGame();
    I_ShutdownGraphics();

    std.process.exit(@bitCast(@as(i8, -1)));
}
