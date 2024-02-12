const std = @import("std");

pub fn SHORT(x: c_short) c_short {
    return std.mem.littleToNative(c_short, x);
}

pub fn LONG(x: c_int) c_int {
    return std.mem.littleToNative(c_int, x);
}
