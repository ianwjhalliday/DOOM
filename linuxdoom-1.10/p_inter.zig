const c = @cImport({
    @cInclude("doomtype.h");
    @cInclude("doomstat.h");
    @cInclude("info.h");
    @cInclude("dstrings.h");
    @cInclude("p_local.h");
    @cInclude("p_mobj.h");
    @cInclude("r_main.h");
});

const am_map = @import("am_map.zig");
const AM_Stop = am_map.AM_Stop;
const doomdef = @import("doomdef.zig");
const AmmoType = doomdef.AmmoType;
const Card = doomdef.Card;
const PowerDuration = doomdef.PowerDuration;
const PowerType = doomdef.PowerType;
const WeaponType = doomdef.WeaponType;
const doomstat = @import("doomstat.zig");
const d_items = @import("d_items.zig");
const d_player = @import("d_player.zig");
const Player = d_player.Player;
const g_game = @import("g_game.zig");
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const I_Tactile = i_system.I_Tactile;
const m_fixed = @import("m_fixed.zig");
const FixedMul = m_fixed.FixedMul;
const FRACUNIT = m_fixed.FRACUNIT;
const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_mobj = @import("p_mobj.zig");
const MF_CORPSE = p_mobj.MF_CORPSE;
const MF_COUNTITEM = p_mobj.MF_COUNTITEM;
const MF_COUNTKILL = p_mobj.MF_COUNTKILL;
const MF_DROPPED = p_mobj.MF_DROPPED;
const MF_DROPOFF = p_mobj.MF_DROPOFF;
const MF_FLOAT = p_mobj.MF_FLOAT;
const MF_JUSTHIT = p_mobj.MF_JUSTHIT;
const MF_NOCLIP = p_mobj.MF_NOCLIP;
const MF_NOGRAVITY = p_mobj.MF_NOGRAVITY;
const MF_SHADOW = p_mobj.MF_SHADOW;
const MF_SHOOTABLE = p_mobj.MF_SHOOTABLE;
const MF_SKULLFLY = p_mobj.MF_SKULLFLY;
const MF_SOLID = p_mobj.MF_SOLID;
const MObj = p_mobj.MObj;
const P_RemoveMobj = p_mobj.P_RemoveMobj;
const P_SetMobjState = p_mobj.P_SetMobjState;
const P_SpawnMobj = p_mobj.P_SpawnMobj;
const sounds = @import("sounds.zig");
const Sfx = sounds.Sfx;
const s_sound = @import("s_sound.zig");
const S_StartSound = s_sound.S_StartSound_Zig;

const BONUSADD = 6;


// a weapon is found with two clip loads,
// a big item has five clip loads
pub export const maxammo = [@intFromEnum(AmmoType.NUMAMMO)]c_int{200, 50, 300, 50};
const clipammo = [@intFromEnum(AmmoType.NUMAMMO)]c_int{10, 4, 20, 1};


//
// GET STUFF
//

//
// P_GiveAmmo
// Num is the number of clip loads,
// not the individual count (0= 1/2 clip).
// Returns false if the ammo can't be picked up at all
//
fn P_GiveAmmo(player: *Player, ammo: AmmoType, _num: c_int) bool {
    if (ammo == .NoAmmo) {
        return false;
    }

    const ammoidx: usize = @intCast(@intFromEnum(ammo));

    if (player.ammo[ammoidx] == player.maxammo[ammoidx]) {
        return false;
    }

    var num = if (_num != 0)
        _num * clipammo[ammoidx]
    else
        @divTrunc(clipammo[ammoidx], 2);

    if (g_game.gameskill == .Baby or g_game.gameskill == .Nightmare) {
        // give double ammo in trainer mode,
        // you'll need in nightmare
        num <<= 1;
    }

    var oldammo = player.ammo[ammoidx];
    player.ammo[ammoidx] += num;

    if (player.ammo[ammoidx] > player.maxammo[ammoidx]) {
        player.ammo[ammoidx] = player.maxammo[ammoidx];
    }

    // If non zero ammo,
    // don't change up weapons,
    // player was lower on purpose.
    if (oldammo != 0) {
        return true;
    }

    // We were down to zero,
    // so select a new weapon.
    // Preferences are not user selectable.
    switch (ammo) {
        .Clip => {
            if (player.readyweapon == .Fist) {
                if (player.weaponowned[@intFromEnum(WeaponType.Chaingun)] != c.false) {
                    player.pendingweapon = .Chaingun;
                } else {
                    player.pendingweapon = .Pistol;
                }
            }
        },

        .Shell => {
            if (player.readyweapon == .Fist or player.readyweapon == .Pistol) {
                if (player.weaponowned[@intFromEnum(WeaponType.Shotgun)] != c.false) {
                    player.pendingweapon = .Shotgun;
                }
            }
        },

        .Cell => {
            if (player.readyweapon == .Fist or player.readyweapon == .Pistol) {
                if (player.weaponowned[@intFromEnum(WeaponType.Plasma)] != c.false) {
                    player.pendingweapon = .Plasma;
                }
            }
        },

        .Missile => {
            if (player.readyweapon == .Fist) {
                if (player.weaponowned[@intFromEnum(WeaponType.Missile)] != c.false) {
                    player.pendingweapon = .Missile;
                }
            }
        },

        else => {},
    }

    return true;
}


//
// P_GiveWeapon
// The weapon name may have a MF_DROPPED flag ored in.
//
fn P_GiveWeapon(player: *Player, weapon: WeaponType, dropped: bool) bool {
    const weaponidx = @intFromEnum(weapon);

    if (g_game.netgame != c.false and g_game.deathmatch != 2 and !dropped) {
        // leave placed weapon forever on net games
        if (player.weaponowned[weaponidx] != c.false) {
            return false;
        }

        player.bonuscount += BONUSADD;
        player.weaponowned[weaponidx] = c.true;


        if (g_game.deathmatch != 0) {
            _ = P_GiveAmmo(player, d_items.weaponinfo[weaponidx].ammo, 5);
        } else {
            _ = P_GiveAmmo(player, d_items.weaponinfo[weaponidx].ammo, 2);
        }
        player.pendingweapon = weapon;

        if (player == &g_game.players[g_game.consoleplayer]) {
            S_StartSound(null, .wpnup);
        }

        return false;
    }

    var gaveammo = false;
    if (d_items.weaponinfo[weaponidx].ammo != .NoAmmo) {
        // give one clip with a dropped weapon,
        // two clips with a found weapon
        if (dropped) {
            gaveammo = P_GiveAmmo(player, d_items.weaponinfo[weaponidx].ammo, 1);
        } else {
            gaveammo = P_GiveAmmo(player, d_items.weaponinfo[weaponidx].ammo, 2);
        }
    }

    var gaveweapon = false;
    if (player.weaponowned[weaponidx] == c.false) {
        gaveweapon = true;
        player.weaponowned[weaponidx] = c.true;
        player.pendingweapon = weapon;
    }

    return gaveweapon or gaveammo;
}

//
// P_GiveBody
// Returns false if the body isn't needed at all
//
fn P_GiveBody(player: *Player, num: c_int) bool {
    if (player.health >= c.MAXHEALTH) {
        return false;
    }

    player.health += num;
    if (player.health > c.MAXHEALTH) {
        player.health = c.MAXHEALTH;
    }
    player.mo.?.health = player.health;

    return true;
}


//
// P_GiveArmor
// Returns false if the armor is worse
// than the current armor.
//
fn P_GiveArmor(player: *Player, armortype: c_int) bool {
    const hits = armortype * 100;
    if (player.armorpoints >= hits) {
        return false;   // don't pick up
    }

    player.armortype = armortype;
    player.armorpoints = hits;

    return true;
}


//
// P_GiveCard
//
fn P_GiveCard(player: *Player, card: Card) void {
    const cardidx = @intFromEnum(card);

    if (player.cards[cardidx] != c.false) {
        return;
    }

    player.bonuscount = BONUSADD;
    player.cards[cardidx] = 1;
}


//
// P_GivePower
//
pub fn P_GivePower(player: *Player, power: PowerType) bool {
    const poweridx = @intFromEnum(power);

    switch (power) {
        .Invulnerability => {
            player.powers[poweridx] = PowerDuration.InvulnTics;
        },
        .Invisibility => {
            player.powers[poweridx] = PowerDuration.InvisTics;
            player.mo.?.flags |= MF_SHADOW;
        },
        .Infrared => {
            player.powers[poweridx] = PowerDuration.InfraTics;
        },
        .IronFeet => {
            player.powers[poweridx] = PowerDuration.IronTics;
        },
        .Strength => {
            _ = P_GiveBody(player, 100);
            player.powers[poweridx] = 1;
        },
        .AllMap => {
            if (player.powers[poweridx] != c.false) {
                return false;   // already got it
            }

            player.powers[poweridx] = 1;
        },
        else => unreachable,
    }

    return true;
}


//
// P_TouchSpecialThing
//
pub export fn P_TouchSpecialThing(special: *MObj, toucher: *MObj) void {
    const delta = special.z - toucher.z;

    if (delta > toucher.height or delta < -8 * FRACUNIT) {
        // out of reach
        return;
    }

    var sound = Sfx.itemup;
    const player = toucher.player.?;

    // Dead thing touching.
    // Can happen with a sliding player corpse.
    if (toucher.health <= 0) {
        return;
    }

    // Identify by sprite.
    switch (special.sprite) {
        // armor
        c.SPR_ARM1 => {
            if (!P_GiveArmor(player, 1)) {
                return;
            }
            player.message = c.GOTARMOR;
        },

        c.SPR_ARM2 => {
            if (!P_GiveArmor(player, 2)) {
                return;
            }
            player.message = c.GOTMEGA;
        },

        // bonus items
        c.SPR_BON1 => {
            player.health += 1;             // can go over 100%
            if (player.health > 200) {
                player.health = 200;
            }
            player.mo.?.health = player.health;
            player.message = c.GOTHTHBONUS;
        },

        c.SPR_BON2 => {
            player.armorpoints += 1;        // can go over 100%
            if (player.armorpoints > 200) {
                player.armorpoints = 200;
            }
            if (player.armortype == 0) {
                player.armortype = 1;
            }
            player.message = c.GOTARMBONUS;
        },

        c.SPR_SOUL => {
            player.health += 100;
            if (player.health > 200) {
                player.health = 200;
            }
            player.mo.?.health = player.health;
            player.message = c.GOTSUPER;
            sound = .getpow;
        },

        c.SPR_MEGA => {
            if (doomstat.gamemode != .Commercial) {
                return;
            }
            player.health = 200;
            player.mo.?.health = player.health;
            _ = P_GiveArmor(player, 2);
            player.message = c.GOTMSPHERE;
            sound = .getpow;
        },

        // cards
        // leave cards for everyone
        c.SPR_BKEY => {
            if (player.cards[@intFromEnum(Card.BlueCard)] == c.false) {
                player.message = c.GOTBLUECARD;
            }
            P_GiveCard(player, .BlueCard);
            if (g_game.netgame != c.false) {
                return;
            }
        },

        c.SPR_YKEY => {
            if (player.cards[@intFromEnum(Card.YellowCard)] == c.false) {
                player.message = c.GOTYELWCARD;
            }
            P_GiveCard(player, .YellowCard);
            if (g_game.netgame != c.false) {
                return;
            }
        },

        c.SPR_RKEY => {
            if (player.cards[@intFromEnum(Card.RedCard)] == c.false) {
                player.message = c.GOTREDCARD;
            }
            P_GiveCard(player, .RedCard);
            if (g_game.netgame != c.false) {
                return;
            }
        },

        c.SPR_BSKU => {
            if (player.cards[@intFromEnum(Card.BlueSkull)] == c.false) {
                player.message = c.GOTBLUESKUL;
            }
            P_GiveCard(player, Card.BlueSkull);
            if (g_game.netgame != c.false) {
                return;
            }
        },

        c.SPR_YSKU => {
            if (player.cards[@intFromEnum(Card.YellowSkull)] == c.false) {
                player.message = c.GOTYELWSKUL;
            }
            P_GiveCard(player, Card.YellowSkull);
            if (g_game.netgame != c.false) {
                return;
            }
        },

        c.SPR_RSKU => {
            if (player.cards[@intFromEnum(Card.RedSkull)] == c.false) {
                player.message = c.GOTREDSKULL;
            }
            P_GiveCard(player, Card.RedSkull);
            if (g_game.netgame != c.false) {
                return;
            }
        },

        // medikits, heals
        c.SPR_STIM => {
            if (!P_GiveBody(player, 10)) {
                return;
            }
            player.message = c.GOTSTIM;
        },

        c.SPR_MEDI => {
            if (!P_GiveBody(player, 25)) {
                return;
            }

            if (player.health < 25) {
                player.message = c.GOTMEDINEED;
            } else {
                player.message = c.GOTMEDIKIT;
            }
        },

        // power ups
        c.SPR_PINV => {
            if (!P_GivePower(player, .Invulnerability)) {
                return;
            }
            player.message = c.GOTINVUL;
            sound = .getpow;
        },

        c.SPR_PSTR => {
            if (!P_GivePower(player, .Strength)) {
                return;
            }
            player.message = c.GOTBERSERK;
            sound = .getpow;

            if (player.readyweapon != .Fist) {
                player.pendingweapon = .Fist;
            }
        },

        c.SPR_PINS => {
            if (!P_GivePower(player, .Invisibility)) {
                return;
            }
            player.message = c.GOTINVIS;
            sound = .getpow;
        },

        c.SPR_SUIT => {
            if (!P_GivePower(player, .IronFeet)) {
                return;
            }
            player.message = c.GOTSUIT;
            sound = .getpow;
        },

        c.SPR_PMAP => {
            if (!P_GivePower(player, .AllMap)) {
                return;
            }
            player.message = c.GOTMAP;
            sound = .getpow;
        },

        c.SPR_PVIS => {
            if (!P_GivePower(player, .Infrared)) {
                return;
            }
            player.message = c.GOTVISOR;
            sound = .getpow;
        },

        // ammo
        c.SPR_CLIP => {
            if (special.flags & MF_DROPPED != 0) {
                if (!P_GiveAmmo(player, .Clip, 0)) {
                    return;
                }
            } else {
                if (!P_GiveAmmo(player, .Clip, 1)) {
                    return;
                }
            }
            player.message = c.GOTCLIP;
        },

        c.SPR_AMMO => {
            if (!P_GiveAmmo(player, .Clip, 5)) {
                return;
            }
            player.message = c.GOTCLIPBOX;
        },

        c.SPR_ROCK => {
            if (!P_GiveAmmo(player, .Missile, 1)) {
                return;
            }
            player.message = c.GOTROCKET;
        },

        c.SPR_BROK => {
            if (!P_GiveAmmo(player, .Missile, 5)) {
                return;
            }
            player.message = c.GOTROCKBOX;
        },

        c.SPR_CELL => {
            if (!P_GiveAmmo(player, .Cell, 1)) {
                return;
            }
            player.message = c.GOTCELL;
        },

        c.SPR_CELP => {
            if (!P_GiveAmmo(player, .Cell, 5)) {
                return;
            }
            player.message = c.GOTCELLBOX;
        },

        c.SPR_SHEL => {
            if (!P_GiveAmmo(player, .Shell, 1)) {
                return;
            }
            player.message = c.GOTSHELLS;
        },

        c.SPR_SBOX => {
            if (!P_GiveAmmo(player, .Shell, 5)) {
                return;
            }
            player.message = c.GOTSHELLBOX;
        },

        c.SPR_BPAK => {
            if (player.backpack == c.false) {
                for (&player.maxammo) |*ma| {
                    ma.* *= 2;
                }
                player.backpack = c.true;
            }
            for (0..player.maxammo.len) |i| {
                _ = P_GiveAmmo(player, @enumFromInt(i), 1);
            }
            player.message = c.GOTBACKPACK;
        },

        // weapons
        c.SPR_BFUG => {
            if (!P_GiveWeapon(player, .Bfg, false)) {
                return;
            }
            player.message = c.GOTBFG9000;
            sound = .wpnup;
        },

        c.SPR_MGUN => {
            if (!P_GiveWeapon(player, .Chaingun, special.flags & MF_DROPPED != 0)) {
                return;
            }
            player.message = c.GOTCHAINGUN;
            sound = .wpnup;
        },

        c.SPR_CSAW => {
            if (!P_GiveWeapon(player, .Chainsaw, false)) {
                return;
            }
            player.message = c.GOTCHAINSAW;
            sound = .wpnup;
        },

        c.SPR_LAUN => {
            if (!P_GiveWeapon(player, .Missile, false)) {
                return;
            }
            player.message = c.GOTLAUNCHER;
            sound = .wpnup;
        },

        c.SPR_PLAS => {
            if (!P_GiveWeapon(player, .Plasma, false)) {
                return;
            }
            player.message = c.GOTPLASMA;
            sound = .wpnup;
        },

        c.SPR_SHOT => {
            if (!P_GiveWeapon(player, .Shotgun, special.flags & MF_DROPPED != 0)) {
                return;
            }
            player.message = c.GOTSHOTGUN;
            sound = .wpnup;
        },

        c.SPR_SGN2 => {
            if (!P_GiveWeapon(player, .SuperShotgun, special.flags & MF_DROPPED != 0)) {
                return;
            }
            player.message = c.GOTSHOTGUN2;
            sound = .wpnup;
        },

        else => {
            I_Error("P_SpecialThing: Unknown gettable thing");
        }
    }

    if (special.flags & MF_COUNTITEM != 0) {
        player.itemcount += 1;
    }
    P_RemoveMobj(special);
    player.bonuscount += BONUSADD;
    if (player == &g_game.players[g_game.consoleplayer]) {
        S_StartSound(null, sound);
    }
}


//
// KillMobj
//
fn P_KillMobj(source: ?*MObj, target: *MObj) void {
    target.flags &= ~(MF_SHOOTABLE|MF_FLOAT|MF_SKULLFLY);

    if (target.type != c.MT_SKULL) {
        target.flags &= ~MF_NOGRAVITY;
    }

    target.flags |= MF_CORPSE|MF_DROPOFF;
    target.height >>= 2;

    if (source != null and source.?.player != null) {
        // count for intermission
        if (target.flags & MF_COUNTKILL != 0) {
            source.?.player.?.killcount += 1;
        }

        if (target.player != null) {
            const playeridx = @intFromPtr(target.player.?) - @intFromPtr(&g_game.players[0]);
            source.?.player.?.frags[playeridx] += 1;
        }
    } else if (g_game.netgame == c.false and target.flags & MF_COUNTKILL != 0) {
        // count all monster deaths,
        // even those caused by other monsters
        g_game.players[0].killcount += 1;
    }

    if (target.player != null) {
        // count environment kills against you
        if (source == null) {
            const playeridx = @intFromPtr(target.player.?) - @intFromPtr(&g_game.players[0]);
            target.player.?.frags[playeridx] += 1;
        }

        target.flags &= ~MF_SOLID;
        target.player.?.playerstate = .Dead;
        c.P_DropWeapon(@ptrCast(target.player));

        if (target.player == &g_game.players[g_game.consoleplayer]
            and c.automapactive != c.false) {
            // don't die in auto map,
            // switch view prior to dying
            AM_Stop();
        }
    }

    if (target.health < -target.info.spawnhealth
        and target.info.xdeathstate != 0) {
        _ = P_SetMobjState(target, @intCast(target.info.xdeathstate));
    } else {
        _ = P_SetMobjState(target, @intCast(target.info.deathstate));
    }
    target.tics -= P_Random() & 3;

    if (target.tics < 1) {
        target.tics = 1;
    }


    // Drop stuff.
    // This determines the kind of object spawned
    // during the death frame of a thing.
    const item = switch (target.type) {
        c.MT_WOLFSS,
        c.MT_POSSESSED => c.MT_CLIP,
        c.MT_SHOTGUY => c.MT_SHOTGUN,
        c.MT_CHAINGUY => c.MT_CHAINGUN,
        else => {
            return;
        },
    };

    const mo = P_SpawnMobj(target.x, target.y, c.ONFLOORZ, @intCast(item));
    mo.flags |= MF_DROPPED; // special versions of items
}


//
// P_DamageMobj
// Damages both enemies and players
// "inflictor" is the thing that caused the damage
//  creature or missile, can be NULL (slime, etc)
// "source" is the thing to target after taking damage
//  creature or NULL
// Source and inflictor are the same for melee attacks.
// Source can be NULL for slime, barrel explosions
// and other environmental stuff.
//
pub export fn P_DamageMobj(target: *MObj, inflictor: ?*MObj, source: ?*MObj, _damage: c_int) void {
    var damage = _damage;

    if (target.flags & MF_SHOOTABLE == 0) {
        return; // shouldn't happen...
    }

    if (target.health <= 0) {
        return;
    }

    if (target.flags & MF_SKULLFLY != 0) {
        target.momx = 0;
        target.momy = 0;
        target.momz = 0;
    }

    const player = target.player;
    if (player != null and g_game.gameskill == .Baby) {
        damage >>= 1;   // take half damage in trainer mode
    }

    // Some close combat weapons should not
    // inflict thrust and push the victim out of reach,
    // thus kick away unless using the chainsaw.
    if (inflictor != null
        and target.flags & MF_NOCLIP == 0
        and (source == null
            or source.?.player == null
            or source.?.player.?.readyweapon != .Chainsaw)) {
        var ang = c.R_PointToAngle2(
            inflictor.?.x,
            inflictor.?.y,
            target.x,
            target.y
        );
        var thrust = @divTrunc(damage * (FRACUNIT >> 3) * 100, target.info.mass);

        // make fall forwards sometimes
        if (damage < 40
            and damage > target.health
            and target.z - inflictor.?.z > 64 * FRACUNIT
            and P_Random() & 1 != 0) {
            ang += c.ANG180;
            thrust *= 4;
        }

        ang >>= c.ANGLETOFINESHIFT;
        target.momx += FixedMul(thrust, c.finecosine[ang]);
        target.momy += FixedMul(thrust, c.finesine[ang]);
    }

    // player specific
    if (player != null) {
        // end of game hell hack
        if (target.subsector.sector[0].special == 11
            and damage >= target.health) {
            damage = target.health - 1;
        }


        // Below certain threshold,
        // ignore damage in GOD mode, or with INVUL power.
        if (damage < 1000
            and (player.?.cheats & c.CF_GODMODE != 0
                or player.?.powers[@intFromEnum(PowerType.Invulnerability)] != c.false)) {
            return;
        }

        var saved: c_int = 0;
        if (player.?.armortype != 0) {
            if (player.?.armortype == 1) {
                saved = @divTrunc(damage, 3);
            } else {
                saved = @divTrunc(damage, 2);
            }

            if (player.?.armorpoints <= saved) {
                // armor is used up
                saved = player.?.armorpoints;
                player.?.armortype = 0;
            }
            player.?.armorpoints -= saved;
            damage -= saved;
        }

        player.?.health -= damage;  // mirror mobj health here for Dave
        if (player.?.health < 0) {
            player.?.health = 0;
        }

        player.?.attacker = source;
        player.?.damagecount += damage; // add damage after armor / invuln

        if (player.?.damagecount > 100) {
            player.?.damagecount = 100; // teleport stomp does 10k points...
        }

        const temp = @max(damage, 100);

        if (player == &g_game.players[g_game.consoleplayer]) {
            I_Tactile(40, 10, 40 + temp * 2);
        }
    }

    // do the damage
    target.health -= damage;
    if (target.health <= 0) {
        P_KillMobj(source, target);
        return;
    }

    if (P_Random() < target.info.painchance
        and target.flags & MF_SKULLFLY == 0) {
        target.flags |= MF_JUSTHIT; // fight back!
        _ = P_SetMobjState(target, @intCast(target.info.painstate));
    }

    target.reactiontime = 0;    // we're awake now...

    if ((target.threshold == 0 or target.type == c.MT_VILE)
        and source != null
        and source != target
        and source.?.type != c.MT_VILE) {
        // if not intent on another player,
        // chase after this one
        target.target = source;
        target.threshold = c.BASETHRESHOLD;
        if (target.state == &p_mobj.c.states[@intCast(target.info.spawnstate)]
            and target.info.seestate != c.S_NULL) {
            _ = P_SetMobjState(target, @intCast(target.info.seestate));
        }
    }
}
