const c = @import("c");
const std = @import("std");

const doomstat = @import("doomstat.zig");
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const g_game = @import("g_game.zig");
const p_ceilng = @import("p_ceilng.zig");
const p_doors = @import("p_doors.zig");
const p_floor = @import("p_floor.zig");
const p_lights = @import("p_lights.zig");
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const p_plats = @import("p_plats.zig");
const p_setup = @import("p_setup.zig");
const s_sound = @import("s_sound.zig");
const sounds = @import("sounds.zig");
const Sfx = sounds.Sfx;

const BUTTONTIME = 35; // 1 second, in ticks

const ButtonWhere = enum(c_uint) {
    top,
    middle,
    bottom,
};

const SwitchDef = struct {
    off: [:0]const u8,
    on: [:0]const u8,
    episode: i32,
};

const alph_switch_list = [_]SwitchDef{
    // Doom shareware episode 1 switches
    .{ .off = "SW1BRCOM", .on = "SW2BRCOM", .episode = 1 },
    .{ .off = "SW1BRN1", .on = "SW2BRN1", .episode = 1 },
    .{ .off = "SW1BRN2", .on = "SW2BRN2", .episode = 1 },
    .{ .off = "SW1BRNGN", .on = "SW2BRNGN", .episode = 1 },
    .{ .off = "SW1BROWN", .on = "SW2BROWN", .episode = 1 },
    .{ .off = "SW1COMM", .on = "SW2COMM", .episode = 1 },
    .{ .off = "SW1COMP", .on = "SW2COMP", .episode = 1 },
    .{ .off = "SW1DIRT", .on = "SW2DIRT", .episode = 1 },
    .{ .off = "SW1EXIT", .on = "SW2EXIT", .episode = 1 },
    .{ .off = "SW1GRAY", .on = "SW2GRAY", .episode = 1 },
    .{ .off = "SW1GRAY1", .on = "SW2GRAY1", .episode = 1 },
    .{ .off = "SW1METAL", .on = "SW2METAL", .episode = 1 },
    .{ .off = "SW1PIPE", .on = "SW2PIPE", .episode = 1 },
    .{ .off = "SW1SLAD", .on = "SW2SLAD", .episode = 1 },
    .{ .off = "SW1STARG", .on = "SW2STARG", .episode = 1 },
    .{ .off = "SW1STON1", .on = "SW2STON1", .episode = 1 },
    .{ .off = "SW1STON2", .on = "SW2STON2", .episode = 1 },
    .{ .off = "SW1STONE", .on = "SW2STONE", .episode = 1 },
    .{ .off = "SW1STRTN", .on = "SW2STRTN", .episode = 1 },

    // Doom registered episodes 2&3 switches
    .{ .off = "SW1BLUE", .on = "SW2BLUE", .episode = 2 },
    .{ .off = "SW1CMT", .on = "SW2CMT", .episode = 2 },
    .{ .off = "SW1GARG", .on = "SW2GARG", .episode = 2 },
    .{ .off = "SW1GSTON", .on = "SW2GSTON", .episode = 2 },
    .{ .off = "SW1HOT", .on = "SW2HOT", .episode = 2 },
    .{ .off = "SW1LION", .on = "SW2LION", .episode = 2 },
    .{ .off = "SW1SATYR", .on = "SW2SATYR", .episode = 2 },
    .{ .off = "SW1SKIN", .on = "SW2SKIN", .episode = 2 },
    .{ .off = "SW1VINE", .on = "SW2VINE", .episode = 2 },
    .{ .off = "SW1WOOD", .on = "SW2WOOD", .episode = 2 },

    // Doom II switches
    .{ .off = "SW1PANEL", .on = "SW2PANEL", .episode = 3 },
    .{ .off = "SW1ROCK", .on = "SW2ROCK", .episode = 3 },
    .{ .off = "SW1MET2", .on = "SW2MET2", .episode = 3 },
    .{ .off = "SW1WDMET", .on = "SW2WDMET", .episode = 3 },
    .{ .off = "SW1BRIK", .on = "SW2BRIK", .episode = 3 },
    .{ .off = "SW1MOD1", .on = "SW2MOD1", .episode = 3 },
    .{ .off = "SW1ZIM", .on = "SW2ZIM", .episode = 3 },
    .{ .off = "SW1STON6", .on = "SW2STON6", .episode = 3 },
    .{ .off = "SW1TEK", .on = "SW2TEK", .episode = 3 },
    .{ .off = "SW1MARB", .on = "SW2MARB", .episode = 3 },
    .{ .off = "SW1SKULL", .on = "SW2SKULL", .episode = 3 },
};

var switchlist_buf: [alph_switch_list.len * 2]c_int = undefined;
/// Off/on texture pairs for this game's switches. Entry i ^ 1 is entry i's partner.
var switchlist: []c_int = &.{};

pub export var buttonlist: [c.MAXBUTTONS]c.button_t = @splat(std.mem.zeroes(c.button_t));

pub fn P_InitSwitchList() void {
    const episode: i32 = switch (doomstat.gamemode) {
        .Registered, .Retail => 2, // BUGFIX: Switches in DOOMU ep 4 included here
        .Commercial => 3,
        else => 1,
    };

    var index: usize = 0;
    for (&alph_switch_list) |*as| {
        if (as.episode <= episode) {
            switchlist_buf[index] = c.R_TextureNumForName(@constCast(as.off));
            index += 1;
            switchlist_buf[index] = c.R_TextureNumForName(@constCast(as.on));
            index += 1;
        }
    }
    switchlist = switchlist_buf[0..index];
}

/// Start a button counting down till it turns off.
fn P_StartButton(line: *c.line_t, w: ButtonWhere, texture: c_int, time: c_int) void {
    // See if button is already pressed
    for (&buttonlist) |*button| {
        if (button.btimer != 0 and button.line == line) {
            return;
        }
    }

    // Otherwise look for an empty (finished) button slot to (re)use.
    for (&buttonlist) |*button| {
        if (button.btimer == 0) {
            button.line = line;
            button.where = @backingInt(w);
            button.btexture = texture;
            button.btimer = time;
            button.soundorg = @ptrCast(&line.frontsector.*.soundorg);
            return;
        }
    }

    I_Error("P_StartButton: no button slots left!");
}

/// Function that changes wall texture.
/// Tell it if switch is ok to use again (1=yes, it's a button).
pub export fn P_ChangeSwitchTexture(line: *c.line_t, useAgain: c_int) void {
    if (useAgain == 0) {
        line.special = 0;
    }

    const side = &p_setup.sides[@intCast(line.sidenum[0])];
    const parts = [_]struct { tex: *c_short, where: ButtonWhere }{
        .{ .tex = &side.toptexture, .where = .top },
        .{ .tex = &side.midtexture, .where = .middle },
        .{ .tex = &side.bottomtexture, .where = .bottom },
    };

    const sound: Sfx = if (line.special == 11) .swtchx else .swtchn;

    for (switchlist, 0..) |tex, i| for (parts) |part| {
        if (tex != part.tex.*) continue;

        // BUG: Vanilla plays the sound at buttonlist[0]'s origin, not this
        // line's sector. It is usually null (full volume, unpositioned) or a
        // stale sector from an earlier button.
        s_sound.S_StartSound_Zig(@ptrCast(buttonlist[0].soundorg), sound);

        part.tex.* = @intCast(switchlist[i ^ 1]);

        if (useAgain != 0) {
            P_StartButton(line, part.where, tex, BUTTONTIME);
        }
        return;
    };
}

pub fn P_UseSpecialLine(thing: *MObj, line: *c.line_t, side: c_int) bool {
    // Only front sides are usable. Vanilla let 124 through for the
    // unfinished sliding door, which did nothing.
    if (side != 0) return false;

    // Switches that non-player things can activate.
    if (thing.player == null) {
        // never open secret doors
        if (line.flags & c.ML_SECRET != 0) return false;

        switch (line.special) {
            1, // Manual door raise
            32, // Manual blue
            33, // Manual red
            34, // Manual yellow
            => {}, // nothing
            else => return false,
        }
    }

    // good to do something now
    switch (line.special) {
        // Manuals
        1, // Vertical door
        26, // Blue door
        27, // Yellow door
        28, // Red door

        31, // Manual door open
        32, // Blue locked door open
        33, // Red locked door open
        34, // Yellow locked door open

        117, // Blazing door raise
        118, // Blazing door open
        => p_doors.EV_VerticalDoor(line, thing),

        // Switches

        // Build Stairs
        7 => if (p_floor.EV_BuildStairs(line, .build8) != 0) P_ChangeSwitchTexture(line, 0),

        // Change Donut
        9 => if (c.EV_DoDonut(line) != 0) P_ChangeSwitchTexture(line, 0),

        // Exit level
        11 => {
            P_ChangeSwitchTexture(line, 0);
            g_game.G_ExitLevel();
        },

        // Raise Floor 32 and change texture
        14 => if (p_plats.EV_DoPlat(line, .raiseAndChange, 32) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Floor 24 and change texture
        15 => if (p_plats.EV_DoPlat(line, .raiseAndChange, 24) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Floor to next highest floor
        18 => if (p_floor.EV_DoFloor(line, .raiseFloorToNearest) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Plat to next highest floor and change texture
        20 => if (p_plats.EV_DoPlat(line, .raiseToNearestAndChange, 0) != 0) P_ChangeSwitchTexture(line, 0),

        // PlatDownWaitUpStay
        21 => if (p_plats.EV_DoPlat(line, .downWaitUpStay, 0) != 0) P_ChangeSwitchTexture(line, 0),

        // Lower Floor to lowest
        23 => if (p_floor.EV_DoFloor(line, .lowerFloorToLowest) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Door
        29 => if (p_doors.EV_DoDoor(line, .normal) != 0) P_ChangeSwitchTexture(line, 0),

        // Lower Ceiling to floor
        41 => if (p_ceilng.EV_DoCeiling(line, .lowerToFloor) != 0) P_ChangeSwitchTexture(line, 0),

        // Turbo Lower Floor
        71 => if (p_floor.EV_DoFloor(line, .turboLower) != 0) P_ChangeSwitchTexture(line, 0),

        // Ceiling Crush And Raise
        49 => if (p_ceilng.EV_DoCeiling(line, .crushAndRaise) != 0) P_ChangeSwitchTexture(line, 0),

        // Close Door
        50 => if (p_doors.EV_DoDoor(line, .close) != 0) P_ChangeSwitchTexture(line, 0),

        // Secret EXIT
        51 => {
            P_ChangeSwitchTexture(line, 0);
            g_game.G_SecretExitLevel();
        },

        // Raise Floor Crush
        55 => if (p_floor.EV_DoFloor(line, .raiseFloorCrush) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Floor
        101 => if (p_floor.EV_DoFloor(line, .raiseFloor) != 0) P_ChangeSwitchTexture(line, 0),

        // Lower Floor to Surrounding floor height
        102 => if (p_floor.EV_DoFloor(line, .lowerFloor) != 0) P_ChangeSwitchTexture(line, 0),

        // Open Door
        103 => if (p_doors.EV_DoDoor(line, .open) != 0) P_ChangeSwitchTexture(line, 0),

        // Blazing Door Raise (faster than TURBO!)
        111 => if (p_doors.EV_DoDoor(line, .blazeRaise) != 0) P_ChangeSwitchTexture(line, 0),

        // Blazing Door Open (faster than TURBO!)
        112 => if (p_doors.EV_DoDoor(line, .blazeOpen) != 0) P_ChangeSwitchTexture(line, 0),

        // Blazing Door Close (faster than TURBO!)
        113 => if (p_doors.EV_DoDoor(line, .blazeClose) != 0) P_ChangeSwitchTexture(line, 0),

        // Blazing PlatDownWaitUpStay
        122 => if (p_plats.EV_DoPlat(line, .blazeDWUS, 0) != 0) P_ChangeSwitchTexture(line, 0),

        // Build Stairs Turbo 16
        127 => if (p_floor.EV_BuildStairs(line, .turbo16) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Floor Turbo
        131 => if (p_floor.EV_DoFloor(line, .raiseFloorTurbo) != 0) P_ChangeSwitchTexture(line, 0),

        133, // BlzOpenDoor BLUE
        135, // BlzOpenDoor RED
        137, // BlzOpenDoor YELLOW
        => if (p_doors.EV_DoLockedDoor(line, .blazeOpen, thing) != 0) P_ChangeSwitchTexture(line, 0),

        // Raise Floor 512
        140 => if (p_floor.EV_DoFloor(line, .raiseFloor512) != 0) P_ChangeSwitchTexture(line, 0),

        // BUTTONS

        // Close Door
        42 => if (p_doors.EV_DoDoor(line, .close) != 0) P_ChangeSwitchTexture(line, 1),

        // Lower Ceiling to Floor
        43 => if (p_ceilng.EV_DoCeiling(line, .lowerToFloor) != 0) P_ChangeSwitchTexture(line, 1),

        // Lower Floor to Surrounding floor height
        45 => if (p_floor.EV_DoFloor(line, .lowerFloor) != 0) P_ChangeSwitchTexture(line, 1),

        // Lower Floor to Lowest
        60 => if (p_floor.EV_DoFloor(line, .lowerFloorToLowest) != 0) P_ChangeSwitchTexture(line, 1),

        // Open Door
        61 => if (p_doors.EV_DoDoor(line, .open) != 0) P_ChangeSwitchTexture(line, 1),

        // PlatDownWaitUpStay
        62 => if (p_plats.EV_DoPlat(line, .downWaitUpStay, 1) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Door
        63 => if (p_doors.EV_DoDoor(line, .normal) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Floor to ceiling
        64 => if (p_floor.EV_DoFloor(line, .raiseFloor) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Floor 24 and change texture
        66 => if (p_plats.EV_DoPlat(line, .raiseAndChange, 24) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Floor 32 and change texture
        67 => if (p_plats.EV_DoPlat(line, .raiseAndChange, 32) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Floor Crush
        65 => if (p_floor.EV_DoFloor(line, .raiseFloorCrush) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Plat to next highest floor and change texture
        68 => if (p_plats.EV_DoPlat(line, .raiseToNearestAndChange, 0) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Floor to next highest floor
        69 => if (p_floor.EV_DoFloor(line, .raiseFloorToNearest) != 0) P_ChangeSwitchTexture(line, 1),

        // Turbo Lower Floor
        70 => if (p_floor.EV_DoFloor(line, .turboLower) != 0) P_ChangeSwitchTexture(line, 1),

        // Blazing Door Raise (faster than TURBO!)
        114 => if (p_doors.EV_DoDoor(line, .blazeRaise) != 0) P_ChangeSwitchTexture(line, 1),

        // Blazing Door Open (faster than TURBO!)
        115 => if (p_doors.EV_DoDoor(line, .blazeOpen) != 0) P_ChangeSwitchTexture(line, 1),

        // Blazing Door Close (faster than TURBO!)
        116 => if (p_doors.EV_DoDoor(line, .blazeClose) != 0) P_ChangeSwitchTexture(line, 1),

        // Blazing PlatDownWaitUpStay
        123 => if (p_plats.EV_DoPlat(line, .blazeDWUS, 0) != 0) P_ChangeSwitchTexture(line, 1),

        // Raise Floor Turbo
        132 => if (p_floor.EV_DoFloor(line, .raiseFloorTurbo) != 0) P_ChangeSwitchTexture(line, 1),

        99, // BlzOpenDoor BLUE
        134, // BlzOpenDoor RED
        136, // BlzOpenDoor YELLOW
        => if (p_doors.EV_DoLockedDoor(line, .blazeOpen, thing) != 0) P_ChangeSwitchTexture(line, 1),

        // Light Turn On
        138 => {
            p_lights.EV_LightTurnOn(line, 255);
            P_ChangeSwitchTexture(line, 1);
        },

        // Light Turn Off
        139 => {
            p_lights.EV_LightTurnOn(line, 35);
            P_ChangeSwitchTexture(line, 1);
        },

        else => {},
    }

    return true;
}
