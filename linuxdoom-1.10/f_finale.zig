const c = @import("c");

const std = @import("std");

const doomdef = @import("doomdef.zig");
const doomstat = @import("doomstat.zig");
const d_info = @import("d_info.zig");
const MObjType = d_info.MObjType;
const State = d_info.State;
const StateNum = d_info.StateNum;
const d_main = @import("d_main.zig");
const Event = d_main.Event;
const g_game = @import("g_game.zig");
const hu_stuff = @import("hu_stuff.zig");
const m_swap = @import("m_swap.zig");
const LONG = m_swap.LONG;
const SHORT = m_swap.SHORT;
const sounds = @import("sounds.zig");
const Sfx = sounds.Sfx;
const s_sound = @import("s_sound.zig");
const S_ChangeMusicEnum = s_sound.S_ChangeMusicEnum;
const S_StartMusic = s_sound.S_StartMusic;
const S_StartSound = s_sound.S_StartSound_Zig;
const v_video = @import("v_video.zig");
const V_DrawPatch = v_video.c.V_DrawPatch;
const V_DrawPatchFlipped = v_video.V_DrawPatchFlipped;
const w_wad = @import("w_wad.zig");
const W_CacheLumpName = w_wad.W_CacheLumpNameZig;
const W_CacheLumpNameFmt = w_wad.W_CacheLumpNameFmt;
const W_CacheLumpNum = w_wad.W_CacheLumpNumZig;
const Z_Tag = @import("z_zone.zig").Z_Tag;

extern var automapactive: c.boolean;    // in AM_map.c

const patch_t = v_video.c.patch_t;

// Stage of animation:
//  0 = text, 1 = art screen, 2 = character cast
var finalestage: c_int = 0;

var finalecount: c_int = 0;

const TEXTSPEED = 3;
const TEXTWAIT = 250;

var finaletext: []const u8 = undefined;
var finaleflat: []const u8 = undefined;

//
// F_StartFinale
//
pub fn F_StartFinale() void {
    g_game.gameaction = .Nothing;
    g_game.gamestate = .Finale;
    g_game.viewactive = false;
    automapactive = c.false;

    // Okay - IWAD dependend stuff.
    // This has been changed severly, and
    //  some stuff might have changed in the process.
    switch (doomstat.gamemode) {

        // DOOM 1 - E1, E3 or E4, but each nine missions
        .Shareware,
        .Registered,
        .Retail => {
            S_ChangeMusicEnum(.victor, true);

            switch (g_game.gameepisode) {
                1 => {
                    finaleflat = "FLOOR4_8";
                    finaletext = c.E1TEXT;
                },
                2 => {
                    finaleflat = "SFLR6_1";
                    finaletext = c.E2TEXT;
                },
                3 => {
                    finaleflat = "MFLR8_4";
                    finaletext = c.E3TEXT;
                },
                4 => {
                    finaleflat = "MFLR8_3";
                    finaletext = c.E4TEXT;
                },
                else => {}, // Ouch.
            }
        },

        // DOOM II and missions packs with E1, M34
        .Commercial => {
            S_ChangeMusicEnum(.read_m, true);

            switch (g_game.gamemap) {
                6 => {
                    finaleflat = "SLIME16";
                    finaletext = c.C1TEXT;
                },
                11 => {
                    finaleflat = "RROCK14";
                    finaletext = c.C2TEXT;
                },
                20 => {
                    finaleflat = "RROCK07";
                    finaletext = c.C3TEXT;
                },
                30 => {
                    finaleflat = "RROCK17";
                    finaletext = c.C4TEXT;
                },
                15 => {
                    finaleflat = "RROCK13";
                    finaletext = c.C5TEXT;
                },
                31 => {
                    finaleflat = "RROCK19";
                    finaletext = c.C6TEXT;
                },
                else => {} // Ouch.
            }
        },

        .Indetermined => {
            S_ChangeMusicEnum(.read_m, true);
            finaleflat = "F_SKY1"; // Not used anywhere else.
            finaletext = c.C1TEXT;  // FIXME - other text, music?
        }
    }

    finalestage = 0;
    finalecount = 0;
}


pub fn F_Responder(event: *Event) bool {
    if (finalestage == 2) {
        return F_CastResponder(event);
    }

    return false;
}

//
// F_Ticker
//
pub fn F_Ticker() void {
    // check for skipping
    if (doomstat.gamemode == .Commercial and finalecount > 50) {
        // go on to the next level
        for (0..doomdef.MAXPLAYERS) |i| {
            if (g_game.players[i].cmd.buttons != 0) {
                if (g_game.gamemap == 30) {
                    F_StartCast();
                } else {
                    g_game.gameaction = .WorldDone;
                }
                break;
            }
        }
    }

    // advance animation
    finalecount += 1;

    if (finalestage == 2) {
        F_CastTicker();
        return;
    }

    if (doomstat.gamemode == .Commercial) {
        return;
    }

    if (finalestage == 0 and finalecount > finaletext.len * TEXTSPEED + TEXTWAIT) {
        finalecount = 0;
        finalestage = 1;
        d_main.wipegamestate = .ForceWipe;
        if (g_game.gameepisode == 3) {
            S_StartMusic(.bunny);
        }
    }
}

//
// F_TextWrite
//
fn F_TextWrite() void {
    // erase the entire screen to a tiled background
    const src = W_CacheLumpName([*]const u8, finaleflat, .Cache);
    var dest = v_video.screens[0];

    for (0..doomdef.SCREENHEIGHT) |y| {
        for (0..@divTrunc(doomdef.SCREENWIDTH, 64)) |x| {
            _ = x;
            @memcpy(dest[0..64], src + ((y & 63) << 6));
            dest += 64;
        }

        if (doomdef.SCREENWIDTH & 63 != 0) {
            const w = doomdef.SCREENWIDTH & 63;
            @memcpy(dest[0..w], src + ((y & 63) << 6));
            dest += w;
        }
    }

    // draw some of the text onto the screen
    var cx: c_int = 10;
    var cy: c_int = 10;

    const count = @min(finaletext.len, @divTrunc(@as(usize, @intCast(@max(0, finalecount - 10))), TEXTSPEED));
    for (finaletext[0..count]) |ch| {
        if (ch == '\n') {
            cx = 10;
            cy += 11;
            continue;
        }

        const chup = std.ascii.toUpper(ch);
        if (chup < hu_stuff.HU_FONTSTART or chup > hu_stuff.HU_FONTEND) {
            cx += 4;
            continue;
        }
        const chidx = chup - hu_stuff.HU_FONTSTART;

        const w = SHORT(hu_stuff.hu_font[chidx].width);
        if (cx + w > doomdef.SCREENWIDTH) {
            break;
        }

        V_DrawPatch(cx, cy, 0, hu_stuff.hu_font[chidx]);
        cx += w;
    }
}

//
// Final DOOM 2 animation
// Casting by id Software.
//   in order of appearance
//
const CastInfo = struct {
    name: []const u8,
    type: MObjType,
};

const castorder = [_]CastInfo{
    .{.name = c.CC_ZOMBIE, .type = .POSSESSED},
    .{.name = c.CC_SHOTGUN, .type = .SHOTGUY},
    .{.name = c.CC_HEAVY, .type = .CHAINGUY},
    .{.name = c.CC_IMP, .type = .TROOP},
    .{.name = c.CC_DEMON, .type = .SERGEANT},
    .{.name = c.CC_LOST, .type = .SKULL},
    .{.name = c.CC_CACO, .type = .HEAD},
    .{.name = c.CC_HELL, .type = .KNIGHT},
    .{.name = c.CC_BARON, .type = .BRUISER},
    .{.name = c.CC_ARACH, .type = .BABY},
    .{.name = c.CC_PAIN, .type = .PAIN},
    .{.name = c.CC_REVEN, .type = .UNDEAD},
    .{.name = c.CC_MANCU, .type = .FATSO},
    .{.name = c.CC_ARCH, .type = .VILE},
    .{.name = c.CC_SPIDER, .type = .SPIDER},
    .{.name = c.CC_CYBER, .type = .CYBORG},
    .{.name = c.CC_HERO, .type = .PLAYER},
};

var castnum: usize = 0;
var casttics: c_long = 0;
var caststate: *State = undefined;
var castdeath = false;
var castframes: c_int = 0;
var castonmelee = false;
var castattacking = false;

//
// F_StartCast
//
fn F_StartCast() void {
    d_main.wipegamestate = .ForceWipe;
    castnum = 0;
    caststate = castorder[castnum].type.info().seestate.state();
    casttics = caststate.tics;
    castdeath = false;
    finalestage = 2;	
    castframes = 0;
    castonmelee = false;
    castattacking = false;
    S_ChangeMusicEnum(.evil, true);
}


//
// F_CastTicker
//
fn F_CastTicker() void {
    casttics -= 1;
    if (casttics > 0) {
        return;     // not time to change state yet
    }

    var moinfo = castorder[castnum].type.info();

    if (caststate.tics == -1 or caststate.nextstate == .NULL) {
        // switch from deathstate to next monster
        castnum += 1;
        castdeath = false;

        if (castnum == castorder.len) {
            castnum = 0;
        }

        moinfo = castorder[castnum].type.info();

        if (moinfo.seesound != .None) {
            S_StartSound(null, moinfo.seesound);
        }

        caststate = moinfo.seestate.state();
        castframes = 0;
    } else {
        // just advance to next state in animation
        if (caststate == StateNum.PLAY_ATK1.state()) {
            // TODO: Cannot goto in Zig. Is there a better way to handle this code
            // than duplicating the code that follows the label?
            // goto stopattack;    // Oh, gross hack!
            castattacking = false;
            castframes = 0;
            caststate = moinfo.seestate.state();

            casttics = caststate.tics;
            if (casttics == -1) {
                casttics = 15;
            }
            return;
        }

        const st = caststate.nextstate;
        caststate = st.state();
        castframes += 1;

        // sound hacks...
        const sfx: Sfx = switch (st) {
            .PLAY_ATK1 => .dshtgn,
            .POSS_ATK2 => .pistol,
            .SPOS_ATK2 => .shotgn,
            .VILE_ATK2 => .vilatk,
            .SKEL_FIST2 => .skeswg,
            .SKEL_FIST4 => .skepch,
            .SKEL_MISS2 => .skeatk,
            .FATT_ATK8,
            .FATT_ATK5,
            .FATT_ATK2 => .firsht,
            .CPOS_ATK2,
            .CPOS_ATK3,
            .CPOS_ATK4 => .shotgn,
            .TROO_ATK3 => .claw,
            .SARG_ATK2 => .sgtatk,
            .BOSS_ATK2,
            .BOS2_ATK2,
            .HEAD_ATK2 => .firsht,
            .SKULL_ATK2 => .sklatk,
            .SPID_ATK2,
            .SPID_ATK3 => .shotgn,
            .BSPI_ATK2 => .plasma,
            .CYBER_ATK2,
            .CYBER_ATK4,
            .CYBER_ATK6 => .rlaunc,
            .PAIN_ATK3 => .sklatk,
            else => .None,
        };

        if (sfx != .None) {
            S_StartSound(null, sfx);
        }
    }

    if (castframes == 12) {
        // go into attack frame
        castattacking = true;

        caststate = if (castonmelee)
            moinfo.meleestate.state()
        else
            moinfo.missilestate.state();

        castonmelee = !castonmelee;

        if (caststate == StateNum.NULL.state()) {
            caststate = if (castonmelee)
                moinfo.meleestate.state()
            else
                moinfo.missilestate.state();
        }
    }

    if (castattacking) {
        if (castframes == 24 or caststate == moinfo.seestate.state()) {
            // stopattack:  TODO: fix this goto
            castattacking = false;
            castframes = 0;
            caststate = moinfo.seestate.state();
        }
    }

    casttics = caststate.tics;
    if (casttics == -1) {
        casttics = 15;
    }
}


//
// F_CastResponder
//
fn F_CastResponder(ev: *Event) bool {
    if (ev.type != .KeyDown) {
        return false;
    }

    if (castdeath) {
        return true;                    // already in dying frames
    }

    // go into death frame
    const info = castorder[castnum].type.info();
    castdeath = true;
    caststate = info.deathstate.state();
    casttics = caststate.tics;
    castframes = 0;
    castattacking = false;
    if (info.deathsound != .None) {
        S_StartSound(null, info.deathsound);
    }

    return true;
}


fn F_CastPrint(text: []const u8) void {
    // find width
    var width: usize = 0;

    for (text) |ch| {
        const chup = std.ascii.toUpper(ch);
        if (chup < hu_stuff.HU_FONTSTART or chup > hu_stuff.HU_FONTEND) {
            width += 4;
            continue;
        }

        const chidx: usize = @intCast(chup - hu_stuff.HU_FONTSTART);
        const w = SHORT(hu_stuff.hu_font[chidx].width);
        width += @intCast(w);
    }


    // draw it
    var cx: usize = 160 - @divTrunc(width, 2);

    for (text) |ch| {
        const chup = std.ascii.toUpper(ch);
        if (chup < hu_stuff.HU_FONTSTART or chup > hu_stuff.HU_FONTEND) {
            cx += 4;
            continue;
        }

        const chidx: usize = @intCast(chup - hu_stuff.HU_FONTSTART);
        V_DrawPatch(@intCast(cx), 180, 0, hu_stuff.hu_font[chidx]);
        const w = SHORT(hu_stuff.hu_font[chidx].width);
        cx += @intCast(w);
    }
}


//
// F_CastDrawer
//
fn F_CastDrawer() void {
    V_DrawPatch(0, 0, 0, W_CacheLumpName(*patch_t, "BOSSBACK", .Cache));

    F_CastPrint(castorder[castnum].name);

    // draw the current frame in the middle of the screen
    const sprdef = &c.sprites[@intCast(@backingInt(caststate.sprite))];
    const sprframe = &sprdef.spriteframes[@intCast(caststate.frame & c.FF_FRAMEMASK)];
    const lump = sprframe.lump[0];
    const flip = if (sprframe.flip[0] != 0) true else false;

    const patch = W_CacheLumpNum(*patch_t, lump + c.firstspritelump, .Cache);

    if (flip) {
        V_DrawPatchFlipped(160, 170, 0, patch);
    } else {
        V_DrawPatch(160, 170, 0, patch);
    }
}


//
// F_DrawPatchCol
//
fn F_DrawPatchCol(x: c_int, patch: *v_video.c.patch_t, col: c_int) void {
    const patchAsBytes = @as([*]u8, @ptrCast(patch));
    const columnofs = @as([*]c_int, @ptrCast(&patch.columnofs[0]));
    const colofs: usize = @intCast(LONG(columnofs[@intCast(col)]));

    var column: *c.column_t = @ptrCast(patchAsBytes + colofs);
    const desttop = v_video.screens[0] + @as(usize, @intCast(x));

    // step through the posts in a column
    while (column.topdelta != 0xff) {
        const columnAsBytes = @as([*]u8, @ptrCast(column));

        var source: [*]u8 = columnAsBytes + 3;
        var dest = desttop + @as(usize, column.topdelta) * doomdef.SCREENWIDTH;
        var count = column.length;

        while (count != 0) : (count -= 1) {
            dest[0] = source[0];
            source += 1;
            dest += doomdef.SCREENWIDTH;
        }

        column = @ptrCast(columnAsBytes + column.length + 4);
    }
}


//
// F_BunnyScroll
//
fn F_BunnyScroll() void {
    const S = struct {
        var laststage: c_int = 0;
    };

    const p1 = W_CacheLumpName(*patch_t, "PFUB2", .Level);
    const p2 = W_CacheLumpName(*patch_t, "PFUB1", .Level);

    var scrolled = 320 - @divTrunc(finalecount - 230, 2);
    if (scrolled > 320) {
        scrolled = 320;
    }
    if (scrolled < 0) {
        scrolled = 0;
    }

    for (0..doomdef.SCREENWIDTH) |i| {
        const x: c_int = @intCast(i);
        if (x + scrolled < 320) {
            F_DrawPatchCol(x, p1, x + scrolled);
        } else {
            F_DrawPatchCol(x, p2, x + scrolled - 320);
        }
    }

    if (finalecount < 1130) {
        return;
    }

    if (finalecount < 1180) {
        V_DrawPatch(
            @divTrunc(doomdef.SCREENWIDTH - 13 * 8, 2),
            @divTrunc(doomdef.SCREENHEIGHT - 8 * 8, 2),
            0,
            W_CacheLumpName(*patch_t, "END0", .Cache)
        );
        S.laststage = 0;
        return;
    }

    var stage = @divTrunc(finalecount - 1180, 5);
    if (stage > 6) {
        stage = 6;
    }
    if (stage > S.laststage) {
        S_StartSound(null, .pistol);
        S.laststage = stage;
    }

    V_DrawPatch(
        @divTrunc(doomdef.SCREENWIDTH - 13 * 8, 2),
        @divTrunc(doomdef.SCREENHEIGHT - 8 * 8, 2),
        0,
        W_CacheLumpNameFmt(*patch_t, "END{d}", .{stage}, .Cache),
    );
}


//
// F_Drawer
//
pub fn F_Drawer() void {
    if (finalestage == 2) {
        F_CastDrawer();
        return;
    }

    if (finalestage == 0) {
        F_TextWrite();
        return;
    }

    switch (g_game.gameepisode) {
        1 =>
            if (doomstat.gamemode == .Retail)
                V_DrawPatch(0, 0, 0, W_CacheLumpName(*patch_t, "CREDIT", .Cache))
            else
                V_DrawPatch(0, 0, 0, W_CacheLumpName(*patch_t, "HELP2", .Cache)),
        2 => V_DrawPatch(0, 0, 0, W_CacheLumpName(*patch_t, "VICTORY2", .Cache)),
        3 => F_BunnyScroll(),
        4 => V_DrawPatch(0, 0, 0, W_CacheLumpName(*patch_t, "ENDPIC", .Cache)),
        else => unreachable,
    }
}
