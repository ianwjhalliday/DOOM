const c = @cImport({
    @cInclude("dstrings.h");
    @cInclude("r_state.h");
    @cInclude("v_video.h");
    @cInclude("info.h");
});

const std = @import("std");

const doomdef = @import("doomdef.zig");
const doomstat = @import("doomstat.zig");
const d_main = @import("d_main.zig");
const Event = d_main.Event;
const g_game = @import("g_game.zig");
const hu_stuff = @import("hu_stuff.zig");
const sounds = @import("sounds.zig");
const Sfx = sounds.Sfx;
const s_sound = @import("s_sound.zig");
const S_ChangeMusicEnum = s_sound.S_ChangeMusicEnum;
const S_StartMusic = s_sound.S_StartMusic;
const S_StartSound = s_sound.S_StartSound_Zig;
const w_wad = @import("w_wad.zig");
const W_CacheLumpName = w_wad.W_CacheLumpName;
const W_CacheLumpNum = w_wad.W_CacheLumpNum;
const Z_Tag = @import("z_zone.zig").Z_Tag;

extern var automapactive: c.boolean;    // in AM_map.c
extern var screens: [5][*]u8;

fn W_CacheLumpNameAsPatch(name: [*]const u8, tag: Z_Tag) *c.patch_t {
    return @ptrCast(@alignCast(W_CacheLumpName(name, tag)));
}

fn W_CacheLumpNumAsPatch(lump: c_int, tag: Z_Tag) *c.patch_t {
    return @ptrCast(@alignCast(W_CacheLumpNum(lump, tag)));
}

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
    g_game.viewactive = c.false;
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
    const src: [*]u8 = @ptrCast(W_CacheLumpName(finaleflat.ptr, .Cache));
    var dest = screens[0];

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

    c.V_MarkRect(0, 0, doomdef.SCREENWIDTH, doomdef.SCREENHEIGHT);

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

        const w = std.mem.littleToNative(c_short, hu_stuff.hu_font[chidx].width);
        if (cx + w > doomdef.SCREENWIDTH) {
            break;
        }

        c.V_DrawPatch(cx, cy, 0, @ptrCast(hu_stuff.hu_font[chidx]));
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
    type: c.mobjtype_t,
};

const castorder = [_]CastInfo{
    .{.name = c.CC_ZOMBIE, .type = c.MT_POSSESSED},
    .{.name = c.CC_SHOTGUN, .type = c.MT_SHOTGUY},
    .{.name = c.CC_HEAVY, .type = c.MT_CHAINGUY},
    .{.name = c.CC_IMP, .type = c.MT_TROOP},
    .{.name = c.CC_DEMON, .type = c.MT_SERGEANT},
    .{.name = c.CC_LOST, .type = c.MT_SKULL},
    .{.name = c.CC_CACO, .type = c.MT_HEAD},
    .{.name = c.CC_HELL, .type = c.MT_KNIGHT},
    .{.name = c.CC_BARON, .type = c.MT_BRUISER},
    .{.name = c.CC_ARACH, .type = c.MT_BABY},
    .{.name = c.CC_PAIN, .type = c.MT_PAIN},
    .{.name = c.CC_REVEN, .type = c.MT_UNDEAD},
    .{.name = c.CC_MANCU, .type = c.MT_FATSO},
    .{.name = c.CC_ARCH, .type = c.MT_VILE},
    .{.name = c.CC_SPIDER, .type = c.MT_SPIDER},
    .{.name = c.CC_CYBER, .type = c.MT_CYBORG},
    .{.name = c.CC_HERO, .type = c.MT_PLAYER},
};

var castnum: usize = 0;
var casttics: c_long = 0;
var caststate: *c.state_t = undefined;
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
    caststate = &c.states[@intCast(c.mobjinfo[castorder[castnum].type].seestate)];
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

    var moinfo = c.mobjinfo[castorder[castnum].type];

    if (caststate.tics == -1 or caststate.nextstate == c.S_NULL) {
        // switch from deathstate to next monster
        castnum += 1;
        castdeath = false;

        if (castnum == castorder.len) {
            castnum = 0;
        }

        moinfo = c.mobjinfo[castorder[castnum].type];

        if (moinfo.seesound != 0) {
            S_StartSound(null, @enumFromInt(moinfo.seesound));
        }

        caststate = &c.states[@intCast(moinfo.seestate)];
        castframes = 0;
    } else {
        // just advance to next state in animation
        if (caststate == &c.states[c.S_PLAY_ATK1]) {
            // TODO: Cannot goto in Zig. Is there a better way to handle this code
            // than duplicating the code that follows the label?
            // goto stopattack;    // Oh, gross hack!
            castattacking = false;
            castframes = 0;
            caststate = &c.states[@intCast(moinfo.seestate)];

            casttics = caststate.tics;
            if (casttics == -1) {
                casttics = 15;
            }
            return;
        }

        const st = caststate.nextstate;
        caststate = &c.states[@intCast(st)];
        castframes += 1;

        // sound hacks...
        const sfx = switch (st) {
            c.S_PLAY_ATK1 => Sfx.dshtgn,
            c.S_POSS_ATK2 => Sfx.pistol,
            c.S_SPOS_ATK2 => Sfx.shotgn,
            c.S_VILE_ATK2 => Sfx.vilatk,
            c.S_SKEL_FIST2 => Sfx.skeswg,
            c.S_SKEL_FIST4 => Sfx.skepch,
            c.S_SKEL_MISS2 => Sfx.skeatk,
            c.S_FATT_ATK8,
            c.S_FATT_ATK5,
            c.S_FATT_ATK2 => Sfx.firsht,
            c.S_CPOS_ATK2,
            c.S_CPOS_ATK3,
            c.S_CPOS_ATK4 => Sfx.shotgn,
            c.S_TROO_ATK3 => Sfx.claw,
            c.S_SARG_ATK2 => Sfx.sgtatk,
            c.S_BOSS_ATK2,
            c.S_BOS2_ATK2,
            c.S_HEAD_ATK2 => Sfx.firsht,
            c.S_SKULL_ATK2 => Sfx.sklatk,
            c.S_SPID_ATK2,
            c.S_SPID_ATK3 => Sfx.shotgn,
            c.S_BSPI_ATK2 => Sfx.plasma,
            c.S_CYBER_ATK2,
            c.S_CYBER_ATK4,
            c.S_CYBER_ATK6 => Sfx.rlaunc,
            c.S_PAIN_ATK3 => Sfx.sklatk,
            else => Sfx.None,
        };

        if (sfx != Sfx.None) {
            S_StartSound(null, sfx);
        }
    }

    if (castframes == 12) {
        // go into attack frame
        castattacking = true;

        if (castonmelee) {
            caststate = &c.states[@intCast(moinfo.meleestate)];
        } else {
            caststate = &c.states[@intCast(moinfo.missilestate)];
        }

        castonmelee = !castonmelee;

        if (caststate == &c.states[c.S_NULL]) {
            if (castonmelee) {
                caststate = &c.states[@intCast(moinfo.meleestate)];
            } else {
                caststate = &c.states[@intCast(moinfo.missilestate)];
            }
        }
    }

    if (castattacking) {
        if (castframes == 24 or caststate == &c.states[@intCast(moinfo.seestate)]) {
            // stopattack:  TODO: fix this goto
            castattacking = false;
            castframes = 0;
            caststate = &c.states[@intCast(moinfo.seestate)];
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
    castdeath = true;
    caststate = &c.states[@intCast(c.mobjinfo[castorder[castnum].type].deathstate)];
    casttics = caststate.tics;
    castframes = 0;
    castattacking = false;
    if (c.mobjinfo[castorder[castnum].type].deathsound != 0) {
        S_StartSound(null, @enumFromInt(c.mobjinfo[castorder[castnum].type].deathsound));
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
        const w = std.mem.littleToNative(c_short, hu_stuff.hu_font[chidx].width);
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
        c.V_DrawPatch(@intCast(cx), 180, 0, @ptrCast(hu_stuff.hu_font[chidx]));
        const w = std.mem.littleToNative(c_short, hu_stuff.hu_font[chidx].width);
        cx += @intCast(w);
    }
}


//
// F_CastDrawer
//
extern fn V_DrawPatchFlipped(x: c_int, y: c_int, scrn: c_int, patch: *c.patch_t) void;

fn F_CastDrawer() void {
    c.V_DrawPatch(0, 0, 0, W_CacheLumpNameAsPatch("BOSSBACK", .Cache));

    F_CastPrint(castorder[castnum].name);

    // draw the current frame in the middle of the screen
    const sprdef = &c.sprites[caststate.sprite];
    const sprframe = &sprdef.spriteframes[@intCast(caststate.frame & c.FF_FRAMEMASK)];
    const lump = sprframe.lump[0];
    const flip = if (sprframe.flip[0] != 0) true else false;

    const patch = W_CacheLumpNumAsPatch(lump + c.firstspritelump, .Cache);

    if (flip) {
        V_DrawPatchFlipped(160, 170, 0, patch);
    } else {
        c.V_DrawPatch(160, 170, 0, patch);
    }
}


//
// F_DrawPatchCol
//
fn F_DrawPatchCol(x: c_int, patch: *c.patch_t, col: c_int) void {
    const patchAsBytes = @as([*]u8, @ptrCast(patch));
    const columnofs = @as([*]c_int, @ptrCast(&patch.columnofs[0]));
    const colofs: usize = @intCast(std.mem.littleToNative(c_int, columnofs[@intCast(col)]));

    var column: *c.column_t = @ptrCast(patchAsBytes + colofs);
    const desttop = screens[0] + @as(usize, @intCast(x));

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

    const p1 = W_CacheLumpNameAsPatch("PFUB2", .Level);
    const p2 = W_CacheLumpNameAsPatch("PFUB1", .Level);

    c.V_MarkRect(0, 0, doomdef.SCREENWIDTH, doomdef.SCREENHEIGHT);

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
        c.V_DrawPatch(
            @divTrunc(doomdef.SCREENWIDTH - 13 * 8, 2),
            @divTrunc(doomdef.SCREENHEIGHT - 8 * 8, 2),
            0,
            W_CacheLumpNameAsPatch("END0", .Cache)
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

    var namebuffer: [10]u8 = undefined;
    const name = std.fmt.bufPrintZ(&namebuffer, "END{d}", .{stage}) catch unreachable;
    c.V_DrawPatch(
        @divTrunc(doomdef.SCREENWIDTH - 13 * 8, 2),
        @divTrunc(doomdef.SCREENHEIGHT - 8 * 8, 2),
        0,
        W_CacheLumpNameAsPatch(name.ptr, .Cache),
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
                c.V_DrawPatch(0, 0, 0, W_CacheLumpNameAsPatch("CREDIT", .Cache))
            else
                c.V_DrawPatch(0, 0, 0, W_CacheLumpNameAsPatch("HELP2", .Cache)),
        2 => c.V_DrawPatch(0, 0, 0, W_CacheLumpNameAsPatch("VICTORY2", .Cache)),
        3 => F_BunnyScroll(),
        4 => c.V_DrawPatch(0, 0, 0, W_CacheLumpNameAsPatch("ENDPIC", .Cache)),
        else => unreachable,
    }
}
