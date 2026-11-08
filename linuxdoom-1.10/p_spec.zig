const c = @import("c");
const std = @import("std");

const d_player = @import("d_player.zig");
const Player = d_player.Player;
const g_game = @import("g_game.zig");
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const m_argv = @import("m_argv.zig");
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FRACUNIT = m_fixed.FRACUNIT;
const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_ceilng = @import("p_ceilng.zig");
const p_doors = @import("p_doors.zig");
const p_floor = @import("p_floor.zig");
const p_inter = @import("p_inter.zig");
const p_lights = @import("p_lights.zig");
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const p_plats = @import("p_plats.zig");
const p_setup = @import("p_setup.zig");
const p_switch = @import("p_switch.zig");
const ButtonWhere = p_switch.ButtonWhere;
const p_telept = @import("p_telept.zig");
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");
const w_wad = @import("w_wad.zig");
const z_zone = @import("z_zone.zig");

const Anim = struct {
    istexture: bool,
    picnum: c_int,
    basepic: c_int,
    numpics: c_int,
    speed: c_int,
};

const AnimDef = struct {
    istexture: bool,
    endname: [:0]const u8,
    startname: [:0]const u8,
    speed: c_int,
};

// Floor/ceiling animation sequences,
//  defined by first and last frame,
//  i.e. the flat (64x64 tile) name to
//  be used.
// The full animation sequence is given
//  using all the flats between the start
//  and end entry, in the order found in
//  the WAD file.
//
const animdefs = [_]AnimDef{
    .{ .istexture = false, .endname = "NUKAGE3", .startname = "NUKAGE1", .speed = 8 },
    .{ .istexture = false, .endname = "FWATER4", .startname = "FWATER1", .speed = 8 },
    .{ .istexture = false, .endname = "SWATER4", .startname = "SWATER1", .speed = 8 },
    .{ .istexture = false, .endname = "LAVA4", .startname = "LAVA1", .speed = 8 },
    .{ .istexture = false, .endname = "BLOOD3", .startname = "BLOOD1", .speed = 8 },

    // DOOM II flat animations.
    .{ .istexture = false, .endname = "RROCK08", .startname = "RROCK05", .speed = 8 },
    .{ .istexture = false, .endname = "SLIME04", .startname = "SLIME01", .speed = 8 },
    .{ .istexture = false, .endname = "SLIME08", .startname = "SLIME05", .speed = 8 },
    .{ .istexture = false, .endname = "SLIME12", .startname = "SLIME09", .speed = 8 },

    .{ .istexture = true, .endname = "BLODGR4", .startname = "BLODGR1", .speed = 8 },
    .{ .istexture = true, .endname = "SLADRIP3", .startname = "SLADRIP1", .speed = 8 },

    .{ .istexture = true, .endname = "BLODRIP4", .startname = "BLODRIP1", .speed = 8 },
    .{ .istexture = true, .endname = "FIREWALL", .startname = "FIREWALA", .speed = 8 },
    .{ .istexture = true, .endname = "GSTFONT3", .startname = "GSTFONT1", .speed = 8 },
    .{ .istexture = true, .endname = "FIRELAVA", .startname = "FIRELAV3", .speed = 8 },
    .{ .istexture = true, .endname = "FIREMAG3", .startname = "FIREMAG1", .speed = 8 },
    .{ .istexture = true, .endname = "FIREBLU2", .startname = "FIREBLU1", .speed = 8 },
    .{ .istexture = true, .endname = "ROCKRED3", .startname = "ROCKRED1", .speed = 8 },

    .{ .istexture = true, .endname = "BFALL4", .startname = "BFALL1", .speed = 8 },
    .{ .istexture = true, .endname = "SFALL4", .startname = "SFALL1", .speed = 8 },
    .{ .istexture = true, .endname = "WFALL4", .startname = "WFALL1", .speed = 8 },
    .{ .istexture = true, .endname = "DBRAIN4", .startname = "DBRAIN1", .speed = 8 },
};

var anims_buf: [animdefs.len]Anim = undefined;
var anims: []Anim = &.{};

// Animating line specials
const MAXLINEANIMS = 64;
var linespeciallist_buf: [MAXLINEANIMS]*c.line_t = undefined;
var linespeciallist: []*c.line_t = &.{};

pub fn P_InitPicAnims() void {
    var index: usize = 0;
    for (&animdefs) |*animdef| {
        const picnum: c_int, const basepic: c_int = if (animdef.istexture) blk: {
            // different episode?
            if (c.R_CheckTextureNumForName(@constCast(animdef.startname)) == -1) continue;
            break :blk .{
                c.R_TextureNumForName(@constCast(animdef.endname)),
                c.R_TextureNumForName(@constCast(animdef.startname)),
            };
        } else blk: {
            if (w_wad.W_CheckNumForName(animdef.startname.ptr) == -1) continue;
            break :blk .{
                c.R_FlatNumForName(@constCast(animdef.endname)),
                c.R_FlatNumForName(@constCast(animdef.startname)),
            };
        };

        const numpics = picnum - basepic + 1;
        if (numpics < 2) {
            I_Error(
                "P_InitPicAnims: bad cycle from %s to %s",
                animdef.startname.ptr,
                animdef.endname.ptr,
            );
        }

        anims_buf[index] = .{
            .istexture = animdef.istexture,
            .picnum = picnum,
            .basepic = basepic,
            .numpics = numpics,
            .speed = animdef.speed,
        };
        index += 1;
    }
    anims = anims_buf[0..index];
}

/// Will return a side_t* given the number of the current sector, the line
/// number, and the side (0/1) that you want.
pub fn getSide(currentSector: c_int, line: c_int, side: c_int) *c.side_t {
    return &p_setup.sides[@intCast(p_setup.sectors[@intCast(currentSector)].lines[@intCast(line)].*.sidenum[@intCast(side)])];
}

/// Will return a sector_t* given the number of the current sector, the line
/// number and the side (0/1) that you want.
pub fn getSector(currentSector: c_int, line: c_int, side: c_int) *c.sector_t {
    return getSide(currentSector, line, side).sector;
}

/// Given the sector number and the line number, it will tell you whether the
/// line is two-sided or not.
pub fn twoSided(sector: c_int, line: c_int) bool {
    return p_setup.sectors[@intCast(sector)].lines[@intCast(line)].*.flags & c.ML_TWOSIDED != 0;
}

/// Return *sector_t of sector next to current. null if not two-sided line.
pub fn getNextSector(line: *c.line_t, sec: *c.sector_t) ?*c.sector_t {
    if (line.flags & c.ML_TWOSIDED == 0) return null;

    return if (line.frontsector == sec)
        line.backsector
    else
        line.frontsector;
}

// Find the lowest floor height in surrounding sectors
pub fn P_FindLowestFloorSurrounding(sec: *c.sector_t) fixed_t {
    var floor = sec.floorheight;
    for (sec.lines[0..@intCast(sec.linecount)]) |line| {
        const other = getNextSector(line, sec) orelse continue;
        floor = @min(floor, other.floorheight);
    }
    return floor;
}

// Find the highest floor height in surrounding sectors
pub fn P_FindHighestFloorSurrounding(sec: *c.sector_t) fixed_t {
    // BUG: Vanilla starts at -500 instead of the lowest possible height, so if
    // every neighbor's floor is below -500 this returns -500.
    var floor: fixed_t = -500 * FRACUNIT;
    for (sec.lines[0..@intCast(sec.linecount)]) |line| {
        const other = getNextSector(line, sec) orelse continue;
        floor = @max(floor, other.floorheight);
    }
    return floor;
}

// Note: P_FindNextHighestFloor should be doable w/o a fixed array.
// 20 adjoining sectors max!
// BUG: The cap counts lines, not sectors. A neighbor that shares several
// lines with sec is added once per line, so the loop can stop with fewer
// than 20 distinct neighbors. The lines it skips are never checked, so
// the result can be higher than the real next floor up.
const MAX_ADJOINING_SECTORS = 20;

/// Find next highest floor in surrounding sectors.
pub fn P_FindNextHighestFloor(sec: *c.sector_t, currentheight: fixed_t) fixed_t {
    var heightlist: [MAX_ADJOINING_SECTORS]fixed_t = undefined;
    var h: usize = 0;

    for (sec.lines[0..@intCast(sec.linecount)]) |line| {
        const other = getNextSector(line, sec) orelse continue;

        if (other.floorheight > currentheight) {
            heightlist[h] = other.floorheight;
            h += 1;
        }

        // Check for overflow. Exit.
        if (h >= MAX_ADJOINING_SECTORS) {
            i_system.stderr().print("Sector with more than 20 adjoining sectors\n", .{}) catch {};
            break;
        }
    }

    // Find lowest height in list
    if (h == 0) return currentheight;
    return std.mem.min(fixed_t, heightlist[0..h]);
}

// Find the lowest ceiling height in surrounding sectors
pub fn P_FindLowestCeilingSurrounding(sec: *c.sector_t) fixed_t {
    var height: fixed_t = std.math.maxInt(fixed_t);
    for (sec.lines[0..@intCast(sec.linecount)]) |line| {
        const other = getNextSector(line, sec) orelse continue;
        height = @min(height, other.ceilingheight);
    }
    return height;
}

// Find the highest ceiling height in surrounding sectors
pub fn P_FindHighestCeilingSurrounding(sec: *c.sector_t) fixed_t {
    // BUG: Vanilla starts at 0, so if every neighbor's ceiling is below 0
    // this returns 0.
    var height: fixed_t = 0;
    for (sec.lines[0..@intCast(sec.linecount)]) |line| {
        const other = getNextSector(line, sec) orelse continue;
        height = @max(height, other.ceilingheight);
    }
    return height;
}

/// Return the next sector number that line tag refers to.
pub fn P_FindSectorFromLineTag(line: *c.line_t, start: c_int) c_int {
    for (@intCast(start + 1)..@intCast(p_setup.numsectors)) |i| {
        if (p_setup.sectors[i].tag == line.tag) {
            return @intCast(i);
        }
    }
    return -1;
}

/// Find minimum light from an adjacent sector
pub fn P_FindMinSurroundingLight(sector: *c.sector_t, max: c_int) c_int {
    var min = max;
    for (sector.lines[0..@intCast(sector.linecount)]) |line| {
        const other = getNextSector(line, sector) orelse continue;
        min = @min(min, other.lightlevel);
    }
    return min;
}

/// W1 triggers fire once. The argument is evaluated first, so the special
/// clears after the action runs, as in vanilla.
fn once(line: *c.line_t, _: anytype) void {
    line.special = 0;
}

/// Called every time a thing origin is about to cross a line with a non-zero
/// special.
pub fn P_CrossSpecialLine(line: *c.line_t, side: c_int, thing: *MObj) void {
    // Triggers that other things can activate
    if (thing.player == null) {
        // Things that should not trigger specials
        switch (thing.type) {
            c.MT_ROCKET,
            c.MT_PLASMA,
            c.MT_BFG,
            c.MT_TROOPSHOT,
            c.MT_HEADSHOT,
            c.MT_BRUISERSHOT,
            => return,
            else => {},
        }

        // Triggers that non-player things can activate
        switch (line.special) {
            39, // Teleport trigger
            97, // Teleport retrigger
            125, // Teleport monsteronly trigger
            126, // Teleport monsteronly retrigger
            4, // Raise door
            10, // Plat down-wait-up-stay trigger
            88, // Plat down-wait-up-stay retrigger
            => {}, // allowed
            else => return, // not allowed
        }
    }

    switch (line.special) {
        // Triggers

        2 => once(line, p_doors.EV_DoDoor(line, .open)), // Open door
        3 => once(line, p_doors.EV_DoDoor(line, .close)), // Close door
        4 => once(line, p_doors.EV_DoDoor(line, .normal)), // Raise door
        5 => once(line, p_floor.EV_DoFloor(line, .raiseFloor)), // Raise floor
        6 => once(line, p_ceilng.EV_DoCeiling(line, .fastCrushAndRaise)), // Fast ceiling crush & raise
        8 => once(line, p_floor.EV_BuildStairs(line, .build8)), // Build stairs
        10 => once(line, p_plats.EV_DoPlat(line, .downWaitUpStay, 0)), // PlatDownWaitUp
        12 => once(line, p_lights.EV_LightTurnOn(line, 0)), // Light turn on - brightest near
        13 => once(line, p_lights.EV_LightTurnOn(line, 255)), // Light turn on 255
        16 => once(line, p_doors.EV_DoDoor(line, .close30ThenOpen)), // Close door 30
        17 => once(line, p_lights.EV_StartLightStrobing(line)), // Start light strobing
        19 => once(line, p_floor.EV_DoFloor(line, .lowerFloor)), // Lower floor
        22 => once(line, p_plats.EV_DoPlat(line, .raiseToNearestAndChange, 0)), // Raise floor to nearest height and change texture
        25 => once(line, p_ceilng.EV_DoCeiling(line, .crushAndRaise)), // Ceiling crush and raise
        30 => once(line, p_floor.EV_DoFloor(line, .raiseToTexture)), // Raise floor to shortest texture height on either side of lines
        35 => once(line, p_lights.EV_LightTurnOn(line, 35)), // Lights very dark
        36 => once(line, p_floor.EV_DoFloor(line, .turboLower)), // Lower floor turbo
        37 => once(line, p_floor.EV_DoFloor(line, .lowerAndChange)), // LowerAndChange
        38 => once(line, p_floor.EV_DoFloor(line, .lowerFloorToLowest)), // Lower floor to lowest
        39 => once(line, p_telept.EV_Teleport(line, side, thing)), // Teleport
        40 => { // RaiseCeilingLowerFloor
            _ = p_ceilng.EV_DoCeiling(line, .raiseToHighest);
            _ = p_floor.EV_DoFloor(line, .lowerFloorToLowest);
            line.special = 0;
        },
        44 => once(line, p_ceilng.EV_DoCeiling(line, .lowerAndCrush)), // Ceiling crush
        52 => g_game.G_ExitLevel(), // Exit!
        53 => once(line, p_plats.EV_DoPlat(line, .perpetualRaise, 0)), // Perpetual platform raise
        54 => once(line, p_plats.EV_StopPlat(line)), // Platform stop
        56 => once(line, p_floor.EV_DoFloor(line, .raiseFloorCrush)), // Raise floor crush
        57 => once(line, p_ceilng.EV_CeilingCrushStop(line)), // Ceiling crush stop
        58 => once(line, p_floor.EV_DoFloor(line, .raiseFloor24)), // Raise floor 24
        59 => once(line, p_floor.EV_DoFloor(line, .raiseFloor24AndChange)), // Raise floor 24 and change
        100 => once(line, p_floor.EV_BuildStairs(line, .turbo16)), // Build stairs turbo 16
        104 => once(line, p_lights.EV_TurnTagLightsOff(line)), // Turn lights off in sector(tag)
        108 => once(line, p_doors.EV_DoDoor(line, .blazeRaise)), // Blazing door raise (faster than turbo!)
        109 => once(line, p_doors.EV_DoDoor(line, .blazeOpen)), // Blazing door open (faster than turbo!)
        110 => once(line, p_doors.EV_DoDoor(line, .blazeClose)), // Blazing door close (faster than turbo!)
        119 => once(line, p_floor.EV_DoFloor(line, .raiseFloorToNearest)), // Raise floor to nearest surrounding floor
        121 => once(line, p_plats.EV_DoPlat(line, .blazeDWUS, 0)), // Blazing PlatDownWaitUpStay
        124 => g_game.G_SecretExitLevel(), // Secret exit
        125 => if (thing.player == null) { // Teleport monsteronly
            _ = p_telept.EV_Teleport(line, side, thing);
            line.special = 0;
        },
        130 => once(line, p_floor.EV_DoFloor(line, .raiseFloorTurbo)), // Raise floor turbo
        141 => once(line, p_ceilng.EV_DoCeiling(line, .silentCrushAndRaise)), // Silent ceiling crush & raise

        // Retriggers
        72 => _ = p_ceilng.EV_DoCeiling(line, .lowerAndCrush), // Ceiling crush
        73 => _ = p_ceilng.EV_DoCeiling(line, .crushAndRaise), // Ceiling crush and raise
        74 => _ = p_ceilng.EV_CeilingCrushStop(line), // Ceiling crush stop
        75 => _ = p_doors.EV_DoDoor(line, .close), // Close door
        76 => _ = p_doors.EV_DoDoor(line, .close30ThenOpen), // Close door 30
        77 => _ = p_ceilng.EV_DoCeiling(line, .fastCrushAndRaise), // Fast ceiling crush & raise
        79 => _ = p_lights.EV_LightTurnOn(line, 35), // Lights very dark
        80 => _ = p_lights.EV_LightTurnOn(line, 0), // Light turn on - brightest near
        81 => _ = p_lights.EV_LightTurnOn(line, 255), // Light turn on 255
        82 => _ = p_floor.EV_DoFloor(line, .lowerFloorToLowest), // Lower floor to lowest
        83 => _ = p_floor.EV_DoFloor(line, .lowerFloor), // Lower floor
        84 => _ = p_floor.EV_DoFloor(line, .lowerAndChange), // LowerAndChange
        86 => _ = p_doors.EV_DoDoor(line, .open), // Open door
        87 => _ = p_plats.EV_DoPlat(line, .perpetualRaise, 0), // Perpetual platform raise
        88 => _ = p_plats.EV_DoPlat(line, .downWaitUpStay, 0), // PlatDownWaitUp
        89 => _ = p_plats.EV_StopPlat(line), // Platform stop
        90 => _ = p_doors.EV_DoDoor(line, .normal), // Raise door
        91 => _ = p_floor.EV_DoFloor(line, .raiseFloor), // Raise floor
        92 => _ = p_floor.EV_DoFloor(line, .raiseFloor24), // Raise floor 24
        93 => _ = p_floor.EV_DoFloor(line, .raiseFloor24AndChange), // Raise floor 24 and change
        94 => _ = p_floor.EV_DoFloor(line, .raiseFloorCrush), // Raise floor crush
        95 => _ = p_plats.EV_DoPlat(line, .raiseToNearestAndChange, 0), // Raise floor to nearest height and change texture
        96 => _ = p_floor.EV_DoFloor(line, .raiseToTexture), // Raise floor to shortest texture height on either side of lines
        97 => _ = p_telept.EV_Teleport(line, side, thing), // Teleport
        98 => _ = p_floor.EV_DoFloor(line, .turboLower), // Lower floor turbo
        105 => _ = p_doors.EV_DoDoor(line, .blazeRaise), // Blazing door raise (faster than turbo!)
        106 => _ = p_doors.EV_DoDoor(line, .blazeOpen), // Blazing door open (faster than turbo!)
        107 => _ = p_doors.EV_DoDoor(line, .blazeClose), // Blazing door close (faster than turbo!)
        120 => _ = p_plats.EV_DoPlat(line, .blazeDWUS, 0), // Blazing PlatDownWaitUpStay
        126 => if (thing.player == null) { // Teleport monsteronly
            _ = p_telept.EV_Teleport(line, side, thing);
        },
        128 => _ = p_floor.EV_DoFloor(line, .raiseFloorToNearest), // Raise to nearest floor
        129 => _ = p_floor.EV_DoFloor(line, .raiseFloorTurbo), // Raise floor turbo

        else => {},
    }
}

/// Impact specials. Called when a thing shoots a special line.
pub fn P_ShootSpecialLine(thing: *MObj, line: *c.line_t) void {
    // Impacts that other things can activate.
    if (thing.player == null) {
        switch (line.special) {
            46 => {}, // Open door impact
            else => return,
        }
    }

    switch (line.special) {
        // Raise floor
        24 => {
            _ = p_floor.EV_DoFloor(line, .raiseFloor);
            p_switch.P_ChangeSwitchTexture(line, false);
        },

        // Open door
        46 => {
            _ = p_doors.EV_DoDoor(line, .open);
            p_switch.P_ChangeSwitchTexture(line, true);
        },

        // Raise floor near and change
        47 => {
            _ = p_plats.EV_DoPlat(line, .raiseToNearestAndChange, 0);
            p_switch.P_ChangeSwitchTexture(line, false);
        },

        else => {},
    }
}

/// Called every tic frame that the player origin is in a special sector.
pub fn P_PlayerInSpecialSector(player: *Player) void {
    const sector: *c.sector_t = player.mo.?.subsector.sector;

    // Falling but not all the way down yet?
    if (player.mo.?.z != sector.floorheight) return;

    // Has hit ground.
    switch (sector.special) {
        // Hellslime Damage
        5 => if (player.power(.IronFeet).* == 0 and p_tick.leveltime & 0x1f == 0)
            p_inter.P_DamageMobj(player.mo.?, null, null, 10),

        // Nukage Damage
        7 => if (player.power(.IronFeet).* == 0 and p_tick.leveltime & 0x1f == 0)
            p_inter.P_DamageMobj(player.mo.?, null, null, 5),

        // Super Hellslime Damage, Strobe Hurt
        16, 4 => if ((player.power(.IronFeet).* == 0 or P_Random() < 5) and p_tick.leveltime & 0x1f == 0)
            p_inter.P_DamageMobj(player.mo.?, null, null, 20),

        // Secret Sector
        9 => {
            player.secretcount += 1;
            sector.special = 0;
        },

        // Exit Super Damage! (for E1M8 finale)
        11 => {
            player.cheats &= ~c.CF_GODMODE;

            if (p_tick.leveltime & 0x1f == 0) {
                p_inter.P_DamageMobj(player.mo.?, null, null, 20);
            }

            if (player.health <= 10) {
                g_game.G_ExitLevel();
            }
        },

        else => I_Error("P_PlayerInSpecialSector: unknown special %i", sector.special),
    }
}

var levelTimer = false;
var levelTimeCount: c_int = 0;

/// Animate planes, scroll walls, etc.
pub fn P_UpdateSpecials() void {
    // Level timer (-avg and -timer args)
    if (levelTimer) {
        levelTimeCount -= 1;
        if (levelTimeCount == 0) {
            g_game.G_ExitLevel();
        }
    }

    // Animate flats and textures globally
    for (anims) |*anim| {
        for (@intCast(anim.basepic)..@intCast(anim.basepic + anim.numpics)) |i| {
            const pic = anim.basepic + @mod(@divTrunc(p_tick.leveltime, anim.speed) + @as(c_int, @intCast(i)), anim.numpics);
            if (anim.istexture) {
                c.texturetranslation[i] = pic;
            } else {
                c.flattranslation[i] = pic;
            }
        }
    }

    // Animate line specials
    for (linespeciallist) |line| {
        if (line.special == 48) {
            // Effect Firstcol Scroll +
            p_setup.sides[@intCast(line.sidenum[0])].textureoffset += FRACUNIT;
        }
    }

    // Do buttons
    for (&p_switch.buttonlist) |*button| if (button.btimer != 0) {
        button.btimer -= 1;
        if (button.btimer == 0) {
            const side = &p_setup.sides[@intCast(button.line.?.sidenum[0])];
            switch (button.where) {
                .top => side.toptexture = @intCast(button.btexture),
                .middle => side.midtexture = @intCast(button.btexture),
                .bottom => side.bottomtexture = @intCast(button.btexture),
            }
            // BUG: Vanilla passes the address of the soundorg field, not the sector
            // origin it points to. The sound code reads the origin's x and y from
            // whatever follows that field in buttonlist, so the pop is positioned
            // at garbage coordinates and is sometimes too far away to hear.
            s_sound.S_StartSound_Zig(@ptrCast(&button.soundorg), .swtchn);
            button.* = .{};
        }
    };
}

pub fn EV_DoDonut(line: *c.line_t) bool {
    var rtn = false;

    var secnum: c_int = -1;
    while (true) {
        secnum = P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const s1 = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (s1.specialdata != null) continue;

        rtn = true;
        // BUG: Vanilla doesn't check for a null s2 (a one-sided first line)
        // and dereferences it. We panic here instead.
        const s2 = getNextSector(s1.lines[0], s1).?;

        for (s2.lines[0..@intCast(s2.linecount)]) |s2_line| {
            if (s2_line.*.flags & c.ML_TWOSIDED == 0 or s2_line.*.backsector == s1) continue;

            // BUG: A two-sided line can lack a back sector in a malformed
            // map. Vanilla reads garbage through it. We panic here instead.
            const s3: *c.sector_t = s2_line.*.backsector;

            // Spawn rising slime
            const s2_floor = z_zone.create(p_floor.Floor, .LevSpec, null);
            p_tick.P_AddThinker(&s2_floor.thinker);
            s2.specialdata = s2_floor;
            s2_floor.thinker.function.acp1 = p_tick.thinkFn(p_floor.Floor, &p_floor.T_MoveFloor);
            s2_floor.type = .donutRaise;
            s2_floor.crush = c.false;
            s2_floor.direction = .Up;
            s2_floor.sector = s2;
            s2_floor.speed = p_floor.FLOORSPEED / 2;
            s2_floor.texture = s3.floorpic;
            s2_floor.newspecial = 0;
            s2_floor.floordestheight = s3.floorheight;

            // Spawn lowering donut-hole
            const s1_floor = z_zone.create(p_floor.Floor, .LevSpec, null);
            p_tick.P_AddThinker(&s1_floor.thinker);
            s1.specialdata = s1_floor;
            s1_floor.thinker.function.acp1 = p_tick.thinkFn(p_floor.Floor, &p_floor.T_MoveFloor);
            s1_floor.type = .lowerFloor;
            s1_floor.crush = c.false;
            s1_floor.direction = .Down;
            s1_floor.sector = s1;
            s1_floor.speed = p_floor.FLOORSPEED / 2;
            s1_floor.floordestheight = s3.floorheight;

            break;
        }
    }

    return rtn;
}

/// After the map has been loaded scan for specials that spawn thinkers
pub fn P_SpawnSpecials() void {
    levelTimer = false;

    var i = m_argv.M_CheckParm("-avg");
    if (i != 0 and g_game.deathmatch != c.false) {
        levelTimer = true;
        levelTimeCount = 20 * 60 * 35;
    }

    i = m_argv.M_CheckParm("-timer");
    if (i != 0 and g_game.deathmatch != c.false) {
        const minutes = std.fmt.parseInt(c_int, std.mem.span(m_argv.myargv[@intCast(i + 1)]), 10) catch 0;
        levelTimer = true;
        // Wraps above 1022 minutes, as vanilla does.
        levelTimeCount = minutes *% 60 *% 35;
    }

    // Init special sectors
    for (p_setup.sectors_slice) |*sector| {
        switch (sector.special) {
            1 => p_lights.P_SpawnLightFlash(sector), // Flickering lights
            2 => p_lights.P_SpawnStrobeFlash(sector, p_lights.FASTDARK, false), // Strobe fast
            3 => p_lights.P_SpawnStrobeFlash(sector, p_lights.SLOWDARK, false), // Strobe slow
            4 => { // Strobe fast/death slime
                p_lights.P_SpawnStrobeFlash(sector, p_lights.FASTDARK, false);
                sector.special = 4;
            },
            8 => p_lights.P_SpawnGlowingLight(sector), // Glowing light
            9 => g_game.totalsecret += 1, // Secret sector
            10 => p_doors.P_SpawnDoorCloseIn30(sector), // Door close in 30 seconds
            12 => p_lights.P_SpawnStrobeFlash(sector, p_lights.SLOWDARK, true), // Sync strobe slow
            13 => p_lights.P_SpawnStrobeFlash(sector, p_lights.FASTDARK, true), // Sync strobe fast
            14 => p_doors.P_SpawnDoorRaiseIn5Mins(sector), // Door raise in 5 minutes
            17 => p_lights.P_SpawnFireFlicker(sector), // Fire flicker
            else => {},
        }
    }

    // Init line effects
    var index: usize = 0;
    for (p_setup.lines_slice) |*line| switch (line.special) {
        48 => { // Effect Firstcol Scroll+
            linespeciallist_buf[index] = line;
            index += 1;
        },
        else => {},
    };
    linespeciallist = linespeciallist_buf[0..index];

    // Init other misc stuff
    p_ceilng.activeceilings = @splat(null);
    p_plats.activeplats = @splat(null);
    p_switch.buttonlist = @splat(.{});
}
