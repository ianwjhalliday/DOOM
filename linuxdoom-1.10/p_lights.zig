const c = @import("c");

const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_setup = @import("p_setup.zig");
const p_spec = @import("p_spec.zig");
const p_tick = @import("p_tick.zig");
const z_zone = @import("z_zone.zig");

const GLOWSPEED = 8;
const STROBEBRIGHT = 5;
pub const FASTDARK = 15;
pub const SLOWDARK = 35;

const GlowDirection = enum(c_int) {
    Down = -1,
    Up = 1,
};

const FireFlicker = extern struct {
    thinker: c.thinker_t,
    sector: *c.sector_t,
    count: c_int,
    maxlight: c_int,
    minlight: c_int,
};

fn T_FireFlicker(flick: *FireFlicker) void {
    const sector: *c.sector_t = flick.sector;

    flick.count -= 1;
    if (flick.count != 0) return;

    const amount = @mod(P_Random(), 4) * 16;

    if (sector.lightlevel - amount < flick.minlight) {
        sector.lightlevel = @intCast(flick.minlight);
    } else {
        sector.lightlevel = @intCast(flick.maxlight - amount);
    }

    flick.count = 4;
}

pub fn P_SpawnFireFlicker(sector: *c.sector_t) void {
    // Note that we are resetting sector attributes.
    // Nothing special about it during gameplay.
    sector.special = 0;

    const flick = z_zone.create(FireFlicker, .LevSpec, null);

    p_tick.P_AddThinker(@ptrCast(&flick.thinker));

    flick.thinker.function.acp1 = @ptrCast(&T_FireFlicker);
    flick.sector = sector;
    flick.maxlight = sector.lightlevel;
    flick.minlight = p_spec.P_FindMinSurroundingLight(sector, sector.lightlevel) + 16;
    flick.count = 4;
}

pub export fn T_LightFlash(flash: *c.lightflash_t) void {
    const sector: *c.sector_t = flash.sector;

    flash.count -= 1;
    if (flash.count != 0) return;

    if (sector.lightlevel == flash.maxlight) {
        sector.lightlevel = @intCast(flash.minlight);
        flash.count = (P_Random() & flash.mintime) + 1;
    } else {
        sector.lightlevel = @intCast(flash.maxlight);
        flash.count = (P_Random() & flash.maxtime) + 1;
    }
}

pub fn P_SpawnLightFlash(sector: *c.sector_t) void {
    // nothing special about it during gameplay
    sector.special = 0;

    const flash = z_zone.create(c.lightflash_t, .LevSpec, null);

    p_tick.P_AddThinker(@ptrCast(&flash.thinker));

    flash.thinker.function.acp1 = @ptrCast(&T_LightFlash);
    flash.sector = sector;
    flash.maxlight = sector.lightlevel;
    flash.minlight = p_spec.P_FindMinSurroundingLight(sector, sector.lightlevel);
    // BUG: 64 isn't a 2^n-1 mask like mintime's 7, so P_Random() & maxtime
    // is 0 or 64 and the bright phase lasts 1 or 65 tics, not 1 to 64.
    flash.maxtime = 64;
    flash.mintime = 7;
    flash.count = (P_Random() & flash.maxtime) + 1;
}

pub export fn T_StrobeFlash(flash: *c.strobe_t) void {
    const sector: *c.sector_t = flash.sector;

    flash.count -= 1;
    if (flash.count != 0) return;

    if (sector.lightlevel == flash.minlight) {
        sector.lightlevel = @intCast(flash.maxlight);
        flash.count = flash.brighttime;
    } else {
        sector.lightlevel = @intCast(flash.minlight);
        flash.count = flash.darktime;
    }
}

pub fn P_SpawnStrobeFlash(sector: *c.sector_t, fastOrSlow: c_int, inSync: bool) void {
    const flash = z_zone.create(c.strobe_t, .LevSpec, null);

    p_tick.P_AddThinker(@ptrCast(&flash.thinker));

    flash.sector = sector;
    flash.darktime = fastOrSlow;
    flash.brighttime = STROBEBRIGHT;
    flash.thinker.function.acp1 = @ptrCast(&T_StrobeFlash);
    flash.maxlight = sector.lightlevel;
    flash.minlight = p_spec.P_FindMinSurroundingLight(sector, sector.lightlevel);

    if (flash.minlight == flash.maxlight) flash.minlight = 0;

    // nothing special about it during gameplay
    sector.special = 0;

    flash.count = if (inSync) 1 else @mod(P_Random(), 8) + 1;
}

pub fn EV_StartLightStrobing(line: *c.line_t) void {
    var secnum: c_int = -1;
    while (true) {
        secnum = p_spec.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const sec = &p_setup.sectors_slice[@intCast(secnum)];

        if (sec.specialdata != null) continue;

        P_SpawnStrobeFlash(sec, SLOWDARK, false);
    }
}

pub fn EV_TurnTagLightsOff(line: *c.line_t) void {
    for (p_setup.sectors_slice) |*sector| if (sector.tag == line.tag) {
        var min = sector.lightlevel;
        for (sector.lines[0..@intCast(sector.linecount)]) |l| {
            const s = p_spec.getNextSector(l, sector) orelse continue;
            min = @min(min, s.lightlevel);
        }
        sector.lightlevel = min;
    };
}

pub fn EV_LightTurnOn(line: *c.line_t, brightness: c_int) void {
    var bright = brightness;
    for (p_setup.sectors_slice) |*sector| if (sector.tag == line.tag) {
        // bright = 0 means to search for highest light level surrounding sector
        // BUG: bright isn't reset per sector, so only the first tagged
        // sector searches its neighbors and the rest reuse its result.
        if (bright == 0) {
            for (sector.lines[0..@intCast(sector.linecount)]) |l| {
                const s = p_spec.getNextSector(l, sector) orelse continue;
                bright = @max(bright, s.lightlevel);
            }
        }

        sector.lightlevel = @intCast(bright);
    };
}

pub export fn T_Glow(g: *c.glow_t) void {
    const sector: *c.sector_t = g.sector;
    const glowdir: GlowDirection = @fromBackingInt(g.direction);

    switch (glowdir) {
        .Down => {
            sector.lightlevel -= GLOWSPEED;
            if (sector.lightlevel <= g.minlight) {
                sector.lightlevel += GLOWSPEED;
                g.direction = @backingInt(GlowDirection.Up);
            }
        },
        .Up => {
            sector.lightlevel += GLOWSPEED;
            if (sector.lightlevel >= g.maxlight) {
                sector.lightlevel -= GLOWSPEED;
                g.direction = @backingInt(GlowDirection.Down);
            }
        },
    }
}

pub fn P_SpawnGlowingLight(sector: *c.sector_t) void {
    const g = z_zone.create(c.glow_t, .LevSpec, null);

    p_tick.P_AddThinker(@ptrCast(&g.thinker));

    g.sector = sector;
    g.minlight = p_spec.P_FindMinSurroundingLight(sector, sector.lightlevel);
    g.maxlight = sector.lightlevel;
    g.thinker.function.acp1 = @ptrCast(&T_Glow);
    g.direction = @backingInt(GlowDirection.Down);

    sector.special = 0;
}
