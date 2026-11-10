const c = @import("c");
const std = @import("std");

const d_player = @import("d_player.zig");
const Player = d_player.Player;
const d_strings = @import("d_strings.zig");
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

pub const DoorDirection = enum(c_int) {
    Down = -1,
    Waiting = 0,
    Up = 1,
    InitialWait = 2,
};

pub const DoorType = enum(c_uint) {
    normal,
    close30ThenOpen,
    close,
    open,
    raiseIn5Mins,
    blazeRaise,
    blazeOpen,
    blazeClose,
};

/// extern so `thinker` stays at offset 0, since P_RunThinkers passes the
/// thinker pointer to T_VerticalDoor as a *Door. p_saveg also saves this
/// struct as raw bytes, so reordering or retyping fields breaks savegames.
pub const Door = extern struct {
    thinker: p_tick.Thinker,
    type: DoorType,
    sector: *c.sector_t,
    topheight: fixed_t,
    speed: fixed_t,
    direction: DoorDirection,
    topwait: c_int,
    topcountdown: c_int,
};

comptime {
    std.debug.assert(@sizeOf(Door) == 64); // saved as raw bytes by p_saveg
}

const Lock = struct {
    card: Card,
    skull: Card,
    message: [*:0]const u8,
};

fn setDoorDirection(door: *Door, dir: DoorDirection, sfx: Sfx) void {
    door.direction = dir;
    s_sound.S_StartSound_Zig(@ptrCast(&door.sector.soundorg), sfx);
}

fn removeDoor(door: *Door) void {
    door.sector.specialdata = null;
    p_tick.P_RemoveThinker(&door.thinker); // unlink and free
}

fn waitAtTop(door: *Door, tics: c_int) void {
    door.direction = .Waiting;
    door.topcountdown = tics;
}

pub fn T_VerticalDoor(door: *Door) callconv(.c) void {
    switch (door.direction) {
        .Waiting => {
            door.topcountdown -= 1;
            if (door.topcountdown == 0) switch (door.type) {
                .blazeRaise => setDoorDirection(door, .Down, .bdcls),
                .normal => setDoorDirection(door, .Down, .dorcls),
                .close30ThenOpen => setDoorDirection(door, .Up, .doropn),
                else => {},
            };
        },
        .InitialWait => {
            door.topcountdown -= 1;
            if (door.topcountdown == 0 and door.type == .raiseIn5Mins) {
                door.type = .normal;
                setDoorDirection(door, .Up, .doropn);
            }
        },
        .Down => {
            const res = T_MovePlane(door.sector, door.speed, door.sector.floorheight, c.false, .Ceiling, .Down);
            if (res == .PastDest) switch (door.type) {
                .blazeRaise, .blazeClose => {
                    removeDoor(door);
                    // BUG: Vanilla plays bdcls again on landing, after the one at close start.
                    s_sound.S_StartSound_Zig(@ptrCast(&door.sector.soundorg), .bdcls);
                },
                .normal, .close => removeDoor(door),
                .close30ThenOpen => waitAtTop(door, 35 * 30),
                .open, .raiseIn5Mins, .blazeOpen => {},
            } else if (res == .Crushed) switch (door.type) {
                .blazeClose, .close => {}, // Do not go back up
                else => setDoorDirection(door, .Up, .doropn),
            };
        },
        .Up => {
            const res = T_MovePlane(door.sector, door.speed, door.topheight, c.false, .Ceiling, .Up);
            if (res == .PastDest) switch (door.type) {
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
        99, 133 => .{ .card = .BlueCard, .skull = .BlueSkull, .message = d_strings.text.PD_BLUEO },
        134, 135 => .{ .card = .RedCard, .skull = .RedSkull, .message = d_strings.text.PD_REDO },
        136, 137 => .{ .card = .YellowCard, .skull = .YellowSkull, .message = d_strings.text.PD_YELLOWO },
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
        const door = z_zone.create(Door, .LevSpec, null);
        p_tick.P_AddThinker(&door.thinker);
        sec.specialdata = door;

        door.thinker.function.acp1 = p_tick.thinkFn(Door, &T_VerticalDoor);
        door.sector = sec;
        door.type = doortype;
        door.topwait = VDOORWAIT;

        door.topheight, const direction: DoorDirection, door.speed, const sfx: Sfx = switch (doortype) {
            .blazeClose => .{ doorOpenHeight(sec), .Down, VDOORSPEED * 4, .bdcls },
            .close => .{ doorOpenHeight(sec), .Down, VDOORSPEED, .dorcls },
            .close30ThenOpen => .{ sec.ceilingheight, .Down, VDOORSPEED, .dorcls },
            .blazeRaise, .blazeOpen => .{ doorOpenHeight(sec), .Up, VDOORSPEED * 4, .bdopn },
            .normal, .open => .{ doorOpenHeight(sec), .Up, VDOORSPEED, .doropn },
            .raiseIn5Mins => unreachable,
        };

        door.direction = direction;
        // An opening door that is already fully open stays silent.
        if (direction != .Up or door.topheight != sec.ceilingheight) {
            s_sound.S_StartSound_Zig(@ptrCast(&sec.soundorg), sfx);
        }
    }

    return rtn;
}

pub fn EV_VerticalDoor(line: *c.line_t, thing: *MObj) void {
    const blue: Lock = .{ .card = .BlueCard, .skull = .BlueSkull, .message = d_strings.text.PD_BLUEK };
    const yellow: Lock = .{ .card = .YellowCard, .skull = .YellowSkull, .message = d_strings.text.PD_YELLOWK };
    const red: Lock = .{ .card = .RedCard, .skull = .RedSkull, .message = d_strings.text.PD_REDK };

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
            // BUG: specialdata may be a ceiling, plat or floor, and vanilla treats it
            // as a door anyway. Door.direction's offset holds a ceiling's speed, a
            // plat's count or a floor's texture, so it is accessed as a raw c_int
            // instead of a DoorDirection that those values would make invalid.
            const door: *Door = @ptrCast(@alignCast(data));
            const direction: *c_int = @ptrCast(&door.direction);
            if (direction.* == @backingInt(DoorDirection.Down)) {
                direction.* = @backingInt(DoorDirection.Up); // go back up
            } else {
                if (thing.player == null) return; // JDC: bad guys never close doors
                direction.* = @backingInt(DoorDirection.Down); // start going down immediately
            }
            return;
        },
        // BUG: an open door falls through and stacks a second thinker on the sector.
        else => {},
    };

    s_sound.S_StartSound_Zig(@ptrCast(&sec.soundorg), if (blaze) .bdopn else .doropn);

    const door = z_zone.create(Door, .LevSpec, null);
    p_tick.P_AddThinker(&door.thinker);
    sec.specialdata = door;
    door.thinker.function.acp1 = p_tick.thinkFn(Door, &T_VerticalDoor);
    door.sector = sec;
    door.type = doortype;
    door.direction = .Up;
    door.speed = if (blaze) VDOORSPEED * 4 else VDOORSPEED;
    door.topwait = VDOORWAIT;
    door.topheight = doorOpenHeight(sec);

    // Open doors only work once
    if (doortype == .open or doortype == .blazeOpen) line.special = 0;
}

pub fn P_SpawnDoorCloseIn30(sec: *c.sector_t) void {
    const door = z_zone.create(Door, .LevSpec, null);

    p_tick.P_AddThinker(&door.thinker);

    sec.specialdata = door;
    sec.special = 0;

    door.thinker.function.acp1 = p_tick.thinkFn(Door, &T_VerticalDoor);
    door.sector = sec;
    door.direction = .Waiting;
    door.type = .normal;
    door.speed = VDOORSPEED;
    // BUG: vanilla leaves topheight and topwait unset, and a blocked door
    // reopens to them. Zone garbage can't match vanilla's anyway, so reopen
    // to the starting height and wait the usual time.
    door.topheight = sec.ceilingheight;
    door.topwait = VDOORWAIT;
    door.topcountdown = 30 * 35;
}

pub fn P_SpawnDoorRaiseIn5Mins(sec: *c.sector_t) void {
    const door = z_zone.create(Door, .LevSpec, null);

    p_tick.P_AddThinker(&door.thinker);

    sec.specialdata = door;
    sec.special = 0;

    door.thinker.function.acp1 = p_tick.thinkFn(Door, &T_VerticalDoor);
    door.sector = sec;
    door.direction = .InitialWait;
    door.type = .raiseIn5Mins;
    door.speed = VDOORSPEED;
    door.topheight = doorOpenHeight(sec);
    door.topwait = VDOORWAIT;
    door.topcountdown = 5 * 60 * 35;
}
