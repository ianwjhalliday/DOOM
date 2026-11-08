const c = @import("c");
const std = @import("std");

const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
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

pub const CeilingType = enum(c_uint) {
    lowerToFloor,
    raiseToHighest,
    lowerAndCrush,
    crushAndRaise,
    fastCrushAndRaise,
    silentCrushAndRaise,
};

pub const CeilingDirection = enum(c_int) {
    Down = -1,
    InStasis = 0,
    Up = 1,
};

/// extern so `thinker` stays at offset 0, since P_RunThinkers passes the
/// thinker pointer to T_MoveCeiling as a *Ceiling. p_saveg also saves this
/// struct as raw bytes, so reordering or retyping fields breaks savegames.
pub const Ceiling = extern struct {
    thinker: p_tick.Thinker,
    type: CeilingType,
    sector: *c.sector_t,
    bottomheight: fixed_t,
    topheight: fixed_t,
    speed: fixed_t,
    crush: c.boolean, // c.boolean is a 4-byte c_int, and a 1-byte bool would shift every later field in the saved layout.
    direction: CeilingDirection,
    tag: c_int,
    olddirection: CeilingDirection,
};

comptime {
    std.debug.assert(@sizeOf(Ceiling) == 72); // saved as raw bytes by p_saveg
}

pub fn T_MoveCeiling(ceil: *Ceiling) callconv(.c) void {
    switch (ceil.direction) {
        .InStasis => {},
        .Up => {
            const res = p_floor.T_MovePlane(ceil.sector, ceil.speed, ceil.topheight, c.false, .Ceiling, .Up);

            if (@mod(p_tick.leveltime, 8) == 0 and ceil.type != .silentCrushAndRaise) {
                s_sound.S_StartSound_Zig(@ptrCast(&ceil.sector.soundorg), .stnmov);
            }

            if (res == .PastDest) pastdest: switch (ceil.type) {
                .raiseToHighest => P_RemoveActiveCeiling(ceil),
                .silentCrushAndRaise => {
                    s_sound.S_StartSound_Zig(@ptrCast(&ceil.sector.soundorg), .pstop);
                    continue :pastdest .crushAndRaise;
                },
                .fastCrushAndRaise, .crushAndRaise => ceil.direction = .Down,
                .lowerAndCrush, .lowerToFloor => {},
            };
        },
        .Down => {
            const res = p_floor.T_MovePlane(ceil.sector, ceil.speed, ceil.bottomheight, ceil.crush, .Ceiling, .Down);

            if (@mod(p_tick.leveltime, 8) == 0 and ceil.type != .silentCrushAndRaise) {
                s_sound.S_StartSound_Zig(@ptrCast(&ceil.sector.soundorg), .stnmov);
            }

            if (res == .PastDest) pastdest: switch (ceil.type) {
                .silentCrushAndRaise => {
                    s_sound.S_StartSound_Zig(@ptrCast(&ceil.sector.soundorg), .pstop);
                    continue :pastdest .crushAndRaise;
                },
                .crushAndRaise => {
                    ceil.speed = CEILSPEED;
                    continue :pastdest .fastCrushAndRaise;
                },
                .fastCrushAndRaise => ceil.direction = .Up,
                .lowerAndCrush, .lowerToFloor => P_RemoveActiveCeiling(ceil),
                .raiseToHighest => {},
            } else if (res == .Crushed) switch (ceil.type) {
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
        const ceil = z_zone.create(Ceiling, .LevSpec, null);
        p_tick.P_AddThinker(&ceil.thinker);
        sec.specialdata = ceil;
        ceil.type = ceiltype;
        ceil.thinker.function.acp1 = p_tick.thinkFn(Ceiling, &T_MoveCeiling);
        ceil.sector = sec;
        ceil.crush = c.false;
        ceil.tag = sec.tag;

        init: switch (ceiltype) {
            .fastCrushAndRaise => {
                ceil.crush = c.true;
                ceil.topheight = sec.ceilingheight;
                ceil.bottomheight = sec.floorheight + 8 * FRACUNIT;
                ceil.direction = .Down;
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
                ceil.direction = .Down;
                ceil.speed = CEILSPEED;
            },
            .raiseToHighest => {
                ceil.topheight = p_spec.P_FindHighestCeilingSurrounding(sec);
                ceil.direction = .Up;
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
        if (ac.tag == line.tag and ac.direction != .InStasis) {
            ac.olddirection = ac.direction;
            ac.thinker.function.acv = null;
            ac.direction = .InStasis;
            rtn = true;
        }
    };

    return rtn;
}

pub var activeceilings: [MAXCEILINGS]?*Ceiling = @splat(null);

pub fn P_AddActiveCeiling(ceil: *Ceiling) void {
    for (&activeceilings) |*ac| {
        if (ac.* == null) {
            ac.* = ceil;
            return;
        }
    }
}

fn P_RemoveActiveCeiling(ceil: *Ceiling) void {
    for (&activeceilings) |*ac| {
        if (ceil == ac.*) {
            ceil.sector.specialdata = null;
            p_tick.P_RemoveThinker(&ceil.thinker);
            ac.* = null;
            return;
        }
    }
}

fn P_ActivateInStasisCeiling(line: *c.line_t) void {
    for (activeceilings) |ac_slot| if (ac_slot) |ac| {
        if (ac.tag == line.tag and ac.direction == .InStasis) {
            ac.direction = ac.olddirection;
            ac.thinker.function.acp1 = p_tick.thinkFn(Ceiling, &T_MoveCeiling);
        }
    };
}
