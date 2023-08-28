const mem = @import("std").mem;

const I_Error = @import("i_system.zig").I_Error;
const W_CacheLumpName = @import("w_wad.zig").W_CacheLumpName;

extern fn V_CopyRect(srcx: c_int, srcy: c_int, srcscrn: c_int, width: c_int, height: c_int, destx: c_int, desty: c_int, destscr: c_int) void;
extern fn V_DrawPatch(x: c_int, y: c_int, scrn: c_int, patch: *c.patch_t) void;

const st_stuff = @import("st_stuff.zig");
const c = st_stuff.c;
const ST_Y = st_stuff.ST_Y;

//
// Background and foreground screen numbers
//
pub const BG = 4;
pub const FG = 0;

//
// Widget structs
//

// Number widget

// TODO: Use zig native types instead of c_ types
pub const StNumber = struct {
    // upper right-hand corner
    //  of the number (right-justified)
    x: c_int,
    y: c_int,

    // max # of digits in number
    width: c_int,

    // last number value
    oldnum: c_int,

    // pointer to current value
    num: *c_int,

    // pointer to boolean stating
    //  whether to update number
    on: *c.boolean,

    // list of patches for 0-9
    p: [*]*c.patch_t,

    // user data
    data: c_int,
};

// Percent widget ("child" of number widget,
//  or, more precisely, contains a number widget.)
pub const StPercent = struct {
    // number information
    n: StNumber,

    // percent sign graphic
    p: *c.patch_t,
};

// Multiple Icon widget
// TODO: Use zig native types instead of c_ types
pub const StMultIcon = struct {
    // center-justified location of icons
    x: c_int,
    y: c_int,

    // last icon number
    oldinum: c_int,

    // pointer to current icon
    inum: *c_int,

    // pointer to boolean stating
    //  whether to update icon
    on: *c.boolean,

    // list of icons
    p: [*]*c.patch_t,

    // user data
    data: c_int,
};

// Binary Icon widget

// TODO: Use zig native types instead of c_ types
pub const StBinIcon = struct {
    // center-justified location of icon
    x: c_int,
    y: c_int,

    // last icon value
    oldval: c.boolean,

    // pointer to current icon status
    val: *c.boolean,

    // pointer to boolean
    //  stating whether to update icon
    on: *c.boolean,

    p: *c.patch_t, // icon
    data: c_int, // user data
};

//
// Hack display negative frags.
//  Loads and store the stminus lump.
//
var sttminus: *c.patch_t = undefined;

pub fn STlib_init() void {
    sttminus = @ptrCast(@alignCast(W_CacheLumpName("STTMINUS", .Static)));
}

// TODO: Replace with Zig struct initializer at each callsite, and move these
// functions into the structs themselves.
pub fn STlib_initNum(n: *StNumber, x: c_int, y: c_int, pl: [*]*c.patch_t, num: *c_int, on: *c.boolean, width: c_int) void {
    n.x = x;
    n.y = y;
    n.oldnum = 0;
    n.width = width;
    n.num = num;
    n.on = on;
    n.p = pl;
}

//
// A fairly efficient way to draw a number
//  based on differences from the old number.
// Note: worth the trouble?
//
pub fn STlib_drawNum(n: *StNumber, refresh: c.boolean) void {
    _ = refresh;
    var numdigits = n.width;
    var num = n.num.*;

    const w = mem.nativeToLittle(c_short, n.p[0].width);
    const h = mem.nativeToLittle(c_short, n.p[0].height);

    n.oldnum = n.num.*;

    const neg = num < 0;

    if (neg) {
        if (numdigits == 2 and num < -9) {
            num = -9;
        } else if (numdigits == 3 and num < -99) {
            num = -99;
        }

        num = -num;
    }

    // clear the area
    var x = n.x - numdigits * w;

    if (n.y - ST_Y < 0) {
        I_Error("drawNum: n.y - ST_Y < 0");
    }

    V_CopyRect(x, n.y - ST_Y, BG, w * numdigits, h, x, n.y, FG);

    // if non-number, do not draw it
    if (num == 1994) {
        return;
    }

    x = n.x;

    // in the special case of 0, you draw 0
    if (num == 0) {
        V_DrawPatch(x - w, n.y, FG, n.p[0]);
    }

    // draw the new number
    while (num != 0 and numdigits != 0) : (numdigits -= 1) {
        x -= w;
        // TODO: If num was unsigned might these expressions be simpler?
        V_DrawPatch(x, n.y, FG, n.p[@intCast(@mod(num, 10))]);
        num = @divTrunc(num, 10);
    }

    // draw a minus sign if necessary
    if (neg) {
        V_DrawPatch(x - 8, n.y, FG, sttminus);
    }
}

pub fn STlib_updateNum(n: *StNumber, refresh: c.boolean) void {
    if (n.on.* != c.false) {
        STlib_drawNum(n, refresh);
    }
}

pub fn STlib_initPercent(p: *StPercent, x: c_int, y: c_int, pl: [*]*c.patch_t, num: *c_int, on: *c.boolean, percent: *c.patch_t) void {
    STlib_initNum(&p.n, x, y, pl, num, on, 3);
    p.p = percent;
}

pub fn STlib_updatePercent(per: *StPercent, refresh: c.boolean) void {
    if (refresh != c.false and per.n.on.* != c.false) {
        V_DrawPatch(per.n.x, per.n.y, FG, per.p);
    }

    STlib_updateNum(&per.n, refresh);
}

pub fn STlib_initMultIcon(i: *StMultIcon, x: c_int, y: c_int, il: [*]*c.patch_t, inum: *c_int, on: *c.boolean) void {
    i.x = x;
    i.y = y;
    i.oldinum = -1;
    i.inum = inum;
    i.on = on;
    i.p = il;
}

pub fn STlib_updateMultIcon(mi: *StMultIcon, refresh: c.boolean) void {
    if (mi.on.* != c.false and (mi.oldinum != mi.inum.* or refresh != c.false) and mi.inum.* != -1) {
        if (mi.oldinum != -1) {
            const patch = mi.p[@intCast(mi.oldinum)];
            const x = mi.x - mem.nativeToLittle(c_short, patch.leftoffset);
            const y = mi.y - mem.nativeToLittle(c_short, patch.topoffset);
            const w = mem.nativeToLittle(c_short, patch.width);
            const h = mem.nativeToLittle(c_short, patch.height);

            if (y - ST_Y < 0) {
                I_Error("updateMultIcon: y - ST_Y < 0");
            }

            V_CopyRect(x, y - ST_Y, BG, w, h, x, y, FG);
        }

        V_DrawPatch(mi.x, mi.y, FG, mi.p[@intCast(mi.inum.*)]);
        mi.oldinum = mi.inum.*;
    }
}

pub fn STlib_initBinIcon(b: *StBinIcon, x: c_int, y: c_int, i: *c.patch_t, val: *c.boolean, on: *c.boolean) void {
    b.x = x;
    b.y = y;
    b.oldval = 0;
    b.val = val;
    b.on = on;
    b.p = i;
}

pub fn STlib_updateBinIcon(bi: *StBinIcon, refresh: c.boolean) void {
    if (bi.on.* != c.false and (bi.oldval != bi.val.* or refresh != c.false)) {
        const x = bi.x - mem.nativeToLittle(c_short, bi.p.leftoffset);
        const y = bi.y - mem.nativeToLittle(c_short, bi.p.topoffset);
        const w = mem.nativeToLittle(c_short, bi.p.width);
        const h = mem.nativeToLittle(c_short, bi.p.height);

        if (y - ST_Y < 0) {
            I_Error("updateBinIcon: y - ST_Y < 0");
        }

        if (bi.val.* != 0) {
            V_DrawPatch(bi.x, bi.y, FG, bi.p);
        } else {
            V_CopyRect(x, y - ST_Y, BG, w, h, x, y, FG);
        }

        bi.oldval = bi.val.*;
    }
}
