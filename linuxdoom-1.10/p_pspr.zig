const c = @import("c");
const std = @import("std");

const d_items = @import("d_items.zig");
const d_player = @import("d_player.zig");
const Player = d_player.Player;
const PSprNum = d_player.PSprNum;
const doomstat = @import("doomstat.zig");
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FRACBITS = m_fixed.FRACBITS;
const FRACUNIT = m_fixed.FRACUNIT;
const FixedMul = m_fixed.FixedMul;
const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_enemy = @import("p_enemy.zig");
const p_inter = @import("p_inter.zig");
const p_map = @import("p_map.zig");
const p_mobj = @import("p_mobj.zig");
const MF_JUSTATTACKED = p_mobj.MF_JUSTATTACKED;
const MObj = p_mobj.MObj;
const p_tick = @import("p_tick.zig");
const s_sound = @import("s_sound.zig");

const LOWERSPEED = 6 * FRACUNIT;
const RAISESPEED = 6 * FRACUNIT;

const WEAPONBOTTOM = 128 * FRACUNIT;
const WEAPONTOP = 32 * FRACUNIT;

// plasma cells for a bfg attack
const BFGCELLS = 40;

fn P_SetPsprite(player: *Player, position: PSprNum, initial: c.statenum_t) void {
    const psp = player.psprite(position);
    var stnum = initial;

    // an initial state of 0 could cycle through
    while (true) {
        if (stnum == c.S_NULL) {
            // object removed itself
            psp.state = null;
            return;
        }

        const state = &c.states[@intCast(stnum)];
        psp.state = state;
        psp.tics = @intCast(state.tics); // could be 0

        if (state.misc1 != 0) {
            // coordinate set
            psp.sx = @as(fixed_t, @intCast(state.misc1)) << FRACBITS;
            psp.sy = @as(fixed_t, @intCast(state.misc2)) << FRACBITS;
        }

        // Call action routine. Modified handling.
        if (state.action.acp2) |acp2| {
            acp2(player, psp);
            if (psp.state == null) return;
        }

        if (psp.tics != 0) return;
        stnum = psp.state.*.nextstate;
    }
}

/// Starts bringing the pending weapon up from the bottom of the screen.
fn P_BringUpWeapon(player: *Player) void {
    if (player.pendingweapon == .NoChange) {
        player.pendingweapon = player.readyweapon;
    }

    if (player.pendingweapon == .Chainsaw) {
        s_sound.S_StartSound_Zig(player.mo, .sawup);
    }

    const newstate = d_items.weaponUpState(player.pendingweapon);

    player.pendingweapon = .NoChange;
    player.psprite(.Weapon).sy = WEAPONBOTTOM;

    P_SetPsprite(player, .Weapon, newstate);
}

/// Returns true if there is enough ammo to shoot. If not, selects the next
/// weapon to use.
fn P_CheckAmmo(player: *Player) bool {
    const ammo = d_items.weaponAmmo(player.readyweapon);

    // Minimal amount for one shot varies.
    const count: c_int = switch (player.readyweapon) {
        .Bfg => BFGCELLS,
        .SuperShotgun => 2, // Double barrel
        else => 1, // Regular
    };

    // Some do not need ammunition anyway. Return if current ammunition
    // sufficient.
    if (ammo == .NoAmmo or player.ammoOf(ammo).* >= count) {
        return true;
    }

    // Out of ammo, pick a weapon to change to. Preferences are set here.
    // BUG: vanilla wants one more than a shot's worth for the super shotgun
    // (3 shells) and BFG (41 cells). Kept for demo sync.
    const mode = doomstat.gamemode;
    player.pendingweapon = pick: {
        if (player.owns(.Plasma) and player.ammoOf(.Cell).* > 0 and mode != .Shareware) break :pick .Plasma;
        if (player.owns(.SuperShotgun) and player.ammoOf(.Shell).* > 2 and mode == .Commercial) break :pick .SuperShotgun;
        if (player.owns(.Chaingun) and player.ammoOf(.Clip).* > 0) break :pick .Chaingun;
        if (player.owns(.Shotgun) and player.ammoOf(.Shell).* > 0) break :pick .Shotgun;
        if (player.ammoOf(.Clip).* > 0) break :pick .Pistol;
        if (player.owns(.Chainsaw)) break :pick .Chainsaw;
        if (player.owns(.Missile) and player.ammoOf(.Missile).* > 0) break :pick .Missile;
        if (player.owns(.Bfg) and player.ammoOf(.Cell).* > BFGCELLS and mode != .Shareware) break :pick .Bfg;

        break :pick .Fist; // If everything fails.
    };

    // Now set appropriate weapon overlay.
    P_SetPsprite(player, .Weapon, d_items.weaponDownState(player.readyweapon));

    return false;
}

fn P_FireWeapon(player: *Player) void {
    if (!P_CheckAmmo(player)) return;

    _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY_ATK1);
    P_SetPsprite(player, .Weapon, d_items.weaponAttackState(player.readyweapon));
    p_enemy.P_NoiseAlert(player.mo.?, player.mo.?);
}

/// Player died, so put the weapon away.
pub fn P_DropWeapon(player: *Player) void {
    P_SetPsprite(player, .Weapon, d_items.weaponDownState(player.readyweapon));
}

/// The player can fire the weapon or change to another weapon at this time.
/// Follows after getting weapon up, or after previous attack/fire sequence.
pub export fn A_WeaponReady(player: *Player, psp: *c.pspdef_t) void {
    // get out of attack state
    if (player.mo.?.state == &c.states[c.S_PLAY_ATK1] or
        player.mo.?.state == &c.states[c.S_PLAY_ATK2])
    {
        _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY);
    }

    if (player.readyweapon == .Chainsaw and psp.state == &c.states[c.S_SAW]) {
        s_sound.S_StartSound_Zig(player.mo, .sawidl);
    }

    // check the change
    //  if player is dead, put the weapon away
    if (player.pendingweapon != .NoChange or player.health == 0) {
        // change weapon
        //  (pending weapon should already be validated)
        P_SetPsprite(player, .Weapon, d_items.weaponDownState(player.readyweapon));
        return;
    }

    // check for fire
    //  the missile launcher and bfg do not auto fire
    if (player.cmd.buttons & c.BT_ATTACK != 0) {
        if (player.attackdown == c.false or
            (player.readyweapon != .Missile and player.readyweapon != .Bfg))
        {
            player.attackdown = c.true;
            P_FireWeapon(player);
            return;
        }
    } else {
        player.attackdown = c.false;
    }

    // bob the weapon based on movement speed
    const anglex = (128 *% p_tick.leveltime) & c.FINEMASK;
    const angley = anglex & (c.FINEANGLES / 2 - 1);
    psp.sx = FRACUNIT + FixedMul(player.bob, c.finecosine[@intCast(anglex)]);
    psp.sy = WEAPONTOP + FixedMul(player.bob, c.finesine[@intCast(angley)]);
}

/// The player can re-fire the weapon without lowering it entirely.
pub export fn A_ReFire(player: *Player, _: *c.pspdef_t) void {
    // check for fire
    //  (if a weaponchange is pending, let it go through instead)
    if (player.cmd.buttons & c.BT_ATTACK != 0 and
        player.pendingweapon == .NoChange and
        player.health != 0)
    {
        player.refire += 1;
        P_FireWeapon(player);
    } else {
        player.refire = 0;
        _ = P_CheckAmmo(player);
    }
}

pub export fn A_CheckReload(player: *Player, _: *c.pspdef_t) void {
    _ = P_CheckAmmo(player);
}

/// Lowers current weapon and changes weapon at bottom.
pub export fn A_Lower(player: *Player, psp: *c.pspdef_t) void {
    psp.sy += LOWERSPEED;

    // Is already down.
    if (psp.sy < WEAPONBOTTOM) return;

    // Player is dead.
    if (player.playerstate == .Dead) {
        psp.sy = WEAPONBOTTOM;

        // don't bring weapon back up
        return;
    }

    // The old weapon has been lowered off the screen, so change the weapon
    // and start raising it
    if (player.health == 0) {
        // Player is dead, so keep the weapon off screen.
        P_SetPsprite(player, .Weapon, c.S_NULL);
        return;
    }

    player.readyweapon = player.pendingweapon;

    P_BringUpWeapon(player);
}

pub export fn A_Raise(player: *Player, psp: *c.pspdef_t) void {
    psp.sy -= RAISESPEED;

    if (psp.sy > WEAPONTOP) return;

    psp.sy = WEAPONTOP;

    // The weapon has been raised all the way, so change to the ready state.
    P_SetPsprite(player, .Weapon, d_items.weaponReadyState(player.readyweapon));
}

pub export fn A_GunFlash(player: *Player, _: *c.pspdef_t) void {
    _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY_ATK2);
    P_SetPsprite(player, .Flash, d_items.weaponFlashState(player.readyweapon));
}

pub export fn A_Punch(player: *Player, _: *c.pspdef_t) void {
    const multiplier: c_int = if (player.power(.Strength).* != 0) 10 else 1;
    const damage = 2 * (@mod(P_Random(), 10) + 1) * multiplier;

    const spread = (P_Random() - P_Random()) << 18;
    const angle = player.mo.?.angle +% @as(c.angle_t, @bitCast(spread));
    const slope = p_map.P_AimLineAttack(player.mo.?, angle, c.MELEERANGE);
    p_map.P_LineAttack(player.mo.?, angle, c.MELEERANGE, slope, damage);

    // turn to face target
    if (p_map.linetarget) |linetarget| {
        s_sound.S_StartSound_Zig(player.mo, .punch);
        player.mo.?.angle = c.R_PointToAngle2(player.mo.?.x, player.mo.?.y, linetarget.x, linetarget.y);
    }
}

pub export fn A_Saw(player: *Player, _: *c.pspdef_t) void {
    const damage = 2 * (@mod(P_Random(), 10) + 1);

    const spread = (P_Random() - P_Random()) << 18;
    const angle = player.mo.?.angle +% @as(c.angle_t, @bitCast(spread));
    // use meleerange + 1 so the puff doesn't skip the flash
    const slope = p_map.P_AimLineAttack(player.mo.?, angle, c.MELEERANGE + 1);
    p_map.P_LineAttack(player.mo.?, angle, c.MELEERANGE + 1, slope, damage);

    const linetarget = p_map.linetarget orelse {
        s_sound.S_StartSound_Zig(player.mo, .sawful);
        return;
    };

    s_sound.S_StartSound_Zig(player.mo, .sawhit);

    // turn to face target
    const newangle = c.R_PointToAngle2(player.mo.?.x, player.mo.?.y, linetarget.x, linetarget.y);
    const delta = newangle -% player.mo.?.angle;

    if (delta > c.ANG180) {
        // BUG: in C, -ANG90/20 is unsigned (about 13.5°), so after
        // delta > ANG180 this is never true. Kept for demo sync.
        if (delta < -c.ANG90 / 20) {
            player.mo.?.angle = newangle +% c.ANG90 / 21;
        } else {
            player.mo.?.angle -%= c.ANG90 / 20;
        }
    } else {
        if (delta > c.ANG90 / 20) {
            player.mo.?.angle = newangle -% c.ANG90 / 21;
        } else {
            player.mo.?.angle +%= c.ANG90 / 20;
        }
    }

    player.mo.?.flags |= MF_JUSTATTACKED;
}

pub export fn A_FireMissile(player: *Player, _: *c.pspdef_t) void {
    player.readyAmmo().* -= 1;
    p_mobj.P_SpawnPlayerMissile(player.mo.?, c.MT_ROCKET);
}

pub export fn A_FireBFG(player: *Player, _: *c.pspdef_t) void {
    player.readyAmmo().* -= BFGCELLS;
    p_mobj.P_SpawnPlayerMissile(player.mo.?, c.MT_BFG);
}

pub export fn A_FirePlasma(player: *Player, _: *c.pspdef_t) void {
    player.readyAmmo().* -= 1;
    const flash = d_items.weaponFlashState(player.readyweapon) +
        @as(c.statenum_t, @intCast(P_Random() & 1));
    P_SetPsprite(player, .Flash, flash);
    p_mobj.P_SpawnPlayerMissile(player.mo.?, c.MT_PLASMA);
}

var bulletslope: fixed_t = 0;

/// Sets a slope so a near miss is at approximately the height of the
/// intended target
fn P_BulletSlope(mo: *MObj) void {
    // see which target is to be aimed at
    var an = mo.angle;
    bulletslope = p_map.P_AimLineAttack(mo, an, 16 * 64 * FRACUNIT);

    if (p_map.linetarget == null) {
        an +%= 1 << 26;
        bulletslope = p_map.P_AimLineAttack(mo, an, 16 * 64 * FRACUNIT);
        if (p_map.linetarget == null) {
            an -%= 2 << 26;
            bulletslope = p_map.P_AimLineAttack(mo, an, 16 * 64 * FRACUNIT);
        }
    }
}

fn P_GunShot(mo: *MObj, accurate: bool) void {
    const damage = 5 * (@mod(P_Random(), 3) + 1);
    var angle = mo.angle;

    if (!accurate) {
        const spread = (P_Random() - P_Random()) << 18;
        angle +%= @bitCast(spread);
    }

    p_map.P_LineAttack(mo, angle, c.MISSILERANGE, bulletslope, damage);
}

pub export fn A_FirePistol(player: *Player, _: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .pistol);
    _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY_ATK2);

    player.readyAmmo().* -= 1;

    P_SetPsprite(player, .Flash, d_items.weaponFlashState(player.readyweapon));

    P_BulletSlope(player.mo.?);
    P_GunShot(player.mo.?, player.refire == c.false);
}

pub export fn A_FireShotgun(player: *Player, _: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .shotgn);
    _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY_ATK2);

    player.readyAmmo().* -= 1;

    P_SetPsprite(player, .Flash, d_items.weaponFlashState(player.readyweapon));

    P_BulletSlope(player.mo.?);

    for (0..7) |_| {
        P_GunShot(player.mo.?, false);
    }
}

pub export fn A_FireShotgun2(player: *Player, _: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .dshtgn);
    _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY_ATK2);

    player.readyAmmo().* -= 2;

    P_SetPsprite(player, .Flash, d_items.weaponFlashState(player.readyweapon));

    P_BulletSlope(player.mo.?);

    for (0..20) |_| {
        const damage = 5 * (@mod(P_Random(), 3) + 1);
        const spread = (P_Random() - P_Random()) << 19;
        const angle = player.mo.?.angle +% @as(c.angle_t, @bitCast(spread));

        const bslope = bulletslope + ((P_Random() - P_Random()) << 5);
        p_map.P_LineAttack(player.mo.?, angle, c.MISSILERANGE, bslope, damage);
    }
}

pub export fn A_FireCGun(player: *Player, psp: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .pistol);

    if (player.readyAmmo().* == 0) {
        return;
    }

    _ = p_mobj.P_SetMobjState(player.mo.?, c.S_PLAY_ATK2);

    player.readyAmmo().* -= 1;

    const newstate: c.statenum_t = @intCast(d_items.weaponFlashState(player.readyweapon) +
        (psp.state - &c.states[c.S_CHAIN1]));
    P_SetPsprite(player, .Flash, newstate);

    P_BulletSlope(player.mo.?);
    P_GunShot(player.mo.?, player.refire == 0);
}

pub export fn A_Light0(player: *Player, _: *c.pspdef_t) void {
    player.extralight = 0;
}

pub export fn A_Light1(player: *Player, _: *c.pspdef_t) void {
    player.extralight = 1;
}

pub export fn A_Light2(player: *Player, _: *c.pspdef_t) void {
    player.extralight = 2;
}

pub export fn A_BFGSpray(mo: *MObj) void {
    for (0..40) |i| {
        const an = mo.angle -% c.ANG90 / 2 +% @as(c.angle_t, c.ANG90 / 40) * @as(c.angle_t, @intCast(i));

        // mo.target is the originator (player) of the missle
        // BUG: loading a save clears mobj targets, so a BFG ball fired
        // before the save has no target here. Vanilla crashes; this panics.
        _ = p_map.P_AimLineAttack(mo.target.?, an, 16 * 64 * FRACUNIT);

        const linetarget = p_map.linetarget orelse continue;

        _ = p_mobj.P_SpawnMobj(
            linetarget.x,
            linetarget.y,
            linetarget.z + (linetarget.height >> 2),
            c.MT_EXTRABFG,
        );

        var damage: c_int = 0;
        for (0..15) |_| {
            damage += @mod(P_Random(), 8) + 1;
        }

        p_inter.P_DamageMobj(linetarget, mo.target, mo.target, damage);
    }
}

pub export fn A_BFGsound(player: *Player, _: *c.pspdef_t) void {
    s_sound.S_StartSound_Zig(player.mo, .bfg);
}

/// Called at start of level for each player.
pub fn P_SetupPsprites(player: *Player) void {
    // remove all psprites
    for (&player.psprites) |*psp| {
        psp.state = null;
    }

    // spawn the gun
    player.pendingweapon = player.readyweapon;
    P_BringUpWeapon(player);
}

/// Called every tic by player thinking routine.
pub fn P_MovePsprites(player: *Player) void {
    for (std.enums.values(PSprNum)) |n| {
        const psp = player.psprite(n);

        // a null state means not active
        const state = psp.state orelse continue;

        // drop tic count and possibly change state
        // a -1 tic count never changes
        if (psp.tics != -1) {
            psp.tics -= 1;
            if (psp.tics == 0) {
                P_SetPsprite(player, n, state.*.nextstate);
            }
        }
    }

    const weapon = player.psprite(.Weapon);
    const flash = player.psprite(.Flash);
    flash.sx = weapon.sx;
    flash.sy = weapon.sy;
}
