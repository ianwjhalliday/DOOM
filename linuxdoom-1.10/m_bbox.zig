const std = @import("std");

const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;

pub const BBox = extern struct {
    top: fixed_t,
    bottom: fixed_t,
    left: fixed_t,
    right: fixed_t,

    pub const empty: BBox = .{
        .top = std.math.minInt(fixed_t),
        .bottom = std.math.maxInt(fixed_t),
        .left = std.math.maxInt(fixed_t),
        .right = std.math.minInt(fixed_t),
    };

    pub fn add(box: *BBox, x: fixed_t, y: fixed_t) void {
        if (x < box.left) {
            box.left = x;
        } else if (x > box.right) {
            box.right = x;
        }

        if (y < box.bottom) {
            box.bottom = y;
        } else if (y > box.top) {
            box.top = y;
        }
    }
};
