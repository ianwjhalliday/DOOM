extern var myargc: c_int;
extern var myargv: [*c][*c]const u8;

extern fn D_DoomMain() void;

const std = @import("std");

pub fn main() void {
    // overkill buffer for args, prob should move to something else
    var argsbuffer: [8192]u8 = undefined;
    var argsfba = std.heap.FixedBufferAllocator.init(&argsbuffer);
    var allocator = argsfba.allocator();

    // TODO: eliminate myarg* and use args directly
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

    myargc = @intCast(c_int, args.len);
    myargv = @ptrCast([*c][*c]const u8, cargv);

    D_DoomMain();
}
