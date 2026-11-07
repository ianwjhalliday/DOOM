const c = @import("c");
const std = @import("std");

const doomdef = @import("doomdef.zig");
const g_game = @import("g_game.zig");
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const m_fixed = @import("m_fixed.zig");
const FRACBITS = m_fixed.FRACBITS;
const p_ceilng = @import("p_ceilng.zig");
const p_doors = @import("p_doors.zig");
const p_floor = @import("p_floor.zig");
const p_lights = @import("p_lights.zig");
const p_maputil = @import("p_maputil.zig");
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const p_plats = @import("p_plats.zig");
const p_setup = @import("p_setup.zig");
const p_tick = @import("p_tick.zig");
const z_zone = @import("z_zone.zig");


/// Vanilla pads to 4 bytes before each struct. The padding is part of the
/// file format; the bytes are copied, so buffer alignment doesn't matter.
fn padding(pos: usize) usize {
    return std.mem.alignForward(usize, pos, 4) - pos;
}

fn padWrite(writer: *std.Io.Writer) !void {
    try writer.splatByteAll(0, padding(writer.end));
}

fn padRead(reader: *std.Io.Reader) !void {
    try reader.discardAll(padding(reader.seek));
}

/// Pointer fields hold an index while in the file. Written as a usize so
/// @ptrFromInt's alignment check doesn't trip on odd indexes.
fn storeIndex(slot: anytype, index: usize) void {
    @as(*usize, @ptrCast(slot)).* = index;
}

fn loadIndex(slot: anytype) usize {
    return @as(*const usize, @ptrCast(slot)).*;
}

fn stateIndex(state: *const c.state_t) usize {
    return state - &c.states[0];
}

fn stateFromIndex(index: usize) !*c.state_t {
    if (index >= c.NUMSTATES) return error.BadSaveGame;
    return &c.states[index];
}

fn sectorIndex(sector: *const c.sector_t) usize {
    return sector - &p_setup.sectors_slice[0];
}

fn sectorFromIndex(index: usize) !*c.sector_t {
    if (index >= p_setup.sectors_slice.len) return error.BadSaveGame;
    return &p_setup.sectors_slice[index];
}

pub fn P_ArchivePlayers(writer: *std.Io.Writer) !void {
    for (g_game.playeringame, &g_game.players) |playeringame, *player| if (playeringame != c.false) {
        try padWrite(writer);
        var saved = player.*;
        for (&saved.psprites) |*psp| {
            if (psp.state != null) storeIndex(&psp.state, stateIndex(psp.state));
        }
        try writer.writeAll(std.mem.asBytes(&saved));
    };
}

pub fn P_UnArchivePlayers(reader: *std.Io.Reader) !void {
    for (g_game.playeringame, &g_game.players) |playeringame, *player| if (playeringame != c.false) {
        try padRead(reader);
        try reader.readSliceAll(std.mem.asBytes(player));
        // will be set when unarc thinker
        player.mo = null;
        player.message = null;
        player.attacker = null;
        for (&player.psprites) |*psp| {
            if (psp.state != null) {
                psp.state = try stateFromIndex(loadIndex(&psp.state));
            }
        }
    };
}

pub fn P_ArchiveWorld(writer: *std.Io.Writer) !void {
    for (p_setup.sectors_slice) |*sector| {
        // BUG: Heights are saved as whole map units. A sector saved
        // mid-move at a fractional height reloads snapped down a unit.
        try writer.writeInt(c_short, @intCast(sector.floorheight >> FRACBITS), .little);
        try writer.writeInt(c_short, @intCast(sector.ceilingheight >> FRACBITS), .little);
        try writer.writeInt(c_short, sector.floorpic, .little);
        try writer.writeInt(c_short, sector.ceilingpic, .little);
        try writer.writeInt(c_short, sector.lightlevel, .little);
        try writer.writeInt(c_short, sector.special, .little);
        try writer.writeInt(c_short, sector.tag, .little);
    }

    for (p_setup.lines_slice) |*line| {
        try writer.writeInt(c_short, line.flags, .little);
        try writer.writeInt(c_short, line.special, .little);
        try writer.writeInt(c_short, line.tag, .little);

        for (line.sidenum) |sidenum| if (sidenum != -1) {
            const side = &p_setup.sides[@intCast(sidenum)];

            try writer.writeInt(c_short, @intCast(side.textureoffset >> FRACBITS), .little);
            try writer.writeInt(c_short, @intCast(side.rowoffset >> FRACBITS), .little);
            try writer.writeInt(c_short, side.toptexture, .little);
            try writer.writeInt(c_short, side.bottomtexture, .little);
            try writer.writeInt(c_short, side.midtexture, .little);
        };
    }
}

pub fn P_UnArchiveWorld(reader: *std.Io.Reader) !void {
    for (p_setup.sectors_slice) |*sector| {
        sector.floorheight = @as(c_int, try reader.takeInt(c_short, .little)) << FRACBITS;
        sector.ceilingheight = @as(c_int, try reader.takeInt(c_short, .little)) << FRACBITS;
        sector.floorpic = try reader.takeInt(c_short, .little);
        sector.ceilingpic = try reader.takeInt(c_short, .little);
        sector.lightlevel = try reader.takeInt(c_short, .little);
        sector.special = try reader.takeInt(c_short, .little);
        sector.tag = try reader.takeInt(c_short, .little);
        sector.specialdata = null;
        sector.soundtarget = null;
    }

    for (p_setup.lines_slice) |*line| {
        line.flags = try reader.takeInt(c_short, .little);
        line.special = try reader.takeInt(c_short, .little);
        line.tag = try reader.takeInt(c_short, .little);

        for (line.sidenum) |sidenum| if (sidenum != -1) {
            const side = &p_setup.sides[@intCast(sidenum)];

            side.textureoffset = @as(c_int, try reader.takeInt(c_short, .little)) << FRACBITS;
            side.rowoffset = @as(c_int, try reader.takeInt(c_short, .little)) << FRACBITS;
            side.toptexture = try reader.takeInt(c_short, .little);
            side.bottomtexture = try reader.takeInt(c_short, .little);
            side.midtexture = try reader.takeInt(c_short, .little);
        };
    }
}

const ThinkerClass = enum(u8) {
    end,
    mobj,
};

pub fn P_ArchiveThinkers(writer: *std.Io.Writer) !void {
    var it = p_tick.mobj_thinkers();
    while (it.next()) |mo| {
        try writer.writeByte(@backingInt(ThinkerClass.mobj));
        try padWrite(writer);

        var saved = mo.*;
        // Never null: S_NULL removes the mobj, which takes it off mobj_thinker.
        storeIndex(&saved.state, stateIndex(saved.state.?));
        if (saved.player) |player| {
            storeIndex(&saved.player, player - &g_game.players[0] + 1);
        }
        try writer.writeAll(std.mem.asBytes(&saved));
    }
    try writer.writeByte(@backingInt(ThinkerClass.end));
}

pub fn P_UnArchiveThinkers(reader: *std.Io.Reader) !void {
    // remove all the current thinkers
    var it = p_tick.thinkers();
    while (it.next()) |th| {
        if (th.function.acp1 == p_mobj.mobj_thinker) {
            p_mobj.P_RemoveMobj(@ptrCast(th));
        } else {
            z_zone.destroy(th);
        }
    }
    p_tick.P_InitThinkers();

    // read in saved thinkers
    while (true) {
        const tclass = std.enums.fromInt(ThinkerClass, try reader.takeByte()) orelse return error.BadSaveGame;
        switch (tclass) {
            .end => return, // end of list
            .mobj => {
                try padRead(reader);

                const mo = z_zone.create(MObj, .Level, null);
                try reader.readSliceAll(std.mem.asBytes(mo));
                mo.state = try stateFromIndex(loadIndex(&mo.state));
                mo.target = null;
                // BUG: Vanilla leaves tracer pointing at the old address, so a
                // loaded revenant missile homes on whatever is there now.
                // Zone garbage can't match vanilla's anyway.
                mo.tracer = null;
                if (mo.player != null) {
                    const i = loadIndex(&mo.player);
                    if (i < 1 or i > doomdef.MAXPLAYERS) return error.BadSaveGame;
                    mo.player = &g_game.players[i - 1];
                    mo.player.?.mo = mo;
                }
                p_maputil.P_SetThingPosition(mo);
                mo.info = &c.mobjinfo[@intCast(mo.type)];
                mo.floorz = mo.subsector.sector.*.floorheight;
                mo.ceilingz = mo.subsector.sector.*.ceilingheight;
                mo.thinker.function.acp1 = p_mobj.mobj_thinker;
                p_tick.P_AddThinker(&mo.thinker);
            }
        }
    }
}

const SpecialKind = struct {
    T: type,
    think: c.actionf_p1,
    /// Sets sector.specialdata on load (floors and ceilings that move).
    owns_sector: bool,
};

/// Each kind's index is its tag in the file, so this order is the format.
/// BUG: Fire flickers are missing, so they are not saved and a loaded
/// sector stays at the light level it had when saved.
const specials = [_]SpecialKind{
    .{ .T = c.ceiling_t, .think = @ptrCast(&p_ceilng.T_MoveCeiling), .owns_sector = true },
    .{ .T = c.vldoor_t, .think = @ptrCast(&p_doors.T_VerticalDoor), .owns_sector = true },
    .{ .T = c.floormove_t, .think = @ptrCast(&p_floor.T_MoveFloor), .owns_sector = true },
    .{ .T = c.plat_t, .think = @ptrCast(&p_plats.T_PlatRaise), .owns_sector = true },
    .{ .T = c.lightflash_t, .think = @ptrCast(&p_lights.T_LightFlash), .owns_sector = false },
    .{ .T = c.strobe_t, .think = @ptrCast(&p_lights.T_StrobeFlash), .owns_sector = false },
    .{ .T = c.glow_t, .think = @ptrCast(&p_lights.T_Glow), .owns_sector = false },
};
const tc_ceiling = 0;
const tc_endspecials = specials.len;

fn archiveSpecial(writer: *std.Io.Writer, comptime tc: u8, th: *p_tick.Thinker) !void {
    const T = specials[tc].T;
    try writer.writeByte(tc);
    try padWrite(writer);
    var saved: T = @as(*const T, @ptrCast(th)).*;
    storeIndex(&saved.sector, sectorIndex(saved.sector));
    try writer.writeAll(std.mem.asBytes(&saved));
}

fn unarchiveSpecial(reader: *std.Io.Reader, comptime T: type) !*T {
    try padRead(reader);
    const s = z_zone.create(T, .Level, null);
    try reader.readSliceAll(std.mem.asBytes(s));
    s.sector = try sectorFromIndex(loadIndex(&s.sector));
    return s;
}

/// True if a thinker with a null function is a ceiling in stasis.
fn isActiveCeiling(th: *p_tick.Thinker) bool {
    const ceiling: *c.ceiling_t = @ptrCast(th);
    return std.mem.indexOfScalar(?*c.ceiling_t, &p_ceilng.activeceilings, ceiling) != null;
}

pub fn P_ArchiveSpecials(writer: *std.Io.Writer) !void {
    var it = p_tick.thinkers();
    thinkers: while (it.next()) |th| {
        if (th.function.acv == null) {
            // In stasis. Only ceilings are recognized.
            // BUG: Plats in stasis are dropped.
            if (isActiveCeiling(th)) try archiveSpecial(writer, tc_ceiling, th);
            continue;
        }
        inline for (specials, 0..) |kind, tc| {
            if (th.function.acp1 == kind.think) {
                try archiveSpecial(writer, tc, th);
                continue :thinkers;
            }
        }
    }
    try writer.writeByte(tc_endspecials);
}

pub fn P_UnArchiveSpecials(reader: *std.Io.Reader) !void {
    while (true) {
        const tc = try reader.takeByte();
        switch (tc) {
            tc_endspecials => return,
            inline 0...specials.len - 1 => |i| {
                const kind = specials[i];
                const s = try unarchiveSpecial(reader, kind.T);
                // Ceilings in stasis were saved with a null function. Every other
                // saved function pointer is a stale non-null address, so this
                // matches vanilla's per-kind handling.
                if (s.thinker.function.acp1 != null) s.thinker.function.acp1 = kind.think;
                if (kind.owns_sector) s.sector.*.specialdata = s;
                if (kind.T == c.ceiling_t) p_ceilng.P_AddActiveCeiling(s);
                if (kind.T == c.plat_t) p_plats.P_AddActivePlat(s);
                p_tick.P_AddThinker(@ptrCast(&s.thinker));
            },
            else => return error.BadSaveGame,
        }
    }
}
