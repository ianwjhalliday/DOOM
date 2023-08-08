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

// TODO: restore imports once no C files call FixedMul
// const fixed_t = @import("m_fixed.zig").fixed_t;
// const FixedMul = @import("m_fixed.zig").FixedMul;
const fixed_t = c_int;
extern fn FixedMul(a: fixed_t, b: fixed_t) fixed_t;

// Index of the special effects (INVUL inverse) map.
const INVERSECOLORMAP = 32;

// 16 pixels of bob
const MAXBOB = 0x100000;

var onground = false;

//
// P_Thrust
// Moves the given origin along a given angle.
//
fn P_Thrust(player: *c.player_t, angle: c.angle_t, move: fixed_t) void {
    const fineangle = angle >> c.ANGLETOFINESHIFT;

    player.mo[0].momx += FixedMul(move, c.finecosine[fineangle]);
    player.mo[0].momy += FixedMul(move, c.finesine[fineangle]);
}


//
// P_CalcHeight
// Calculate the walking / running height adjustment
//
fn P_CalcHeight(player: *c.player_t) void {
    // Regular movement bobbing
    // (needs to be calculated for gun swing
    // even if not on ground)
    // OPTIMIZE: tablify angle
    // Note: a LUT allows for effects
    //  like a ramp with low health.
    player.bob = FixedMul(player.mo[0].momx, player.mo[0].momx) + FixedMul(player.mo[0].momy, player.mo[0].momy);
    player.bob >>= 2;
    player.bob = @min(player.bob, MAXBOB);

    if (player.cheats & c.CF_NOMOMENTUM != 0 or !onground) {
        // BUG: This block is suspicious, setting viewz three different ways
        player.viewz = player.mo[0].z + c.VIEWHEIGHT;
        player.viewz = @min(player.viewz, player.mo[0].ceilingz - 4*c.FRACUNIT);
        player.viewz = player.mo[0].z + player.viewheight;
        return;
    }

    const angle = (c.FINEANGLES / 20 * c.leveltime) & c.FINEMASK;
    const bob = FixedMul(@divTrunc(player.bob, 2), c.finesine[@intCast(angle)]);


    // move viewheight
    if (player.playerstate == c.PST_LIVE) {
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
    player.viewz = @min(player.mo[0].z + player.viewheight + bob, player.mo[0].ceilingz - 4*c.FRACUNIT);
}


//
// P_MovePlayer
//
fn P_MovePlayer(player: *c.player_t) void {
    const cmd = &player.cmd;

    player.mo[0].angle +%= @bitCast(@as(c_int, cmd.angleturn) << 16);

    // Do not let the player control movement
    // if not on ground.
    onground = player.mo[0].z <= player.mo[0].floorz;

    if (cmd.forwardmove != 0 and onground) {
        P_Thrust(player, player.mo[0].angle, @as(c_int, @as(i8, @bitCast(cmd.forwardmove))) * 2048);
    }

    if (cmd.sidemove != 0 and onground) {
        P_Thrust(player, player.mo[0].angle -% c.ANG90, @as(c_int, @as(i8, @bitCast(cmd.sidemove))) * 2048);
    }

    if ((cmd.forwardmove != 0 or cmd.sidemove != 0) and player.mo[0].state == &c.states[c.S_PLAY]) {
        _ = c.P_SetMobjState(player.mo, c.S_PLAY_RUN1);
    }
}


//
// P_DeathThink
// Fall on your face when dying.
// Decrease POV height to floor height.
//
const ANG5 = c.ANG90/18;

fn P_DeathThink(player: *c.player_t) void {
    c.P_MovePsprites(player);

    // fall to the ground
    if (player.viewheight > 6 * c.FRACUNIT) {
        player.viewheight -= c.FRACUNIT;
    }

    if (player.viewheight < 6 * c.FRACUNIT) {
        player.viewheight = 6 * c.FRACUNIT;
    }

    player.deltaviewheight = 0;
    onground = player.mo[0].z <= player.mo[0].floorz;
    P_CalcHeight(player);

    if (player.attacker != null and player.attacker != player.mo) {
        const angle = c.R_PointToAngle2(player.mo[0].x, player.mo[0].y, player.attacker[0].x, player.attacker[0].y);
        const delta = angle -% player.mo[0].angle;

        if (delta < ANG5 or delta > -ANG5) {
            // Looking at killer,
            //  so fade damage flash down.
            player.mo[0].angle = angle;

            if (player.damagecount != 0) {
                player.damagecount -= 1;
            }
        } else if (delta < c.ANG180) {
            player.mo[0].angle += ANG5;
        } else {
            player.mo[0].angle -%= ANG5;
        }
    } else if (player.damagecount != 0) {
        player.damagecount -= 1;
    }

    if (player.cmd.buttons & c.BT_USE != 0) {
        player.playerstate = c.PST_REBORN;
    }
}


//
// P_PlayerThink
//
pub export fn P_PlayerThink(player: *c.player_t) void {
    // fixme: do this in the cheat code
    if (player.cheats & c.CF_NOCLIP != 0) {
        player.mo[0].flags |= c.MF_NOCLIP;
    } else {
        player.mo[0].flags &= ~c.MF_NOCLIP;
    }

    // chain saw run forward
    const cmd = &player.cmd;
    if (player.mo[0].flags & c.MF_JUSTATTACKED != 0) {
        cmd.angleturn = 0;
        cmd.forwardmove = 0xc800/512;
        cmd.sidemove = 0;
        player.mo[0].flags &= ~c.MF_JUSTATTACKED;
    }

    if (player.playerstate == c.PST_DEAD) {
        P_DeathThink(player);
        return;
    }

    // Move around.
    // Reactiontime is used to prevent movement
    //  for a bit after a teleport.
    if (player.mo[0].reactiontime != 0) {
        player.mo[0].reactiontime -= 1;
    } else {
        P_MovePlayer(player);
    }

    P_CalcHeight(player);

    if (player.mo[0].subsector[0].sector[0].special != 0) {
        c.P_PlayerInSpecialSector(player);
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
        var newweapon = (cmd.buttons & c.BT_WEAPONMASK) >> c.BT_WEAPONSHIFT;

        if (newweapon == c.wp_fist and player.weaponowned[c.wp_chainsaw] != 0 and player.weaponowned[c.wp_chainsaw] != 0 and !(player.readyweapon == c.wp_chainsaw and player.powers[c.pw_strength] != 0)) {
            newweapon = c.wp_chainsaw;
        }

        if (c.gamemode == c.commercial and newweapon == c.wp_shotgun and player.weaponowned[c.wp_supershotgun] != 0 and player.readyweapon != c.wp_supershotgun) {
            newweapon = c.wp_supershotgun;
        }

        if (player.weaponowned[@intCast(newweapon)] != 0 and newweapon != player.readyweapon) {
            // Do not go to plasma or BFG in shareware,
            //  even if cheated.
            if ((newweapon != c.wp_plasma and newweapon != c.wp_bfg) or c.gamemode != c.shareware) {
                player.pendingweapon = @intCast(newweapon);
            }
        }
    }

    // check for use
    if (cmd.buttons & c.BT_USE != 0) {
        if (player.usedown == c.false) {
            c.P_UseLines(player);
            player.usedown = c.true;
        }
    } else {
        player.usedown = c.false;
    }

    // cycle psprites
    c.P_MovePsprites(player);

    // Counters, time dependend power ups.

    // Strength counts up to diminish fade.
    if (player.powers[c.pw_strength] != 0) {
        player.powers[c.pw_strength] += 1;
    }

    if (player.powers[c.pw_invulnerability] != 0) {
        player.powers[c.pw_invulnerability] -= 1;
    }

    if (player.powers[c.pw_invisibility] != 0) {
        player.powers[c.pw_invisibility] -= 1;
        if (player.powers[c.pw_invisibility] == 0) {
            player.mo[0].flags &= ~c.MF_SHADOW;
        }
    }

    if (player.powers[c.pw_infrared] != 0) {
        player.powers[c.pw_infrared] -= 1;
    }

    if (player.powers[c.pw_ironfeet] != 0) {
        player.powers[c.pw_ironfeet] -= 1;
    }

    if (player.damagecount != 0) {
        player.damagecount -= 1;
    }

    if (player.bonuscount != 0) {
        player.bonuscount -= 1;
    }

    // Handling colormaps.
    if (player.powers[c.pw_invulnerability] != 0) {
        if (player.powers[c.pw_invulnerability] > 4 * 32 or player.powers[c.pw_invulnerability] & 8 != 0) {
            player.fixedcolormap = INVERSECOLORMAP;
        } else {
            player.fixedcolormap = 0;
        }
    } else if (player.powers[c.pw_infrared] != 0) {
        if (player.powers[c.pw_infrared] > 4 * 32 or player.powers[c.pw_infrared] & 8 != 0) {
            // almost full bright
            player.fixedcolormap = 1;
        } else {
            player.fixedcolormap = 0;
        }
    } else {
        player.fixedcolormap = 0;
    }
}
