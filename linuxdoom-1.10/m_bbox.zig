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

    /// Views a C `fixed_t[4]` box, indexed by BOXTOP/BOXBOTTOM/BOXLEFT/BOXRIGHT, as a BBox.
    pub fn fromArray(a: *const [4]fixed_t) *const BBox {
        return @ptrCast(a);
    }

    /// Grows the box to include the point at (x, y).
    /// Like vanilla M_AddToBox, a point only moves one side per axis, so the
    /// first point added to `.empty` sets left and bottom but not right and top.
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

    /// True if the boxes overlap. Boxes that only touch along an edge don't count.
    pub fn overlaps(a: BBox, b: BBox) bool {
        return a.right > b.left and a.left < b.right and a.top > b.bottom and a.bottom < b.top;
    }
};

comptime {
    const c = @import("c");
    // Ensure BBox remains an ABI identical view of fixed_t[4] and BOX* enum
    std.debug.assert(@offsetOf(BBox, "top") == c.BOXTOP * @sizeOf(fixed_t));
    std.debug.assert(@offsetOf(BBox, "bottom") == c.BOXBOTTOM * @sizeOf(fixed_t));
    std.debug.assert(@offsetOf(BBox, "left") == c.BOXLEFT * @sizeOf(fixed_t));
    std.debug.assert(@offsetOf(BBox, "right") == c.BOXRIGHT * @sizeOf(fixed_t));
}
