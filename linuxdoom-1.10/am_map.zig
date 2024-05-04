const c = @cImport({
    @cInclude("doomstat.h");
    @cInclude("dstrings.h");
    @cInclude("tables.h");
    @cInclude("p_local.h");
    @cInclude("r_state.h");
});

const std = @import("std");

const doomdata = @import("doomdata.zig");
const doomdef = @import("doomdef.zig");
const d_main = @import("d_main.zig");
const Event = d_main.Event;
const d_player = @import("d_player.zig");
const Player = d_player.Player;
const g_game = @import("g_game.zig");
const m_cheat = @import("m_cheat.zig");
const CheatSeq = m_cheat.CheatSeq;
const cht_CheckCheat = m_cheat.cht_CheckCheat;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FixedDiv = m_fixed.FixedDiv;
const FixedMod = m_fixed.FixedMod;
const FixedMul = m_fixed.FixedMul;
const FRACBITS = m_fixed.FRACBITS;
const FRACUNIT = m_fixed.FRACUNIT;
const p_setup = @import("p_setup.zig");
const st_stuff = @import("st_stuff.zig");
const ST_Responder = st_stuff.ST_Responder;
const v_video = @import("v_video.zig");
const V_DrawPatch = v_video.V_DrawPatchSigned;
const w_wad = @import("w_wad.zig");
const W_CacheLumpNameFmt = w_wad.W_CacheLumpNameFmt;
const z_zone = @import("z_zone.zig");

pub const AM_MSGHEADER = 'a' << 24 | 'm' << 16;
pub const AM_MSGENTERED = AM_MSGHEADER | 'e' << 8;
pub const AM_MSGEXITED = AM_MSGHEADER | 'x' << 8;

const MAXINT = std.math.maxInt(fixed_t);
const MININT = std.math.minInt(fixed_t);

// For use if I do walls with outsides/insides
const REDS              = 256 - 5 * 16;
const REDRANGE          = 16;
const BLUES             = 256 - 4 * 16 + 8;
const BLUERANGE         = 8;
const GREENS            = 7 * 16;
const GREENRANGE        = 16;
const GRAYS             = 6 * 16;
const GRAYSRANGE        = 16;
const BROWNS            = 4 * 16;
const BROWNRANGE        = 16;
const YELLOWS           = 256 - 32 + 7;
const YELLOWRANGE       = 1;
const BLACK             = 0;
const WHITE             = 256 - 47;

// Automap colors
const BACKGROUND        = BLACK;
const YOURCOLORS        = WHITE;
const YOURRANGE         = 0;
const WALLCOLORS        = REDS;
const WALLRANGE         = REDRANGE;
const TSWALLCOLORS      = GRAYS;
const TSWALLRANGE       = GRAYSRANGE;
const FDWALLCOLORS      = BROWNS;
const FDWALLRANGE       = BROWNRANGE;
const CDWALLCOLORS      = YELLOWS;
const CDWALLRANGE       = YELLOWRANGE;
const THINGCOLORS       = GREENS;
const THINGRANGE        = GREENRANGE;
const SECRETWALLCOLORS  = WALLCOLORS;
const SECRETWALLRANGE   = WALLRANGE;
const GRIDCOLORS        = (GRAYS + GRAYSRANGE/2);
const GRIDRANGE         = 0;
const XHAIRCOLORS       = GRAYS;

// drawing stuff
const FB                = 0;

const AM_PANDOWNKEY     = doomdef.KEY_DOWNARROW;
const AM_PANUPKEY       = doomdef.KEY_UPARROW;
const AM_PANRIGHTKEY    = doomdef.KEY_RIGHTARROW;
const AM_PANLEFTKEY     = doomdef.KEY_LEFTARROW;
const AM_ZOOMINKEY      = '=';
const AM_ZOOMOUTKEY     = '-';
const AM_STARTKEY       = doomdef.KEY_TAB;
const AM_ENDKEY         = doomdef.KEY_TAB;
const AM_GOBIGKEY       = '0';
const AM_FOLLOWKEY      = 'f';
const AM_GRIDKEY        = 'g';
const AM_MARKKEY        = 'm';
const AM_CLEARMARKKEY   = 'c';

const AM_NUMMARKPOINTS  = 10;

// scale on entry
const INITSCALEMTOF     = 0.2 * FRACUNIT;
// how much the automap moves window per tic in frame-buffer coordinates
// moves 140 pixels in 1 second
const F_PANINC          = 4;
// how much zoom-in per tic
// goes to 2x in 1 second
const M_ZOOMIN          = @as(comptime_int, @intFromFloat(1.02*FRACUNIT));
// how much zoom-out per tic
// pulls out to 0.5x in 1 second
const M_ZOOMOUT         = @as(comptime_int, @intFromFloat(@as(comptime_float, FRACUNIT)/1.02));

// translates between frame-buffer and map distances
fn FTOM(x: fixed_t) fixed_t { return FixedMul(x << 16, scale_ftom); }
fn MTOF(x: fixed_t) fixed_t { return FixedMul(x, scale_mtof) >> 16; }
// translates between frame-buffer and map coordinates
fn CXMTOF(x: fixed_t) fixed_t { return f_x + MTOF(x - m_x); }
fn CYMTOF(y: fixed_t) fixed_t { return f_y + f_h - MTOF(y - m_y); }


const fpoint_t = struct {
    x: c_int,
    y: c_int,
};

const fline_t = struct {
    a: fpoint_t,
    b: fpoint_t,
};

const mpoint_t = struct {
    x: fixed_t,
    y: fixed_t,
};

const mline_t = struct {
    a: mpoint_t,
    b: mpoint_t,
};

const islope_t = struct {
    slp: fixed_t,
    islp: fixed_t,
};



fn mline(ax: fixed_t, ay: fixed_t, bx: fixed_t, by: fixed_t) mline_t {
    return mline_t{
        .a = .{ .x = ax, .y = ay },
        .b = .{ .x = bx, .y = by },
    };
}

fn mlinef(comptime ax: comptime_float, comptime ay: comptime_float, comptime bx: comptime_float, comptime by: comptime_float) mline_t {
    return mline(
        @intFromFloat(ax), @intFromFloat(ay),
        @intFromFloat(bx), @intFromFloat(by),
    );
}

//
// The vector graphics for the automap.
//  A line drawing of the player pointing right,
//   starting from the middle.
//
const player_arrow = blk: {
    const R = 8 * c.PLAYERRADIUS / 7;
    break :blk [_]mline_t{
        mline(-R + R/8, 0, R, 0),   // -----
        mline(R, 0, R - R/2, R/4),   // ----->
        mline(R, 0, R - R/2, -R/4),
        mline(-R + R/8, 0, -R - R/8, R/4),   // >----->
        mline(-R + R/8, 0, -R - R/8, -R/4),
        mline(-R + 3*R/8, 0, -R + R/8, R/4),   // >>----->
        mline(-R + 3*R/8, 0, -R + R/8, -R/4),
    };
};

const cheat_player_arrow = blk: {
    const R = 8 * c.PLAYERRADIUS / 7;
    break :blk [_]mline_t{
        mline(-R + R/8, 0, R, 0),   // -----
        mline(R, 0, R - R/2, R/6),  // ----->
        mline(R, 0, R - R/2, -R/6),
        mline(-R + R/8, 0, -R - R/8, R/6),  // >----->
        mline(-R + R/8, 0, -R - R/8, -R/6),
        mline(-R + 3*R/8, 0, -R + R/8, R/6),  // >>----->
        mline(-R + 3*R/8, 0, -R + R/8, -R/6),
        mline(-R/2, 0, -R/2, -R/6), // >>-d--->
        mline(-R/2, -R/6, -R/2 + R/6, -R/6),
        mline(-R/2 + R/6, -R/6, -R/2 + R/6, R/4),
        mline(-R/6, 0, -R/6, -R/6), // >>-dd-->
        mline(-R/6, -R/6, 0, -R/6),
        mline(0, -R/6, 0, R/4),
        mline(R/6, R/4, R/6, -R/7), // >>-ddt->
        mline(R/6, -R/7, R/6 + R/32, -R/7 - R/32),
        mline(R/6 + R/32, -R/7 - R/32, R/6 + R/10, -R/7),
    };
};

const triangle_guy = blk: {
    const R: comptime_float = @floatFromInt(FRACUNIT);
    break :blk [_]mline_t{
        mlinef(-0.867*R, -0.5*R, 0.867*R, -0.5*R),
        mlinef(0.867*R, -0.5*R, 0, R),
        mlinef(0, R, -0.867*R, -0.5*R),
    };
};

const thintriangle_guy = blk: {
    const R: comptime_float = @floatFromInt(FRACUNIT);
    break :blk [_]mline_t{
        mlinef(-0.5*R, -0.7*R, R, 0),
        mlinef(R, 0, -0.5*R, 0.7*R),
        mlinef(-0.5*R, 0.7*R, -0.5*R, -0.7*R),
    };
};



var cheating: c_int = 0;
var grid = false;

pub export var automapactive: c.boolean = c.false;

// location of window on screen
var f_x: c_int = undefined;
var f_y: c_int = undefined;

// size of window on screen
var f_w: c_int = undefined;
var f_h: c_int = undefined;

var lightlev: u8 = undefined;       // used for funky strobing effect
var fb: [*]u8 = undefined;          // pseudo-frame buffer
var amclock: c_int = undefined;

var m_paninc: mpoint_t = undefined; // how far the window pans each tic (map coords)
var mtof_zoommul: fixed_t = undefined;  // how far the window zooms in each tic (map coords)
var ftom_zoommul: fixed_t = undefined;  // how far the window zooms in each tic (fb coords)

var m_x: fixed_t = undefined;   // LL x,y where the window is on the map (map coords)
var m_y: fixed_t = undefined;
var m_x2: fixed_t = undefined;  // UR x,y where the window is on the map (map coords)
var m_y2: fixed_t = undefined;

//
// width/height of window on map (map coords)
//
var m_w: fixed_t = undefined;
var m_h: fixed_t = undefined;

// based on level size
var min_x: fixed_t = undefined;
var min_y: fixed_t = undefined;
var max_x: fixed_t = undefined;
var max_y: fixed_t = undefined;

var max_w: fixed_t = undefined; // max_x-min_x,
var max_h: fixed_t = undefined; // max_y-min_y

// based on player size
var min_w: fixed_t = undefined;
var min_h: fixed_t = undefined;


var min_scale_mtof: fixed_t = undefined;    // used to tell when to stop zooming out
var max_scale_mtof: fixed_t = undefined;    // used to tell when to stop zooming in

// old stuff for recovery later
var old_m_w: fixed_t = undefined;
var old_m_h: fixed_t = undefined;
var old_m_x: fixed_t = undefined;
var old_m_y: fixed_t = undefined;

// old location used by the Follower routine
var f_oldloc: mpoint_t = undefined;

// used by MTOF to scale from map-to-frame-buffer coords
var scale_mtof: fixed_t = @intFromFloat(INITSCALEMTOF);
// used by FTOM to scale from frame-buffer-to-map coords (=1/scale_mtof)
var scale_ftom: fixed_t = undefined;

var plr: *Player = undefined;

var marknums: [10]*v_video.c.patch_t = undefined; // numbers used for marking by the automap
var markpoints: [AM_NUMMARKPOINTS]mpoint_t = undefined; // where the points are
var markpointnum: usize = 0;    // next point to be assigned

var followplayer = true;        // specifies whether to follow the player

var cheat_amap_seq = [_]u8{0xb2, 0x26, 0x26, 0x2e, 0xff};
var cheat_amap = CheatSeq{ .sequence=&cheat_amap_seq, .p=null };

var stopped = true;


// Calculates the slope and slope according to the x-axis of a line
// segment in map coordinates (with the upright y-axis n' all) so
// that it can be used with the brain-dead drawing stuff.

fn AM_getIslope(ml: *mline_t, is: *islope_t) void {
    const dy = ml.a.y - ml.b.y;
    const dx = ml.b.x - ml.a.x;
    if (dy == 0) {
        is.islp = if (dx < 0) MININT else MAXINT;
    } else {
        is.islp = FixedDiv(dx, dy);
    }

    if (dx == 0) {
        is.slp = if (dy < 0) MININT else MAXINT;
    } else {
        is.slp = FixedDiv(dy, dx);
    }
}

//
//
//
fn AM_activateNewScale() void {
    m_x += @divTrunc(m_w, 2);
    m_y += @divTrunc(m_h, 2);
    m_w = FTOM(f_w);
    m_h = FTOM(f_h);
    m_x -= @divTrunc(m_w, 2);
    m_y -= @divTrunc(m_h, 2);
    m_x2 = m_x + m_w;
    m_y2 = m_y + m_h;
}

//
//
//
fn AM_saveScaleAndLoc() void {
    old_m_x = m_x;
    old_m_y = m_y;
    old_m_w = m_w;
    old_m_h = m_h;
}

//
//
//
fn AM_restoreScaleAndLoc() void {
    m_w = old_m_w;
    m_h = old_m_h;

    if (!followplayer) {
        m_x = old_m_x;
        m_y = old_m_y;
    } else {
        m_x = plr.mo.?.x - @divTrunc(m_w, 2);
        m_y = plr.mo.?.y - @divTrunc(m_h, 2);
    }

    m_x2 = m_x + m_w;
    m_y2 = m_y + m_h;

    // Change the scaling multipliers
    scale_mtof = FixedDiv(f_w << FRACBITS, m_w);
    scale_ftom = FixedDiv(FRACUNIT, scale_mtof);
}

//
// adds a marker at the current location
//
fn AM_addMark() void {
    markpoints[markpointnum].x = m_x + @divTrunc(m_w, 2);
    markpoints[markpointnum].y = m_y + @divTrunc(m_h, 2);
    markpointnum += 1;
    markpointnum %= AM_NUMMARKPOINTS;
}

//
// Determines bounding box of all vertices,
// sets global variables controlling zoom range.
//
fn AM_findMinMaxBoundries() void {
    min_x = MAXINT;
    min_y = MAXINT;
    max_x = MININT;
    max_y = MININT;

    for (p_setup.vertexes) |vertex| {
        if (vertex.x < min_x) {
            min_x = vertex.x;
        } else if (vertex.x > max_x) {
            max_x = vertex.x;
        }

        if (vertex.y < min_y) {
            min_y = vertex.y;
        } else if (vertex.y > max_y) {
            max_y = vertex.y;
        }
    }

    max_w = max_x - min_x;
    max_h = max_y - min_y;

    min_w = 2 * c.PLAYERRADIUS; // const? never changed?
    min_h = 2 * c.PLAYERRADIUS;

    const a = FixedDiv(f_w << FRACBITS, max_w);
    const b = FixedDiv(f_h << FRACBITS, max_h);

    min_scale_mtof = if (a < b) a else b;
    max_scale_mtof = FixedDiv(f_h << FRACBITS, 2 * c.PLAYERRADIUS);
}


//
//
//
fn AM_changeWindowLoc() void {
    if (m_paninc.x != 0 or m_paninc.y != 0) {
        followplayer = false;
        f_oldloc.x = MAXINT;
    }

    m_x += m_paninc.x;
    m_y += m_paninc.y;

    const m_w_half = @divTrunc(m_w, 2);
    if (m_x + m_w_half > max_x) {
        m_x = max_x - m_w_half;
    } else if (m_x + m_w_half < min_x) {
        m_x = min_x - m_w_half;
    }

    const m_h_half = @divTrunc(m_h, 2);
    if (m_y + m_h_half > max_y) {
        m_y = max_y - m_h_half;
    } else if (m_y + m_h_half < min_y) {
        m_y = min_y - m_h_half;
    }

    m_x2 = m_x + m_w;
    m_y2 = m_y + m_h;
}

//
//
//
fn AM_initVariables() void {
    automapactive = c.true;
    fb = v_video.screens[0];

    f_oldloc.x = MAXINT;
    amclock = 0;
    lightlev = 0;

    m_paninc.x = 0;
    m_paninc.y = 0;
    ftom_zoommul = FRACUNIT;
    mtof_zoommul = FRACUNIT;

    m_w = FTOM(f_w);
    m_h = FTOM(f_h);

    // find player to center on initially
    var pnum: usize = @intCast(g_game.consoleplayer);
    if (g_game.playeringame[pnum] == c.false) {
        for (g_game.playeringame, 0..) |ingame, i| {
            if (ingame != c.false) {
                pnum = i;
                break;
            }
        }
    }

    plr = &g_game.players[pnum];
    m_x = plr.mo.?.x - @divTrunc(m_w, 2);
    m_y = plr.mo.?.y - @divTrunc(m_h, 2);
    AM_changeWindowLoc();

    // for saving & restoring
    old_m_x = m_x;
    old_m_y = m_y;
    old_m_w = m_w;
    old_m_h = m_h;

    // inform the status bar of the change
    const st_notify = Event{.type = .KeyUp, .data1 = AM_MSGENTERED, .data2 = undefined, .data3 = undefined };
    _ = ST_Responder(&st_notify);
}

//
//
//
fn AM_loadPics() void {
    for (0..10) |i| {
        marknums[i] = W_CacheLumpNameFmt(*v_video.c.patch_t, "AMMNUM{d}", .{i}, .Static);
    }
}

fn AM_unloadPics() void {
    for (0..10) |i| {
        z_zone.Z_ChangeTag(marknums[i], .Cache);
    }
}

fn AM_clearMarks() void {
    for (0..AM_NUMMARKPOINTS) |i| {
        markpoints[i].x = -1; // means empty
    }
    markpointnum = 0;
}

//
// should be called at the start of every level
// right now, i figure it out myself
//
fn AM_LevelInit() void {
    f_x = 0;
    f_y = 0;
    f_w = doomdef.SCREENWIDTH;
    f_h = doomdef.SCREENHEIGHT - 32;

    AM_clearMarks();

    AM_findMinMaxBoundries();
    scale_mtof = FixedDiv(min_scale_mtof, @intFromFloat(0.7 * FRACUNIT));
    if (scale_mtof > max_scale_mtof) {
        scale_mtof = min_scale_mtof;
    }
    scale_ftom = FixedDiv(FRACUNIT, scale_mtof);
}



//
//
//
pub export fn AM_Stop() void {
    const st_notify = Event{.type = .KeyUp, .data1 = AM_MSGEXITED, .data2 = undefined, .data3 = undefined };

    AM_unloadPics();
    automapactive = c.false;
    _ = ST_Responder(&st_notify);
    stopped = true;
}

//
//
//
fn AM_Start() void {
    const S = struct {
        var lastlevel: c_int = -1;
        var lastepisode: c_int = -1;
    };

    if (!stopped) {
        AM_Stop();
    }
    stopped = false;
    if (S.lastlevel != g_game.gamemap or S.lastepisode != g_game.gameepisode) {
        AM_LevelInit();
        S.lastlevel = g_game.gamemap;
        S.lastepisode = g_game.gameepisode;
    }

    AM_initVariables();
    AM_loadPics();
}

//
// set the window scale to the maximum size
//
fn AM_minOutWindowScale() void {
    scale_mtof = min_scale_mtof;
    scale_ftom = FixedDiv(FRACUNIT, scale_mtof);
    AM_activateNewScale();
}

//
// set the window scale to the minimum size
//
fn AM_maxOutWindowScale() void {
    scale_mtof = max_scale_mtof;
    scale_ftom = FixedDiv(FRACUNIT, scale_mtof);
    AM_activateNewScale();
}


//
// Handle events (user inputs) in automap mode
//
pub fn AM_Responder(ev: *Event) bool {
    const S = struct {
        var bigstate = false;
        var buffer: [19:0]u8 = undefined;
    };

    var rc = false;

    if (automapactive == c.false) {
        if (ev.type == .KeyDown and ev.data1 == AM_STARTKEY) {
            AM_Start();
            g_game.viewactive = false;
            rc = false;
        }
    }
    else if (ev.type == .KeyDown) {
        rc = true;
        switch (ev.data1) {
            AM_PANRIGHTKEY => {
                if (!followplayer) {
                    m_paninc.x = FTOM(F_PANINC);
                } else {
                    rc = false;
                }
            },

            AM_PANLEFTKEY => {
                if (!followplayer) {
                    m_paninc.x = -FTOM(F_PANINC);
                } else {
                    rc = false;
                }
            },

            AM_PANUPKEY => {
                if (!followplayer) {
                    m_paninc.y = FTOM(F_PANINC);
                } else {
                    rc = false;
                }
            },

            AM_PANDOWNKEY => {
                if (!followplayer) {
                    m_paninc.y = -FTOM(F_PANINC);
                } else {
                    rc = false;
                }
            },

            AM_ZOOMOUTKEY => {
                mtof_zoommul = M_ZOOMOUT;
                ftom_zoommul = M_ZOOMIN;
            },

            AM_ZOOMINKEY => {
                mtof_zoommul = M_ZOOMIN;
                ftom_zoommul = M_ZOOMOUT;
            },

            AM_ENDKEY => {
                S.bigstate = false;
                g_game.viewactive = true;
                AM_Stop();
            },

            AM_GOBIGKEY => {
                S.bigstate = !S.bigstate;
                if (S.bigstate) {
                    AM_saveScaleAndLoc();
                    AM_minOutWindowScale();
                } else {
                    AM_restoreScaleAndLoc();
                }
            },

            AM_FOLLOWKEY => {
                followplayer = !followplayer;
                f_oldloc.x = MAXINT;
                plr.message = if (followplayer) c.AMSTR_FOLLOWON else c.AMSTR_FOLLOWOFF;
            },

            AM_GRIDKEY => {
                grid = !grid;
                plr.message = if (grid) c.AMSTR_GRIDON else c.AMSTR_GRIDOFF;
            },

            AM_MARKKEY => {
                _ = std.fmt.bufPrintZ(&S.buffer, "{s} {d}", .{c.AMSTR_MARKEDSPOT, markpointnum}) catch unreachable;
                plr.message = &S.buffer;
                AM_addMark();
            },

            AM_CLEARMARKKEY => {
                AM_clearMarks();
                plr.message = c.AMSTR_MARKSCLEARED;
            },

            else => {
                rc = false;
            }
        }

        if (c.deathmatch == c.false and cht_CheckCheat(&cheat_amap, @intCast(ev.data1))) {
            rc = false;
            cheating = @mod(cheating + 1, 3);
        }
    }
    else if (ev.type == .KeyUp) {
        rc = false;
        switch (ev.data1) {
            AM_PANLEFTKEY,
            AM_PANRIGHTKEY => {
                if (!followplayer) {
                    m_paninc.x = 0;
                }
            },

            AM_PANUPKEY,
            AM_PANDOWNKEY => {
                if (!followplayer) {
                    m_paninc.y = 0;
                }
            },

            AM_ZOOMOUTKEY,
            AM_ZOOMINKEY => {
                mtof_zoommul = FRACUNIT;
                ftom_zoommul = FRACUNIT;
            },

            else => {}
        }
    }

    return rc;
}


//
// Zooming
//
fn AM_changeWindowScale() void {
    // Change the scaling multipliers
    scale_mtof = FixedMul(scale_mtof, mtof_zoommul);
    scale_ftom = FixedDiv(FRACUNIT, scale_mtof);

    if (scale_mtof < min_scale_mtof) {
        AM_minOutWindowScale();
    } else if (scale_mtof > max_scale_mtof) {
        AM_maxOutWindowScale();
    } else {
        AM_activateNewScale();
    }
}


//
//
//
fn AM_doFollowPlayer() void {
    if (f_oldloc.x != plr.mo.?.x or f_oldloc.y != plr.mo.?.y) {
        m_x = FTOM(MTOF(plr.mo.?.x)) - @divTrunc(m_w, 2);
        m_y = FTOM(MTOF(plr.mo.?.y)) - @divTrunc(m_h, 2);
        m_x2 = m_x + m_w;
        m_y2 = m_y + m_h;
        f_oldloc.x = plr.mo.?.x;
        f_oldloc.y = plr.mo.?.y;
    }
}

//
//
//
fn AM_updateLightLev() void {
    const S = struct {
        var nexttic: c_int = 0;
        const litelevels = [_]u8{ 0, 4, 7, 10, 12, 14, 15, 15 };
        var litelevelscnt: usize = 0;
    };

    // Change light level
    if (amclock > S.nexttic) {
        lightlev = S.litelevels[S.litelevelscnt];
        S.litelevelscnt += 1;

        if (S.litelevelscnt == S.litelevels.len) {
            S.litelevelscnt = 0;
        }

        S.nexttic = amclock + 6 - @mod(amclock, 6);
    }
}


//
// Updates on Game Tick
//
pub fn AM_Ticker() void {
    if (automapactive == c.false) {
        return;
    }

    amclock += 1;

    if (followplayer) {
        AM_doFollowPlayer();
    }

    // Change the zoom if necessary
    if (ftom_zoommul != FRACUNIT) {
        AM_changeWindowScale();
    }

    // Change x,y location
    if (m_paninc.x != 0 or m_paninc.y != 0) {
        AM_changeWindowLoc();
    }

    // Update light level
    // TODO: What happens if this is enabled? Looks like it would just
    // cycle infinitely through lightlev values
    // AM_updateLightLev();
}

//
// Clear automap frame buffer.
//
fn AM_clearFB(color: u8) void {
    @memset(fb[0..@intCast(f_w * f_h)], color);
}


//
// Automap clipping of lines.
//
// Based on Cohen-Sutherland clipping algorithm but with a slightly
// faster reject and precalculated slopes.  If the speed is needed,
// use a hash algorithm to handle the common cases.
//
const LEFT = 1;
const RIGHT = 2;
const BOTTOM = 4;
const TOP = 8;

fn DOOUTCODE(mx: c_int, my: c_int) c_int {
    var oc: c_int = 0;

    if (my < 0) {
        oc |= TOP;
    } else if (my >= f_h) {
        oc |= BOTTOM;
    }

    if (mx < 0) {
        oc |= LEFT;
    } else if (mx >= f_w) {
        oc |= RIGHT;
    }

    return oc;
}

fn AM_clipMline(ml: *mline_t, fl: *fline_t) bool {
    var outcode1: c_int = 0;
    var outcode2: c_int = 0;

    // do trivial rejects and outcodes
    if (ml.a.y > m_y2) {
        outcode1 = TOP;
    } else if (ml.a.y < m_y) {
        outcode1 = BOTTOM;
    }

    if (ml.b.y > m_y2) {
        outcode2 = TOP;
    } else if (ml.b.y < m_y) {
        outcode2 = BOTTOM;
    }

    if (outcode1 & outcode2 != 0) {
        return false; // trivially outside
    }

    if (ml.a.x < m_x) {
        outcode1 |= LEFT;
    } else if (ml.a.x > m_x2) {
        outcode1 |= RIGHT;
    }

    if (ml.b.x < m_x) {
        outcode2 |= LEFT;
    } else if (ml.b.x > m_x2) {
        outcode2 |= RIGHT;
    }

    if (outcode1 & outcode2 != 0) {
        return false; // trivially outside
    }

    // transform to frame-buffer coordinates.
    fl.a.x = CXMTOF(ml.a.x);
    fl.a.y = CYMTOF(ml.a.y);
    fl.b.x = CXMTOF(ml.b.x);
    fl.b.y = CYMTOF(ml.b.y);

    outcode1 = DOOUTCODE(fl.a.x, fl.a.y);
    outcode2 = DOOUTCODE(fl.b.x, fl.b.y);

    if (outcode1 & outcode2 != 0) {
        return false;
    }

    var outside: c_int = 0;
    var tmp: fpoint_t = undefined;
    var dx: c_int = 0;
    var dy: c_int = 0;

    while (outcode1 | outcode2 != 0) {
        // may be partially inside box
        // find an outside point
        if (outcode1 != 0) {
            outside = outcode1;
        } else {
            outside = outcode2;
        }

        // clip to each side
        if (outside & TOP != 0) {
            dy = fl.a.y - fl.b.y;
            dx = fl.b.x - fl.a.x;
            tmp.x = fl.a.x + @divTrunc(dx * fl.a.y, dy);
            tmp.y = 0;
        } else if (outside & BOTTOM != 0) {
            dy = fl.a.y - fl.b.y;
            dx = fl.b.x - fl.a.x;
            tmp.x = fl.a.x + @divTrunc(dx * (fl.a.y - f_h), dy);
            tmp.y = f_h - 1;
        } else if (outside & RIGHT != 0) {
            dy = fl.b.y - fl.a.y;
            dx = fl.b.x - fl.a.x;
            tmp.y = fl.a.y + @divTrunc(dy * (f_w - 1 - fl.a.x), dx);
            tmp.x = f_w - 1;
        } else if (outside & LEFT != 0) {
            dy = fl.b.y - fl.a.y;
            dx = fl.b.x - fl.a.x;
            tmp.y = fl.a.y + @divTrunc(dy * -fl.a.x, dx);
            tmp.x = 0;
        }

        if (outside == outcode1) {
            fl.a = tmp;
            outcode1 = DOOUTCODE(fl.a.x, fl.a.y);
        } else {
            fl.b = tmp;
            outcode2 = DOOUTCODE(fl.b.x, fl.b.y);
        }

        if (outcode1 & outcode2 != 0) {
            return false; // trivially outside
        }
    }

    return true;
}


//
// Classic Bresenham w/ whatever optimizations needed for speed
//
fn AM_drawFline(fl: *fline_t, color: u8) void {
    var x: c_int = 0;
    var y: c_int = 0;
    var dx: c_int = 0;
    var dy: c_int = 0;
    var sx: c_int = 0;
    var sy: c_int = 0;
    var ax: c_int = 0;
    var ay: c_int = 0;
    var d: c_int = 0;

    dx = fl.b.x - fl.a.x;
    ax = 2 * if (dx < 0) -dx else dx;
    sx = if (dx < 0) -1 else 1;

    dy = fl.b.y - fl.a.y;
    ay = 2 * if (dy < 0) -dy else dy;
    sy = if (dy < 0) -1 else 1;

    x = fl.a.x;
    y = fl.a.y;

    if (ax > ay) {
        d = ay - @divTrunc(ax, 2);
        while (true) {
            fb[@intCast(y * f_w + x)] = color;

            if (x == fl.b.x) {
                return;
            }

            if (d >= 0) {
                y += sy;
                d -= ax;
            }

            x += sx;
            d += ay;
        }
    } else {
        d = ax - @divTrunc(ay, 2);
        while (true) {
            fb[@intCast(y * f_w + x)] = color;

            if (y == fl.b.y) {
                return;
            }

            if (d >= 0) {
                x += sx;
                d -= ay;
            }

            y += sy;
            d += ax;
        }
    }
}


//
// Clip lines, draw visible parts of lines.
//
fn AM_drawMline(ml: *mline_t, color: u8) void {
    var fl: fline_t = undefined;

    if (AM_clipMline(ml, &fl)) {
        AM_drawFline(&fl, color); // draws it on frame buffer using fb coords
    }
}



//
// Draws flat (floor/ceiling tile) aligned grid lines.
//
fn AM_drawGrid(color: u8) void {
    // Figure out start of vertical gridlines
    var start = m_x;
    if (@mod(start - c.bmaporgx, c.MAPBLOCKUNITS << FRACBITS) != 0) {
        start += (c.MAPBLOCKUNITS << FRACBITS) - @mod(start - c.bmaporgx, c.MAPBLOCKUNITS << FRACBITS);
    }
    var end = m_x + m_w;

    // draw vertical gridlines
    var ml: mline_t = undefined;
    ml.a.y = m_y;
    ml.b.y = m_y + m_h;
    var x = start;
    while (x < end) : (x += c.MAPBLOCKUNITS << FRACBITS) {
        ml.a.x = x;
        ml.b.x = x;
        AM_drawMline(&ml, color);
    }

    // Figure out start of horizontal gridlines
    start = m_y;
    if (@mod(start - c.bmaporgy, c.MAPBLOCKUNITS << FRACBITS) != 0) {
        start += (c.MAPBLOCKUNITS << FRACBITS) - @mod(start - c.bmaporgy, c.MAPBLOCKUNITS << FRACBITS);
    }
    end = m_y + m_h;

    // draw horizontal gridlines
    ml.a.x = m_x;
    ml.b.x = m_x + m_w;
    var y = start;
    while (y < end) : (y += c.MAPBLOCKUNITS << FRACBITS) {
        ml.a.y = y;
        ml.b.y = y;
        AM_drawMline(&ml, color);
    }
}

//
// Determines visible lines, draws them.
// This is LineDef based, not LineSeg based.
//
fn AM_drawWalls() void {
    for (c.lines[0..@intCast(c.numlines)]) |line| {
        var l: mline_t = undefined;

        l.a.x = line.v1[0].x;
        l.a.y = line.v1[0].y;
        l.b.x = line.v2[0].x;
        l.b.y = line.v2[0].y;

        if (cheating != 0 or line.flags & doomdata.ML_MAPPED != 0) {
            if (line.flags & doomdata.ML_DONTDRAW != 0 and cheating == 0) {
                continue;
            }

            if (line.backsector == c.false) {
                AM_drawMline(&l, WALLCOLORS + lightlev);
            } else {
                if (line.special == 39) {
                    // teleporters
                    AM_drawMline(&l, WALLCOLORS + WALLRANGE / 2);
                } else if (line.flags & doomdata.ML_SECRET != 0) { // secret door
                    const color: u8 = if (cheating != 0) SECRETWALLCOLORS else WALLCOLORS;
                    AM_drawMline(&l, color + lightlev);
                } else if (line.backsector[0].floorheight != line.frontsector[0].floorheight) {
                    AM_drawMline(&l, FDWALLCOLORS + lightlev); // floor level change
                } else if (line.backsector[0].ceilingheight != line.frontsector[0].ceilingheight) {
                    AM_drawMline(&l, CDWALLCOLORS + lightlev); // ceiling level change
                } else if (cheating != 0) {
                    AM_drawMline(&l, TSWALLCOLORS + lightlev);
                }
            }
        } else if (plr.powers[@intFromEnum(doomdef.PowerType.AllMap)] != 0) {
            if (line.flags & doomdata.ML_DONTDRAW == 0) {
                AM_drawMline(&l, GRAYS + 3);
            }
        }
    }
}


//
// Rotation in 2D.
// Used to rotate player arrow line character.
//
fn AM_rotate(x: *fixed_t, y: *fixed_t, a: c.angle_t) void {
    var tmpx =
        FixedMul(x.*, c.finecosine[a >> c.ANGLETOFINESHIFT])
        - FixedMul(y.*, c.finesine[a >> c.ANGLETOFINESHIFT]);

    y.* =
        FixedMul(x.*, c.finesine[a >> c.ANGLETOFINESHIFT])
        + FixedMul(y.*, c.finecosine[a >> c.ANGLETOFINESHIFT]);

    x.* = tmpx;
}

fn AM_drawLineCharacter(
    lineguylines: []const mline_t,
    scale: fixed_t,
    angle: c.angle_t,
    color: u8,
    x: fixed_t,
    y: fixed_t,
) void {
    for (lineguylines) |line| {
        var l = line;

        if (scale != 0) {
            l.a.x = FixedMul(scale, l.a.x);
            l.a.y = FixedMul(scale, l.a.y);
            l.b.x = FixedMul(scale, l.b.x);
            l.b.y = FixedMul(scale, l.b.y);
        }

        if (angle != 0) {
            AM_rotate(&l.a.x, &l.a.y, angle);
            AM_rotate(&l.b.x, &l.b.y, angle);
        }

        l.a.x += x;
        l.a.y += y;
        l.b.x += x;
        l.b.y += y;

        AM_drawMline(&l, color);
    }
}

fn AM_drawPlayers() void {
    if (g_game.netgame == c.false) {
        const arrow = if (cheating != 0) &cheat_player_arrow else &player_arrow;
        AM_drawLineCharacter(arrow, 0, plr.mo.?.angle, WHITE, plr.mo.?.x, plr.mo.?.y);
        return;
    }

    const their_colors = [_]u8{ GREENS, GRAYS, BROWNS, REDS };
    for (&g_game.players, g_game.playeringame, their_colors) |*p, playeringame, their_color| {
        if (g_game.deathmatch != c.false and !g_game.singledemo and p != plr) {
            continue;
        }

        if (playeringame == c.false) {
            continue;
        }

        const color =
            if (p.powers[@intFromEnum(doomdef.PowerType.Invisibility)] != c.false)
                246 // *close* to black
            else
                their_color;

        AM_drawLineCharacter(&player_arrow, 0, p.mo.?.angle, color, p.mo.?.x, p.mo.?.y);
    }
}

fn AM_drawThings(color: u8) void {
    for (c.sectors[0..@intCast(c.numsectors)]) |sector| {
        var t = sector.thinglist;
        while (t != null) : (t = t[0].snext) {
            AM_drawLineCharacter(&thintriangle_guy, 16 << FRACBITS, t[0].angle, color + lightlev, t[0].x, t[0].y);
        }
    }
}

fn AM_drawMarks() void {
    for (markpoints, marknums) |markpoint, marknum| {
        if (markpoint.x == -1) { continue; }

        var w: c_int = 5;
        var h: c_int = 6;
        var fx = CXMTOF(markpoint.x);
        var fy = CYMTOF(markpoint.y);
        if (fx >= f_x and fx <= f_w - w and fy >= f_y and fy <= f_h - h) {
            V_DrawPatch(fx, fy, FB, marknum);
        }
    }
}

fn AM_drawCrosshair(color: u8) void {
    fb[@intCast(@divTrunc(f_w * (f_h + 1), 2))] = color; // single point for now
}

pub fn AM_Drawer() void {
    if (automapactive == c.false) { return; }

    AM_clearFB(BACKGROUND);
    if (grid) {
        AM_drawGrid(GRIDCOLORS);
    }

    AM_drawWalls();
    AM_drawPlayers();
    if (cheating == 2) {
        AM_drawThings(THINGCOLORS);
    }

    AM_drawCrosshair(XHAIRCOLORS);
    AM_drawMarks();

    // TODO: Delete all dirtybox and V_MarkRect code
    // V_MarkRect(f_x, f_y, f_w, f_h);
}
