const c = @import("c");
const std = @import("std");

const m_fixed = @import("m_fixed.zig");
const FRACUNIT = m_fixed.FRACUNIT;
const p_floor = @import("p_floor.zig");
const p_setup = @import("p_setup.zig");
const p_spec = @import("p_spec.zig");
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");
const z_zone = @import("z_zone.zig");

const CEILSPEED = FRACUNIT;
const CEILWAIT = 150;
const MAXCEILINGS = 30;

const CeilingType = enum(c_uint) {
    lowerToFloor,
    raiseToHighest,
    lowerAndCrush,
    crushAndRaise,
    fastCrushAndRaise,
    silentCrushAndRaise,
};

const CeilingDirection = enum(c_int) {
    Down = -1,
    InStasis = 0,
    Up = 1,
};

comptime {
    // While ceiling_e still exists in the C code ensure that our enum matches the ordering.
    for (@typeInfo(CeilingType).@"enum".field_names) |name| {
        if (@backingInt(@field(CeilingType, name)) != @field(c, name))
            @compileError("CeilingType." ++ name ++ " doesn't match C ceiling_e");
    }

    std.debug.assert(@backingInt(CeilingDirection.Down) == -1);
    std.debug.assert(@backingInt(CeilingDirection.InStasis) == 0);
    std.debug.assert(@backingInt(CeilingDirection.Up) == 1);
}

pub export fn T_MoveCeiling(ceil: *c.ceiling_t) void {
    const sector: *c.sector_t = ceil.sector;
    const ceildir: CeilingDirection = @fromBackingInt(ceil.direction);
    const ceiltype: CeilingType = @fromBackingInt(ceil.type);

    switch (ceildir) {
        .InStasis => {},
        .Up => {
            const res = p_floor.T_MovePlane(sector, ceil.speed, ceil.topheight, c.false, .Ceiling, .Up);

            if (@mod(p_tick.leveltime, 8) == 0 and
                ceiltype != .silentCrushAndRaise)
            {
                s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .stnmov);
            }

            if (res == .PastDest) pastdest: switch (ceiltype) {
                .raiseToHighest => P_RemoveActiveCeiling(ceil),
                .silentCrushAndRaise => {
                    s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .pstop);
                    continue :pastdest .crushAndRaise;
                },
                .fastCrushAndRaise,
                .crushAndRaise,
                => ceil.direction = @backingInt(CeilingDirection.Down),
                .lowerAndCrush, .lowerToFloor => {},
            };
        },
        .Down => {
            const res = p_floor.T_MovePlane(sector, ceil.speed, ceil.bottomheight, ceil.crush, .Ceiling, .Down);

            if (@mod(p_tick.leveltime, 8) == 0 and
                ceiltype != .silentCrushAndRaise)
            {
                s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .stnmov);
            }

            if (res == .PastDest) pastdest: switch (ceiltype) {
                .silentCrushAndRaise => {
                    s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .pstop);
                    continue :pastdest .crushAndRaise;
                },
                .crushAndRaise => {
                    ceil.speed = CEILSPEED;
                    continue :pastdest .fastCrushAndRaise;
                },
                .fastCrushAndRaise => ceil.direction = @backingInt(CeilingDirection.Up),
                .lowerAndCrush, .lowerToFloor => P_RemoveActiveCeiling(ceil),
                .raiseToHighest => {},
            } else if (res == .Crushed) switch (ceiltype) {
                .silentCrushAndRaise, .crushAndRaise, .lowerAndCrush => ceil.speed = CEILSPEED / 8,
                .fastCrushAndRaise, .lowerToFloor, .raiseToHighest => {},
            };
        },
    }
}

pub fn EV_DoCeiling(line: *c.line_t, ceiltype: CeilingType) bool {
    // Reactivate in-stasis ceilings for certain types.
    switch (ceiltype) {
        .fastCrushAndRaise, .silentCrushAndRaise, .crushAndRaise => P_ActivateInStasisCeiling(line),
        .lowerToFloor, .lowerAndCrush, .raiseToHighest => {},
    }

    var secnum: c_int = -1;
    var rtn = false;
    while (true) {
        secnum = p_spec.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const sec = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (sec.specialdata != null) continue;

        rtn = true;
        const ceil = z_zone.create(c.ceiling_t, .LevSpec, null);
        p_tick.P_AddThinker(@ptrCast(&ceil.thinker));
        sec.specialdata = ceil;
        ceil.type = @backingInt(ceiltype);
        ceil.thinker.function.acp1 = @ptrCast(&T_MoveCeiling);
        ceil.sector = sec;
        ceil.crush = c.false;
        ceil.tag = sec.tag;

        init: switch (ceiltype) {
            .fastCrushAndRaise => {
                ceil.crush = c.true;
                ceil.topheight = sec.ceilingheight;
                ceil.bottomheight = sec.floorheight + 8 * FRACUNIT;
                ceil.direction = @backingInt(CeilingDirection.Down);
                ceil.speed = CEILSPEED * 2;
            },
            .silentCrushAndRaise, .crushAndRaise => {
                ceil.crush = c.true;
                ceil.topheight = sec.ceilingheight;
                continue :init .lowerAndCrush;
            },
            .lowerAndCrush, .lowerToFloor => {
                ceil.bottomheight = sec.floorheight;
                if (ceiltype != .lowerToFloor) ceil.bottomheight += 8 * FRACUNIT;
                ceil.direction = @backingInt(CeilingDirection.Down);
                ceil.speed = CEILSPEED;
            },
            .raiseToHighest => {
                ceil.topheight = p_spec.P_FindHighestCeilingSurrounding(sec);
                ceil.direction = @backingInt(CeilingDirection.Up);
                ceil.speed = CEILSPEED;
            },
        }

        P_AddActiveCeiling(ceil);
    }

    return rtn;
}

pub fn EV_CeilingCrushStop(line: *c.line_t) bool {
    var rtn = false;
    for (activeceilings) |ac_slot| if (ac_slot) |ac| {
        if (ac.tag == line.tag and
            ac.direction != @backingInt(CeilingDirection.InStasis))
        {
            ac.olddirection = ac.direction;
            ac.thinker.function.acv = null;
            ac.direction = @backingInt(CeilingDirection.InStasis);
            rtn = true;
        }
    };

    return rtn;
}

pub export var activeceilings: [MAXCEILINGS]?*c.ceiling_t = @splat(null);

pub export fn P_AddActiveCeiling(ceil: *c.ceiling_t) void {
    for (&activeceilings) |*ac| {
        if (ac.* == null) {
            ac.* = ceil;
            return;
        }
    }
}

fn P_RemoveActiveCeiling(ceil: *c.ceiling_t) void {
    for (&activeceilings) |*ac| {
        if (ceil == ac.*) {
            ceil.sector.*.specialdata = null;
            p_tick.P_RemoveThinker(@ptrCast(&ceil.thinker));
            ac.* = null;
            return;
        }
    }
}

fn P_ActivateInStasisCeiling(line: *c.line_t) void {
    for (activeceilings) |ac_slot| if (ac_slot) |ac| {
        if (ac.tag == line.tag and
            ac.direction == @backingInt(CeilingDirection.InStasis))
        {
            ac.direction = ac.olddirection;
            ac.thinker.function.acp1 = @ptrCast(&T_MoveCeiling);
        }
    };
}
