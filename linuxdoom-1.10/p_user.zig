const c = @cImport({
    @cInclude("d_event.h");
    @cInclude("d_player.h");
    @cInclude("p_local.h");
    @cInclude("p_mobj.h");
    @cInclude("p_spec.h");
    @cInclude("r_main.h");
    @cInclude("doomstat.h");
    @cInclude("tables.h");
});

const doomdef = @import("doomdef.zig");
const PowerType = doomdef.PowerType;
const WeaponType = doomdef.WeaponType;

const doomstat = @import("doomstat.zig");

const d_player = @import("d_player.zig");
const CF_NOCLIP = d_player.CF_NOCLIP;
const CF_NOMOMENTUM = d_player.CF_NOMOMENTUM;
const Player = d_player.Player;

const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FixedMul = m_fixed.FixedMul;

// Index of the special effects (INVUL inverse) map.
const INVERSECOLORMAP = 32;

// 16 pixels of bob
const MAXBOB = 0x100000;

var onground = false;

//
// P_Thrust
// Moves the given origin along a given angle.
//
fn P_Thrust(player: *Player, angle: c.angle_t, move: fixed_t) void {
    const fineangle = angle >> c.ANGLETOFINESHIFT;

    player.mo.?.momx += FixedMul(move, c.finecosine[fineangle]);
    player.mo.?.momy += FixedMul(move, c.finesine[fineangle]);
}


//
// P_CalcHeight
// Calculate the walking / running height adjustment
//
fn P_CalcHeight(player: *Player) void {
    // Regular movement bobbing
    // (needs to be calculated for gun swing
    // even if not on ground)
    // OPTIMIZE: tablify angle
    // Note: a LUT allows for effects
    //  like a ramp with low health.
    player.bob = FixedMul(player.mo.?.momx, player.mo.?.momx) + FixedMul(player.mo.?.momy, player.mo.?.momy);
    player.bob >>= 2;
    player.bob = @min(player.bob, MAXBOB);

    if (player.cheats & CF_NOMOMENTUM != 0 or !onground) {
        // BUG: This block is suspicious, setting viewz three different ways
        player.viewz = player.mo.?.z + c.VIEWHEIGHT;
        player.viewz = @min(player.viewz, player.mo.?.ceilingz - 4*c.FRACUNIT);
        player.viewz = player.mo.?.z + player.viewheight;
        return;
    }

    const angle = (c.FINEANGLES / 20 * c.leveltime) & c.FINEMASK;
    const bob = FixedMul(@divTrunc(player.bob, 2), c.finesine[@intCast(angle)]);


    // move viewheight
    if (player.playerstate == .Live) {
        player.viewheight += player.deltaviewheight;

        if (player.viewheight > c.VIEWHEIGHT) {
            player.viewheight = c.VIEWHEIGHT;
            player.deltaviewheight = 0;
        }

        if (player.viewheight < c.VIEWHEIGHT/2) {
            player.viewheight = c.VIEWHEIGHT/2;
            if (player.deltaviewheight <= 0) {
                player.deltaviewheight = 1;
            }
        }

        if (player.deltaviewheight != 0) {
            player.deltaviewheight += c.FRACUNIT/4;
            if (player.deltaviewheight == 0) {
                player.deltaviewheight = 1;
            }
        }
    }
    player.viewz = @min(player.mo.?.z + player.viewheight + bob, player.mo.?.ceilingz - 4*c.FRACUNIT);
}


//
// P_MovePlayer
//
fn P_MovePlayer(player: *Player) void {
    const cmd = &player.cmd;

    player.mo.?.angle +%= @bitCast(@as(c_int, cmd.angleturn) << 16);

    // Do not let the player control movement
    // if not on ground.
    onground = player.mo.?.z <= player.mo.?.floorz;

    if (cmd.forwardmove != 0 and onground) {
        P_Thrust(player, player.mo.?.angle, @as(c_int, @as(i8, @bitCast(cmd.forwardmove))) * 2048);
    }

    if (cmd.sidemove != 0 and onground) {
        P_Thrust(player, player.mo.?.angle -% c.ANG90, @as(c_int, @as(i8, @bitCast(cmd.sidemove))) * 2048);
    }

    if ((cmd.forwardmove != 0 or cmd.sidemove != 0) and player.mo.?.state == &d_player.c.states[c.S_PLAY]) {
        _ = d_player.c.P_SetMobjState(player.mo, c.S_PLAY_RUN1);
    }
}


//
// P_DeathThink
// Fall on your face when dying.
// Decrease POV height to floor height.
//
const ANG5 = c.ANG90/18;

fn P_DeathThink(player: *Player) void {
    c.P_MovePsprites(@ptrCast(player));

    // fall to the ground
    if (player.viewheight > 6 * c.FRACUNIT) {
        player.viewheight -= c.FRACUNIT;
    }

    if (player.viewheight < 6 * c.FRACUNIT) {
        player.viewheight = 6 * c.FRACUNIT;
    }

    player.deltaviewheight = 0;
    onground = player.mo.?.z <= player.mo.?.floorz;
    P_CalcHeight(player);

    if (player.attacker != null and player.attacker != player.mo) {
        const angle = c.R_PointToAngle2(player.mo.?.x, player.mo.?.y, player.attacker.?.x, player.attacker.?.y);
        const delta = angle -% player.mo.?.angle;

        if (delta < ANG5 or delta > -ANG5) {
            // Looking at killer,
            //  so fade damage flash down.
            player.mo.?.angle = angle;

            if (player.damagecount != 0) {
                player.damagecount -= 1;
            }
        } else if (delta < c.ANG180) {
            player.mo.?.angle += ANG5;
        } else {
            player.mo.?.angle -%= ANG5;
        }
    } else if (player.damagecount != 0) {
        player.damagecount -= 1;
    }

    if (player.cmd.buttons & c.BT_USE != 0) {
        player.playerstate = .Reborn;
    }
}


//
// P_PlayerThink
//
pub export fn P_PlayerThink(player: *Player) void {
    // fixme: do this in the cheat code
    if (player.cheats & CF_NOCLIP != 0) {
        player.mo.?.flags |= c.MF_NOCLIP;
    } else {
        player.mo.?.flags &= ~c.MF_NOCLIP;
    }

    // chain saw run forward
    const cmd = &player.cmd;
    if (player.mo.?.flags & c.MF_JUSTATTACKED != 0) {
        cmd.angleturn = 0;
        cmd.forwardmove = 0xc800/512;
        cmd.sidemove = 0;
        player.mo.?.flags &= ~c.MF_JUSTATTACKED;
    }

    if (player.playerstate == .Dead) {
        P_DeathThink(player);
        return;
    }

    // Move around.
    // Reactiontime is used to prevent movement
    //  for a bit after a teleport.
    if (player.mo.?.reactiontime != 0) {
        player.mo.?.reactiontime -= 1;
    } else {
        P_MovePlayer(player);
    }

    P_CalcHeight(player);

    if (player.mo.?.subsector[0].sector[0].special != 0) {
        c.P_PlayerInSpecialSector(@ptrCast(player));
    }

    // Check for weapon change.

    // A special event has no other buttons.
    if (cmd.buttons & c.BT_SPECIAL != 0) {
        cmd.buttons = 0;
    }

    if (cmd.buttons & c.BT_CHANGE != 0) {
        // The actual changing of the weapon is done
        //  when the weapon psprite can do it
        //  (read: not in the middle of an attack).
        var newweapon: WeaponType = @enumFromInt((cmd.buttons & c.BT_WEAPONMASK) >> c.BT_WEAPONSHIFT);

        if (newweapon == .Fist
            and player.weaponowned[@intFromEnum(WeaponType.Chainsaw)] != 0
            and !(player.readyweapon == .Chainsaw
                and player.powers[@intFromEnum(PowerType.Strength)] != 0)) {
            newweapon = .Chainsaw;
        }

        if (doomstat.gamemode == .Commercial
            and newweapon == .Shotgun
            and player.weaponowned[@intFromEnum(WeaponType.SuperShotgun)] != 0
            and player.readyweapon != .SuperShotgun) {
            newweapon = .SuperShotgun;
        }

        if (player.weaponowned[@intFromEnum(newweapon)] != 0
            and newweapon != player.readyweapon) {
            // Do not go to plasma or BFG in shareware,
            //  even if cheated.
            if ((newweapon != .Plasma and newweapon != .Bfg) or doomstat.gamemode != .Shareware) {
                player.pendingweapon = newweapon;
            }
        }
    }

    // check for use
    if (cmd.buttons & c.BT_USE != 0) {
        if (player.usedown == c.false) {
            c.P_UseLines(@ptrCast(player));
            player.usedown = c.true;
        }
    } else {
        player.usedown = c.false;
    }

    // cycle psprites
    c.P_MovePsprites(@ptrCast(player));

    // Counters, time dependend power ups.

    // Strength counts up to diminish fade.
    if (player.powers[@intFromEnum(PowerType.Strength)] != 0) {
        player.powers[@intFromEnum(PowerType.Strength)] += 1;
    }

    if (player.powers[@intFromEnum(PowerType.Invulnerability)] != 0) {
        player.powers[@intFromEnum(PowerType.Invulnerability)] -= 1;
    }

    if (player.powers[@intFromEnum(PowerType.Invisibility)] != 0) {
        player.powers[@intFromEnum(PowerType.Invisibility)] -= 1;
        if (player.powers[@intFromEnum(PowerType.Invisibility)] == 0) {
            player.mo.?.flags &= ~c.MF_SHADOW;
        }
    }

    if (player.powers[@intFromEnum(PowerType.Infrared)] != 0) {
        player.powers[@intFromEnum(PowerType.Infrared)] -= 1;
    }

    if (player.powers[@intFromEnum(PowerType.IronFeet)] != 0) {
        player.powers[@intFromEnum(PowerType.IronFeet)] -= 1;
    }

    if (player.damagecount != 0) {
        player.damagecount -= 1;
    }

    if (player.bonuscount != 0) {
        player.bonuscount -= 1;
    }

    // Handling colormaps.
    if (player.powers[@intFromEnum(PowerType.Invulnerability)] != 0) {
        if (player.powers[@intFromEnum(PowerType.Invulnerability)] > 4 * 32
            or player.powers[@intFromEnum(PowerType.Invulnerability)] & 8 != 0) {
            player.fixedcolormap = INVERSECOLORMAP;
        } else {
            player.fixedcolormap = 0;
        }
    } else if (player.powers[@intFromEnum(PowerType.Infrared)] != 0) {
        if (player.powers[@intFromEnum(PowerType.Infrared)] > 4 * 32
            or player.powers[@intFromEnum(PowerType.Infrared)] & 8 != 0) {
            // almost full bright
            player.fixedcolormap = 1;
        } else {
            player.fixedcolormap = 0;
        }
    } else {
        player.fixedcolormap = 0;
    }
}
