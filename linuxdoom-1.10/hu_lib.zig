pub const c = @cImport({
    @cInclude("r_defs.h");
    @cInclude("r_main.h");
    @cInclude("r_draw.h");
    @cInclude("v_video.h");
});

const std = @import("std");

const doomdef = @import("doomdef.zig");
const SCREENWIDTH = doomdef.SCREENWIDTH;


// background and foreground screen numbers
// different from other modules.
const BG = 1;
const FG = 0;

const HU_MAXLINES = 4;
pub const HU_MAXLINELENGTH = 80;

//
// Typedefs of widgets
//

// Text Line widget
//  (parent of Scrolling Text and Input Text widgets)
pub const HudTextLine = struct {
    // left-justified position of scrolling text window
    x: c_int,
    y: c_int,

    f: []*c.patch_t,            // font
    sc: c_int,                  // start character
    l: [HU_MAXLINELENGTH+1:0]u8,  // line of text
    len: usize,                 // current line length

    // whether this line needs to be updated
    needsupdate: c_int,
};



// Scrolling Text window widget
//  (child of Text Line widget)
pub const HudSText = struct {
    l: [HU_MAXLINES]HudTextLine,    // text lines to draw
    h: usize,                       // height in lines
    cl: usize,                      // current line number

    // pointer to boolean stating whether to update window
    on: *bool,
    laston: bool,                   // last value of .*.on.
};



// Input Text Line widget
//  (child of Text Line widget)
pub const HudIText = struct {
    l: HudTextLine,     // text line to input on

    // left margin past which I am not to delete characters
    lm: usize,

    // pointer to boolean stating whether to update window
    on: *bool,
    laston: bool,       // last value of *->on;
};

extern var automapactive: c.boolean;    // in AM_map.c


fn HUlib_clearTextLine(t: *HudTextLine) void {
    t.len = 0;
    t.l[0] = 0;
    t.needsupdate = 1; // "true"
}

pub fn HUlib_initTextLine(t: *HudTextLine, x: c_int, y: c_int, f: []*c.patch_t, sc: c_int) void {
    t.x = x;
    t.y = y;
    t.f = f;
    t.sc = sc;
    HUlib_clearTextLine(t);
}

pub fn HUlib_addCharToTextLine(t: *HudTextLine, ch: u8) bool {
    if (t.len == HU_MAXLINELENGTH) {
        return false;
    }

    t.l[t.len] = ch;
    t.len += 1;
    t.l[t.len] = 0;
    t.needsupdate = 4;
    return true;
}

fn HUlib_delCharFromTextLine(t: *HudTextLine) bool {
    if (t.len == 0) {
        return false;
    }

    t.len -= 1;
    t.l[t.len] = 0;
    t.needsupdate = 4;
    return true;
}

pub fn HUlib_drawTextLine(l: *HudTextLine, drawcursor: bool) void {
    // draw the new stuff
    var x = l.x;
    for (0..l.len) |i| {
        const ch = std.ascii.toUpper(l.l[i]);
        if (ch != ' ' and ch >= l.sc and ch <= '_') {
            const w = std.mem.littleToNative(c_short, l.f[@intCast(ch - l.sc)].width);
            if (x + w > SCREENWIDTH) {
                break;
            }
            c.V_DrawPatch(x, l.y, FG, l.f[@intCast(ch - l.sc)]);
            x += w;
        } else {
            x += 4;
            if (x >= SCREENWIDTH) {
                break;
            }
        }
    }

    // draw the cursor if requested
    if (drawcursor and x + std.mem.littleToNative(c_short, l.f[@intCast('_' - l.sc)].width) <= SCREENWIDTH) {
        c.V_DrawPatch(x, l.y, FG, l.f[@intCast('_' - l.sc)]);
    }
}


// sorta called by HU_Erase and just better darn get things straight
pub fn HUlib_eraseTextLine(l: *HudTextLine) void {
    // Only erases when NOT in automap and the screen is reduced,
    // and the text must either need updating or refreshing
    // (because of a recent change back from the automap)

    if (automapactive == c.false and c.viewwindowx != 0 and l.needsupdate != 0) {
        const lh = std.mem.littleToNative(c_short, l.f[0].height) + 1;
        for (@intCast(l.y)..@intCast(l.y + lh)) |y| {
            const yoffset = y * SCREENWIDTH;
            if (y < c.viewwindowy or y >= c.viewwindowy + c.viewheight) {
                c.R_VideoErase(@intCast(yoffset), SCREENWIDTH);   // erase entire line
            } else {
                c.R_VideoErase(@intCast(yoffset), c.viewwindowx); // erase left border
                c.R_VideoErase(@as(c_uint, @intCast(yoffset)) + @as(c_uint, @intCast(c.viewwindowx + c.viewwidth)), c.viewwindowx);
                // erase right border
            }
        }
    }

    if (l.needsupdate != 0) {
        l.needsupdate -= 1;
    }
}

pub fn HUlib_initSText(s: *HudSText, x: c_int, y: c_int, h: u32, font: []*c.patch_t, startchar: c_int, on: *bool) void {
    s.h = h;
    s.on = on;
    s.laston = true;
    s.cl = 0;

    const fh = std.mem.littleToNative(c_short, font[0].height) + 1;
    for (0..h) |i| {
        HUlib_initTextLine(&s.l[i], x, y - @as(c_int, @intCast(i)) * fh, font, startchar);
    }
}

fn HUlib_addLineToSText(s: *HudSText) void {
    // add a clear line
    s.cl += 1;
    if (s.cl == s.h) {
        s.cl = 0;
    }
    HUlib_clearTextLine(&s.l[s.cl]);

    // everthing needs updating
    for (0..s.h) |i| {
        s.l[i].needsupdate = 4;
    }
}

pub fn HUlib_addMessageToSText(s: *HudSText, prefix: []const u8, msg: []const u8) void {
    HUlib_addLineToSText(s);

    for (prefix) |ch| {
        _ = HUlib_addCharToTextLine(&s.l[s.cl], ch);
    }

    for (msg) |ch| {
        _ = HUlib_addCharToTextLine(&s.l[s.cl], ch);
    }
}

pub fn HUlib_drawSText(s: *HudSText) void {
    if (!s.on.*) {
        return; // if not on don't draw
    }

    // draw everything
    for (0..s.h) |i| {
        const idx =
            if (s.cl < i)
                s.cl + s.h - i  // handle queue of lines
            else
                s.cl - i;

        const l = &s.l[idx];

        // need a decision mode here on whether to skip the draw
        HUlib_drawTextLine(l, false);  // no cursor, please
    }
}

pub fn HUlib_eraseSText(s: *HudSText) void {
    for (0..s.h) |i| {
        if (s.laston and !s.on.*) {
            s.l[i].needsupdate = 4;
        }
        HUlib_eraseTextLine(&s.l[i]);
    }

    s.laston = s.on.*;
}

pub fn HUlib_initIText(it: *HudIText, x: c_int, y: c_int, font: []*c.patch_t, startchar: c_int, on: *bool) void {
    it.lm = 0; // default left margin is start of text
    it.on = on;
    it.laston = true;
    HUlib_initTextLine(&it.l, x, y, font, startchar);
}

// The following deletion routines adhere to the left margin restriction
fn HUlib_delCharFromIText(it: *HudIText) void {
    if (it.l.len != it.lm) {
        _ = HUlib_delCharFromTextLine(&it.l);
    }
}

fn HUlib_eraseLineFromIText(it: *HudIText) void {
    while (it.lm != it.l.len) {
        _ = HUlib_delCharFromTextLine(&it.l);
    }
}

// Resets left margin as well
pub fn HUlib_resetIText(it: *HudIText) void {
    it.lm = 0;
    HUlib_clearTextLine(&it.l);
}

fn HUlib_addPrefixToIText(it: *HudIText, str: []const u8) void {
    for (str) |ch| {
        _ = HUlib_addCharToTextLine(&it.l, ch);
    }
    it.lm = it.l.len;
}

// wrapper function for handling general keyed input.
// returns true if it ate the key
pub fn HUlib_keyInIText(it: *HudIText, ch: u8) bool {
    if (ch >= ' ' and ch <= '_') {
        _ = HUlib_addCharToTextLine(&it.l, ch);
    } else {
        if (ch == doomdef.KEY_BACKSPACE) {
            HUlib_delCharFromIText(it);
        } else if (ch != doomdef.KEY_ENTER) {
            return false; // did not eat key
        }
    }

    return true; // ate the key
}

pub fn HUlib_drawIText(it: *HudIText) void {
    if (!it.on.*) {
        return;
    }

    HUlib_drawTextLine(&it.l, true); // draw the line w/ cursor
}

pub fn HUlib_eraseIText(it: *HudIText) void {
    if (it.laston and !it.on.*) {
        it.l.needsupdate = 4;
    }

    HUlib_eraseTextLine(&it.l);
    it.laston = it.on.*;
}
