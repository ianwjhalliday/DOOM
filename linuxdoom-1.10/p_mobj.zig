pub const c = @cImport({
    // Basics.
    @cInclude("tables.h");

    // We need the WAD data structure for Map things,
    // from the THINGS lump.
    @cInclude("doomdata.h");

    // States are tied to finite states are
    //  tied to animation frames.
    // Needs precompiled tables/data structures.
    @cInclude("info.h");

    @cInclude("doomstat.h");
    @cInclude("r_defs.h");
    @cInclude("r_main.h");
    @cInclude("p_local.h");
});

const std = @import("std");

const doomdef = @import("doomdef.zig");
const MAXPLAYERS = doomdef.MAXPLAYERS;
const MTF_AMBUSH = doomdef.MTF_AMBUSH;
const d_main = @import("d_main.zig");
const d_player = @import("d_player.zig");
const CF_NOMOMENTUM = d_player.CF_NOMOMENTUM;
const Player = d_player.Player;
const g_game = @import("g_game.zig");
const G_PlayerReborn = g_game.G_PlayerReborn;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FixedMul = m_fixed.FixedMul;
const FRACBITS = m_fixed.FRACBITS;
const FRACUNIT = m_fixed.FRACUNIT;
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const hu_stuff = @import("hu_stuff.zig");
const HU_Start = hu_stuff.HU_Start;
const m_random = @import("m_random.zig");
const P_Random = m_random.P_Random;
const p_tick = @import("p_tick.zig");
const P_AddThinker = p_tick.P_AddThinker;
const P_RemoveThinker = p_tick.P_RemoveThinker;
const Thinker = p_tick.Thinker;
const r_sky = @import("r_sky.zig");
const s_sound = @import("s_sound.zig");
const S_StartSound = s_sound.S_StartSound_Zig;
const S_StopSound = s_sound.S_StopSound;
const st_stuff = @import("st_stuff.zig");
const ST_Start = st_stuff.ST_Start;
const z_zone = @import("z_zone.zig");

//
// NOTES: mobj_t
//
// mobj_ts are used to tell the refresh where to draw an image,
// tell the world simulation when objects are contacted,
// and tell the sound driver how to position a sound.
//
// The refresh uses the next and prev links to follow
// lists of things in sectors as they are being drawn.
// The sprite, frame, and angle elements determine which patch_t
// is used to draw the sprite if it is visible.
// The sprite and frame values are allmost allways set
// from state_t structures.
// The statescr.exe utility generates the states.h and states.c
// files that contain the sprite/frame numbers from the
// statescr.txt source file.
// The xyz origin point represents a point at the bottom middle
// of the sprite (between the feet of a biped).
// This is the default origin position for patch_ts grabbed
// with lumpy.exe.
// A walking creature will have its z equal to the floor
// it is standing on.
//
// The sound code uses the x,y, and subsector fields
// to do stereo positioning of any sound effited by the mobj_t.
//
// The play simulation uses the blocklinks, x,y,z, radius, height
// to determine when mobj_ts are touching each other,
// touching lines in the map, or hit by trace lines (gunshots,
// lines of sight, etc).
// The mobj_t->flags element has various bit flags
// used by the simulation.
//
// Every mobj_t is linked into a single sector
// based on its origin coordinates.
// The subsector_t is found with R_PointInSubsector(x,y),
// and the sector_t can be found with subsector->sector.
// The sector links are only used by the rendering code,
// the play simulation does not care about them at all.
//
// Any mobj_t that needs to be acted upon by something else
// in the play world (block movement, be shot, etc) will also
// need to be linked into the blockmap.
// If the thing has the MF_NOBLOCK flag set, it will not use
// the block links. It can still interact with other things,
// but only as the instigator (missiles will run into other
// things, but nothing can run into a missile).
// Each block in the grid is 128*128 units, and knows about
// every line_t that it contains a piece of, and every
// interactable mobj_t that has its origin contained.
//
// A valid mobj_t is a mobj_t that has the proper subsector_t
// filled in for its xy coordinates and is linked into the
// sector from which the subsector was made, or has the
// MF_NOSECTOR flag set (the subsector_t needs to be valid
// even if MF_NOSECTOR is set), and is linked into a blockmap
// block or has the MF_NOBLOCKMAP flag set.
// Links should only be modified by the P_[Un]SetThingPosition()
// functions.
// Do not change the MF_NO? flags while a thing is valid.
//
// Any questions?
//

//
// Misc. mobj flags
//

// Call P_SpecialThing when touched.
pub const MF_SPECIAL: c_int = 1;
// Blocks.
pub const MF_SOLID: c_int = 2;
// Can be hit.
pub const MF_SHOOTABLE: c_int = 4;
// Don't use the sector links (invisible but touchable).
pub const MF_NOSECTOR: c_int = 8;
// Don't use the blocklinks (inert but displayable)
pub const MF_NOBLOCKMAP: c_int = 16;

// Not to be activated by sound, deaf monster.
pub const MF_AMBUSH: c_int = 32;
// Will try to attack right back.
pub const MF_JUSTHIT: c_int = 64;
// Will take at least one step before attacking.
pub const MF_JUSTATTACKED: c_int = 128;
// On level spawning (initial position),
//  hang from ceiling instead of stand on floor.
pub const MF_SPAWNCEILING: c_int = 256;
// Don't apply gravity (every tic),
//  that is, object will float, keeping current height
//  or changing it actively.
pub const MF_NOGRAVITY: c_int = 512;

// Movement flags.
// This allows jumps from high places.
pub const MF_DROPOFF: c_int = 0x400;
// For players, will pick up items.
pub const MF_PICKUP: c_int = 0x800;
// Player cheat. ???
pub const MF_NOCLIP: c_int = 0x1000;
// Player: keep info about sliding along walls.
pub const MF_SLIDE: c_int = 0x2000;
// Allow moves to any height, no gravity.
// For active floaters, e.g. cacodemons, pain elementals.
pub const MF_FLOAT: c_int = 0x4000;
// Don't cross lines
//   ??? or look at heights on teleport.
pub const MF_TELEPORT: c_int = 0x8000;
// Don't hit same species, explode on block.
// Player missiles as well as fireballs of various kinds.
pub const MF_MISSILE: c_int = 0x10000;
// Dropped by a demon, not level spawned.
// E.g. ammo clips dropped by dying former humans.
pub const MF_DROPPED: c_int = 0x20000;
// Use fuzzy draw (shadow demons or spectres),
//  temporary player invisibility powerup.
pub const MF_SHADOW: c_int = 0x40000;
// Flag: don't bleed when shot (use puff),
//  barrels and shootable furniture shall not bleed.
pub const MF_NOBLOOD: c_int = 0x80000;
// Don't stop moving halfway off a step,
//  that is, have dead bodies slide down all the way.
pub const MF_CORPSE: c_int = 0x100000;
// Floating to a height for a move, ???
//  don't auto float to target's height.
pub const MF_INFLOAT: c_int = 0x200000;

// On kill, count this enemy object
//  towards intermission kill total.
// Happy gathering.
pub const MF_COUNTKILL: c_int = 0x400000;

// On picking up, count this item object
//  towards intermission item total.
pub const MF_COUNTITEM: c_int = 0x800000;

// Special handling: skull in flight.
// Neither a cacodemon nor a missile.
pub const MF_SKULLFLY: c_int = 0x1000000;

// Don't spawn this object
//  in death match mode (e.g. key cards).
pub const MF_NOTDMATCH: c_int = 0x2000000;

// Player sprites in multiplayer modes are modified
//  using an internal color lookup table for re-indexing.
// If 0x4 0x8 or 0xc,
//  use a translation table for player colormaps
pub const MF_TRANSLATION: c_int = 0xc000000;
// Hmm ???.
pub const MF_TRANSSHIFT: c_int = 26;



// Map Object definition.
// WARNING: MObj must be an `extern` struct and must have `thinker: Thinker`
// as its first field to ensure that code that uses thinker pointers can
// cast back to *MObj and Z_Free.
pub const MObj = extern struct {
    // List: thinker links.
    thinker: Thinker,

    // Info for drawing: position.
    x: fixed_t,
    y: fixed_t,
    z: fixed_t,

    // More list: links in sector (if needed)
    snext: ?*MObj,
    sprev: ?*MObj,

    //More drawing info: to determine current sprite.
    angle: c.angle_t,       // orientation
    sprite: c.spritenum_t,  // used to find patch_t and flip value
    frame: c_int,           // might be ORed with FF_FULLBRIGHT

    // Interaction info, by BLOCKMAP.
    // Links in blocks (if needed).
    bnext: ?*MObj,
    bprev: ?*MObj,

    subsector: *c.subsector_t,

    // The closest interval over all contacted Sectors.
    floorz: fixed_t,
    ceilingz: fixed_t,

    // For movement checking.
    radius: fixed_t,
    height: fixed_t,

    // Momentums, used to update position.
    momx: fixed_t,
    momy: fixed_t,
    momz: fixed_t,

    // If == validcount, already checked.
    validcount: c_int,

    type: c.mobjtype_t,
    info: *c.mobjinfo_t,    // &mobjinfo[mobj.type]

    tics: c_int,    // state tic counter
    state: ?*c.state_t,
    flags: c_int,
    health: c_int,

    // Movement direction, movement generation (zig-zagging).
    movedir: c_int,     // 0-7
    movecount: c_int,   // when 0, select a new dir

    // Thing being chased/attacked (or NULL),
    // also the originator for missiles.
    target: ?*MObj,

    // Reaction time: if non 0, don't attack yet.
    // Used by player to freeze a bit after teleporting.
    reactiontime: c_int,

    // If >0, the target will be chased
    // no matter what (even if shot)
    threshold: c_int,

    // Additional info record for player avatars only.
    // Only valid if type == MT_PLAYER
    player: ?*Player,

    // Player number last looked for.
    lastlook: c_int,

    // For nightmare respawn.
    spawnpoint: c.mapthing_t,

    // Thing being chased/attacked for tracers.
    tracer: ?*MObj,
};



//
// P_SetMobjState
// Returns true if the mobj is still present.
//
pub export fn P_SetMobjState(mobj: *MObj, _state: c.statenum_t) bool {
    var state = _state;
    while (true) {
        if (state == c.S_NULL) {
            mobj.state = null;
            P_RemoveMobj(mobj);
            return false;
        }

        const st = &c.states[state];
        mobj.state = st;
        mobj.tics = @intCast(st.tics);
        mobj.sprite = st.sprite;
        mobj.frame = @intCast(st.frame);

        // Modified handling.
        // Call action functions when the state is set
        if (st.action.acp1 != null) {
            st.action.acp1.?(mobj);
        }

        state = st.nextstate;

        if (mobj.tics != 0) {
            break;
        }
    }

    return true;
}


//
// P_ExplodeMissile
//
fn P_ExplodeMissile(mo: *MObj) void {
    mo.momx = 0;
    mo.momy = 0;
    mo.momz = 0;

    _ = P_SetMobjState(mo, @intCast(c.mobjinfo[mo.type].deathstate));

    mo.tics -= P_Random() & 3;

    if (mo.tics < 1) {
        mo.tics = 1;
    }

    mo.flags &= ~MF_MISSILE;

    if (mo.info.deathsound != 0) {
        S_StartSound(mo, @enumFromInt(mo.info.deathsound));
    }
}


//
// P_XYMovement
//
const STOPSPEED = 0x1000;
const FRICTION = 0xe800;

fn P_XYMovement(mo: *MObj) void {
    if (mo.momx == 0 and mo.momy == 0) {
        if (mo.flags & MF_SKULLFLY != 0) {
            // the skull slammed into something
            mo.flags &= ~MF_SKULLFLY;
            mo.momx = 0;
            mo.momy = 0;
            mo.momz = 0;

            _ = P_SetMobjState(mo, @intCast(mo.info.spawnstate));
        }
        return;
    }

    const player = mo.player;

    if (mo.momx > c.MAXMOVE) {
        mo.momx = c.MAXMOVE;
    } else if (mo.momx < -c.MAXMOVE) {
        mo.momx = -c.MAXMOVE;
    }

    if (mo.momy > c.MAXMOVE) {
        mo.momy = c.MAXMOVE;
    } else if (mo.momy < -c.MAXMOVE) {
        mo.momy = -c.MAXMOVE;
    }

    var xmove = mo.momx;
    var ymove = mo.momy;

    while (true) {
        var ptryx: fixed_t = undefined;
        var ptryy: fixed_t = undefined;

        if (xmove > c.MAXMOVE / 2 or ymove > c.MAXMOVE / 2) {
            ptryx = mo.x + @divTrunc(xmove, 2);
            ptryy = mo.y + @divTrunc(ymove, 2);
            xmove >>= 1;
            ymove >>= 1;
        } else {
            ptryx = mo.x + xmove;
            ptryy = mo.y + ymove;
            xmove = 0;
            ymove = 0;
        }

        if (c.P_TryMove(@ptrCast(mo), ptryx, ptryy) == c.false) {
            // blocked move
            if (mo.player != null) {
                // try to slide along it
                c.P_SlideMove(@ptrCast(mo));
            } else if (mo.flags & MF_MISSILE != 0) {
                // explode a missile
                if (c.ceilingline != null and
                    c.ceilingline[0].backsector != null and
                    c.ceilingline[0].backsector[0].ceilingpic == r_sky.skyflatnum)
                {
                    // Hack to prevent missiles exploding
                    // against the sky.
                    // Does not handle sky floors.
                    P_RemoveMobj(mo);
                    return;
                }
                P_ExplodeMissile(mo);
            } else {
                mo.momx = 0;
                mo.momy = 0;
            }
        }

        if (xmove == 0 and ymove == 0) {
            break;
        }
    }

    // slow down
    if (player != null and player.?.cheats & CF_NOMOMENTUM != 0) {
        // debug option for no sliding at all
        mo.momx = 0;
        mo.momy = 0;
        return;
    }

    if (mo.flags & (MF_MISSILE | MF_SKULLFLY) != 0) {
        return; // no friction for missiles ever
    }

    if (mo.z > mo.floorz) {
        return; // no friction when airborne
    }

    if (mo.flags & MF_CORPSE != 0) {
        // do not stop sliding
        //  if halfway off a step with some momentum
        if (mo.momx > FRACUNIT / 4 or mo.momx < -FRACUNIT / 4 or mo.momy > FRACUNIT / 4 or mo.momy < -FRACUNIT / 4) {
            if (mo.floorz != mo.subsector.sector[0].floorheight) {
                return;
            }
        }
    }

    if (mo.momx > -STOPSPEED and mo.momx < STOPSPEED and mo.momy > -STOPSPEED and mo.momy < STOPSPEED and (player == null or (player.?.cmd.forwardmove == 0 and player.?.cmd.sidemove == 0))) {
        // if in a walking frame, stop moving
        if (player != null and @intFromPtr(player.?.mo.?.state.?) - @intFromPtr(&c.states[0]) - c.S_PLAY_RUN1 < 4) {
            _ = P_SetMobjState(player.?.mo.?, c.S_PLAY);
        }

        mo.momx = 0;
        mo.momy = 0;
    } else {
        mo.momx = FixedMul(mo.momx, FRICTION);
        mo.momy = FixedMul(mo.momy, FRICTION);
    }
}


//
// P_ZMovement
//
fn P_ZMovement(mo: *MObj) void {
    // check for smooth step up
    if (mo.player != null and mo.z < mo.floorz) {
        mo.player.?.viewheight -= mo.floorz - mo.z;

        mo.player.?.deltaviewheight = (c.VIEWHEIGHT - mo.player.?.viewheight) >> 3;
    }

    // adjust height
    mo.z += mo.momz;

    if (mo.flags & MF_FLOAT != 0 and mo.target != null) {
        // float down towards target if too close
        if (mo.flags & MF_SKULLFLY == 0 and mo.flags & MF_INFLOAT == 0) {
            const dist = c.P_AproxDistance(mo.x - mo.target.?.x, mo.y - mo.target.?.y);

            const delta = (mo.target.?.z + (mo.height >> 1)) - mo.z;

            if (delta < 0 and dist < -delta * 3) {
                mo.z -= c.FLOATSPEED;
            } else if (delta > 0 and dist < delta * 3) {
                mo.z += c.FLOATSPEED;
            }
        }
    }

    // clip movement
    if (mo.z <= mo.floorz) {
        // hit the floor

        // Note (id):
        //  somebody left this after the setting momz to 0,
        //  kinda useless there.
        if (mo.flags & MF_SKULLFLY != 0) {
            // the skull slammed into something
            mo.momz = -mo.momz;
        }

        if (mo.momz < 0) {
            if (mo.player != null and mo.momz < -c.GRAVITY * 8) {
                // Squat down.
                // Decrease viewheight for a moment
                // after hitting the ground (hard),
                // and utter appropriate sound.
                mo.player.?.deltaviewheight = mo.momz >> 3;
                S_StartSound(mo, .oof);
            }
            mo.momz = 0;
        }
        mo.z = mo.floorz;

        if (mo.flags & MF_MISSILE != 0 and mo.flags & MF_NOCLIP == 0) {
            P_ExplodeMissile(mo);
            return;
        }
    } else if (mo.flags & MF_NOGRAVITY == 0) {
        if (mo.momz == 0) {
            mo.momz = -c.GRAVITY * 2;
        } else {
            mo.momz -= c.GRAVITY;
        }
    }

    if (mo.z + mo.height > mo.ceilingz) {
        // BUG: Is this a bug? Original doom C code looked like this:
        //
        // ```c
        // // hit the ceiling
        // if (mo.momz > 0)
        //     mo.momz = 0;
        // {
        //     mo.z = mo.ceilingz - mo.height;
        // }
        //
        // ...
        // ```
        //
        // which appears as though both assigments were meant to be
        // part of the if then clause.

        // hit the ceiling
        if (mo.momz > 0) {
            mo.momz = 0;
        }
        mo.z = mo.ceilingz - mo.height;

        if (mo.flags & MF_SKULLFLY != 0) {
            // the skull slammed into something
            mo.momz = -mo.momz;
        }

        if (mo.flags & MF_MISSILE != 0 and mo.flags & MF_NOCLIP == 0) {
            P_ExplodeMissile(mo);
            return;
        }
    }
}


//
// P_NightmareRespawn
//
fn P_NightmareRespawn(mobj: *MObj) void {
    const x = @as(fixed_t, mobj.spawnpoint.x) << FRACBITS;
    const y = @as(fixed_t, mobj.spawnpoint.y) << FRACBITS;

    // somthing is occupying it's position?
    if (c.P_CheckPosition(@ptrCast(mobj), x, y) == c.false) {
        return; // no respawn
    }

    // spawn a teleport fog at old spot
    // because of removal of the body?
    var mo = P_SpawnMobj(mobj.x, mobj.y, mobj.subsector.sector[0].floorheight, c.MT_TFOG);
    // initiate teleport sound
    S_StartSound(mo, .telept);

    // spawn a teleport fog at the new spot
    const ss = c.R_PointInSubsector(x, y);

    mo = P_SpawnMobj(x, y, ss[0].sector[0].floorheight, c.MT_TFOG);

    S_StartSound(mo, .telept);

    // spawn the new monster
    const mthing = &mobj.spawnpoint;

    // spawn it
    const z = if (mobj.info.flags & MF_SPAWNCEILING != 0)
        c.ONCEILINGZ
    else
        c.ONFLOORZ;

    // inherit attributes from deceased one
    mo = P_SpawnMobj(x, y, z, mobj.type);
    mo.spawnpoint = mobj.spawnpoint;
    mo.angle = @divTrunc(@as(c.angle_t, @intCast(mthing.angle)), 45) * c.ANG45;

    if (mthing.options & MTF_AMBUSH != 0) {
        mo.flags |= MF_AMBUSH;
    }

    mo.reactiontime = 18;

    // remove the old monster,
    P_RemoveMobj(mobj);
}


//
// P_MobjThinker
//
pub export fn P_MobjThinker(mobj: *MObj) void {
    // momentum movement
    if (mobj.momx != 0 or mobj.momy != 0 or mobj.flags & MF_SKULLFLY != 0) {
        P_XYMovement(mobj);

        // FIXME: decent NOP/NULL/Nil function pointer please.
        if (@as(isize, @bitCast(@intFromPtr(mobj.thinker.function.acv))) == -1) {
            return; // mobj was removed
        }
    }

    if (mobj.z != mobj.floorz or mobj.momz != 0) {
        P_ZMovement(mobj);

        // FIXME: decent NOP/NULL/Nil function pointer please.
        if (@as(isize, @bitCast(@intFromPtr(mobj.thinker.function.acv))) == -1) {
            return; // mobj was removed
        }
    }

    // cycle through states,
    // calling action functions at transitions
    if (mobj.tics != -1) {
        mobj.tics -= 1;

        // you can cycle through multiple states in a tic
        if (mobj.tics == 0) {
            if (!P_SetMobjState(mobj, mobj.state.?.nextstate)) {
                return; // freed itself
            }
        }
    } else {
        // check for nightmare respawn
        if (mobj.flags & MF_COUNTKILL == 0) {
            return;
        }

        if (!g_game.respawnmonsters) {
            return;
        }

        mobj.movecount += 1;

        if (mobj.movecount < 12 * 35) {
            return;
        }

        if (p_tick.leveltime & 31 != 0) {
            return;
        }

        if (P_Random() > 4) {
            return;
        }

        P_NightmareRespawn(mobj);
    }
}


//
// P_SpawnMobj
//
pub export fn P_SpawnMobj(x: fixed_t, y: fixed_t, z: fixed_t, motype: c.mobjtype_t) *MObj {
    const mobj = z_zone.create(MObj, .Level, null);
    mobj.* = std.mem.zeroes(MObj);
    const info = &c.mobjinfo[motype];

    mobj.type = motype;
    mobj.info = info;
    mobj.x = x;
    mobj.y = y;
    mobj.radius = info.radius;
    mobj.height = info.height;
    mobj.flags = info.flags;
    mobj.health = info.spawnhealth;

    if (g_game.gameskill != .Nightmare) {
        mobj.reactiontime = info.reactiontime;
    }

    mobj.lastlook = @mod(P_Random(), MAXPLAYERS);
    // do not set the state with P_SetMobjState,
    // because action routines can not be called yet
    const st = &c.states[@intCast(info.spawnstate)];

    mobj.state = st;
    mobj.tics = @intCast(st.tics);
    mobj.sprite = st.sprite;
    mobj.frame = @intCast(st.frame);

    // set subsector and/or block links
    c.P_SetThingPosition(@ptrCast(mobj));

    mobj.floorz = mobj.subsector.sector[0].floorheight;
    mobj.ceilingz = mobj.subsector.sector[0].ceilingheight;

    if (z == c.ONFLOORZ) {
        mobj.z = mobj.floorz;
    } else if (z == c.ONCEILINGZ) {
        mobj.z = mobj.ceilingz - mobj.info.height;
    } else {
        mobj.z = z;
    }

    mobj.thinker.function.acp1 = @ptrCast(&P_MobjThinker);

    P_AddThinker(&mobj.thinker);

    return mobj;
}


//
// P_RemoveMobj
//
var itemrespawnque: [c.ITEMQUESIZE]c.mapthing_t = undefined;
var itemrespawntime: [c.ITEMQUESIZE]c_int = undefined;
export var iquehead: usize = 0;
export var iquetail: usize = 0;


pub export fn P_RemoveMobj(mobj: *MObj) void {
    if (mobj.flags & MF_SPECIAL != 0
        and mobj.flags & MF_DROPPED == 0
        and mobj.type != c.MT_INV
        and mobj.type != c.MT_INS) {
        itemrespawnque[iquehead] = mobj.spawnpoint;
        itemrespawntime[iquehead] = p_tick.leveltime;
        iquehead = (iquehead + 1) % c.ITEMQUESIZE;

        // lose one off the end?
        if (iquehead == iquetail) {
            iquetail = (iquetail + 1) % c.ITEMQUESIZE;
        }
    }

    // unlink from sector and block lists
    c.P_UnsetThingPosition(@ptrCast(mobj));

    // stop any playing sound
    S_StopSound(mobj);

    // free block
    P_RemoveThinker(&mobj.thinker);
}


//
// P_RespawnSpecials
//
pub fn P_RespawnSpecials() void {
    // only respawn items in deathmatch
    if (g_game.deathmatch != 2) {
        return;
    }

    // nothing left to respawn?
    if (iquehead == iquetail) {
        return;
    }

    // wait at least 30 seconds
    if (p_tick.leveltime - itemrespawntime[iquetail] < 30 * 35) {
        return;
    }

    const mthing = &itemrespawnque[iquetail];

    const x = @as(fixed_t, mthing.x) << FRACBITS;
    const y = @as(fixed_t, mthing.y) << FRACBITS;

    // spawn a teleport fog at the new spot
    const ss = c.R_PointInSubsector(x, y);
    var mo = P_SpawnMobj(x, y, ss[0].sector[0].floorheight, c.MT_IFOG);
    S_StartSound(mo, .itmbk);

    // find which type to spawn
    const i = for (c.mobjinfo, 0..) |info, ii| {
        if (mthing.type == info.doomednum) break ii;
    } else unreachable;

    // spawn it
    const z = if (c.mobjinfo[i].flags & MF_SPAWNCEILING != 0)
        c.ONCEILINGZ
    else
        c.ONFLOORZ;

    mo = P_SpawnMobj(x, y, z, @intCast(i));
    mo.spawnpoint = mthing.*;
    mo.angle = @divTrunc(@as(c.angle_t, @intCast(mthing.angle)), 45) * c.ANG45;

    // pull it from the que
    iquetail = (iquetail + 1) % c.ITEMQUESIZE;
}


//
// P_SpawnPlayer
// Called when a player is spawned on the level.
// Most of the player structure stays unchanged
//  between levels.
//
pub fn P_SpawnPlayer(mthing: *c.mapthing_t) void {
    const typeidx = @as(u32, @intCast(mthing.type - 1));

    // not playing?
    if (g_game.playeringame[typeidx] == c.false) {
        return;
    }

    const p = &g_game.players[typeidx];

    if (p.playerstate == .Reborn) {
        G_PlayerReborn(typeidx);
    }

    const x = @as(fixed_t, mthing.x) << FRACBITS;
    const y = @as(fixed_t, mthing.y) << FRACBITS;
    const z = c.ONFLOORZ;
    const mobj = P_SpawnMobj(x, y, z, c.MT_PLAYER);

    // set color translations for player sprites
    if (mthing.type > 1) {
        mobj.flags |= @as(c_int, mthing.type - 1) << c.MF_TRANSSHIFT;
    }

    mobj.angle = @divTrunc(@as(c.angle_t, @intCast(mthing.angle)), 45) * c.ANG45;
    mobj.player = p;
    mobj.health = p.health;

    p.mo = mobj;
    p.playerstate = .Live;
    p.refire = 0;
    p.message = null;
    p.damagecount = 0;
    p.bonuscount = 0;
    p.extralight = 0;
    p.fixedcolormap = 0;
    p.viewheight = c.VIEWHEIGHT;

    // setup gun psprite
    c.P_SetupPsprites(@ptrCast(p));

    // give all cards in death match mode
    if (g_game.deathmatch != 0) {
        for (&p.cards) |*card| {
            card.* = c.true;
        }
    }

    if (typeidx == g_game.consoleplayer) {
        // wake up the status bar
        ST_Start();
        // wake up the heads up text
        HU_Start();
    }
}



//
// P_SpawnMapThing
// The fields of the mapthing should
// already be in host byte order.
//
pub export fn P_SpawnMapThing(mthing: *c.mapthing_t) void {
    // count deathmatch start positions
    if (mthing.type == 11) {
        if (c.deathmatch_p <= &c.deathmatchstarts[9]) {
            c.deathmatch_p.* = mthing.*;
            c.deathmatch_p += 1;
        }
        return;
    }

    // check for players specially
    if (mthing.type <= 4) {
        // save spots for respawning in network games
        c.playerstarts[@intCast(mthing.type - 1)] = mthing.*;
        if (g_game.deathmatch == 0) {
            P_SpawnPlayer(mthing);
        }

        return;
    }

    // check for appropriate skill level
    if (g_game.netgame == c.false and mthing.options & 16 != 0) {
        return;
    }

    const bit: c_short = switch (g_game.gameskill) {
        .Baby, .Easy => 1,
        .Medium => 2,
        .Hard, .Nightmare => 4,
    };

    if (mthing.options & bit == 0) {
        return;
    }

    // find which type to spawn
    const i = for (c.mobjinfo, 0..) |info, ii| {
        if (mthing.type == info.doomednum) break ii;
    } else {
        I_Error("P_SpawnMapThing: Unknown type {} at ({}, {})",
            mthing.type,
            mthing.x, mthing.y);
    };

    // don't spawn keycards and players in deathmatch
    if (g_game.deathmatch != 0 and c.mobjinfo[i].flags & MF_NOTDMATCH != 0) {
        return;
    }

    // don't spawn any monsters if -nomonsters
    if (d_main.nomonsters
        and (i == c.MT_SKULL or c.mobjinfo[i].flags & MF_COUNTKILL != 0)) {
        return;
    }

    // spawn it
    const x = @as(fixed_t, mthing.x) << FRACBITS;
    const y = @as(fixed_t, mthing.y) << FRACBITS;

    const z = if (c.mobjinfo[i].flags & MF_SPAWNCEILING != 0)
        c.ONCEILINGZ
    else
        c.ONFLOORZ;

    const mobj = P_SpawnMobj(x, y, z, @intCast(i));
    mobj.spawnpoint = mthing.*;

    if (mobj.tics > 0) {
        mobj.tics = 1 + @mod(P_Random(), mobj.tics);
    }

    if (mobj.flags & MF_COUNTKILL != 0) {
        g_game.totalkills += 1;
    }

    if (mobj.flags & MF_COUNTITEM != 0) {
        g_game.totalitems += 1;
    }

    mobj.angle = @divTrunc(@as(c.angle_t, @intCast(mthing.angle)), 45) * c.ANG45;

    if (mthing.options & c.MTF_AMBUSH != 0) {
        mobj.flags |= MF_AMBUSH;
    }
}



//
// GAME SPAWN FUNCTIONS
//


//
// P_SpawnPuff
//
extern var attackrange: fixed_t;

pub export fn P_SpawnPuff(x: fixed_t, y: fixed_t, z: fixed_t) void {
    const z_jittered = z + ((P_Random() - P_Random()) << 10);

    const th = P_SpawnMobj(x, y, z_jittered, c.MT_PUFF);
    th.momz = FRACUNIT;
    th.tics -= P_Random() & 3;

    if (th.tics < 1) {
        th.tics = 1;
    }

    // don't make punches spark on the wall
    if (attackrange == c.MELEERANGE) {
        _ = P_SetMobjState(th, c.S_PUFF3);
    }
}


//
// P_SpawnBlood
//
pub export fn P_SpawnBlood(x: fixed_t, y: fixed_t, z: fixed_t, damage: c_int) void {
    const z_jittered = z + ((P_Random() - P_Random()) << 10);

    const th = P_SpawnMobj(x, y, z_jittered, c.MT_BLOOD);
    th.momz = FRACUNIT * 2;
    th.tics -= P_Random() & 3;

    if (th.tics < 1) {
        th.tics = 1;
    }

    if (damage >= 9 and damage <= 12) {
        _ = P_SetMobjState(th, c.S_BLOOD2);
    } else if (damage < 9) {
        _ = P_SetMobjState(th, c.S_BLOOD3);
    }
}



//
// P_CheckMissileSpawn
// Moves the missile forward a bit
//  and possibly explodes it right there.
//
fn P_CheckMissileSpawn(th: *MObj) void {
    th.tics -= P_Random() & 3;
    if (th.tics < 1) {
        th.tics = 1;
    }

    // move a little forward so an angle can
    // be computed if it immediately explodes
    th.x += th.momx >> 1;
    th.y += th.momy >> 1;
    th.z += th.momz >> 1;

    if (c.P_TryMove(@ptrCast(th), th.x, th.y) == c.false) {
        P_ExplodeMissile(th);
    }
}


//
// P_SpawnMissile
//
pub export fn P_SpawnMissile(source: *MObj, dest: *MObj, motype: c.mobjtype_t) *MObj {
    const th = P_SpawnMobj(source.x, source.y, source.z + 4*8*FRACUNIT, motype);

    if (th.info.seesound != 0) {
        S_StartSound(th, @enumFromInt(th.info.seesound));
    }

    th.target = source;     // where it came from
    var an = c.R_PointToAngle2(source.x, source.y, dest.x, dest.y);

    // fuzzy player
    if (dest.flags & MF_SHADOW != 0) {
        an +%= @bitCast((P_Random() - P_Random()) << 20);
    }

    th.angle = an;
    an >>= c.ANGLETOFINESHIFT;
    th.momx = FixedMul(th.info.speed, c.finecosine[an]);
    th.momy = FixedMul(th.info.speed, c.finesine[an]);

    var dist = c.P_AproxDistance(dest.x - source.x, dest.y - source.y);
    dist = @divTrunc(dist, th.info.speed);

    if (dist < 1) {
        dist = 1;
    }

    th.momz = @divTrunc(dest.z - source.z, dist);

    P_CheckMissileSpawn(th);

    return th;
}


//
// P_SpawnPlayerMissile
// Tries to aim at a nearby monster
//
pub export fn P_SpawnPlayerMissile(source: *MObj, motype: c.mobjtype_t) void {
    // see which target is to be aimed at
    var an = source.angle;
    var slope = c.P_AimLineAttack(@ptrCast(source), an, 16 * 64 * FRACUNIT);

    if (c.linetarget == null) {
        an +%= 1 << 26;
        slope = c.P_AimLineAttack(@ptrCast(source), an, 16 * 64 * FRACUNIT);

        if (c.linetarget == null) {
            an -= 2 << 26;
            slope = c.P_AimLineAttack(@ptrCast(source), an, 16 * 64 * FRACUNIT);
        }

        if (c.linetarget == null) {
            an = source.angle;
            slope = 0;
        }
    }

    const x = source.x;
    const y = source.y;
    const z = source.z + 4 * 8 * FRACUNIT;

    const th = P_SpawnMobj(x, y, z, motype);

    if (th.info.seesound != 0) {
        S_StartSound(th, @enumFromInt(th.info.seesound));
    }

    th.target = source;
    th.angle = an;
    th.momx = FixedMul(th.info.speed, c.finecosine[an >> c.ANGLETOFINESHIFT]);
    th.momy = FixedMul(th.info.speed, c.finesine[an >> c.ANGLETOFINESHIFT]);
    th.momz = FixedMul(th.info.speed, slope);

    P_CheckMissileSpawn(th);
}
