const c = @import("c");
const std = @import("std");

const d_player = @import("d_player.zig");
const Player = d_player.Player;
const doomdata = @import("doomdata.zig");
const doomstat = @import("doomstat.zig");
const g_game = @import("g_game.zig");
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const ML_SOUNDBLOCK = doomdata.ML_SOUNDBLOCK;
const ML_TWOSIDED = doomdata.ML_TWOSIDED;
const m_fixed = @import("m_fixed.zig");
const FRACUNIT = m_fixed.FRACUNIT;
const fixed_t = m_fixed.fixed_t;
const FixedAbs = m_fixed.FixedAbs;
const FixedMul = m_fixed.FixedMul;
const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_map = @import("p_map.zig");
const p_maputil = @import("p_maputil.zig");
const p_mobj = @import("p_mobj.zig");
const MF_AMBUSH = p_mobj.MF_AMBUSH;
const MF_CORPSE = p_mobj.MF_CORPSE;
const MF_FLOAT = p_mobj.MF_FLOAT;
const MF_INFLOAT = p_mobj.MF_INFLOAT;
const MF_JUSTATTACKED = p_mobj.MF_JUSTATTACKED;
const MF_JUSTHIT = p_mobj.MF_JUSTHIT;
const MF_SHADOW = p_mobj.MF_SHADOW;
const MF_SHOOTABLE = p_mobj.MF_SHOOTABLE;
const MF_SKULLFLY = p_mobj.MF_SKULLFLY;
const MF_SOLID = p_mobj.MF_SOLID;
const DirType = p_mobj.DirType;
const MObj = p_mobj.MObj;
const p_inter = @import("p_inter.zig");
const p_setup = @import("p_setup.zig");
const p_sight = @import("p_sight.zig");
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");
const sounds = @import("sounds.zig");
const asSfx = sounds.asSfx;
const sfxOffset = sounds.sfxOffset;
const Sfx = sounds.Sfx;

//
// P_NewChaseDir related LUT.
//
const opposite = [_]DirType{
    .West,
    .SouthWest,
    .South,
    .SouthEast,
    .East,
    .NorthEast,
    .North,
    .NorthWest,
    .NoDir,
};

//
// ENEMY THINKING
// Enemies are always spawned with targetplayer = -1, thresold = 0. Most
// monsters are spawned unaware of all players, but some can be made pre-aware.
//

var soundtarget: *MObj = undefined;

/// Called by P_NoiseAlert. Recursively traverse adjacent sectors, sound
/// blocking lines cut off traversal.
fn P_RecursiveSound(sec: *c.sector_t, soundblocks: c_int) void {
    // wake up all monsters in this sector
    if (sec.validcount == c.validcount and sec.soundtraversed <= soundblocks + 1) {
        return; // already flooded
    }

    sec.validcount = c.validcount;
    sec.soundtraversed = soundblocks + 1;
    sec.soundtarget = @ptrCast(soundtarget);

    for (0..@intCast(sec.linecount)) |i| {
        const check = sec.lines[i];
        if (check.*.flags & ML_TWOSIDED == 0) {
            continue;
        }

        p_maputil.P_LineOpening(check);

        if (p_maputil.openrange <= 0) {
            continue; // closed door
        }

        const other = if (p_setup.sides[@intCast(check.*.sidenum[0])].sector == sec)
            p_setup.sides[@intCast(check.*.sidenum[1])].sector
        else
            p_setup.sides[@intCast(check.*.sidenum[0])].sector;

        if (check.*.flags & ML_SOUNDBLOCK != 0) {
            if (soundblocks == 0) {
                P_RecursiveSound(other, 1);
            }
        } else {
            P_RecursiveSound(other, soundblocks);
        }
    }
}

/// If a monster yells at a player it will alert other monsters to the player.
pub export fn P_NoiseAlert(target: *MObj, emitter: *MObj) void {
    soundtarget = target;
    c.validcount += 1;
    P_RecursiveSound(emitter.subsector.sector, 0);
}

fn P_CheckMeleeRange(actor: *MObj) bool {
    if (actor.target == null) {
        return false;
    }

    const pl = actor.target.?;
    const dist = p_maputil.P_AproxDistance(pl.x - actor.x, pl.y - actor.y);

    if (dist >= c.MELEERANGE - 20 * FRACUNIT + pl.info.radius) {
        return false;
    }

    if (!p_sight.P_CheckSight(actor, pl)) {
        return false;
    }

    return true;
}

fn P_CheckMissileRange(actor: *MObj) bool {
    if (!p_sight.P_CheckSight(actor, actor.target.?)) {
        return false;
    }

    if (actor.flags & MF_JUSTHIT != 0) {
        // the target just hit the enemy, so fight back!
        actor.flags &= ~MF_JUSTHIT;
        return true;
    }

    if (actor.reactiontime != 0) {
        return false; // do not attack yet
    }

    // OPTIMIZE: get this from a global checksight
    var dist = p_maputil.P_AproxDistance(
        actor.x - actor.target.?.x,
        actor.y - actor.target.?.y,
    ) - 64 * FRACUNIT;

    if (actor.info.meleestate == 0) {
        dist -= 128 * FRACUNIT; // no melee attack, so fire more
    }

    dist >>= 16;

    if (actor.type == c.MT_VILE) {
        if (dist > 14 * 64) {
            return false; // too far away
        }
    }

    if (actor.type == c.MT_UNDEAD) {
        if (dist < 196) {
            return false; // close for fist attack
        }
        dist >>= 1;
    }

    if (actor.type == c.MT_CYBORG or actor.type == c.MT_SPIDER or actor.type == c.MT_SKULL) {
        dist >>= 1;
    }

    if (dist > 200) {
        dist = 200;
    }

    if (actor.type == c.MT_CYBORG and dist > 160) {
        dist = 160;
    }

    if (P_Random() < dist) {
        return false;
    }

    return true;
}

const xspeed = [_]fixed_t{ FRACUNIT, 47000, 0, -47000, -FRACUNIT, -47000, 0, 47000 };
const yspeed = [_]fixed_t{ 0, 47000, FRACUNIT, 47000, 0, -47000, -FRACUNIT, -47000 };

/// Move in the current direction, returns false if the move is blocked.
fn P_Move(actor: *MObj) bool {
    if (actor.movedir == .NoDir) {
        return false;
    }

    if (@as(c_uint, @bitCast(@backingInt(actor.movedir))) >= 8) {
        I_Error("Weird actor.movedir!");
    }

    const tryx = actor.x + actor.info.speed * xspeed[@intCast(@backingInt(actor.movedir))];
    const tryy = actor.y + actor.info.speed * yspeed[@intCast(@backingInt(actor.movedir))];

    if (p_map.P_TryMove(actor, tryx, tryy)) {
        actor.flags &= ~MF_INFLOAT;

        if (actor.flags & MF_FLOAT == 0) {
            actor.z = actor.floorz;
        }

        return true;
    }

    // open any specials
    if (actor.flags & MF_FLOAT != 0 and p_map.floatok) {
        // must adjust height
        if (actor.z < p_map.tmfloorz) {
            actor.z += c.FLOATSPEED;
        } else {
            actor.z -= c.FLOATSPEED;
        }

        actor.flags |= MF_INFLOAT;
        return true;
    }

    if (p_map.numspechit == 0) {
        return false;
    }

    actor.movedir = .NoDir;
    var good = false;
    while (p_map.numspechit > 0) {
        p_map.numspechit -= 1;
        const ld = p_map.spechit[p_map.numspechit];
        // if the special is not a door that can be opened return false
        if (c.P_UseSpecialLine(@ptrCast(actor), ld, 0) != c.false) {
            good = true;
        }
    }

    return good;
}

/// Attempts to move actor on in its current (ob.moveangle) direction. If
/// blocked by either a wall or an actor returns false. If move is either
/// clear or blocked only by a door, returns true and sets... If a door is in
/// the way an OpenDoor call is made to start it opening.
fn P_TryWalk(actor: *MObj) bool {
    if (!P_Move(actor)) {
        return false;
    }

    actor.movecount = @mod(P_Random(), 16);
    return true;
}

fn P_TryDir(actor: *MObj, dir: DirType, excludedir: ?DirType) bool {
    if (dir == .NoDir or (excludedir != null and dir == excludedir.?)) {
        return false;
    }

    actor.movedir = dir;
    return P_TryWalk(actor);
}

fn P_NewChaseDir(actor: *MObj) void {
    if (actor.target == null) {
        I_Error("P_NewChaseDir: called with no target");
    }

    const olddir = actor.movedir;
    const turnaround = opposite[@intCast(@backingInt(olddir))];

    const deltax = actor.target.?.x - actor.x;
    const deltay = actor.target.?.y - actor.y;

    var d1: DirType = if (deltax > 10 * FRACUNIT)
        .East
    else if (deltax < -10 * FRACUNIT)
        .West
    else
        .NoDir;

    var d2: DirType = if (deltay > 10 * FRACUNIT)
        .North
    else if (deltay < -10 * FRACUNIT)
        .South
    else
        .NoDir;

    // try direct route
    if (d1 != .NoDir and d2 != .NoDir) {
        actor.movedir = if (deltay < 0)
            if (deltax > 0) .SouthEast else .SouthWest
        else if (deltax > 0) .NorthEast else .NorthWest;

        if (actor.movedir != turnaround and P_TryWalk(actor)) {
            return;
        }
    }

    // try other directions
    if (P_Random() > 200 or FixedAbs(deltay) > FixedAbs(deltax)) {
        std.mem.swap(DirType, &d1, &d2);
    }

    // try d1, then d2, then olddir
    for ([_]DirType{ d1, d2, olddir }) |dir| {
        if (P_TryDir(actor, dir, turnaround)) {
            return;
        }
    }

    // randomly determine direction of search
    const reverse = @mod(P_Random(), 2) == 0;
    for (0..8) |i| {
        const tdir: DirType = @fromBackingInt(@intCast(if (reverse) 7 - i else i));

        if (P_TryDir(actor, tdir, turnaround)) {
            return;
        }
    }

    // give in and try a 180 finally
    if (P_TryDir(actor, turnaround, null)) {
        return;
    }

    actor.movedir = .NoDir; // cannot move
}

/// If allaround is false, only look 180 degrees in front. Returns true if a
/// player is targeted.
fn P_LookForPlayers(actor: *MObj, allaround: bool) bool {
    var seen: c_int = 0;
    const stop = @mod(actor.lastlook - 1, 4);

    // Advances actor.lastlook on every continue, so the next call resumes
    // where this one left off.
    while (true) : (actor.lastlook = @mod(actor.lastlook + 1, 4)) {
        const i: usize = @intCast(actor.lastlook);

        if (g_game.playeringame[i] == c.false) {
            continue;
        }

        if (seen == 2 or actor.lastlook == stop) {
            // done looking
            return false;
        }
        seen += 1;

        const player = &g_game.players[i];

        if (player.health <= 0) {
            continue; // dead
        }

        if (!p_sight.P_CheckSight(actor, player.mo.?)) {
            continue; // out of sight
        }

        if (!allaround) {
            const an = c.R_PointToAngle2(actor.x, actor.y, player.mo.?.x, player.mo.?.y) -% actor.angle;

            if (an > c.ANG90 and an < c.ANG270) {
                const dist = p_maputil.P_AproxDistance(player.mo.?.x - actor.x, player.mo.?.y - actor.y);
                // if real close, react anyway
                if (dist > c.MELEERANGE) {
                    continue; // behind back
                }
            }
        }

        actor.target = player.mo;
        return true;
    }
}

/// True if a mobj other than actor, of the same type, is still alive.
fn P_OthersAlive(actor: *MObj) bool {
    var th = p_tick.thinkercap.next;
    while (th != &p_tick.thinkercap) : (th = th.?.next) {
        if (th.?.function.acp1 != p_mobj.mobj_thinker) {
            continue;
        }
        const mo2: *MObj = @ptrCast(th);
        if (mo2 != actor and mo2.type == actor.type and mo2.health > 0) {
            return true;
        }
    }
    return false;
}

/// DOOM II special, map 32.
/// Uses special tag 666.
pub export fn A_KeenDie(mo: *MObj) void {
    A_Fall(mo);

    // scan the remaining thinkers to see if all Keens are dead
    if (P_OthersAlive(mo)) {
        return; // other Keen not dead
    }

    var junk: c.line_t = undefined;
    junk.tag = 666;
    _ = c.EV_DoDoor(&junk, c.open);
}

/// Stay in state until a player is sighted.
pub export fn A_Look(actor: *MObj) void {
    actor.threshold = 0; // any shot will wake up

    var seeyou = false;
    const targ: ?*MObj = @ptrCast(actor.subsector.sector.*.soundtarget);

    if (targ) |t| {
        if (t.flags & MF_SHOOTABLE != 0) {
            actor.target = t;
            seeyou = actor.flags & MF_AMBUSH == 0 or p_sight.P_CheckSight(actor, t);
        }
    }

    if (!seeyou and !P_LookForPlayers(actor, false)) {
        return;
    }

    // go into chase state
    if (actor.info.seesound != 0) {
        const seesound = asSfx(actor.info.seesound);
        const sound = switch (seesound) {
            .posit1, .posit2, .posit3 => sfxOffset(Sfx.posit1, @mod(P_Random(), 3)),
            .bgsit1, .bgsit2 => sfxOffset(Sfx.bgsit1, @mod(P_Random(), 2)),
            else => seesound,
        };

        if (actor.type == c.MT_SPIDER or actor.type == c.MT_CYBORG) {
            // full volume
            s_sound.S_StartSound_Zig(null, sound);
        } else {
            s_sound.S_StartSound_Zig(actor, sound);
        }
    }

    _ = p_mobj.P_SetMobjState(actor, @intCast(actor.info.seestate));
}

// Actor has a melee attack, so it tries to close as fast as possible
pub export fn A_Chase(actor: *MObj) void {
    if (actor.reactiontime != 0) {
        actor.reactiontime -= 1;
    }

    // modify target threshold
    if (actor.threshold != 0) {
        if (actor.target == null or actor.target.?.health <= 0) {
            actor.threshold = 0;
        } else {
            actor.threshold -= 1;
        }
    }

    // turn towards movement direction if not there yet
    if (actor.movedir != .NoDir) {
        actor.angle &= 7 << 29; // truncate angle down to next multiple of 45
        const dirangle = @as(c.angle_t, @intCast(@backingInt(actor.movedir))) << 29;
        const delta: i32 = @bitCast(actor.angle -% dirangle);

        if (delta > 0) {
            actor.angle -%= c.ANG45;
        } else if (delta < 0) {
            actor.angle +%= c.ANG45;
        }
    }

    if (actor.target == null or actor.target.?.flags & MF_SHOOTABLE == 0) {
        // look for a new target
        if (P_LookForPlayers(actor, true)) {
            return; // got a new target
        }

        _ = p_mobj.P_SetMobjState(actor, @intCast(actor.info.spawnstate));
        return;
    }

    // do not attack twice in a row
    if (actor.flags & MF_JUSTATTACKED != 0) {
        actor.flags &= ~MF_JUSTATTACKED;

        if (g_game.gameskill != .Nightmare and c.fastparm == c.false) {
            P_NewChaseDir(actor);
        }

        return;
    }

    // check for melee attack
    if (actor.info.meleestate != 0 and P_CheckMeleeRange(actor)) {
        if (actor.info.attacksound != 0) {
            s_sound.S_StartSound_Zig(actor, asSfx(actor.info.attacksound));
        }

        _ = p_mobj.P_SetMobjState(actor, @intCast(actor.info.meleestate));
        return;
    }

    // check for missile attack
    // Below nightmare, a monster that is still moving holds its fire.
    const holdingfire = g_game.gameskill != .Nightmare and c.fastparm == c.false and actor.movecount != 0;
    if (actor.info.missilestate != 0 and !holdingfire and P_CheckMissileRange(actor)) {
        _ = p_mobj.P_SetMobjState(actor, @intCast(actor.info.missilestate));
        actor.flags |= MF_JUSTATTACKED;
        return;
    }

    // possibly choose another target
    if (g_game.netgame != c.false and
        actor.threshold == 0 and
        !p_sight.P_CheckSight(actor, actor.target.?))
    {
        if (P_LookForPlayers(actor, true)) {
            return; // got a new target
        }
    }

    // chase towards player
    actor.movecount -= 1;
    if (actor.movecount < 0 or !P_Move(actor)) {
        P_NewChaseDir(actor);
    }

    // make active sound
    if (actor.info.activesound != 0 and P_Random() < 3) {
        s_sound.S_StartSound_Zig(actor, asSfx(actor.info.activesound));
    }
}

pub export fn A_FaceTarget(actor: *MObj) void {
    const target = actor.target orelse return;

    actor.flags &= ~MF_AMBUSH;

    actor.angle = c.R_PointToAngle2(actor.x, actor.y, target.x, target.y);

    if (target.flags & MF_SHADOW != 0) {
        const spread = (P_Random() - P_Random()) << 21;
        actor.angle +%= @bitCast(spread);
    }
}

pub export fn A_PosAttack(actor: *MObj) void {
    if (actor.target == null) {
        return;
    }

    A_FaceTarget(actor);
    var angle = actor.angle;
    const slope = p_map.P_AimLineAttack(actor, angle, c.MISSILERANGE);

    s_sound.S_StartSound_Zig(actor, .pistol);
    const spread = (P_Random() - P_Random()) << 20;
    angle +%= @bitCast(spread);
    const damage = (@mod(P_Random(), 5) + 1) * 3;
    p_map.P_LineAttack(actor, angle, c.MISSILERANGE, slope, damage);
}

pub export fn A_SPosAttack(actor: *MObj) void {
    if (actor.target == null) {
        return;
    }

    s_sound.S_StartSound_Zig(actor, .shotgn);
    A_FaceTarget(actor);
    const bangle = actor.angle;
    const slope = p_map.P_AimLineAttack(actor, bangle, c.MISSILERANGE);

    for (0..3) |_| {
        const spread = (P_Random() - P_Random()) << 20;
        const angle = bangle +% @as(c.angle_t, @bitCast(spread));
        const damage = (@mod(P_Random(), 5) + 1) * 3;
        p_map.P_LineAttack(actor, angle, c.MISSILERANGE, slope, damage);
    }
}

pub export fn A_CPosAttack(actor: *MObj) void {
    if (actor.target == null) {
        return;
    }

    s_sound.S_StartSound_Zig(actor, .shotgn);
    A_FaceTarget(actor);
    const bangle = actor.angle;
    const slope = p_map.P_AimLineAttack(actor, bangle, c.MISSILERANGE);

    const spread = (P_Random() - P_Random()) << 20;
    const angle = bangle +% @as(c.angle_t, @bitCast(spread));
    const damage = (@mod(P_Random(), 5) + 1) * 3;
    p_map.P_LineAttack(actor, angle, c.MISSILERANGE, slope, damage);
}

pub export fn A_CPosRefire(actor: *MObj) void {
    // keep firing unless target got out of sight
    A_FaceTarget(actor);

    if (P_Random() < 40)
        return;

    if (actor.target == null or
        actor.target.?.health <= 0 or
        !p_sight.P_CheckSight(actor, actor.target.?))
    {
        _ = p_mobj.P_SetMobjState(actor, @intCast(actor.info.seestate));
    }
}

pub export fn A_SpidRefire(actor: *MObj) void {
    // keep firing unless target got out of sight
    A_FaceTarget(actor);

    if (P_Random() < 10) {
        return;
    }

    if (actor.target == null or
        actor.target.?.health <= 0 or
        !p_sight.P_CheckSight(actor, actor.target.?))
    {
        _ = p_mobj.P_SetMobjState(actor, @intCast(actor.info.seestate));
    }
}

pub export fn A_BspiAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);

    // launch a missile
    _ = p_mobj.P_SpawnMissile(actor, target, c.MT_ARACHPLAZ);
}

pub export fn A_TroopAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);
    if (P_CheckMeleeRange(actor)) {
        s_sound.S_StartSound_Zig(actor, .claw);
        const damage = (@mod(P_Random(), 8) + 1) * 3;
        p_inter.P_DamageMobj(target, actor, actor, damage);
        return;
    }

    // launch a missile
    _ = p_mobj.P_SpawnMissile(actor, target, c.MT_TROOPSHOT);
}

pub export fn A_SargAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);
    if (P_CheckMeleeRange(actor)) {
        const damage = (@mod(P_Random(), 10) + 1) * 4;
        p_inter.P_DamageMobj(target, actor, actor, damage);
    }
}

pub export fn A_HeadAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);
    if (P_CheckMeleeRange(actor)) {
        const damage = (@mod(P_Random(), 6) + 1) * 10;
        p_inter.P_DamageMobj(target, actor, actor, damage);
        return;
    }

    // launch a missile
    _ = p_mobj.P_SpawnMissile(actor, target, c.MT_HEADSHOT);
}

pub export fn A_CyberAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);
    _ = p_mobj.P_SpawnMissile(actor, target, c.MT_ROCKET);
}

pub export fn A_BruisAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    if (P_CheckMeleeRange(actor)) {
        s_sound.S_StartSound_Zig(actor, .claw);
        const damage = (@mod(P_Random(), 8) + 1) * 10;

        p_inter.P_DamageMobj(target, actor, actor, damage);
    } else {
        _ = p_mobj.P_SpawnMissile(actor, target, c.MT_BRUISERSHOT);
    }
}

pub export fn A_SkelMissile(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);

    actor.z += 16 * FRACUNIT; // so missile spawns higher
    const mo = p_mobj.P_SpawnMissile(actor, target, c.MT_TRACER);
    actor.z -= 16 * FRACUNIT; // back to normal

    mo.x += mo.momx;
    mo.y += mo.momy;
    mo.tracer = actor.target;
}

pub export fn A_Tracer(actor: *MObj) void {
    if (@mod(g_game.gametic, 4) != 0) {
        return;
    }

    // spawn a puff of smoke behind the rocket
    p_mobj.P_SpawnPuff(actor.x, actor.y, actor.z);

    const th = p_mobj.P_SpawnMobj(actor.x - actor.momx, actor.y - actor.momy, actor.z, c.MT_SMOKE);

    th.momz = FRACUNIT;
    th.tics -= @mod(P_Random(), 4);
    if (th.tics < 1) {
        th.tics = 1;
    }

    // adjust direction
    const dest = actor.tracer orelse return;

    if (dest.health <= 0) {
        return;
    }

    // change angle
    const exact = c.R_PointToAngle2(actor.x, actor.y, dest.x, dest.y);

    const TRACEANGLE = 0xc000000;

    // turn towards dest by at most TRACEANGLE, snapping on when within range
    const delta: i32 = @bitCast(exact -% actor.angle);
    if (@abs(delta) <= TRACEANGLE) {
        actor.angle = exact;
    } else if (delta < 0 and delta != std.math.minInt(i32)) {
        // exactly 180 degrees off (minInt) turns left, as vanilla does
        actor.angle -%= TRACEANGLE;
    } else {
        actor.angle +%= TRACEANGLE;
    }

    const fine = actor.angle >> c.ANGLETOFINESHIFT;
    actor.momx = FixedMul(actor.info.speed, c.finecosine[fine]);
    actor.momy = FixedMul(actor.info.speed, c.finesine[fine]);

    // change slope
    var dist = p_maputil.P_AproxDistance(dest.x - actor.x, dest.y - actor.y);

    dist = @divTrunc(dist, actor.info.speed);

    if (dist < 1) {
        dist = 1;
    }
    const slope = @divTrunc(dest.z + 40 * FRACUNIT - actor.z, dist);

    if (slope < actor.momz) {
        actor.momz -= FRACUNIT / 8;
    } else {
        actor.momz += FRACUNIT / 8;
    }
}

pub export fn A_SkelWhoosh(actor: *MObj) void {
    if (actor.target == null) {
        return;
    }

    A_FaceTarget(actor);
    s_sound.S_StartSound_Zig(actor, .skeswg);
}

pub export fn A_SkelFist(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);

    if (P_CheckMeleeRange(actor)) {
        const damage = (@mod(P_Random(), 10) + 1) * 6;
        s_sound.S_StartSound_Zig(actor, .skepch);
        p_inter.P_DamageMobj(target, actor, actor, damage);
    }
}

var corpsehit: *MObj = undefined;
var vileobj: *MObj = undefined;
var viletryx: fixed_t = 0;
var viletryy: fixed_t = 0;

/// Detect a corpse that could be raised.
fn PIT_VileCheck(thing: *MObj) bool {
    if (thing.flags & MF_CORPSE == 0) {
        return true; // not a monster
    }

    if (thing.tics != -1) {
        return true; // not lying still yet
    }

    if (thing.info.raisestate == c.S_NULL) {
        return true; // monster doesn't have a raise state
    }

    const maxdist = thing.info.radius + c.mobjinfo[c.MT_VILE].radius;

    if (FixedAbs(thing.x - viletryx) > maxdist or
        FixedAbs(thing.y - viletryy) > maxdist)
    {
        return true; // not actually touching
    }

    corpsehit = thing;
    corpsehit.momx = 0;
    corpsehit.momy = 0;
    corpsehit.height <<= 2;
    const check = p_map.P_CheckPosition(corpsehit, corpsehit.x, corpsehit.y);
    corpsehit.height >>= 2;

    if (!check) {
        return true; // doesn't fit here
    }

    return false; // got one, so stop checking
}

/// Check for ressurecting a body
pub export fn A_VileChase(actor: *MObj) void {
    if (actor.movedir != .NoDir) {
        // check for corpses to raise
        viletryx = actor.x + actor.info.speed * xspeed[@intCast(@backingInt(actor.movedir))];
        viletryy = actor.y + actor.info.speed * yspeed[@intCast(@backingInt(actor.movedir))];

        const xl = (viletryx - p_setup.bmaporgx - c.MAXRADIUS * 2) >> c.MAPBLOCKSHIFT;
        const xh = (viletryx - p_setup.bmaporgx + c.MAXRADIUS * 2) >> c.MAPBLOCKSHIFT;
        const yl = (viletryy - p_setup.bmaporgy - c.MAXRADIUS * 2) >> c.MAPBLOCKSHIFT;
        const yh = (viletryy - p_setup.bmaporgy + c.MAXRADIUS * 2) >> c.MAPBLOCKSHIFT;

        vileobj = actor;
        var bx = xl;
        while (bx <= xh) : (bx += 1) {
            var by = yl;
            while (by <= yh) : (by += 1) {
                // Call PIT_VileCheck to check whether object is a corpse
                // that can be raised.
                if (!p_maputil.P_BlockThingsIterator(bx, by, PIT_VileCheck)) {
                    // got one!
                    const temp = actor.target;
                    actor.target = corpsehit;
                    A_FaceTarget(actor);
                    actor.target = temp;

                    _ = p_mobj.P_SetMobjState(actor, @intCast(c.S_VILE_HEAL1));
                    s_sound.S_StartSound_Zig(corpsehit, .slop);
                    const info = corpsehit.info;

                    // BUG: crushed corpses (gibs) have height and radius 0,
                    // so they rise as "ghost" monsters that shots and other
                    // monsters pass through.
                    _ = p_mobj.P_SetMobjState(corpsehit, @intCast(info.raisestate));
                    corpsehit.height <<= 2;
                    corpsehit.flags = info.flags;
                    corpsehit.health = info.spawnhealth;
                    corpsehit.target = null;

                    return;
                }
            }
        }
    }

    // Return to normal attack.
    A_Chase(actor);
}

pub export fn A_VileStart(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .vilatk);
}

pub export fn A_StartFire(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .flamst);
    A_Fire(actor);
}

pub export fn A_FireCrackle(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .flame);
    A_Fire(actor);
}

pub export fn A_Fire(actor: *MObj) void {
    const dest = actor.tracer orelse return;

    // don't move it if the vile lost sight
    if (!p_sight.P_CheckSight(actor.target.?, dest)) {
        return;
    }

    const fine = dest.angle >> c.ANGLETOFINESHIFT;

    p_maputil.P_UnsetThingPosition(actor);
    actor.x = dest.x + FixedMul(24 * FRACUNIT, c.finecosine[fine]);
    actor.y = dest.y + FixedMul(24 * FRACUNIT, c.finesine[fine]);
    actor.z = dest.z;
    p_maputil.P_SetThingPosition(actor);
}

/// Spawn the hellfire
pub export fn A_VileTarget(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);

    // BUG: x instead of y!?
    const fog = p_mobj.P_SpawnMobj(target.x, target.x, target.z, c.MT_FIRE);

    actor.tracer = fog;
    fog.target = actor;
    fog.tracer = target;

    A_Fire(fog);
}

pub export fn A_VileAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    A_FaceTarget(actor);

    if (!p_sight.P_CheckSight(actor, target)) {
        return;
    }

    s_sound.S_StartSound_Zig(actor, .barexp);
    p_inter.P_DamageMobj(target, actor, actor, 20);
    target.momz = @divTrunc(1000 * FRACUNIT, target.info.mass);

    const fine = actor.angle >> c.ANGLETOFINESHIFT;

    const fire = actor.tracer orelse return;

    // move the fire between the vile and the player
    fire.x = target.x - FixedMul(24 * FRACUNIT, c.finecosine[fine]);
    fire.y = target.y - FixedMul(24 * FRACUNIT, c.finesine[fine]);
    p_map.P_RadiusAttack(fire, actor, 70);
}

pub export fn A_FatRaise(actor: *MObj) void {
    A_FaceTarget(actor);
    s_sound.S_StartSound_Zig(actor, .manatk);
}

/// Fire a mancubus missile at target, turned from its aim by spread.
fn A_FatShot(actor: *MObj, target: *MObj, spread: i32) void {
    const mo = p_mobj.P_SpawnMissile(actor, target, c.MT_FATSHOT);

    // Vanilla leaves an unspread missile alone. Re-aiming it anyway would
    // restore momentum to one that exploded on spawn.
    if (spread == 0) {
        return;
    }

    mo.angle +%= @bitCast(spread);
    const fine = mo.angle >> c.ANGLETOFINESHIFT;
    mo.momx = FixedMul(mo.info.speed, c.finecosine[fine]);
    mo.momy = FixedMul(mo.info.speed, c.finesine[fine]);
}

fn A_FatAttack(actor: *MObj, turn: i32, spread1: i32, spread2: i32) void {
    // Lost target can occur when reloading a save game.
    // Look for a new target or bail if can't find one.
    if (actor.target == null and !P_LookForPlayers(actor, true)) {
        return;
    }
    const target = actor.target.?;

    A_FaceTarget(actor);
    actor.angle +%= @bitCast(turn);
    A_FatShot(actor, target, spread1);
    A_FatShot(actor, target, spread2);
}

const FATSPREAD = c.ANG90 / 8;

pub export fn A_FatAttack1(actor: *MObj) void {
    A_FatAttack(actor, FATSPREAD, 0, FATSPREAD);
}

pub export fn A_FatAttack2(actor: *MObj) void {
    A_FatAttack(actor, -FATSPREAD, 0, -FATSPREAD * 2);
}

pub export fn A_FatAttack3(actor: *MObj) void {
    A_FatAttack(actor, 0, -FATSPREAD / 2, FATSPREAD / 2);
}

const SKULLSPEED = 20 * FRACUNIT;

/// Fly at the player like a missile.
pub export fn A_SkullAttack(actor: *MObj) void {
    const target = actor.target orelse return;

    actor.flags |= MF_SKULLFLY;

    s_sound.S_StartSound_Zig(actor, asSfx(actor.info.attacksound));
    A_FaceTarget(actor);

    const fine = actor.angle >> c.ANGLETOFINESHIFT;
    actor.momx = FixedMul(SKULLSPEED, c.finecosine[fine]);
    actor.momy = FixedMul(SKULLSPEED, c.finesine[fine]);
    const dist = @max(1, @divTrunc(p_maputil.P_AproxDistance(target.x - actor.x, target.y - actor.y), SKULLSPEED));
    actor.momz = @divTrunc(target.z + (target.height >> 1) - actor.z, dist);
}

/// Spawn a lost soul and launch it at the target
fn A_PainShootSkull(actor: *MObj, angle: c.angle_t) void {
    // count total number of skull currently on the level
    var count: u32 = 0;
    var currentthinker = p_tick.thinkercap.next;
    while (currentthinker != &p_tick.thinkercap) : (currentthinker = currentthinker.?.next) {
        if (currentthinker.?.function.acp1 == p_mobj.mobj_thinker and
            @as(*MObj, @ptrCast(currentthinker)).type == c.MT_SKULL)
        {
            count += 1;
        }
    }

    // if there are already 20 skulls on the level, don't spit another one.
    if (count > 20) {
        return;
    }

    // okay, there's playe for another one
    const fine = angle >> c.ANGLETOFINESHIFT;

    const prestep = 4 * FRACUNIT + @divTrunc(3 * (actor.info.radius + c.mobjinfo[c.MT_SKULL].radius), 2);
    const x = actor.x + FixedMul(prestep, c.finecosine[fine]);
    const y = actor.y + FixedMul(prestep, c.finesine[fine]);
    const z = actor.z + 8 * FRACUNIT;

    const mo = p_mobj.P_SpawnMobj(x, y, z, c.MT_SKULL);

    // Check for movements.
    if (!p_map.P_TryMove(mo, mo.x, mo.y)) {
        // kill it immediately
        p_inter.P_DamageMobj(mo, actor, actor, 10000);
        return;
    }

    mo.target = actor.target;
    A_SkullAttack(mo);
}

/// Spawn a lost soul and launch it at the target
pub export fn A_PainAttack(actor: *MObj) void {
    if (actor.target == null) {
        return;
    }

    A_FaceTarget(actor);
    A_PainShootSkull(actor, actor.angle);
}

pub export fn A_PainDie(actor: *MObj) void {
    A_Fall(actor);
    A_PainShootSkull(actor, actor.angle +% c.ANG90);
    A_PainShootSkull(actor, actor.angle +% c.ANG180);
    A_PainShootSkull(actor, actor.angle +% c.ANG270);
}

pub export fn A_Scream(actor: *MObj) void {
    const deathsound = asSfx(actor.info.deathsound);
    const sound = switch (deathsound) {
        .None => return,
        .podth1, .podth2, .podth3 => sfxOffset(.podth1, @mod(P_Random(), 3)),
        .bgdth1, .bgdth2 => sfxOffset(.bgdth1, @mod(P_Random(), 2)),
        else => deathsound,
    };

    // Check for bosses.
    if (actor.type == c.MT_SPIDER or actor.type == c.MT_CYBORG) {
        // full volume
        s_sound.S_StartSound_Zig(null, sound);
    } else {
        s_sound.S_StartSound_Zig(actor, sound);
    }
}

pub export fn A_XScream(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .slop);
}

pub export fn A_Pain(actor: *MObj) void {
    if (actor.info.painsound != 0) {
        s_sound.S_StartSound_Zig(actor, asSfx(actor.info.painsound));
    }
}

pub export fn A_Fall(actor: *MObj) void {
    // actor is on ground, it can be walked over
    actor.flags &= ~MF_SOLID;

    // So change this if corpse objects are meant to be obstacles.
}

pub export fn A_Explode(actor: *MObj) void {
    p_map.P_RadiusAttack(actor, actor.target, 128);
}

/// Possibly trigger special effects if on first boss level
pub export fn A_BossDeath(actor: *MObj) void {
    const isboss = if (doomstat.gamemode == .Commercial)
        g_game.gamemap == 7 and (actor.type == c.MT_FATSO or actor.type == c.MT_BABY)
    else switch (g_game.gameepisode) {
        1 => g_game.gamemap == 8 and actor.type == c.MT_BRUISER,
        2 => g_game.gamemap == 8 and actor.type == c.MT_CYBORG,
        3 => g_game.gamemap == 8 and actor.type == c.MT_SPIDER,
        4 => (g_game.gamemap == 6 and actor.type == c.MT_CYBORG) or
            (g_game.gamemap == 8 and actor.type == c.MT_SPIDER),
        else => g_game.gamemap == 8,
    };
    if (!isboss) {
        return;
    }

    // make sure there is a player alive for victory
    for (g_game.playeringame, &g_game.players) |playeringame, *player| {
        if (playeringame != c.false and player.health > 0) {
            break;
        }
    } else {
        return; // no one left alive so do not end the game
    }

    // scan the remaining thinkers to see if all bosses are dead
    if (P_OthersAlive(actor)) {
        return; // other boss not dead
    }

    // victory!
    var junk: c.line_t = undefined;
    junk.tag = 666;

    if (doomstat.gamemode == .Commercial) {
        // gamemap is already determined above to be 7, if Commercial
        if (actor.type == c.MT_FATSO) {
            _ = c.EV_DoFloor(&junk, c.lowerFloorToLowest);
        } else {
            // type already determined above to be MT_BABY, if not MT_FATSO
            junk.tag = 667;
            _ = c.EV_DoFloor(&junk, c.raiseToTexture);
        }
    } else switch (g_game.gameepisode) {
        1 => _ = c.EV_DoFloor(&junk, c.lowerFloorToLowest),
        4 => if (g_game.gamemap == 6) {
            _ = c.EV_DoDoor(&junk, c.blazeOpen);
        } else {
            // gamemap already determined above to be 8, if not 6
            _ = c.EV_DoFloor(&junk, c.lowerFloorToLowest);
        },
        // killing e2m8 or e3m8 bosses exits the level
        else => g_game.G_ExitLevel(),
    }
}

pub export fn A_Hoof(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .hoof);
    A_Chase(actor);
}

pub export fn A_Metal(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .metal);
    A_Chase(actor);
}

pub export fn A_BabyMetal(actor: *MObj) void {
    s_sound.S_StartSound_Zig(actor, .bspwlk);
    A_Chase(actor);
}

pub export fn A_OpenShotgun2(player: *Player, _: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .dbopn);
}

pub export fn A_LoadShotgun2(player: *Player, _: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .dbload);
}

extern "c" fn A_ReFire(player: *Player, psp: *c.pspdef_t) void;

pub export fn A_CloseShotgun2(player: *Player, psp: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .dbcls);
    A_ReFire(player, psp);
}

var braintargets: [32]*MObj = undefined;
var numbraintargets: usize = 0;
var braintargeton: usize = 0;

pub export fn A_BrainAwake(_: *MObj) void {
    numbraintargets = 0;
    braintargeton = 0;

    var th = p_tick.thinkercap.next;
    while (th != &p_tick.thinkercap) : (th = th.?.next) {
        if (th.?.function.acp1 != p_mobj.mobj_thinker) {
            continue;
        }

        const mo = @as(*MObj, @ptrCast(th));

        if (mo.type == c.MT_BOSSTARGET) {
            braintargets[numbraintargets] = mo;
            numbraintargets += 1;
        }
    }

    s_sound.S_StartSound_Zig(null, .bossit);
}

pub export fn A_BrainPain(_: *MObj) void {
    s_sound.S_StartSound_Zig(null, .bospn);
}

pub export fn A_BrainScream(mo: *MObj) void {
    var x = mo.x - 196 * FRACUNIT;
    while (x < mo.x + 320 * FRACUNIT) : (x += 8 * FRACUNIT) {
        const y = mo.y - 320 * FRACUNIT;
        // BUG: 128 isn't scaled by FRACUNIT, so it adds almost nothing to z.
        const z = 128 + P_Random() * 2 * FRACUNIT;
        const th = p_mobj.P_SpawnMobj(x, y, z, c.MT_ROCKET);
        th.momz = P_Random() * 512;

        _ = p_mobj.P_SetMobjState(th, c.S_BRAINEXPLODE1);

        th.tics -= @mod(P_Random(), 8);
        if (th.tics < 1) {
            th.tics = 1;
        }
    }

    s_sound.S_StartSound_Zig(null, .bosdth);
}

pub export fn A_BrainExplode(mo: *MObj) void {
    const x = mo.x + (P_Random() - P_Random()) * 2048;
    const y = mo.y;
    const z = 128 + P_Random() * 2 * FRACUNIT;
    const th = p_mobj.P_SpawnMobj(x, y, z, c.MT_ROCKET);
    th.momz = P_Random() * 512;

    _ = p_mobj.P_SetMobjState(th, c.S_BRAINEXPLODE1);

    th.tics -= @mod(P_Random(), 8);
    if (th.tics < 1) {
        th.tics = 1;
    }
}

pub export fn A_BrainDie(_: *MObj) void {
    g_game.G_ExitLevel();
}

pub export fn A_BrainSpit(mo: *MObj) void {
    const S = struct {
        var easy: c_int = 0;
    };

    S.easy ^= 1;
    if (S.easy == 0 and (g_game.gameskill == .Baby or g_game.gameskill == .Easy)) {
        return;
    }

    // shoot a cube at current target
    const target = braintargets[braintargeton];
    braintargeton = @mod(braintargeton + 1, numbraintargets);

    // spawn brain missile
    const newmobj = p_mobj.P_SpawnMissile(mo, target, c.MT_SPAWNSHOT);
    newmobj.target = target;
    newmobj.reactiontime = @intCast(@divTrunc(@divTrunc(target.y - mo.y, newmobj.momy), newmobj.state.?.tics));

    s_sound.S_StartSound_Zig(null, .bospit);
}

pub export fn A_SpawnSound(mo: *MObj) void {
    s_sound.S_StartSound_Zig(mo, .boscub);
    A_SpawnFly(mo);
}

pub export fn A_SpawnFly(mo: *MObj) void {
    mo.reactiontime -= 1;
    if (mo.reactiontime != 0) {
        return; // still flying
    }

    // mo.target can be lost when reloading a save game. Use self location as
    // approximation of target.
    const target = mo.target orelse mo;

    // First spawn teleport fog.
    const fog = p_mobj.P_SpawnMobj(target.x, target.y, target.z, c.MT_SPAWNFIRE);
    s_sound.S_StartSound_Zig(fog, .telept);

    // Randomly select monster to spawn
    const r = P_Random();

    // Probability distribution (kind of :), decreasing likelihood.
    const mtype = if (r < 50)
        c.MT_TROOP
    else if (r < 90)
        c.MT_SERGEANT
    else if (r < 120)
        c.MT_SHADOWS
    else if (r < 130)
        c.MT_PAIN
    else if (r < 160)
        c.MT_HEAD
    else if (r < 162)
        c.MT_VILE
    else if (r < 172)
        c.MT_UNDEAD
    else if (r < 192)
        c.MT_BABY
    else if (r < 222)
        c.MT_FATSO
    else if (r < 246)
        c.MT_KNIGHT
    else
        c.MT_BRUISER;

    const newmobj = p_mobj.P_SpawnMobj(target.x, target.y, target.z, @intCast(mtype));
    if (P_LookForPlayers(newmobj, true)) {
        _ = p_mobj.P_SetMobjState(newmobj, @intCast(newmobj.info.seestate));
    }

    // telefrag anything in this spot
    _ = p_map.P_TeleportMove(newmobj, newmobj.x, newmobj.y);

    // remove self (i.e., the cube).
    p_mobj.P_RemoveMobj(mo);
}

pub export fn A_PlayerScream(mo: *MObj) void {
    // Default death sound
    const sound: Sfx = if (doomstat.gamemode == .Commercial and mo.health < -50)
        // If the player dies with less than -50% without gibbing
        .pdiehi
    else
        .pldeth;

    s_sound.S_StartSound_Zig(mo, sound);
}
