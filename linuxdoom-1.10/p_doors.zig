const c = @import("c");
const std = @import("std");

const d_player = @import("d_player.zig");
const Player = d_player.Player;
const doomdef = @import("doomdef.zig");
const Card = doomdef.Card;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FRACUNIT = m_fixed.FRACUNIT;
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const p_floor = @import("p_floor.zig");
const p_setup = @import("p_setup.zig");
const p_spec = @import("p_spec.zig");
const p_tick = @import("p_tick.zig");
const T_MovePlane = p_floor.T_MovePlane;
const s_sound = @import("s_sound.zig");
const sounds = @import("sounds.zig");
const Sfx = sounds.Sfx;
const z_zone = @import("z_zone.zig");

const VDOORSPEED = FRACUNIT * 2;
const VDOORWAIT = 150;

const DoorDirection = enum(c_int) {
    Down = -1,
    Waiting = 0,
    Up = 1,
    InitialWait = 2,
};

const DoorType = enum(c_uint) {
    normal,
    close30ThenOpen,
    close,
    open,
    raiseIn5Mins,
    blazeRaise,
    blazeOpen,
    blazeClose,
};

comptime {
    // While vldoor_e still exists in the C code ensure that our enum matches the ordering.
    for (@typeInfo(DoorType).@"enum".field_names) |name| {
        if (@backingInt(@field(DoorType, name)) != @field(c, name))
            @compileError("DoorType." ++ name ++ " doesn't match C vldoor_e");
    }

    std.debug.assert(@backingInt(DoorDirection.Down) == -1);
    std.debug.assert(@backingInt(DoorDirection.Waiting) == 0);
    std.debug.assert(@backingInt(DoorDirection.Up) == 1);
    std.debug.assert(@backingInt(DoorDirection.InitialWait) == 2);
}

const Lock = struct {
    card: Card,
    skull: Card,
    message: [*:0]const u8,
};

fn setDoorDirection(door: *c.vldoor_t, dir: DoorDirection, sfx: Sfx) void {
    door.direction = @backingInt(dir);
    s_sound.S_StartSound_Zig(@ptrCast(&door.sector.*.soundorg), sfx);
}

fn removeDoor(door: *c.vldoor_t) void {
    door.sector.*.specialdata = null;
    p_tick.P_RemoveThinker(@ptrCast(&door.thinker)); // unlink and free
}

fn waitAtTop(door: *c.vldoor_t, tics: c_int) void {
    door.direction = @backingInt(DoorDirection.Waiting);
    door.topcountdown = tics;
}

pub export fn T_VerticalDoor(door: *c.vldoor_t) void {
    const sector: *c.sector_t = door.sector;
    const doordir: DoorDirection = @fromBackingInt(door.direction);
    const doortype: DoorType = @fromBackingInt(door.type);

    switch (doordir) {
        .Waiting => {
            door.topcountdown -= 1;
            if (door.topcountdown == 0) switch (doortype) {
                .blazeRaise => setDoorDirection(door, .Down, .bdcls),
                .normal => setDoorDirection(door, .Down, .dorcls),
                .close30ThenOpen => setDoorDirection(door, .Up, .doropn),
                else => {},
            };
        },
        .InitialWait => {
            door.topcountdown -= 1;
            if (door.topcountdown == 0 and doortype == .raiseIn5Mins) {
                door.type = @backingInt(DoorType.normal);
                setDoorDirection(door, .Up, .doropn);
            }
        },
        .Down => {
            const res = T_MovePlane(sector, door.speed, sector.floorheight, c.false, .Ceiling, .Down);
            if (res == .PastDest) switch (doortype) {
                .blazeRaise, .blazeClose => {
                    removeDoor(door);
                    // BUG: Vanilla plays bdcls again on landing, after the one at close start.
                    s_sound.S_StartSound_Zig(@ptrCast(&sector.soundorg), .bdcls);
                },
                .normal, .close => removeDoor(door),
                .close30ThenOpen => waitAtTop(door, 35 * 30),
                .open, .raiseIn5Mins, .blazeOpen => {},
            } else if (res == .Crushed) switch (doortype) {
                .blazeClose, .close => {}, // Do not go back up
                else => setDoorDirection(door, .Up, .doropn),
            };
        },
        .Up => {
            const res = T_MovePlane(sector, door.speed, door.topheight, c.false, .Ceiling, .Up);
            if (res == .PastDest) switch (doortype) {
                .blazeRaise, .normal => waitAtTop(door, door.topwait),
                .close30ThenOpen, .blazeOpen, .open => removeDoor(door),
                .close, .raiseIn5Mins, .blazeClose => {},
            };
        },
    }
}

// Either key opens the lock. Without one, the player gets told why.
fn checkLock(player: *Player, lock: Lock) bool {
    if (player.hasCard(lock.card) or player.hasCard(lock.skull)) return true;
    player.message = lock.message;
    s_sound.S_StartSound_Zig(null, .oof);
    return false;
}

pub fn EV_DoLockedDoor(line: *c.line_t, doortype: DoorType, thing: *MObj) bool {
    const p = thing.player orelse return false;

    const lock: Lock = switch (line.special) {
        99, 133 => .{ .card = .BlueCard, .skull = .BlueSkull, .message = c.PD_BLUEO },
        134, 135 => .{ .card = .RedCard, .skull = .RedSkull, .message = c.PD_REDO },
        136, 137 => .{ .card = .YellowCard, .skull = .YellowSkull, .message = c.PD_YELLOWO },
        else => return EV_DoDoor(line, doortype), // not locked
    };

    if (!checkLock(p, lock)) return false;
    return EV_DoDoor(line, doortype);
}

/// Doors open to 4 units below the lowest surrounding ceiling.
fn doorOpenHeight(sector: *c.sector_t) fixed_t {
    return p_spec.P_FindLowestCeilingSurrounding(sector) - 4 * FRACUNIT;
}

pub fn EV_DoDoor(line: *c.line_t, doortype: DoorType) bool {
    var secnum: c_int = -1;
    var rtn = false;
    while (true) {
        secnum = p_spec.P_FindSectorFromLineTag(line, secnum);
        if (secnum < 0) break;

        const sec = &p_setup.sectors_slice[@intCast(secnum)];

        if (sec.specialdata != null) continue;

        // new door thinker
        rtn = true;
        const door = z_zone.create(c.vldoor_t, .LevSpec, null);
        p_tick.P_AddThinker(@ptrCast(&door.thinker));
        sec.specialdata = door;

        door.thinker.function.acp1 = @ptrCast(&T_VerticalDoor);
        door.sector = sec;
        door.type = @backingInt(doortype);
        door.topwait = VDOORWAIT;

        door.topheight, const direction: DoorDirection, door.speed, const sfx: Sfx = switch (doortype) {
            .blazeClose => .{ doorOpenHeight(sec), .Down, VDOORSPEED * 4, .bdcls },
            .close => .{ doorOpenHeight(sec), .Down, VDOORSPEED, .dorcls },
            .close30ThenOpen => .{ sec.ceilingheight, .Down, VDOORSPEED, .dorcls },
            .blazeRaise, .blazeOpen => .{ doorOpenHeight(sec), .Up, VDOORSPEED * 4, .bdopn },
            .normal, .open => .{ doorOpenHeight(sec), .Up, VDOORSPEED, .doropn },
            .raiseIn5Mins => unreachable,
        };

        door.direction = @backingInt(direction);
        // An opening door that is already fully open stays silent.
        if (direction != .Up or door.topheight != sec.ceilingheight) {
            s_sound.S_StartSound_Zig(@ptrCast(&sec.soundorg), sfx);
        }
    }

    return rtn;
}

pub fn EV_VerticalDoor(line: *c.line_t, thing: *MObj) void {
    const blue: Lock = .{ .card = .BlueCard, .skull = .BlueSkull, .message = c.PD_BLUEK };
    const yellow: Lock = .{ .card = .YellowCard, .skull = .YellowSkull, .message = c.PD_YELLOWK };
    const red: Lock = .{ .card = .RedCard, .skull = .RedSkull, .message = c.PD_REDK };

    // Map the special to its door type and whether or not it needs a key
    const doortype: DoorType, const lock: ?Lock = switch (line.special) {
        1 => .{ .normal, null },
        26 => .{ .normal, blue },
        27 => .{ .normal, yellow },
        28 => .{ .normal, red },
        31 => .{ .open, null },
        32 => .{ .open, blue },
        33 => .{ .open, red },
        34 => .{ .open, yellow },
        117 => .{ .blazeRaise, null },
        118 => .{ .blazeOpen, null },
        else => unreachable, // P_UseSpecialLine only calls this for the specials above
    };
    const blaze = doortype == .blazeRaise or doortype == .blazeOpen;

    if (lock) |l| {
        const player = thing.player orelse return;
        if (!checkLock(player, l)) return;
    }

    // Only front sides can be used, so the door is the sector behind the line.
    const sec: *c.sector_t = p_setup.sides[@intCast(line.sidenum[1])].sector;

    // If the sector has an active thinker, use it
    if (sec.specialdata) |data| switch (doortype) {
        // Only for "raise" doors, not "open"s
        .normal, .blazeRaise => {
            // BUG: specialdata may be a plat, floor or ceiling thinker, and vanilla
            // writes direction into it regardless. Compare raw so a non-door value
            // can't panic @fromBackingInt.
            const door: *c.vldoor_t = @ptrCast(@alignCast(data));
            if (door.direction == @backingInt(DoorDirection.Down)) {
                door.direction = @backingInt(DoorDirection.Up); // go back up
            } else {
                if (thing.player == null) return; // JDC: bad guys never close doors
                door.direction = @backingInt(DoorDirection.Down); // start going down immediately
            }
            return;
        },
        // BUG: an open door falls through and stacks a second thinker on the sector.
        else => {},
    };

    s_sound.S_StartSound_Zig(@ptrCast(&sec.soundorg), if (blaze) .bdopn else .doropn);

    const door = z_zone.create(c.vldoor_t, .LevSpec, null);
    p_tick.P_AddThinker(@ptrCast(&door.thinker));
    sec.specialdata = door;
    door.thinker.function.acp1 = @ptrCast(&T_VerticalDoor);
    door.sector = sec;
    door.type = @backingInt(doortype);
    door.direction = @backingInt(DoorDirection.Up);
    door.speed = if (blaze) VDOORSPEED * 4 else VDOORSPEED;
    door.topwait = VDOORWAIT;
    door.topheight = doorOpenHeight(sec);

    // Open doors only work once
    if (doortype == .open or doortype == .blazeOpen) line.special = 0;
}

pub fn P_SpawnDoorCloseIn30(sec: *c.sector_t) void {
    const door = z_zone.create(c.vldoor_t, .LevSpec, null);

    p_tick.P_AddThinker(@ptrCast(&door.thinker));

    sec.specialdata = door;
    sec.special = 0;

    door.thinker.function.acp1 = @ptrCast(&T_VerticalDoor);
    door.sector = sec;
    door.direction = @backingInt(DoorDirection.Waiting);
    door.type = @backingInt(DoorType.normal);
    door.speed = VDOORSPEED;
    // BUG: vanilla leaves topheight and topwait unset, and a blocked door
    // reopens to them. Zone garbage can't match vanilla's anyway, so reopen
    // to the starting height and wait the usual time.
    door.topheight = sec.ceilingheight;
    door.topwait = VDOORWAIT;
    door.topcountdown = 30 * 35;
}

pub fn P_SpawnDoorRaiseIn5Mins(sec: *c.sector_t) void {
    const door = z_zone.create(c.vldoor_t, .LevSpec, null);

    p_tick.P_AddThinker(@ptrCast(&door.thinker));

    sec.specialdata = door;
    sec.special = 0;

    door.thinker.function.acp1 = @ptrCast(&T_VerticalDoor);
    door.sector = sec;
    door.direction = @backingInt(DoorDirection.InitialWait);
    door.type = @backingInt(DoorType.raiseIn5Mins);
    door.speed = VDOORSPEED;
    door.topheight = doorOpenHeight(sec);
    door.topwait = VDOORWAIT;
    door.topcountdown = 5 * 60 * 35;
}
