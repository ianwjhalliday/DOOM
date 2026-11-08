const c = @import("c");
const std = @import("std");

const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FRACUNIT = m_fixed.FRACUNIT;
const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_floor = @import("p_floor.zig");
const T_MovePlane = p_floor.T_MovePlane;
const p_setup = @import("p_setup.zig");
const p_spec = @import("p_spec.zig");
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");
const sounds = @import("sounds.zig");
const Sfx = sounds.Sfx;
const z_zone = @import("z_zone.zig");

const PLATWAIT = 3;
const PLATSPEED = FRACUNIT;
const MAXPLATS = 30;

pub const PlatType = enum(c_uint) {
    perpetualRaise,
    downWaitUpStay,
    raiseAndChange,
    raiseToNearestAndChange,
    blazeDWUS,
};

pub const PlatStatus = enum(c_uint) {
    Up,
    Down,
    Waiting,
    InStasis,
};

/// extern so `thinker` stays at offset 0, since P_RunThinkers passes the
/// thinker pointer to T_PlatRaise as a *Plat. p_saveg also saves this
/// struct as raw bytes, so reordering or retyping fields breaks savegames.
pub const Plat = extern struct {
    thinker: p_tick.Thinker,
    sector: *c.sector_t,
    speed: fixed_t,
    low: fixed_t,
    high: fixed_t,
    wait: c_int,
    count: c_int,
    status: PlatStatus,
    oldstatus: PlatStatus,
    crush: c.boolean, // c.boolean is a 4-byte c_int, and a 1-byte bool would shift every later field in the saved layout.
    tag: c_int,
    type: PlatType,
};

comptime {
    std.debug.assert(@sizeOf(Plat) == 72); // saved as raw bytes by p_saveg
}

fn setPlatStatus(plat: *Plat, count: c_int, status: PlatStatus, sfx: Sfx) void {
    plat.count = count;
    plat.status = status;
    s_sound.S_StartSound_Zig(@ptrCast(&plat.sector.soundorg), sfx);
}

pub fn T_PlatRaise(plat: *Plat) callconv(.c) void {
    switch (plat.status) {
        .Up => {
            const res = T_MovePlane(plat.sector, plat.speed, plat.high, plat.crush, .Floor, .Up);

            if (plat.type == .raiseAndChange or plat.type == .raiseToNearestAndChange) {
                if (@mod(p_tick.leveltime, 8) == 0) {
                    s_sound.S_StartSound_Zig(@ptrCast(&plat.sector.soundorg), .stnmov);
                }
            }

            switch (res) {
                .Crushed => if (plat.crush == c.false)
                    setPlatStatus(plat, plat.wait, .Down, .pstart),
                .PastDest => {
                    setPlatStatus(plat, plat.wait, .Waiting, .pstop);

                    switch (plat.type) {
                        .blazeDWUS,
                        .downWaitUpStay,
                        .raiseAndChange,
                        .raiseToNearestAndChange,
                        => P_RemoveActivePlat(plat),
                        .perpetualRaise => {},
                    }
                },
                .Ok => {},
            }
        },
        .Down => {
            const res = T_MovePlane(plat.sector, plat.speed, plat.low, c.false, .Floor, .Down);
            if (res == .PastDest) {
                setPlatStatus(plat, plat.wait, .Waiting, .pstop);
            }
        },
        .Waiting => {
            plat.count -= 1;
            if (plat.count == 0) {
                setPlatStatus(
                    plat,
                    plat.count, // no change
                    if (plat.sector.floorheight == plat.low) .Up else .Down,
                    .pstart,
                );
            }
        },
        .InStasis => {},
    }
}

const PlatInit = struct {
    speed: fixed_t,
    low: fixed_t,
    high: fixed_t,
    wait: c_int,
    status: PlatStatus,
    sfx: Sfx,
};

fn initPlat(plat: *Plat, init: PlatInit) void {
    plat.speed = init.speed;
    plat.low = init.low;
    plat.high = init.high;
    plat.wait = init.wait;
    plat.status = init.status;
    s_sound.S_StartSound_Zig(@ptrCast(&plat.sector.soundorg), init.sfx);
}

pub fn EV_DoPlat(line: *c.line_t, plattype: PlatType, amount: c_int) bool {
    if (plattype == .perpetualRaise) P_ActivateInStasis(line.tag);

    var secnum: c_int = -1;
    var rtn = false;
    while (true) {
        secnum = p_spec.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const sec = &p_setup.sectors_slice[@intCast(secnum)];

        // Already moving? If so, keep going...
        if (sec.specialdata != null) continue;

        rtn = true;
        const plat = z_zone.create(Plat, .LevSpec, null);
        p_tick.P_AddThinker(&plat.thinker);

        sec.specialdata = plat;
        plat.type = plattype;
        plat.sector = sec;
        plat.thinker.function.acp1 = p_tick.thinkFn(Plat, &T_PlatRaise);
        plat.crush = c.false;
        plat.tag = line.tag;

        switch (plattype) {
            .raiseAndChange,
            .raiseToNearestAndChange,
            => {
                sec.floorpic = p_setup.sides[@intCast(line.sidenum[0])].sector.*.floorpic;
                const high = if (plattype == .raiseAndChange)
                    sec.floorheight + amount * FRACUNIT
                else high: {
                    sec.special = 0; // No more damage, if applicable
                    break :high p_spec.P_FindNextHighestFloor(sec, sec.floorheight);
                };
                initPlat(plat, .{
                    .speed = PLATSPEED / 2,
                    // BUG: vanilla leaves low unset for the AndChange types, and a blocked
                    // plat reverses down to it. Zone garbage can't match vanilla's anyway,
                    // so use the starting height.
                    .low = sec.floorheight,
                    .high = high,
                    .wait = 0,
                    .status = .Up,
                    .sfx = .stnmov,
                });
            },
            .downWaitUpStay, .blazeDWUS => initPlat(plat, .{
                .speed = if (plattype == .blazeDWUS) PLATSPEED * 8 else PLATSPEED * 4,
                .low = @min(sec.floorheight, p_spec.P_FindLowestFloorSurrounding(sec)),
                .high = sec.floorheight,
                .wait = 35 * PLATWAIT,
                .status = .Down,
                .sfx = .pstart,
            }),
            .perpetualRaise => initPlat(plat, .{
                .speed = PLATSPEED,
                .low = @min(sec.floorheight, p_spec.P_FindLowestFloorSurrounding(sec)),
                .high = @max(sec.floorheight, p_spec.P_FindHighestFloorSurrounding(sec)),
                .wait = 35 * PLATWAIT,
                .status = if (@mod(P_Random(), 2) == 0) .Up else .Down,
                .sfx = .pstart,
            }),
        }

        P_AddActivePlat(plat);
    }

    return rtn;
}

pub fn EV_StopPlat(line: *c.line_t) void {
    for (activeplats) |ap_slot| if (ap_slot) |ap| {
        if (ap.tag == line.tag and ap.status != .InStasis) {
            ap.oldstatus = ap.status;
            ap.status = .InStasis;
            ap.thinker.function.acv = null;
        }
    };
}

pub var activeplats: [MAXPLATS]?*Plat = @splat(null);

fn P_ActivateInStasis(tag: c_int) void {
    for (activeplats) |ap_slot| if (ap_slot) |ap| {
        if (ap.tag == tag and ap.status == .InStasis) {
            ap.status = ap.oldstatus;
            ap.thinker.function.acp1 = p_tick.thinkFn(Plat, &T_PlatRaise);
        }
    };
}

pub fn P_AddActivePlat(plat: *Plat) void {
    for (&activeplats) |*ap| {
        if (ap.* == null) {
            ap.* = plat;
            return;
        }
    }
    I_Error("P_AddActivePlat: no more plats!");
}

fn P_RemoveActivePlat(plat: *Plat) void {
    for (&activeplats) |*ap| {
        if (plat == ap.*) {
            plat.sector.specialdata = null;
            p_tick.P_RemoveThinker(&plat.thinker);
            ap.* = null;
            return;
        }
    }
    I_Error("P_RemoveActivePlat: can't find plat!");
}
