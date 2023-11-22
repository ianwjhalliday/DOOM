pub const c = @cImport({
    @cInclude("v_video.h");
});

const std = @import("std");

const doomdef = @import("doomdef.zig");
const i_system = @import("i_system.zig");
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const I_AllocLow = i_system.I_AllocLow;

// Each screen is [SCREENWIDTH*SCREENHEIGHT]; 
pub export var screens: [5][*]u8 = undefined;
var dirtybox: [4]c_int = undefined; // TODO: Appears not to be used, remove?

pub var usegamma: c_int = undefined;

// Now where did these came from?
pub const gammatable = [5][256]u8{
    .{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
     17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,
     33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,
     49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,
     65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,
     81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,
     97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,
     113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,
     128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
     144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
     160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
     176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
     192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
     208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
     224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
     240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255},

    .{2,4,5,7,8,10,11,12,14,15,16,18,19,20,21,23,24,25,26,27,29,30,31,
     32,33,34,36,37,38,39,40,41,42,44,45,46,47,48,49,50,51,52,54,55,
     56,57,58,59,60,61,62,63,64,65,66,67,69,70,71,72,73,74,75,76,77,
     78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,
     99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,
     115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,129,
     130,131,132,133,134,135,136,137,138,139,140,141,142,143,144,145,
     146,147,148,148,149,150,151,152,153,154,155,156,157,158,159,160,
     161,162,163,163,164,165,166,167,168,169,170,171,172,173,174,175,
     175,176,177,178,179,180,181,182,183,184,185,186,186,187,188,189,
     190,191,192,193,194,195,196,196,197,198,199,200,201,202,203,204,
     205,205,206,207,208,209,210,211,212,213,214,214,215,216,217,218,
     219,220,221,222,222,223,224,225,226,227,228,229,230,230,231,232,
     233,234,235,236,237,237,238,239,240,241,242,243,244,245,245,246,
     247,248,249,250,251,252,252,253,254,255},

    .{4,7,9,11,13,15,17,19,21,22,24,26,27,29,30,32,33,35,36,38,39,40,42,
     43,45,46,47,48,50,51,52,54,55,56,57,59,60,61,62,63,65,66,67,68,69,
     70,72,73,74,75,76,77,78,79,80,82,83,84,85,86,87,88,89,90,91,92,93,
     94,95,96,97,98,100,101,102,103,104,105,106,107,108,109,110,111,112,
     113,114,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,
     129,130,131,132,133,133,134,135,136,137,138,139,140,141,142,143,144,
     144,145,146,147,148,149,150,151,152,153,153,154,155,156,157,158,159,
     160,160,161,162,163,164,165,166,166,167,168,169,170,171,172,172,173,
     174,175,176,177,178,178,179,180,181,182,183,183,184,185,186,187,188,
     188,189,190,191,192,193,193,194,195,196,197,197,198,199,200,201,201,
     202,203,204,205,206,206,207,208,209,210,210,211,212,213,213,214,215,
     216,217,217,218,219,220,221,221,222,223,224,224,225,226,227,228,228,
     229,230,231,231,232,233,234,235,235,236,237,238,238,239,240,241,241,
     242,243,244,244,245,246,247,247,248,249,250,251,251,252,253,254,254,
     255},

    .{8,12,16,19,22,24,27,29,31,34,36,38,40,41,43,45,47,49,50,52,53,55,
     57,58,60,61,63,64,65,67,68,70,71,72,74,75,76,77,79,80,81,82,84,85,
     86,87,88,90,91,92,93,94,95,96,98,99,100,101,102,103,104,105,106,107,
     108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,
     125,126,127,128,129,130,131,132,133,134,135,135,136,137,138,139,140,
     141,142,143,143,144,145,146,147,148,149,150,150,151,152,153,154,155,
     155,156,157,158,159,160,160,161,162,163,164,165,165,166,167,168,169,
     169,170,171,172,173,173,174,175,176,176,177,178,179,180,180,181,182,
     183,183,184,185,186,186,187,188,189,189,190,191,192,192,193,194,195,
     195,196,197,197,198,199,200,200,201,202,202,203,204,205,205,206,207,
     207,208,209,210,210,211,212,212,213,214,214,215,216,216,217,218,219,
     219,220,221,221,222,223,223,224,225,225,226,227,227,228,229,229,230,
     231,231,232,233,233,234,235,235,236,237,237,238,238,239,240,240,241,
     242,242,243,244,244,245,246,246,247,247,248,249,249,250,251,251,252,
     253,253,254,254,255},

    .{16,23,28,32,36,39,42,45,48,50,53,55,57,60,62,64,66,68,69,71,73,75,76,
     78,80,81,83,84,86,87,89,90,92,93,94,96,97,98,100,101,102,103,105,106,
     107,108,109,110,112,113,114,115,116,117,118,119,120,121,122,123,124,
     125,126,128,128,129,130,131,132,133,134,135,136,137,138,139,140,141,
     142,143,143,144,145,146,147,148,149,150,150,151,152,153,154,155,155,
     156,157,158,159,159,160,161,162,163,163,164,165,166,166,167,168,169,
     169,170,171,172,172,173,174,175,175,176,177,177,178,179,180,180,181,
     182,182,183,184,184,185,186,187,187,188,189,189,190,191,191,192,193,
     193,194,195,195,196,196,197,198,198,199,200,200,201,202,202,203,203,
     204,205,205,206,207,207,208,208,209,210,210,211,211,212,213,213,214,
     214,215,216,216,217,217,218,219,219,220,220,221,221,222,223,223,224,
     224,225,225,226,227,227,228,228,229,229,230,230,231,232,232,233,233,
     234,234,235,235,236,236,237,237,238,239,239,240,240,241,241,242,242,
     243,243,244,244,245,245,246,246,247,247,248,248,249,249,250,250,251,
     251,252,252,253,254,254,255,255}
};

extern fn M_AddToBox(box: [*]fixed_t, x: fixed_t, y: fixed_t) void;

pub export fn V_MarkRect(x: u32, y: u32, width: u32, height: u32) void {
    M_AddToBox(&dirtybox, @intCast(x), @intCast(y));
    M_AddToBox(&dirtybox, @intCast(x + width - 1), @intCast(y + height - 1));
}


//
// V_CopyRect
//
pub fn V_CopyRectSigned(
    srcx: c_int,
    srcy: c_int,
    srcscrn: u32,
    width: c_int,
    height: c_int,
    destx: c_int,
    desty: c_int,
    destscrn: u32,
) void {
    V_CopyRect(
        @intCast(srcx),
        @intCast(srcy),
        srcscrn,
        @intCast(width),
        @intCast(height),
        @intCast(destx),
        @intCast(desty),
        destscrn,
    );
}

pub fn V_CopyRect(
    srcx: u32,
    srcy: u32,
    srcscrn: u32,
    width: u32,
    height: u32,
    destx: u32,
    desty: u32,
    destscrn: u32,
) void {
    V_MarkRect(destx, desty, width, height);

    var src: [*]u8 = screens[srcscrn] + doomdef.SCREENWIDTH * srcy + srcx;
    var dest: [*]u8 = screens[destscrn] + doomdef.SCREENWIDTH * desty + destx;

    for (0..height) |_| {
        @memcpy(dest[0..width], src);
        src += doomdef.SCREENWIDTH;
        dest += doomdef.SCREENWIDTH;
    }
}

//
// V_DrawPatch
// Masks a column based masked pic to the screen.
//
pub fn V_DrawPatchSigned(x: c_int, y: c_int, scrn: u32, patch: *c.patch_t) void {
    V_DrawPatch(@intCast(x), @intCast(y), scrn, patch);
}

pub export fn V_DrawPatch(_x: u32, _y: u32, scrn: u32, patch: *c.patch_t) void {
    var y: u32 = @intCast(@as(i64, _y) - std.mem.littleToNative(c_short, patch.topoffset));
    var x: u32 = @intCast(@as(i64, _x) - std.mem.littleToNative(c_short, patch.leftoffset));

    const w = @as(u32, @intCast(std.mem.littleToNative(c_short, patch.width)));
    const h = @as(u32, @intCast(std.mem.littleToNative(c_short, patch.height)));

    if (scrn == 0) {
        V_MarkRect(x, y, w, h);
    }

    var desttop: [*]u8 = screens[scrn] + y * doomdef.SCREENWIDTH + x;

    const patchAsBytes = @as([*]u8, @ptrCast(patch));

    for (0..w) |col| {
        const columnofs = @as([*]c_int, @ptrCast(&patch.columnofs[0]));
        const colofs: usize = @intCast(std.mem.littleToNative(c_int, columnofs[@intCast(col)]));
        var column: *c.column_t = @ptrCast(patchAsBytes + colofs);

        // step through the posts in a column.
        while (column.topdelta != 0xff) {
            const columnAsBytes = @as([*]u8, @ptrCast(column));

            var source: [*]u8 = columnAsBytes + 3;
            var dest = desttop + col + @as(usize, column.topdelta) * doomdef.SCREENWIDTH;
            var count = column.length;

            while (count != 0) : (count -= 1) {
                dest[0] = source[0];
                source += 1;
                dest += doomdef.SCREENWIDTH;
            }

            column = @ptrCast(columnAsBytes + column.length + 4);
        }
    }
}

//
// V_DrawPatchFlipped 
// Masks a column based masked pic to the screen.
// Flips horizontally, e.g. to mirror face.
//
pub fn V_DrawPatchFlipped(_x: u32, _y: u32, scrn: u32, patch: *c.patch_t) void {
    var y: u32 = @intCast(@as(i64, _y) - std.mem.littleToNative(c_short, patch.topoffset));
    var x: u32 = @intCast(@as(i64, _x) - std.mem.littleToNative(c_short, patch.leftoffset));

    const w = @as(u32, @intCast(std.mem.littleToNative(c_short, patch.width)));
    const h = @as(u32, @intCast(std.mem.littleToNative(c_short, patch.height)));

    if (scrn == 0) {
        V_MarkRect(x, y, w, h);
    }

    var desttop: [*]u8 = screens[scrn] + y * doomdef.SCREENWIDTH + x;

    const patchAsBytes = @as([*]u8, @ptrCast(patch));

    for (0..w) |col| {
        const columnofs = @as([*]c_int, @ptrCast(&patch.columnofs[0]));
        const colofs: usize = @intCast(std.mem.littleToNative(c_int, columnofs[@intCast(w - 1 - col)]));
        var column: *c.column_t = @ptrCast(patchAsBytes + colofs);

        // step through the posts in a column.
        while (column.topdelta != 0xff) {
            const columnAsBytes = @as([*]u8, @ptrCast(column));

            var source: [*]u8 = columnAsBytes + 3;
            var dest = desttop + col + @as(usize, column.topdelta) * doomdef.SCREENWIDTH;
            var count = column.length;

            while (count != 0) : (count -= 1) {
                dest[0] = source[0];
                source += 1;
                dest += doomdef.SCREENWIDTH;
            }

            column = @ptrCast(columnAsBytes + column.length + 4);
        }
    }
}

//
// V_DrawBlock
// Draw a linear block of pixels into the view buffer.
//
pub fn V_DrawBlock(x: u32, y: u32, scrn: u32, width: u32, height: u32, _src: [*]u8) void {
    V_MarkRect(x, y, width, height);

    var dest = screens[scrn] + y * doomdef.SCREENWIDTH + x;
    var src = _src;

    for (0..height) |_| {
        @memcpy(dest[0..width], src);
        src += width;
        dest += doomdef.SCREENWIDTH;
    }
}


//
// V_Init
//
pub fn V_Init() void {
    // stick these in low dos memory on PCs
    var base: [*]u8 = I_AllocLow(doomdef.SCREENWIDTH * doomdef.SCREENHEIGHT * 4) orelse unreachable;

    for (0..4) |i| {
        screens[i] = base + i * doomdef.SCREENWIDTH * doomdef.SCREENHEIGHT;
    }
}
