const c = @import("c");

// Finally, for odd reasons, the player input
// is buffered within the player data struct,
// as commands per game tick.
const d_items = @import("d_items.zig");
const doomdef = @import("doomdef.zig");
const AmmoType = doomdef.AmmoType;
const Card = doomdef.Card;
const MAXPLAYERS = doomdef.MAXPLAYERS ;
const PowerType = doomdef.PowerType;
const WeaponType = doomdef.WeaponType;
const d_ticcmd = @import("d_ticcmd.zig");
const TicCmd = d_ticcmd.TicCmd;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;



//
// Player states.
//
pub const PlayerState = enum(c_int) {
    // Playing or camping.
    Live,
    // Dead on the ground, view follows killer.
    Dead,
    // Ready to restart/respawn???
    Reborn,
};


//
// Player internal flags, for cheats and debug.
//
pub const CF_NOCLIP = 1;
pub const CF_GODMODE = 2;
pub const CF_NOMOMENTUM = 4;

pub const PSprNum = enum {
    Weapon,
    Flash,

    pub const count = @typeInfo(PSprNum).@"enum".field_names.len;
};

comptime {
    const assert = @import("std").debug.assert;
    // C still sizes psprites with NUMPSPRITES (d_player.h, p_saveg.c, r_things.c)
    assert(PSprNum.count == c.NUMPSPRITES);
}

//
// Extended player object info: player_t
//
pub const Player = extern struct {
    mo: ?*MObj,
    playerstate: PlayerState,
    cmd: TicCmd,

    // Determine POV,
    //  including viewpoint bobbing during movement.
    // Focal origin above r.z
    viewz: fixed_t,
    // Base height above floor for viewz.
    viewheight: fixed_t,
    // Bob/squat speed.
    deltaviewheight: fixed_t,
    // bounded/scaled total momentum.
    bob: fixed_t,

    // This is only used between levels,
    // mo->health is used during levels.
    health: c_int,
    armorpoints: c_int,
    // Armor type is 0-2.
    armortype: c_int,

    // Power ups. invinc and invis are tic counters.
    powers: [PowerType.count]c_int,
    cards: [Card.count]c.boolean,
    backpack: c.boolean,

    // Frags, kills of other players.
    frags: [MAXPLAYERS]c_int,
    readyweapon: WeaponType,

    // Is wp_nochange if not changing.
    pendingweapon: WeaponType,

    weaponowned: [WeaponType.count]c.boolean,
    ammo: [AmmoType.count]c_int,
    maxammo: [AmmoType.count]c_int,

    // True if button down last tic.
    attackdown: c_int,
    usedown: c_int,

    // Bit flags, for cheats and debug.
    // See cheat_t, above.
    cheats: c_int,

    // Refired shots are less accurate.
    refire: c_int,

     // For intermission stats.
    killcount: c_int,
    itemcount: c_int,
    secretcount: c_int,

    // Hint messages.
    message: ?[*:0]const u8,

    // For screen flashing (red or bright).
    damagecount: c_int,
    bonuscount: c_int,

    // Who did damage (NULL for floors/ceilings).
    attacker: ?*MObj,

    // So gun flashes light up areas.
    extralight: c_int,

    // Current PLAYPAL, ???
    //  can be set to REDCOLORMAP for pain, etc.
    fixedcolormap: c_int,

    // Player skin colorshift,
    //  0-3 for which color to draw player.
    colormap: c_int,

    // Overlay view sprites (gun, etc).
    psprites: [PSprNum.count]c.pspdef_t,

    // True if secret level has been done.
    didsecret: c.boolean,

    pub fn ammoOf(player: *Player, a: AmmoType) *c_int {
        return &player.ammo[@backingInt(a)];
    }

    pub fn owns(player: *const Player, w: WeaponType) bool {
        return player.weaponowned[@backingInt(w)] != c.false;
    }

    pub fn power(player: *Player, p: PowerType) *c_int {
        return &player.powers[@backingInt(p)];
    }

    pub fn psprite(player: *Player, n: PSprNum) *c.pspdef_t {
        return &player.psprites[@backingInt(n)];
    }

    pub fn readyAmmo(player: *Player) *c_int {
        return player.ammoOf(d_items.weaponAmmo(player.readyweapon));
    }
};


//
// INTERMISSION
// Structure passed e.g. to WI_Start(wb)
//
pub const WbPlayer = extern struct {
    in: c.boolean,      // whether the player is in game

    // Player stats, kills, collected items etc.
    skills: c_int,
    sitems: c_int,
    ssecret: c_int,
    stime: c_int,
    frags: [4]c_int,
    score: c_int,       // current score on entry, modified on return
};

pub const WbStart = extern struct {
    epsd: c_int,    // episode # (0-2)

    // if true, splash the secret level
    didsecret: c.boolean,

    // previous and next levels, origin 0
    last: c_int,
    next: c_int,

    maxkills: c_int,
    maxitems: c_int,
    maxsecret: c_int,
    maxfrags: c_int,

    // the par time
    partime: c_int,

    // index of this player in game
    pnum: c_int,

    plyr: [MAXPLAYERS]WbPlayer,
};
