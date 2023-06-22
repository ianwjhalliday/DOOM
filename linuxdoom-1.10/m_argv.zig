const std = @import("std");

// TODO: Convert to zig native code and expose C wrappers
// i.e.
//   - global `myargs` and expose `myargc` `myargv` only for C code
//   - M_CheckParam that returns usize and works on slices, wrap
//     in wrapper that casts and converts appropriately for C calls
//  Cannot do this until d_main.c is changed to modify `myargs` instead
//  of modifying `myargv` and `myargc`.

pub export var myargc: c_int = undefined;
pub export var myargv: [*c][*c]const u8 = undefined;

pub var myargs: [][:0]const u8 = undefined;

// M_CheckParm
// Checks for the given parameter
// in the program's command line arguments.
// Returns the argument number (1 to argc-1)
// or 0 if not present
pub export fn M_CheckParm(check: [*:0]const u8) c_int {
    var i: usize = 1;
    while (i < myargc) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(
                std.mem.span(check),
                std.mem.span(myargv[i]))) {
            return @intCast(c_int, i);
        }
    }

    return 0;
}
