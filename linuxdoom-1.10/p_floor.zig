const c = @import("c");
const std = @import("std");

const doomdata = @import("doomdata.zig");
const ML_TWOSIDED = doomdata.ML_TWOSIDED;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FRACUNIT = m_fixed.FRACUNIT;
const p_map = @import("p_map.zig");
const p_setup = @import("p_setup.zig");
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");
const z_zone = @import("z_zone.zig");

const FloorType = enum(c_uint) {
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

const StairType = enum(c_uint) {
    build8,     // slowly build by 8
    turbo16,    // quickly build by 16
};

comptime {
    // While floor_e still exists in the C code ensure that our enum matches the ordering.
    for (@typeInfo(FloorType).@"enum".field_names) |name| {
        if (@backingInt(@field(FloorType, name)) != @field(c, name))
            @compileError("FloorType." ++ name ++ " doesn't match C floor_e");
    }

    // Ditto for stair_e
    for (@typeInfo(StairType).@"enum".field_names) |name| {
        if (@backingInt(@field(StairType, name)) != @field(c, name))
            @compileError("StairType." ++ name ++ " doesn't match C stair_e");
    }
}

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

comptime {
    // While the equivalent enums still exist in the C code ensure ours match exactly.
    std.debug.assert(@backingInt(MoveResult.Ok) == c.ok);
    std.debug.assert(@backingInt(MoveResult.Crushed) == c.crushed);
    std.debug.assert(@backingInt(MoveResult.PastDest) == c.pastdest);
    std.debug.assert(@backingInt(MovePlane.Floor) == 0);
    std.debug.assert(@backingInt(MovePlane.Ceiling) == 1);
    std.debug.assert(@backingInt(MoveDirection.Down) == -1);
    std.debug.assert(@backingInt(MoveDirection.Up) == 1);
}

pub export fn T_MovePlane(
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

pub export fn T_MoveFloor(floor: *c.floormove_t) void {
    const sector: *c.sector_t = floor.sector;
    const dir: MoveDirection = @fromBackingInt(floor.direction);

    const res = T_MovePlane(sector, floor.speed, floor.floordestheight, floor.crush, .Floor, dir);

    if (@mod(p_tick.leveltime, 8) == 0) {
        s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .stnmov);
    }

    if (res != .PastDest) return;

    sector.specialdata = null;

    const typ: FloorType = @fromBackingInt(floor.type);
    if ((dir == .Up and typ == .donutRaise) or (dir == .Down and typ == .lowerAndChange)) {
        sector.special = @intCast(floor.newspecial);
        sector.floorpic = floor.texture;
    }

    p_tick.P_RemoveThinker(@ptrCast(&floor.thinker));

    s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .pstop);
}

fn minBottomTextureHeight(secnum: c_int, sec: *c.sector_t) fixed_t {
    var minsize: fixed_t = std.math.maxInt(fixed_t);
    var i: c_int = 0;
    while (i < sec.linecount) : (i += 1) {
        if (c.twoSided(secnum, i) == 0) continue;
        for ([_]c_int{ 0, 1 }) |side| {
            const tex = c.getSide(secnum, i, side).*.bottomtexture;
            if (tex >= 0) minsize = @min(minsize, c.textureheight[@intCast(tex)]);
        }
    }
    return minsize;
}

pub export fn EV_DoFloor(line: *c.line_t, floortype: FloorType) c_int {
    var secnum: c_int = -1;
    var rtn: c_int = 0;

    while (true) {
        secnum = c.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const sec = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (sec.specialdata != null) continue;

        // new floor thinker
        rtn = 1;
        const floor = z_zone.create(c.floormove_t, .LevSpec, null);
        p_tick.P_AddThinker(@ptrCast(&floor.thinker));
        sec.specialdata = floor;
        floor.thinker.function.acp1 = @ptrCast(&T_MoveFloor);
        floor.type = @backingInt(floortype);
        floor.sector = sec;
        floor.crush = if (floortype == .raiseFloorCrush) c.true else c.false;

        floor.direction = @backingInt(switch (floortype) {
            .lowerFloor, .lowerFloorToLowest, .turboLower, .lowerAndChange => MoveDirection.Down,
            else => MoveDirection.Up,
        });

        floor.speed = switch (floortype) {
            .turboLower, .raiseFloorTurbo => c.FLOORSPEED * 4,
            else => c.FLOORSPEED,
        };

        floor.floordestheight = switch (floortype) {
            .lowerFloor => c.P_FindHighestFloorSurrounding(sec),
            .lowerFloorToLowest, .lowerAndChange => c.P_FindLowestFloorSurrounding(sec),
            .turboLower => dest: {
                const dest = c.P_FindHighestFloorSurrounding(sec);
                break :dest if (dest != sec.floorheight)
                    dest + 8 * FRACUNIT
                else
                    dest;
            },
            .raiseFloor, .raiseFloorCrush => dest: {
                const dest = @min(c.P_FindLowestCeilingSurrounding(sec), sec.ceilingheight);
                break :dest if (floortype == .raiseFloorCrush)
                    dest - 8 * FRACUNIT
                else
                    dest;
            },
            .raiseFloorTurbo, .raiseFloorToNearest => c.P_FindNextHighestFloor(sec, sec.floorheight),
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
                    if (c.twoSided(secnum, i) == 0) continue;

                    const other: c_int = if (c.getSide(secnum, i, 0).*.sector - p_setup.sectors == secnum) 1 else 0;
                    s = c.getSector(secnum, i, other);
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

pub export fn EV_BuildStairs(line: *c.line_t, stairtype: StairType) c_int {
    const speed: fixed_t, const stairsize: fixed_t = switch (stairtype) {
        .build8 => .{ c.FLOORSPEED / 4, 8 * FRACUNIT },
        .turbo16 => .{ c.FLOORSPEED * 4, 16 * FRACUNIT },
    };

    var secnum: c_int = -1;
    var rtn: c_int = 0;
    while (true) {
        secnum = c.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        var sec = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (sec.specialdata != null) continue;

        rtn = 1;
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
    const floor = z_zone.create(c.floormove_t, .LevSpec, null);
    p_tick.P_AddThinker(@ptrCast(&floor.thinker));
    sec.specialdata = floor;
    floor.thinker.function.acp1 = @ptrCast(&T_MoveFloor);
    // Vanilla leaves type and crush uninitialized for stairs. Zone garbage
    // can't match vanilla's anyway, so give them the intended values.
    floor.type = @backingInt(FloorType.lowerFloor);
    floor.crush = c.false;
    floor.direction = @backingInt(MoveDirection.Up);
    floor.sector = sec;
    floor.speed = speed;
    floor.floordestheight = destheight;
}
