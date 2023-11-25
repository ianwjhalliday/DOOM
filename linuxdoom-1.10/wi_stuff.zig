const c = @cImport({
    @cInclude("d_event.h");
    @cInclude("d_player.h");
});

const std = @import("std");

const doomdef = @import("doomdef.zig");
const MAXPLAYERS = doomdef.MAXPLAYERS;
const SCREENHEIGHT = doomdef.SCREENHEIGHT;
const SCREENWIDTH = doomdef.SCREENWIDTH;
const TICRATE = doomdef.TICRATE;
const doomstat = @import("doomstat.zig");
const g_game = @import("g_game.zig");
const m_random = @import("m_random.zig");
const M_Random = m_random.M_Random;
const s_sound = @import("s_sound.zig");
const S_ChangeMusic = s_sound.S_ChangeMusicEnum;
const S_StartSound = s_sound.S_StartSound_Zig;
const v_video = @import("v_video.zig");
const V_DrawPatch = v_video.V_DrawPatchSigned;
const V_MarkRect = v_video.V_MarkRect;
const w_wad = @import("w_wad.zig");
const z_zone = @import("z_zone.zig");
const Z_ChangeTag = z_zone.Z_ChangeTag;
const Z_Tag = z_zone.Z_Tag;

fn W_CacheLumpNameAsPatch(name: []const u8, tag: Z_Tag) *v_video.c.patch_t {
    return @ptrCast(@alignCast(w_wad.W_CacheLumpName(name.ptr, tag)));
}

//
// Different vetween registered DOOM (1994) and
//  Ultimate DOOM - Final edition (retail, 1995?).
// This is supposedly ignored for commercial
//  release (aka DOOM II), which had 34 maps
//  in one episode. So there.
const NUMEPISODES = 4;
const NUMMAPS = 9;

// GLOBAL LOCATIONS
const WI_TITLEY = 2;
const WI_SPACINGY = 33;

// SINGPLE-PLAYER STUFF
const SP_STATSX = 50;
const SP_STATSY = 50;

const SP_TIMEX = 16;
const SP_TIMEY = doomdef.SCREENHEIGHT - 32;


// NET GAME STUFF
const NG_STATSY = 50;
fn NG_STATSX() c_short {
    const nodofragoffset: c_short = if (!dofrags) 32 else 0;
    return 32 + @divTrunc(std.mem.littleToNative(c_short, star.width), 2) + nodofragoffset;
}

const NG_SPACINGX = 64;


// DEATHMATCH STUFF
const DM_MATRIXX = 42;
const DM_MATRIXY = 68;

const DM_SPACINGX = 40;

const DM_TOTALSX = 269;

const DM_KILLERSX = 10;
const DM_KILLERSY = 100;
const DM_VICTIMSX = 5;
const DM_VICTIMSY = 50;


// TODO: Does this need to start at -1?
const State = enum(c_int) {
    NoState = -1,
    StatCount,
    ShowNextLoc,
};

const AnimType = enum {
    Always,
    Random,
    Level,
};

const Point = struct {
    x: c_int,
    y: c_int,
};

const patch_t = v_video.c.patch_t;

//
// Animation.
// There is another anim_t used in p_spec.
//
const Anim = struct {
    type: AnimType,

    // period in tics between animations
    period: c_int,

    // number of animation frames
    nanims: c_int,

    // location of animation
    loc: Point,

    // ALWAYS: n/a,
    // RANDOM: period deviation (<256),
    // LEVEL: level
    data1: c_int,

    // ALWAYS: n/a,
    // RANDOM: random base period,
    // LEVEL: n/a
    data2: c_int,

    // actual graphics for frames of animations
    p: [3]*patch_t,

    // following must be initialized to zero before use!

    // next value of bcnt (used in conjunction with period)
    nexttic: c_int,

    // last drawn animation frame
    lastdrawn: c_int,

    // next frame number to animate
    ctr: c_int,

    // used by RANDOM and LEVEL when animating
    state: c_int,
};

const lnodes = [_][NUMMAPS]Point{
    // Episode 0 World Map
    .{
        .{ .x = 185, .y = 164 },    // location of level 0 (CJ)
        .{ .x = 148, .y = 143 },    // location of level 1 (CJ)
        .{ .x = 69, .y = 122 },     // location of level 2 (CJ)
        .{ .x = 209, .y = 102 },    // location of level 3 (CJ)
        .{ .x = 116, .y = 89 },     // location of level 4 (CJ)
        .{ .x = 166, .y = 55 },     // location of level 5 (CJ)
        .{ .x = 71, .y = 56 },      // location of level 6 (CJ)
        .{ .x = 135, .y = 29 },     // location of level 7 (CJ)
        .{ .x = 71, .y = 24 },      // location of level 8 (CJ)
    },

    // Episode 1 World Map
    .{
        .{ .x = 254, .y = 25 },     // location of level 0 (CJ)
        .{ .x = 97, .y = 50 },      // location of level 1 (CJ)
        .{ .x = 188, .y = 64 },     // location of level 2 (CJ)
        .{ .x = 128, .y = 78 },     // location of level 3 (CJ)
        .{ .x = 214, .y = 92 },     // location of level 4 (CJ)
        .{ .x = 133, .y = 130 },    // location of level 5 (CJ)
        .{ .x = 208, .y = 136 },    // location of level 6 (CJ)
        .{ .x = 148, .y = 140 },    // location of level 7 (CJ)
        .{ .x = 235, .y = 158 },    // location of level 8 (CJ)
    },

    // Episode 2 World Map
    .{
        .{ .x = 156, .y = 168 },    // location of level 0 (CJ)
        .{ .x = 48, .y = 154 },     // location of level 1 (CJ)
        .{ .x = 174, .y = 95 },     // location of level 2 (CJ)
        .{ .x = 265, .y = 75 },     // location of level 3 (CJ)
        .{ .x = 130, .y = 48 },     // location of level 4 (CJ)
        .{ .x = 279, .y = 23 },     // location of level 5 (CJ)
        .{ .x = 198, .y = 48 },     // location of level 6 (CJ)
        .{ .x = 140, .y = 25 },     // location of level 7 (CJ)
        .{ .x = 281, .y = 136 },    // location of level 8 (CJ)
    },
};



//
// Animation locations for episode 0 (1).
// Using patches saves a lot of space,
//  as they replace 320x200 full screen frames.
//

fn defAnim(animtype: AnimType, period: c_int, nanims: c_int, x: c_int, y: c_int, data1: c_int) Anim {
    return Anim{
        .type = animtype,
        .period = period,
        .nanims = nanims,
        .loc = Point{ .x = x, .y = y },
        .data1 = data1,
        .data2 = undefined,
        .p = undefined,
        .nexttic = undefined,
        .lastdrawn = undefined,
        .ctr = undefined,
        .state = undefined,
    };
}

var epsd0animinfo = [_]Anim{
    defAnim(.Always, TICRATE/3, 3, 224, 104, undefined),
    defAnim(.Always, TICRATE/3, 3, 184, 160, undefined),
    defAnim(.Always, TICRATE/3, 3, 112, 136, undefined),
    defAnim(.Always, TICRATE/3, 3, 72, 112, undefined),
    defAnim(.Always, TICRATE/3, 3, 88, 96, undefined),
    defAnim(.Always, TICRATE/3, 3, 64, 48, undefined),
    defAnim(.Always, TICRATE/3, 3, 192, 40, undefined),
    defAnim(.Always, TICRATE/3, 3, 136, 16, undefined),
    defAnim(.Always, TICRATE/3, 3, 80, 16, undefined),
    defAnim(.Always, TICRATE/3, 3, 64, 24, undefined),
};

var epsd1animinfo = [_]Anim{
    defAnim(.Level, TICRATE/3, 1, 128, 136, 1),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 2),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 3),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 4),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 5),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 6),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 7),
    defAnim(.Level, TICRATE/3, 3, 192, 144, 8),
    defAnim(.Level, TICRATE/3, 1, 128, 136, 8),
};

var epsd2animinfo = [_]Anim{
    defAnim(.Always, TICRATE/3, 3, 104, 168, undefined),
    defAnim(.Always, TICRATE/3, 3, 40, 136, undefined),
    defAnim(.Always, TICRATE/3, 3, 160, 96, undefined),
    defAnim(.Always, TICRATE/3, 3, 104, 80, undefined),
    defAnim(.Always, TICRATE/3, 3, 120, 32, undefined),
    defAnim(.Always, TICRATE/4, 3, 40, 0, undefined),
};

var anims = [_][]Anim{
    &epsd0animinfo,
    &epsd1animinfo,
    &epsd2animinfo,
};


//
// GENERAL DATA
//

//
// Locally used stuff.
//
const FB = 0;


// in seconds
const SHOWNEXTLOCDELAY = 4;


// used to accelerate or skip a stage
var acceleratestage = false;

// wbs.pnum
var me: usize = undefined;

// specifies current state
var state: State = undefined;

// contains information passed into intermission
var wbs: *g_game.c.wbstartstruct_t = undefined;
var plrs: []g_game.c.wbplayerstruct_t = undefined;    // wbs.plyr[]

// used for general timing
var cnt: c_int = undefined;

// used for timing of background animation
var bcnt: c_int = undefined;

var cnt_kills: [MAXPLAYERS]c_int = undefined;
var cnt_items: [MAXPLAYERS]c_int = undefined;
var cnt_secret: [MAXPLAYERS]c_int = undefined;
var cnt_time: c_int = undefined;
var cnt_par: c_int = undefined;
var cnt_pause: c_int = undefined;

// # of commercial levels
const NUMCMAPS = 32;


//
// GRAPHICS
//

// background (map of levels).
var bg: *patch_t = undefined;

// You Are Here graphic
var yah: [2]*patch_t = undefined;

// splat
var splat: *patch_t = undefined;

// %, : graphics
var percent: *patch_t = undefined;
var colon: *patch_t = undefined;

// 0-9 graphic
var num: [10]*patch_t = undefined;

// minus sign
var wiminus: *patch_t = undefined;

// "Finished!" graphic
var finished: *patch_t = undefined;

// "Entering" graphic
var entering: *patch_t = undefined;

// "secret"
var sp_secret: *patch_t = undefined;

// "Kills", "Scrt", "Items", "Frags"
var kills: *patch_t = undefined;
var secret: *patch_t = undefined;
var items: *patch_t = undefined;
var frags: *patch_t = undefined;

// Time sucks.
var time: *patch_t = undefined;
var par: *patch_t = undefined;
var sucks: *patch_t = undefined;

// "killers", "victims"
var killers: *patch_t = undefined;
var victims: *patch_t = undefined;

// "Total", your face, your dead face
var total: *patch_t = undefined;
var star: *patch_t = undefined;
var bstar: *patch_t = undefined;

// "red P[1..MAXPLAYERS]"
var p: [MAXPLAYERS]*patch_t = undefined;

// "gray P[1..MAXPLAYERS]"
var bp: [MAXPLAYERS]*patch_t = undefined;

// Name graphics of each level (centered)
var lnames: []*patch_t = undefined;

//
// CODE
//


fn WI_slamBackground() void {
    const numpixels = SCREENWIDTH * SCREENHEIGHT;
    @memcpy(v_video.screens[0][0..numpixels], v_video.screens[1]);
    V_MarkRect(0, 0, SCREENWIDTH, SCREENHEIGHT);
}


// Draws "<Levelname> Finished!"
fn WI_drawLF() void {
    const lname = lnames[@intCast(wbs.last)];

    // draw <LevelName>.
    V_DrawPatch(
        @divTrunc(SCREENWIDTH - std.mem.littleToNative(c_short, lname.width), 2),
        WI_TITLEY,
        FB,
        lname,
    );

    // draw "Finished!"
    V_DrawPatch(
        @divTrunc(SCREENWIDTH - std.mem.littleToNative(c_short, finished.width), 2),
        WI_TITLEY + @divTrunc(5 * std.mem.littleToNative(c_short, lname.height), 4),
        FB,
        finished,
    );
}


fn WI_drawEL() void {
    const lname = lnames[@intCast(wbs.next)];

    // draw <LevelName>.
    V_DrawPatch(
        @divTrunc(SCREENWIDTH - std.mem.littleToNative(c_short, entering.width), 2),
        WI_TITLEY,
        FB,
        entering,
    );

    // draw "Finished!"
    V_DrawPatch(
        @divTrunc(SCREENWIDTH - std.mem.littleToNative(c_short, lname.width), 2),
        WI_TITLEY + @divTrunc(5 * std.mem.littleToNative(c_short, lname.height), 4),
        FB,
        lname,
    );
}

fn WI_drawOnLnode(n: usize, cp: [*]*patch_t) void {
    const lnode = lnodes[@intCast(wbs.epsd)][n];

    var i: usize = 0;
    var fits = false;

    while (!fits and i != 2) {
        const left = lnode.x - std.mem.littleToNative(c_short, cp[i].leftoffset);
        const top = lnode.y - std.mem.littleToNative(c_short, cp[i].topoffset);
        const right = left + std.mem.littleToNative(c_short, cp[i].width);
        const bottom = top + std.mem.littleToNative(c_short, cp[i].height);

        if (left >= 0
            and right < SCREENWIDTH
            and top >= 0
            and bottom < SCREENHEIGHT) {
            fits = true;
        } else {
            i += 1;
        }
    }

    if (fits and i < 2) {
        V_DrawPatch(lnode.x, lnode.y, FB, cp[i]);
    } else {
        // DEBUG
        const stderr = std.io.getStdErr().writer();
        stderr.print("Could not place patch on level {d}\n", .{n + 1}) catch {};
    }
}


fn WI_initAnimatedBack() void {
    if (doomstat.gamemode == .Commercial) {
        return;
    }

    if (wbs.epsd > 2) {
        return;
    }

    for (anims[@intCast(wbs.epsd)]) |*a| {
        // init variables
        a.ctr = -1;

        // specify the next time to draw it
        a.nexttic = switch (a.type) {
            .Always => bcnt + 1 + @mod(M_Random(), a.period),
            .Random => bcnt + 1 + a.data2 + @mod(M_Random(), a.data1),
            .Level => bcnt + 1,
        };
    }
}

fn WI_updateAnimatedBack() void {
    if (doomstat.gamemode == .Commercial) {
        return;
    }

    if (wbs.epsd > 2) {
        return;
    }

    for (anims[@intCast(wbs.epsd)], 0..) |*a, i| {
        if (bcnt == a.nexttic) {
            switch (a.type) {
                .Always => {
                    a.ctr += 1;
                    if (a.ctr >= a.nanims) {
                        a.ctr = 0;
                    }

                    a.nexttic = bcnt + a.period;
                },

                .Random => {
                    a.ctr += 1;
                    if (a.ctr == a.nanims) {
                        a.ctr = -1;
                        a.nexttic = bcnt + a.data2 + @mod(M_Random(), a.data1);
                    } else {
                        a.nexttic = bcnt + a.period;
                    }
                },

                .Level => {
                    // gawd-awful hack for level anims
                    if (!(state == .StatCount and i == 7) and wbs.next == a.data1) {
                        a.ctr += 1;
                        if (a.ctr == a.nanims) {
                            a.ctr -= 1;
                        }
                        a.nexttic = bcnt + a.period;
                    }
                }
            }
        }
    }
}


fn WI_drawAnimatedBack() void {
    if (doomstat.gamemode == .Commercial) {
        return;
    }

    if (wbs.epsd > 2) {
        return;
    }

    for (anims[@intCast(wbs.epsd)]) |a| {
        if (a.ctr >= 0) {
            V_DrawPatch(a.loc.x, a.loc.y, FB, a.p[@intCast(a.ctr)]);
        }
    }
}


//
// Draws a number.
// If digits > 0, then use that many digits minimum,
//  otherwise only use as many as necessary.
// Returns new x position.
//
fn WI_drawNum(_x: c_int, y: c_int, _n: c_int, _digits: c_int) c_int {
    const fontwidth = std.mem.littleToNative(c_short, num[0].width);

    var x = _x;
    var n = _n;
    var digits = _digits;

    if (digits < 0) {
        if (n == 0) {
            // make variable-length zeroes 1 digit long
            digits = 1;
        } else {
            // figure out # of digits in #
            digits = 0;
            var temp = n;

            while (temp != 0) {
                temp = @divTrunc(temp, 10);
                digits += 1;
            }
        }
    }

    const neg = n < 0;
    if (neg) {
        n = -n;
    }

    // if non-number, do not draw it
    if (n == 1994) {
        return 0;
    }

    // draw the new number
    for (0..@intCast(digits)) |_| {
        x -= fontwidth;
        V_DrawPatch(x, y, FB, num[@intCast(@mod(n, 10))]);
        n = @divTrunc(n, 10);
    }

    // draw a minus sign if necessary
    if (neg) {
        x -= 8;
        V_DrawPatch(x, y, FB, wiminus);
    }

    return x;
}


fn WI_drawPercent(x: c_int, y: c_int, per: c_int) void {
    if (per < 0) {
        return;
    }

    V_DrawPatch(x, y, FB, percent);
    _ = WI_drawNum(x, y, per, -1);
}



//
// Display level completion time and par,
//  or "sucks" message if overflow.
//
fn WI_drawTime(_x: c_int, y: c_int, t: c_int) void {
    if (t < 0) {
        return;
    }

    var x = _x;

    if (t <= 61 * 59) {
        var div: c_int = 1;

        while (@divTrunc(t, div) != 0) {
            const n = @mod(@divTrunc(t, div), 60);
            x = WI_drawNum(x, y, n, 2) - std.mem.littleToNative(c_short, colon.width);
            div *= 60;

            // draw
            if (div == 60 or @divTrunc(t, div) != 0) {
                V_DrawPatch(x, y, FB, colon);
            }
        }
    } else {
        // "sucks"
        V_DrawPatch(x - std.mem.littleToNative(c_short, sucks.width), y, FB, sucks);
    }
}


fn WI_End() void {
    WI_unloadData();
}

fn WI_initNoState() void {
    state = .NoState;
    acceleratestage = false;
    cnt = 10;
}

fn WI_updateNoState() void {
    WI_updateAnimatedBack();

    cnt -= 1;
    if (cnt == 0) {
        WI_End();
        g_game.G_WorldDone();
    }
}


var snl_pointeron = false;


fn WI_initShowNextLoc() void {
    state = .ShowNextLoc;
    acceleratestage = false;
    cnt = SHOWNEXTLOCDELAY * TICRATE;

    WI_initAnimatedBack();
}

fn WI_updateShowNextLoc() void {
    WI_updateAnimatedBack();

    cnt -= 1;
    if (cnt == 0 or acceleratestage) {
        WI_initNoState();
    } else {
        snl_pointeron = cnt & 32 < 20;
    }
}

fn WI_drawShowNextLoc() void {
    WI_slamBackground();

    // draw animated background
    WI_drawAnimatedBack();

    if (doomstat.gamemode != .Commercial) {
        if (wbs.epsd > 2) {
            WI_drawEL();
            return;
        }

        const last: usize = @intCast(if (wbs.last == 8) wbs.next - 1 else wbs.last);

        // draw a splat on taken cities.
        for (0..last+1) |i| {
            WI_drawOnLnode(i, @ptrCast(&splat));
        }

        // splat the secret level?
        if (wbs.didsecret != c.false) {
            WI_drawOnLnode(8, @ptrCast(&splat));
        }

        // draw flashing ptr
        if (snl_pointeron) {
            WI_drawOnLnode(@intCast(wbs.next), &yah);
        }
    }

    // draws which level you are entering.
    if (doomstat.gamemode != .Commercial or wbs.next != 30) {
        WI_drawEL();
    }
}

fn WI_drawNoState() void {
    snl_pointeron = true;
    WI_drawShowNextLoc();
}

fn WI_fragSum(playernum: usize) c_int {
    var fragcount: c_int = 0;

    for (0..MAXPLAYERS) |i| {
        if (g_game.playeringame[i] != c.false and i != playernum) {
            fragcount += plrs[playernum].frags[i];
        }
    }

    // JDC hack - negative frags.
    fragcount -= plrs[playernum].frags[playernum];

    return fragcount;
}



var dm_state: c_int = undefined;
var dm_frags: [MAXPLAYERS][MAXPLAYERS]c_int = undefined;
var dm_totals: [MAXPLAYERS]c_int = undefined;



fn WI_initDeathmatchStats() void {
    state = .StatCount;
    acceleratestage = false;
    dm_state = 1;

    cnt_pause = TICRATE;

    for (0..MAXPLAYERS) |i| {
        if (g_game.playeringame[i] != c.false) {
            for (0..MAXPLAYERS) |j| {
                if (g_game.playeringame[j] != c.false) {
                    dm_frags[i][j] = 0;
                }
            }

            dm_totals[i] = 0;
        }
    }

    WI_initAnimatedBack();
}



fn WI_updateDeathmatchStats() void {
    WI_updateAnimatedBack();

    if (acceleratestage and dm_state != 4) {
        acceleratestage = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] != c.false) {
                for (0..MAXPLAYERS) |j| {
                    if (g_game.playeringame[j] != c.false) {
                        dm_frags[i][j] = plrs[i].frags[j];
                    }
                }

                dm_totals[i] = WI_fragSum(i);
            }
        }

        S_StartSound(null, .barexp);
        dm_state = 4;
    }


    if (dm_state == 2) {
        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        var stillticking = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] != c.false) {
                for (0..MAXPLAYERS) |j| {
                    if (g_game.playeringame[j] != c.false and dm_frags[i][j] != plrs[i].frags[j]) {
                        if (plrs[i].frags[j] < 0) {
                            dm_frags[i][j] -= 1;
                        } else {
                            dm_frags[i][j] += 1;
                        }

                        if (dm_frags[i][j] > 99) {
                            dm_frags[i][j] = 99;
                        }

                        if (dm_frags[i][j] < -99) {
                            dm_frags[i][j] = -99;
                        }

                        stillticking = true;
                    }
                }

                dm_totals[i] = WI_fragSum(i);

                if (dm_totals[i] > 99) {
                    dm_totals[i] = 99;
                }

                if (dm_totals[i] < -99) {
                    dm_totals[i] = -99;
                }
            }
        }

        if (!stillticking) {
            S_StartSound(null, .barexp);
            dm_state += 1;
        }
    } else if (dm_state == 4) {
        if (acceleratestage) {
            S_StartSound(null, .slop);

            if (doomstat.gamemode == .Commercial) {
                WI_initNoState();
            } else {
                WI_initShowNextLoc();
            }
        }
    } else if (dm_state & 1 != 0) {
        cnt_pause -= 1;
        if (cnt_pause == 0) {
            dm_state += 1;
            cnt_pause = TICRATE;
        }
    }
}


fn WI_drawDeathmatchStats() void {
    WI_slamBackground();

    // draw animated background
    WI_drawAnimatedBack();
    WI_drawLF();

    // draw stat titles (top line)
    V_DrawPatch(
        DM_TOTALSX - @divTrunc(std.mem.littleToNative(c_short, total.width), 2),
        DM_MATRIXY - WI_SPACINGY + 10,
        FB,
        total,
    );

    V_DrawPatch(DM_KILLERSX, DM_KILLERSY, FB, killers);
    V_DrawPatch(DM_VICTIMSX, DM_VICTIMSY, FB, victims);

    // draw P?
    var x: c_int = DM_MATRIXX + DM_SPACINGX;
    var y: c_int = DM_MATRIXY;

    for (0..MAXPLAYERS) |i| {
        if (g_game.playeringame[i] != c.false) {
            const pwhalf = @divTrunc(std.mem.littleToNative(c_short, p[i].width), 2);

            V_DrawPatch(x - pwhalf, DM_MATRIXY - WI_SPACINGY, FB, p[i]);
            V_DrawPatch(DM_MATRIXX - pwhalf, y, FB, p[i]);

            if (i == me) {
                V_DrawPatch(x - pwhalf, DM_MATRIXY - WI_SPACINGY, FB, bstar);
                V_DrawPatch(DM_MATRIXX - pwhalf, y, FB, star);
            }
        }

        x += DM_SPACINGX;
        y += WI_SPACINGY;
    }

    // draw stats
    y = DM_MATRIXY + 10;
    const w = std.mem.littleToNative(c_short, num[0].width);

    for (0..MAXPLAYERS) |i| {
        x = DM_MATRIXX + DM_SPACINGX;

        if (g_game.playeringame[i] != c.false) {
            for (0..MAXPLAYERS) |j| {
                if (g_game.playeringame[j] != c.false) {
                    _ = WI_drawNum(x + w, y, dm_frags[i][j], 2);
                }

                x += DM_SPACINGX;
            }

            _ = WI_drawNum(DM_TOTALSX + w, y, dm_totals[i], 2);
        }

        y += WI_SPACINGY;
    }
}


var cnt_frags: [MAXPLAYERS]c_int = undefined;
var dofrags = false;
var ng_state: c_int = undefined;

fn WI_initNetgameStats() void {
    state = .StatCount;
    acceleratestage = false;
    ng_state = 1;

    cnt_pause = TICRATE;

    var fragsum: c_int = 0;

    for (0..MAXPLAYERS) |i| {
        if (g_game.playeringame[i] == c.false) {
            continue;
        }

        cnt_kills[i] = 0;
        cnt_items[i] = 0;
        cnt_secret[i] = 0;
        cnt_frags[i] = 0;

        fragsum += WI_fragSum(i);
    }

    dofrags = fragsum != 0;

    WI_initAnimatedBack();
}


fn WI_updateNetgameStats() void {
    WI_updateAnimatedBack();

    if (acceleratestage and ng_state != 10) {
        acceleratestage = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] == c.false) {
                continue;
            }

            cnt_kills[i] = @divTrunc(plrs[i].skills * 100, wbs.maxkills);
            cnt_items[i] = @divTrunc(plrs[i].sitems * 100, wbs.maxitems);
            cnt_secret[i] = @divTrunc(plrs[i].ssecret * 100, wbs.maxsecret);

            if (dofrags) {
                cnt_frags[i] = WI_fragSum(i);
            }
        }

        S_StartSound(null, .barexp);
        ng_state = 10;
    }

    if (ng_state == 2) {
        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        var stillticking = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] == c.false) {
                continue;
            }

            cnt_kills[i] += 2;

            if (cnt_kills[i] >= @divTrunc(plrs[i].skills * 100, wbs.maxkills)) {
                cnt_kills[i] = @divTrunc(plrs[i].skills * 100, wbs.maxkills);
            } else {
                stillticking = true;
            }
        }

        if (!stillticking) {
            S_StartSound(null, .barexp);
            ng_state += 1;
        }
    } else if (ng_state == 4) {
        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        var stillticking = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] == c.false) {
                continue;
            }

            cnt_items[i] += 2;
            if (cnt_items[i] >= @divTrunc(plrs[i].sitems * 100, wbs.maxitems)) {
                cnt_items[i] = @divTrunc(plrs[i].sitems * 100, wbs.maxitems);
            } else {
                stillticking = true;
            }
        }

        if (!stillticking) {
            S_StartSound(null, .barexp);
            ng_state += 1;
        }
    } else if (ng_state == 6) {
        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        var stillticking = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] == c.false) {
                continue;
            }

            cnt_secret[i] += 2;
            if (cnt_secret[i] >= @divTrunc(plrs[i].ssecret * 100, wbs.maxsecret)) {
                cnt_secret[i] = @divTrunc(plrs[i].ssecret * 100, wbs.maxsecret);
            } else {
                stillticking = true;
            }
        }

        if (!stillticking) {
            S_StartSound(null, .barexp);
            ng_state += 1;
            if (!dofrags) {
                ng_state += 2;
            }
        }
    } else if (ng_state == 8) {
        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        var stillticking = false;

        for (0..MAXPLAYERS) |i| {
            if (g_game.playeringame[i] == c.false) {
                continue;
            }

            cnt_frags[i] += 1;

            const fsum = WI_fragSum(i);
            if (cnt_frags[i] >= fsum) {
                cnt_frags[i] = fsum;
            } else {
                stillticking = true;
            }
        }

        if (!stillticking) {
            S_StartSound(null, .pldeth);
            ng_state += 1;
        }
    } else if (ng_state == 10) {
        if (acceleratestage) {
            S_StartSound(null, .sgcock);
            if (doomstat.gamemode == .Commercial) {
                WI_initNoState();
            } else {
                WI_initShowNextLoc();
            }
        }
    } else if (ng_state & 1 != 0) {
        cnt_pause -= 1;
        if (cnt_pause == 0) {
            ng_state += 1;
            cnt_pause = TICRATE;
        }
    }
}



fn WI_drawNetgameStats() void {
    WI_slamBackground();

    // draw animated background
    WI_drawAnimatedBack();

    WI_drawLF();

    // draw stat titles (top line)
    V_DrawPatch(
        NG_STATSX() + NG_SPACINGX - std.mem.littleToNative(c_short, kills.width),
        NG_STATSY,
        FB,
        kills,
    );

    V_DrawPatch(
        NG_STATSX() + 2 * NG_SPACINGX - std.mem.littleToNative(c_short, items.width),
        NG_STATSY,
        FB,
        items,
    );

    V_DrawPatch(
        NG_STATSX() + 3 * NG_SPACINGX - std.mem.littleToNative(c_short, secret.width),
        NG_STATSY,
        FB,
        secret,
    );

    if (dofrags) {
        V_DrawPatch(
            NG_STATSX() + 4 * NG_SPACINGX - std.mem.littleToNative(c_short, frags.width),
            NG_STATSY,
            FB,
            frags,
        );
    }

    // draw stats
    var y = NG_STATSY + std.mem.littleToNative(c_short, kills.height);
    const pwidth = std.mem.littleToNative(c_short, percent.width);

    for (0..MAXPLAYERS) |i| {
        if (g_game.playeringame[i] == c.false) {
            continue;
        }

        var x = NG_STATSX();
        V_DrawPatch(x - std.mem.littleToNative(c_short, p[i].width), y, FB, p[i]);

        if (i == me) {
            V_DrawPatch(x - std.mem.littleToNative(c_short, p[i].width), y, FB, star);
        }

        x += NG_SPACINGX;
        WI_drawPercent(x - pwidth, y + 10, cnt_kills[i]);
        x += NG_SPACINGX;
        WI_drawPercent(x - pwidth, y + 10, cnt_items[i]);
        x += NG_SPACINGX;
        WI_drawPercent(x - pwidth, y + 10, cnt_secret[i]);

        if (dofrags) {
            x += NG_SPACINGX;
            _ = WI_drawNum(x, y + 10, cnt_frags[i], -1);
        }

        y += WI_SPACINGY;
    }
}

var sp_state: c_int = undefined;

fn WI_initStats() void {
    state = .StatCount;
    acceleratestage = false;
    sp_state = 1;
    cnt_kills[0] = -1;
    cnt_items[0] = -1;
    cnt_secret[0] = -1;
    cnt_time = -1;
    cnt_par = -1;
    cnt_pause = TICRATE;

    WI_initAnimatedBack();
}

fn WI_updateStats() void {
    WI_updateAnimatedBack();

    if (acceleratestage and sp_state != 10) {
        acceleratestage = false;
        cnt_kills[0] = @divTrunc(plrs[me].skills * 100, wbs.maxkills);
        cnt_items[0] = @divTrunc(plrs[me].sitems * 100, wbs.maxitems);
        cnt_secret[0] = @divTrunc(plrs[me].ssecret * 100, wbs.maxsecret);
        cnt_time = @divTrunc(plrs[me].stime, TICRATE);
        cnt_par = @divTrunc(wbs.partime, TICRATE);
        S_StartSound(null, .barexp);
        sp_state = 10;
    }

    if (sp_state == 2) {
        cnt_kills[0] += 2;

        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        if (cnt_kills[0] >= @divTrunc(plrs[me].skills * 100, wbs.maxkills)) {
            cnt_kills[0] = @divTrunc(plrs[me].skills * 100, wbs.maxkills);
            S_StartSound(null, .barexp);
            sp_state += 1;
        }
    } else if (sp_state == 4) {
        cnt_items[0] += 2;

        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        if (cnt_items[0] >= @divTrunc(plrs[me].sitems * 100, wbs.maxitems)) {
            cnt_items[0] = @divTrunc(plrs[me].sitems * 100, wbs.maxitems);
            S_StartSound(null, .barexp);
            sp_state += 1;
        }
    } else if (sp_state == 6) {
        cnt_secret[0] += 2;

        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        if (cnt_secret[0] >= @divTrunc(plrs[me].ssecret * 100, wbs.maxsecret)) {
            cnt_secret[0] = @divTrunc(plrs[me].ssecret * 100, wbs.maxsecret);
            S_StartSound(null, .barexp);
            sp_state += 1;
        }
    } else if (sp_state == 8) {
        if (bcnt & 3 == 0) {
            S_StartSound(null, .pistol);
        }

        cnt_time += 3;

        if (cnt_time >= @divTrunc(plrs[me].stime, TICRATE)) {
            cnt_time = @divTrunc(plrs[me].stime, TICRATE);
        }

        cnt_par += 3;

        if (cnt_par >= @divTrunc(wbs.partime, TICRATE)) {
            cnt_par = @divTrunc(wbs.partime, TICRATE);

            if (cnt_time >= @divTrunc(plrs[me].stime, TICRATE)) {
                S_StartSound(null, .barexp);
                sp_state += 1;
            }
        }
    } else if (sp_state == 10) {
        if (acceleratestage) {
            S_StartSound(null, .sgcock);

            if (doomstat.gamemode == .Commercial) {
                WI_initNoState();
            } else {
                WI_initShowNextLoc();
            }
        }
    } else if (sp_state & 1 != 0) {
        cnt_pause -= 1;
        if (cnt_pause == 0) {
            sp_state += 1;
            cnt_pause = TICRATE;
        }
    }
}

fn WI_drawStats() void {
    // line height
    const lh = @divTrunc(3 * std.mem.littleToNative(c_short, num[0].height), 2);

    WI_slamBackground();

    // draw animated background
    WI_drawAnimatedBack();

    WI_drawLF();

    V_DrawPatch(SP_STATSX, SP_STATSY, FB, kills);
    WI_drawPercent(SCREENWIDTH - SP_STATSX, SP_STATSY, cnt_kills[0]);

    V_DrawPatch(SP_STATSX, SP_STATSY + lh, FB, items);
    WI_drawPercent(SCREENWIDTH - SP_STATSX, SP_STATSY + lh, cnt_items[0]);

    V_DrawPatch(SP_STATSX, SP_STATSY + 2 * lh, FB, sp_secret);
    WI_drawPercent(SCREENWIDTH - SP_STATSX, SP_STATSY + 2 * lh, cnt_secret[0]);

    V_DrawPatch(SP_TIMEX, SP_TIMEY, FB, time);
    WI_drawTime(SCREENWIDTH/2 - SP_TIMEX, SP_TIMEY, cnt_time);

    if (wbs.epsd < 3) {
        V_DrawPatch(SCREENWIDTH/2 + SP_TIMEX, SP_TIMEY, FB, par);
        WI_drawTime(SCREENWIDTH - SP_TIMEX, SP_TIMEY, cnt_par);
    }
}


fn WI_checkForAccelerate() void {
    // check for button presses to skip delays
    for (&g_game.players, g_game.playeringame) |*player, ingame| {
        if (ingame != c.false) {
            if (player.cmd.buttons & c.BT_ATTACK != 0) {
                if (player.attackdown == c.false) {
                    acceleratestage = true;
                }
                player.attackdown = c.true;
            } else {
                player.attackdown = c.false;
            }

            if (player.cmd.buttons & c.BT_USE != 0) {
                if (player.usedown == c.false) {
                    acceleratestage = true;
                }
                player.usedown = c.true;
            } else {
                player.usedown = c.false;
            }
        }
    }
}



// Updates stuff each tick
pub fn WI_Ticker() void {
    // counter for general background animation
    bcnt += 1;

    if (bcnt == 1) {
        // intermission music
        if (doomstat.gamemode == .Commercial) {
            S_ChangeMusic(.dm2int, true);
        } else {
            S_ChangeMusic(.inter, true);
        }
    }

    WI_checkForAccelerate();

    switch (state) {
        .StatCount => {
            if (g_game.deathmatch != c.false) {
                WI_updateDeathmatchStats();
            } else if (g_game.netgame != c.false) {
                WI_updateNetgameStats();
            } else {
                WI_updateStats();
            }
        },

        .ShowNextLoc => {
            WI_updateShowNextLoc();
        },

        .NoState => {
            WI_updateNoState();
        }
    }
}

fn WI_loadData() void {
    var namebuf: [9]u8 = undefined;
    var name =
        if (doomstat.gamemode == .Commercial
            or doomstat.gamemode == .Retail and wbs.epsd == 3)
            "INTERPIC"
        else
            std.fmt.bufPrintZ(&namebuf, "WIMAP{d}", .{wbs.epsd}) catch unreachable;

    bg = W_CacheLumpNameAsPatch(name, .Cache);
    V_DrawPatch(0, 0, 1, bg);

    if (doomstat.gamemode == .Commercial) {
        lnames = z_zone.alloc(*patch_t, NUMCMAPS, .Static, null);
        for (lnames, 0..) |*lname, i| {
            name = std.fmt.bufPrintZ(&namebuf, "CWILV{d:0>2}", .{i}) catch unreachable;
            lname.* = W_CacheLumpNameAsPatch(name, .Static);
        }
    } else {
        lnames = z_zone.alloc(*patch_t, NUMMAPS, .Static, null);
        for (lnames, 0..) |*lname, i| {
            name = std.fmt.bufPrintZ(&namebuf, "WILV{d}{d}", .{wbs.epsd, i}) catch unreachable;
            lname.* = W_CacheLumpNameAsPatch(name, .Static);
        }

        // you are here
        yah[0] = W_CacheLumpNameAsPatch("WIURH0", .Static);

        // you are here (alt.)
        yah[1] = W_CacheLumpNameAsPatch("WIURH1", .Static);

        // splat
        splat = W_CacheLumpNameAsPatch("WISPLAT", .Static);

        if (wbs.epsd < 3) {
            for (anims[@intCast(wbs.epsd)], 0..) |*a, j| {
                for (0..@intCast(a.nanims)) |i| {
                    // MONDO HACK!
                    if (wbs.epsd != 1 or j != 8) {
                        // animations
                        name = std.fmt.bufPrintZ(&namebuf, "WIA{d}{d:0>2}{d:0>2}", .{wbs.epsd, j, i}) catch unreachable;
                        a.p[i] = W_CacheLumpNameAsPatch(name, .Static);
                    } else {
                        // HACK ALERT!
                        a.p[i] = anims[1][4].p[i];
                    }
                }
            }
        }
    }

    // More hacks on minus sign.
    wiminus = W_CacheLumpNameAsPatch("WIMINUS", .Static);

    for (0..10) |i| {
        // numbers 0-9
        name = std.fmt.bufPrintZ(&namebuf, "WINUM{d}", .{i}) catch unreachable;
        num[i] = W_CacheLumpNameAsPatch(name, .Static);
    }

    // percent sign
    percent = W_CacheLumpNameAsPatch("WIPCNT", .Static);

    // "finished"
    finished = W_CacheLumpNameAsPatch("WIF", .Static);

    // "entering"
    entering = W_CacheLumpNameAsPatch("WIENTER", .Static);

    // "kills"
    kills = W_CacheLumpNameAsPatch("WIOSTK", .Static);

    // "scrt"
    secret = W_CacheLumpNameAsPatch("WIOSTS", .Static);

    // "secret"
    sp_secret = W_CacheLumpNameAsPatch("WISCRT2", .Static);

    // Yuck.
    if (doomstat.language == .French) {
        // "items"
        if (g_game.netgame != c.false and g_game.deathmatch == c.false) {
            items = W_CacheLumpNameAsPatch("WIOBJ", .Static);
        } else {
            items = W_CacheLumpNameAsPatch("WIOSTI", .Static);
        }
    } else {
        items = W_CacheLumpNameAsPatch("WIOSTI", .Static);
    }

    // "frgs"
    frags = W_CacheLumpNameAsPatch("WIFRGS", .Static);

    // ":"
    colon = W_CacheLumpNameAsPatch("WICOLON", .Static);

    // "time"
    time = W_CacheLumpNameAsPatch("WITIME", .Static);

    // "sucks"
    sucks = W_CacheLumpNameAsPatch("WISUCKS", .Static);

    // "par"
    par = W_CacheLumpNameAsPatch("WIPAR", .Static);

    // "killers" (vertical)
    killers = W_CacheLumpNameAsPatch("WIKILRS", .Static);

    // "victims" (horiz)
    victims = W_CacheLumpNameAsPatch("WIVCTMS", .Static);

    // "total"
    total = W_CacheLumpNameAsPatch("WIMSTT", .Static);

    // your face
    star = W_CacheLumpNameAsPatch("STFST01", .Static);

    // dead face
    bstar = W_CacheLumpNameAsPatch("STFDEAD0", .Static);

    for (0..MAXPLAYERS) |i| {
        // "1,2,3,4"
        name = std.fmt.bufPrintZ(&namebuf, "STPB{d}", .{i}) catch unreachable;
        p[i] = W_CacheLumpNameAsPatch(name, .Static);

        // "1,2,3,4"
        name = std.fmt.bufPrintZ(&namebuf, "WIBP{d}", .{i + 1}) catch unreachable;
        bp[i] = W_CacheLumpNameAsPatch(name, .Static);
    }
}


fn WI_unloadData() void {
    Z_ChangeTag(wiminus, .Cache);

    for (0..10) |i| {
        Z_ChangeTag(num[i], .Cache);
    }

    for (lnames) |lname| {
        Z_ChangeTag(lname, .Cache);
    }

    if (doomstat.gamemode != .Commercial) {
        Z_ChangeTag(yah[0], .Cache);
        Z_ChangeTag(yah[1], .Cache);

        Z_ChangeTag(splat, .Cache);

        if (wbs.epsd < 3) {
            for (anims[@intCast(wbs.epsd)], 0..) |a, j| {
                if (wbs.epsd != 1 or j != 8) {
                    for (0..@intCast(a.nanims)) |i| {
                        Z_ChangeTag(a.p[i], .Cache);
                    }
                }
            }
        }
    }

    z_zone.free(lnames);

    Z_ChangeTag(percent, .Cache);
    Z_ChangeTag(colon, .Cache);
    Z_ChangeTag(finished, .Cache);
    Z_ChangeTag(entering, .Cache);
    Z_ChangeTag(kills, .Cache);
    Z_ChangeTag(secret, .Cache);
    Z_ChangeTag(sp_secret, .Cache);
    Z_ChangeTag(items, .Cache);
    Z_ChangeTag(frags, .Cache);
    Z_ChangeTag(time, .Cache);
    Z_ChangeTag(sucks, .Cache);
    Z_ChangeTag(par, .Cache);

    Z_ChangeTag(victims, .Cache);
    Z_ChangeTag(killers, .Cache);
    Z_ChangeTag(total, .Cache);
    //  Z_ChangeTag(star, .Cache);
    //  Z_ChangeTag(bstar, .Cache);

    for (p) |pp| {
        Z_ChangeTag(pp, .Cache);
    }

    for (bp) |bpp| {
        Z_ChangeTag(bpp, .Cache);
    }
}

pub fn WI_Drawer() void {
    switch (state) {
        .StatCount => {
            if (g_game.deathmatch != c.false) {
                WI_drawDeathmatchStats();
            } else if (g_game.netgame != c.false) {
                WI_drawNetgameStats();
            } else {
                WI_drawStats();
            }
        },

        .ShowNextLoc => {
            WI_drawShowNextLoc();
        },

        .NoState => {
            WI_drawNoState();
        }
    }
}


fn WI_initVariables(wbstartstruct: *g_game.c.wbstartstruct_t) void {
    wbs = wbstartstruct;

    acceleratestage = false;
    cnt = 0;
    bcnt = 0;
    me = @intCast(wbs.pnum);
    plrs = &wbs.plyr;

    if (wbs.maxkills == 0) {
        wbs.maxkills = 1;
    }

    if (wbs.maxitems == 0) {
        wbs.maxitems = 1;
    }

    if (wbs.maxsecret == 0) {
        wbs.maxsecret = 1;
    }

    if (doomstat.gamemode != .Retail) {
        if (wbs.epsd > 2) {
            wbs.epsd -= 3;
        }
    }
}

pub fn WI_Start(wbstartstruct: *g_game.c.wbstartstruct_t) void {
    WI_initVariables(wbstartstruct);
    WI_loadData();

    if (g_game.deathmatch != c.false) {
        WI_initDeathmatchStats();
    } else if (g_game.netgame != c.false) {
        WI_initNetgameStats();
    } else {
        WI_initStats();
    }
}
