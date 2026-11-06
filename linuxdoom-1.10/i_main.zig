const std = @import("std");
const i_system = @import("i_system.zig");
const m_argv = @import("m_argv.zig");
const D_DoomMain = @import("d_main.zig").D_DoomMain;

pub fn main(init: std.process.Init) noreturn {
    i_system.io = init.io;
    i_system.environ_map = init.environ_map;
    i_system.initConsole();

    // The arena lives for the whole process, as the args must.
    const allocator = init.arena.allocator();

    const args = init.minimal.args.toSlice(allocator) catch {
        std.log.err("Out of memory reading arguments", .{});
        std.process.exit(1);
    };

    const cargv = allocator.alloc([*c]const u8, args.len) catch {
        std.log.err("Out of memory reading arguments", .{});
        std.process.exit(1);
    };
    for (args, 0..) |arg, i| {
        cargv[i] = arg.ptr;
    }

    // TODO: eliminate myargc/v and use myargs directly
    m_argv.myargc = @intCast(args.len);
    m_argv.myargv = @ptrCast(cargv);
    m_argv.myargs = args;

    D_DoomMain();
}
