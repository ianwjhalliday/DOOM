const c = @import("c");
const std = @import("std");

const doomdata = @import("doomdata.zig");
const ML_TWOSIDED = doomdata.ML_TWOSIDED;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FRACUNIT = m_fixed.FRACUNIT;
const p_map = @import("p_map.zig");
const p_setup = @import("p_setup.zig");
const p_spec = @import("p_spec.zig");
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");
const z_zone = @import("z_zone.zig");

pub const FLOORSPEED = FRACUNIT;

pub const FloorType = enum(c_uint) {
    // lower floor to highest surrounding floor
    lowerFloor,

    // lower floor to lowest surrounding floor
    lowerFloorToLowest,

    // lower floor to highest surrounding floor VERY FAST
    turboLower,

    // raise floor to lowest surrounding CEILING
    raiseFloor,

    // raise floor to next highest surrounding floor
    raiseFloorToNearest,

    // raise floor to shortest height texture around it
    raiseToTexture,

    // lower floor to lowest surrounding floor
    //  and change floorpic
    lowerAndChange,

    raiseFloor24,
    raiseFloor24AndChange,
    raiseFloorCrush,

    // raise to next highest floor, turbo-speed
    raiseFloorTurbo,
    donutRaise,
    raiseFloor512,
};

/// extern so `thinker` stays at offset 0, since P_RunThinkers passes the
/// thinker pointer to T_MoveFloor as a *Floor. p_saveg also saves this
/// struct as raw bytes, so reordering or retyping fields breaks savegames.
pub const Floor = extern struct {
    thinker: p_tick.Thinker,
    type: FloorType,
    crush: c.boolean, // c.boolean is a 4-byte c_int, and a 1-byte bool would shift every later field in the saved layout.
    sector: *c.sector_t,
    direction: MoveDirection,
    newspecial: c_int,
    texture: c_short,
    floordestheight: fixed_t,
    speed: fixed_t,
};

comptime {
    std.debug.assert(@sizeOf(Floor) == 64); // saved as raw bytes by p_saveg
}

pub const StairType = enum(c_uint) {
    build8,     // slowly build by 8
    turbo16,    // quickly build by 16
};

pub const MoveResult = enum(c_int) {
    Ok,
    Crushed,
    PastDest,
};

pub const MovePlane = enum(c_int) {
    Floor,
    Ceiling,
};

pub const MoveDirection = enum(c_int) {
    Down = -1,
    Up = 1,
};

pub fn T_MovePlane(
    sector: *c.sector_t,
    speed: fixed_t,
    dest: fixed_t,
    crush: c.boolean,
    floorOrCeiling: MovePlane,
    direction: MoveDirection,
) MoveResult {
    const height = switch (floorOrCeiling) {
        .Floor => &sector.floorheight,
        .Ceiling => &sector.ceilingheight,
    };
    const lastpos = height.*;

    const pastdest = switch (direction) {
        .Down => lastpos - speed < dest,
        .Up => lastpos + speed > dest,
    };

    if (pastdest) {
        height.* = dest;
        if (p_map.P_ChangeSector(sector, crush) != c.false) {
            height.* = lastpos;
            _ = p_map.P_ChangeSector(sector, crush);
        }
        return .PastDest;
    }

    height.* = switch (direction) {
        .Down => lastpos - speed,
        .Up => lastpos + speed,
    };

    if (p_map.P_ChangeSector(sector, crush) == c.false) return .Ok;

    // Something doesn't fit. A closing plane (floor up, ceiling down) keeps
    // going when crush is set, otherwise the move is undone.
    switch (floorOrCeiling) {
        .Floor => if (direction == .Up and crush != c.false) return .Crushed,
        .Ceiling => {
            // vanilla disabled the rising ceiling check with #if 0
            if (direction == .Up) return .Ok;
            if (crush != c.false) return .Crushed;
        },
    }

    height.* = lastpos;
    _ = p_map.P_ChangeSector(sector, crush);
    return .Crushed;
}

pub fn T_MoveFloor(floor: *Floor) callconv(.c) void {
    const res = T_MovePlane(floor.sector, floor.speed, floor.floordestheight, floor.crush, .Floor, floor.direction);

    if (@mod(p_tick.leveltime, 8) == 0) {
        s_sound.S_StartSound_Zig(@ptrCast(&floor.sector.soundorg), .stnmov);
    }

    if (res != .PastDest) return;

    floor.sector.specialdata = null;

    if ((floor.direction == .Up and floor.type == .donutRaise) or
        (floor.direction == .Down and floor.type == .lowerAndChange))
    {
        floor.sector.special = @intCast(floor.newspecial);
        floor.sector.floorpic = floor.texture;
    }

    p_tick.P_RemoveThinker(&floor.thinker);

    s_sound.S_StartSound_Zig(@ptrCast(&floor.sector.soundorg), .pstop);
}

fn minBottomTextureHeight(secnum: c_int, sec: *c.sector_t) fixed_t {
    var minsize: fixed_t = std.math.maxInt(fixed_t);
    var i: c_int = 0;
    while (i < sec.linecount) : (i += 1) {
        if (!p_spec.twoSided(secnum, i)) continue;
        for ([_]c_int{ 0, 1 }) |side| {
            const tex = p_spec.getSide(secnum, i, side).bottomtexture;
            if (tex >= 0) minsize = @min(minsize, c.textureheight[@intCast(tex)]);
        }
    }
    return minsize;
}

pub fn EV_DoFloor(line: *c.line_t, floortype: FloorType) bool {
    var secnum: c_int = -1;
    var rtn = false;

    while (true) {
        secnum = p_spec.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const sec = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (sec.specialdata != null) continue;

        // new floor thinker
        rtn = true;
        const floor = z_zone.create(Floor, .LevSpec, null);
        p_tick.P_AddThinker(&floor.thinker);
        sec.specialdata = floor;
        floor.thinker.function.acp1 = p_tick.thinkFn(Floor, &T_MoveFloor);
        floor.type = floortype;
        floor.sector = sec;
        floor.crush = if (floortype == .raiseFloorCrush) c.true else c.false;

        floor.direction = switch (floortype) {
            .lowerFloor, .lowerFloorToLowest, .turboLower, .lowerAndChange => .Down,
            else => .Up,
        };

        floor.speed = switch (floortype) {
            .turboLower, .raiseFloorTurbo => FLOORSPEED * 4,
            else => FLOORSPEED,
        };

        floor.floordestheight = switch (floortype) {
            .lowerFloor => p_spec.P_FindHighestFloorSurrounding(sec),
            .lowerFloorToLowest, .lowerAndChange => p_spec.P_FindLowestFloorSurrounding(sec),
            .turboLower => dest: {
                const dest = p_spec.P_FindHighestFloorSurrounding(sec);
                break :dest if (dest != sec.floorheight)
                    dest + 8 * FRACUNIT
                else
                    dest;
            },
            .raiseFloor, .raiseFloorCrush => dest: {
                const dest = @min(p_spec.P_FindLowestCeilingSurrounding(sec), sec.ceilingheight);
                break :dest if (floortype == .raiseFloorCrush)
                    dest - 8 * FRACUNIT
                else
                    dest;
            },
            .raiseFloorTurbo, .raiseFloorToNearest => p_spec.P_FindNextHighestFloor(sec, sec.floorheight),
            .raiseFloor24, .raiseFloor24AndChange => sec.floorheight + 24 * FRACUNIT,
            .raiseFloor512 => sec.floorheight + 512 * FRACUNIT,
            .raiseToTexture => sec.floorheight +% minBottomTextureHeight(secnum, sec),
            .donutRaise => unreachable, // EV_DoDonut builds its own floor thinkers
        };

        switch (floortype) {
            .raiseFloor24AndChange => {
                sec.floorpic = line.frontsector.*.floorpic;
                sec.special = line.frontsector.*.special;
            },
            .lowerAndChange => {
                floor.texture = sec.floorpic;

                // BUG: vanilla reuses sec for the neighbor sector here, so the
                // loop bound becomes the neighbor's linecount. Kept for demo sync.
                var s: *c.sector_t = sec;
                var i: c_int = 0;
                while (i < s.linecount) : (i += 1) {
                    if (!p_spec.twoSided(secnum, i)) continue;

                    const other: c_int = if (p_spec.getSide(secnum, i, 0).sector - p_setup.sectors == secnum) 1 else 0;
                    s = p_spec.getSector(secnum, i, other);
                    if (s.floorheight == floor.floordestheight) {
                        floor.texture = s.floorpic;
                        floor.newspecial = s.special;
                        break;
                    }
                }
            },
            else => {},
        }
    }

    return rtn;
}

pub fn EV_BuildStairs(line: *c.line_t, stairtype: StairType) bool {
    const speed: fixed_t, const stairsize: fixed_t = switch (stairtype) {
        .build8 => .{ FLOORSPEED / 4, 8 * FRACUNIT },
        .turbo16 => .{ FLOORSPEED * 4, 16 * FRACUNIT },
    };

    var secnum: c_int = -1;
    var rtn = false;
    while (true) {
        secnum = p_spec.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        var sec = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (sec.specialdata != null) continue;

        rtn = true;
        var height = sec.floorheight + stairsize;
        addStairStep(sec, speed, height);

        const texture = sec.floorpic;

        // Find next sector to raise
        // 1.   Find 2-sided line with same sector side[0]
        // 2.   Other side is the next sector to raise
        while (true) {
            for (sec.lines[0..@intCast(sec.linecount)]) |ln| {
                if (ln.*.flags & ML_TWOSIDED == 0) continue;
                if (ln.*.frontsector != sec) continue;

                const next: *c.sector_t = ln.*.backsector;
                if (next.floorpic != texture) continue;

                height += stairsize;

                if (next.specialdata != null) continue;

                sec = next;
                // BUG: P_FindSectorFromLineTag resumes from the last step's
                // sector number, so it skips tagged sectors numbered below it.
                secnum = @intCast(next - p_setup.sectors);
                addStairStep(sec, speed, height);
                break;
            } else break;
        }
    }

    return rtn;
}

fn addStairStep(sec: *c.sector_t, speed: fixed_t, destheight: fixed_t) void {
    const floor = z_zone.create(Floor, .LevSpec, null);
    p_tick.P_AddThinker(&floor.thinker);
    sec.specialdata = floor;
    floor.thinker.function.acp1 = p_tick.thinkFn(Floor, &T_MoveFloor);
    // Vanilla leaves type and crush uninitialized for stairs. Zone garbage
    // can't match vanilla's anyway, so give them the intended values.
    floor.type = .lowerFloor;
    floor.crush = c.false;
    floor.direction = .Up;
    floor.sector = sec;
    floor.speed = speed;
    floor.floordestheight = destheight;
}
