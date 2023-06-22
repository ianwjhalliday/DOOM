extern fn D_DoomMain() void;

const std = @import("std");
const m_argv = @import("m_argv.zig");

pub fn main() void {
    // overkill buffer for args, prob should move to something else
    var argsbuffer: [8192]u8 = undefined;
    var argsfba = std.heap.FixedBufferAllocator.init(&argsbuffer);
    var allocator = argsfba.allocator();

    const args = std.process.argsAlloc(allocator) catch {
        std.log.err("Arguments too big for 8kb buffer\n", .{});
        return;
    };
    defer std.process.argsFree(allocator, args);

    const cargv = allocator.alloc([*c]const u8, args.len) catch {
        std.log.err("Arguments too big for 8kb buffer\n", .{});
        return;
    };
    for (args, 0..) |arg, i| {
        cargv[i] = arg.ptr;
    }

    // TODO: eliminate myargc/v and use myargs directly
    m_argv.myargc = @intCast(c_int, args.len);
    m_argv.myargv = @ptrCast([*c][*c]const u8, cargv);
    m_argv.myargs = args;

    D_DoomMain();
}
