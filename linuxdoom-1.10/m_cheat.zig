//
// CHEAT SEQUENCe PACKAGE
//

pub const CheatSeq = extern struct {
    // TODO: Convert to slice and index
    sequence: [*]u8,
    p: ?[*]u8,
};

fn SCRAMBLE(comptime a: comptime_int) comptime_int {
    return ((a & 1) << 7) + ((a & 2) << 5) + (a & 4) + ((a & 8) << 1)
        + ((a & 16) >> 1) + (a & 32) + ((a & 64) >> 5) + ((a & 128) >> 7);
}

var cheat_xlate_table = init: {
    var t: [256]u8 = undefined;
    for (&t, 0..) |*pt, i| {
        pt.* = SCRAMBLE(i);
    }
    break :init t;
};

//
// Called in st_stuff module, which handles the input.
// Returns a 1 if the cheat was successful, 0 if failed.
// TODO: Return bool
//
pub export fn cht_CheckCheat(cht: *CheatSeq, key: u8) c_int {
    if (cht.p == null) {
        cht.p = cht.sequence; // initialize if first time
    }

    if (cht.p.?[0] == 0) {
        cht.p.?[0] = key;
        cht.p.? += 1;
    } else if (cheat_xlate_table[key] == cht.p.?[0]) {
        cht.p.? += 1;
    } else {
        cht.p.? = cht.sequence;
    }

    if (cht.p.?[0] == 1) {
        cht.p.? += 1;
    } else if (cht.p.?[0] == 0xff) { // end of sequence character
        cht.p.? = cht.sequence;
        return 1;
    }

    return 0;
}

pub export fn cht_GetParam(cht: *CheatSeq, buffer: [*]u8) void {
    const p = cht.sequence;
    var i: usize = 0;

    while (p[i] != 1) : (i += 1) {}
    i += 1;

    const start = i;
    var c: u8 = 1;
    while (c != 0 and p[i] != 0xff) : (i += 1) {
        c = p[i];
        p[i] = 0;
        buffer[i - start] = c;
    }

    if (p[i] == 0xff) {
        buffer[i - start] = 0;
    }
}
