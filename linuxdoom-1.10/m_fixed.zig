const math = @import("std").math;

// TODO: User import when `m_fixed.zig` is included via imports instead of build list
extern fn I_Error(errormsg: [*:0]const u8, ...) noreturn;

pub const FRACBITS = 16;
pub const FRACUNIT = 1 << FRACBITS;

pub const fixed_t = c_int;

/// abs() with C's result for minInt: returns minInt instead of overflowing.
pub fn FixedAbs(x: fixed_t) fixed_t {
    return @bitCast(@abs(x));
}

pub export fn FixedMul(a: fixed_t, b: fixed_t) fixed_t {
    // TODO: Is truncation expected here?
    return @truncate((@as(c_longlong, a) * @as(c_longlong, b)) >> FRACBITS);
}

pub export fn FixedDiv(a : fixed_t, b: fixed_t) fixed_t {
    const abs_a = @min(@abs(a), math.maxInt(fixed_t));
    const abs_b = @min(@abs(b), math.maxInt(fixed_t));

    if (abs_a >> 14 >= abs_b) {
        return if (a^b < 0) math.minInt(fixed_t) else math.maxInt(fixed_t);
    }
    return FixedDiv2(a, b);
}

pub export fn FixedDiv2(a : fixed_t, b: fixed_t) fixed_t {
    const c = @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b)) * FRACUNIT;

    if (c >= 2147483648.0 or c < -2147483648.0) {
        I_Error("FixedDiv: divide by zero");
    }

    return @trunc(c);
}
