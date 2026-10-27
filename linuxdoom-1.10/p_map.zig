const c = @import("c");

const d_main = @import("d_main.zig");
const d_player = @import("d_player.zig");
const Player = d_player.Player;
const doomdata = @import("doomdata.zig");
const ML_BLOCKING = doomdata.ML_BLOCKING;
const ML_BLOCKMONSTERS = doomdata.ML_BLOCKMONSTERS;
const ML_TWOSIDED = doomdata.ML_TWOSIDED;
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const g_game = @import("g_game.zig");
const m_bbox = @import("m_bbox.zig");
const BBox = m_bbox.BBox;
const m_fixed = @import("m_fixed.zig");
const FRACBITS = m_fixed.FRACBITS;
const FRACUNIT = m_fixed.FRACUNIT;
const fixed_t = m_fixed.fixed_t;
const FixedAbs = m_fixed.FixedAbs;
const FixedDiv = m_fixed.FixedDiv;
const FixedMul = m_fixed.FixedMul;
const m_random = @import("m_random.zig");
const p_inter = @import("p_inter.zig");
const p_maputil = @import("p_maputil.zig");
const p_mobj = @import("p_mobj.zig");
const MF_DROPPED = p_mobj.MF_DROPPED;
const MF_DROPOFF = p_mobj.MF_DROPOFF;
const MF_FLOAT = p_mobj.MF_FLOAT;
const MF_MISSILE = p_mobj.MF_MISSILE;
const MF_NOBLOOD = p_mobj.MF_NOBLOOD;
const MF_NOCLIP = p_mobj.MF_NOCLIP;
const MF_PICKUP = p_mobj.MF_PICKUP;
const MF_SKULLFLY = p_mobj.MF_SKULLFLY;
const MF_SHOOTABLE = p_mobj.MF_SHOOTABLE;
const MF_SOLID = p_mobj.MF_SOLID;
const MF_SPECIAL = p_mobj.MF_SPECIAL;
const MF_TELEPORT = p_mobj.MF_TELEPORT;
const MObj = p_mobj.MObj;
const p_setup = @import("p_setup.zig");
const p_tick = @import("p_tick.zig");
const r_sky = @import("r_sky.zig");
const s_sound = @import("s_sound.zig");
const S_StartSound = s_sound.S_StartSound_Zig;

var tmbbox: BBox = undefined;
var tmthing: *MObj = undefined;
var tmflags: c_int = 0;
var tmx: fixed_t = 0;
var tmy: fixed_t = 0;

/// If `floatok` true, move would be ok if within `tmfloorz - tmceilingz`.
pub export var floatok: c.boolean = c.false;

pub export var tmfloorz: fixed_t = 0;
var tmceilingz: fixed_t = 0;
var tmdropoffz: fixed_t = 0;

/// Keep track of the line that lowers the ceiling, so missiles don't explode
/// against sky hack walls.
pub var ceilingline: ?*const c.line_t = null;

// keep track of special lines as they are hit, but don't process them until
// the move is proven valid
const MAXSPECIALCROSS = 8;
pub export var spechit: [MAXSPECIALCROSS]*c.line_t = undefined;
pub export var numspechit: usize = 0;

fn PIT_StompThing(thing: *MObj) callconv(.c) c.boolean {
    if (thing.flags & MF_SHOOTABLE == 0) {
        return c.true;
    }

    const blockdist = thing.radius + tmthing.radius;

    if (FixedAbs(thing.x - tmx) >= blockdist or FixedAbs(thing.y - tmy) >= blockdist) {
        // didn't hit it
        return c.true;
    }

    // don't clip against self
    if (thing == tmthing) {
        return c.true;
    }

    // TODO: Consider: This monster stomp hack ought to be controllable in the
    // map data rather than baked into the code.
    //
    // monsters don't stomp things except on boss level
    if (tmthing.player == null and g_game.gamemap != 30) {
        return c.false;
    }

    p_inter.P_DamageMobj(thing, tmthing, tmthing, 10000);

    return c.true;
}

pub export fn P_TeleportMove(thing: *MObj, x: fixed_t, y: fixed_t) c.boolean {
    // kill anything occupying the position
    tmthing = thing;
    tmflags = thing.flags;
    tmx = x;
    tmy = y;
    tmbbox = .{
        .top = y + tmthing.radius,
        .bottom = y - tmthing.radius,
        .right = x + tmthing.radius,
        .left = x - tmthing.radius,
    };

    const newsubsec = c.R_PointInSubsector(x, y);
    ceilingline = null;

    // The base floor/ceiling is from the subsector that contains the point.
    // Any contacted lines the step closer together will adjust them.
    tmfloorz = newsubsec.*.sector.*.floorheight;
    tmdropoffz = newsubsec.*.sector.*.floorheight;
    tmceilingz = newsubsec.*.sector.*.ceilingheight;

    c.validcount += 1;
    numspechit = 0;

    // stomp on any things contacted
    const xl = (tmbbox.left - p_setup.bmaporgx - c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
    const xh = (tmbbox.right - p_setup.bmaporgx + c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
    const yl = (tmbbox.bottom - p_setup.bmaporgy - c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
    const yh = (tmbbox.top - p_setup.bmaporgy + c.MAXRADIUS) >> c.MAPBLOCKSHIFT;

    var bx = xl;
    while (bx <= xh) : (bx += 1) {
        var by = yl;
        while (by <= yh) : (by += 1) {
            if (p_maputil.P_BlockThingsIterator(bx, by, PIT_StompThing) == c.false) {
                return c.false;
            }
        }
    }

    // the move is ok, so link the thing into its new position
    p_maputil.P_UnsetThingPosition(thing);

    thing.floorz = tmfloorz;
    thing.ceilingz = tmceilingz;
    thing.x = x;
    thing.y = y;

    p_maputil.P_SetThingPosition(thing);

    return c.true;
}

fn PIT_CheckLine(ld: *c.line_t) bool {
    if (!tmbbox.overlaps(BBox.fromArray(&ld.bbox).*)) {
        return true;
    }

    if (p_maputil.P_BoxOnLineSide(&tmbbox, ld) != -1) {
        return true;
    }

    // A line has been hit
    //
    // The moving thing's destination position will cross the given line. If
    // this should not be allowed, return false. If the line is special, keep
    // track of it to process later if the move is proven ok.
    //
    // NOTE: specials are NOT sorted by order, so two special lines that are
    // only 8 pixels apart could be crossed in either order.

    if (ld.backsector == null) {
        return false; // one sided line
    }

    if (tmthing.flags & MF_MISSILE == 0) {
        if (ld.flags & ML_BLOCKING != 0) {
            return false; // explicitly blocking everything
        }

        if (tmthing.player == null and ld.flags & ML_BLOCKMONSTERS != 0) {
            return false; // block monsters only
        }
    }

    // set openrange, opentop, openbottom
    p_maputil.P_LineOpening(ld);

    // adjust floor / ceiling heights
    if (p_maputil.opentop < tmceilingz) {
        tmceilingz = p_maputil.opentop;
        ceilingline = ld;
    }

    if (p_maputil.openbottom > tmfloorz) {
        tmfloorz = p_maputil.openbottom;
    }

    if (p_maputil.lowfloor < tmdropoffz) {
        tmdropoffz = p_maputil.lowfloor;
    }

    // if contacted a special line, add it to the list
    if (ld.special != 0) {
        spechit[numspechit] = ld;
        numspechit += 1;
    }

    return true;
}

fn PIT_CheckThing(thing: *MObj) callconv(.c) c.boolean {
    if (thing.flags & (MF_SOLID | MF_SPECIAL | MF_SHOOTABLE) == 0) {
        return c.true;
    }

    const blockdist = thing.radius + tmthing.radius;

    if (FixedAbs(thing.x - tmx) >= blockdist or FixedAbs(thing.y - tmy) >= blockdist) {
        return c.true; // didn't hit it
    }

    // don't clip against self
    if (thing == tmthing) {
        return c.true;
    }

    // check for skulls slamming into things
    if (tmthing.flags & MF_SKULLFLY != 0) {
        const damage = tmthing.info.*.damage * (@mod(m_random.P_Random(), 8) + 1);

        p_inter.P_DamageMobj(thing, tmthing, tmthing, damage);

        tmthing.flags &= ~MF_SKULLFLY;
        tmthing.momx = 0;
        tmthing.momy = 0;
        tmthing.momz = 0;

        _ = p_mobj.P_SetMobjState(tmthing, @intCast(tmthing.info.*.spawnstate));

        return c.false; // stop moving
    }

    // missiles can hit other things
    if (tmthing.flags & MF_MISSILE != 0) {
        // see if it went over / under
        if (tmthing.z > thing.z + thing.height) {
            return c.true; // overhead
        }
        if (tmthing.z + tmthing.height < thing.z) {
            return c.true; // underneath
        }

        if (tmthing.target != null and (tmthing.target.?.type == thing.type or
            (tmthing.target.?.type == c.MT_KNIGHT and thing.type == c.MT_BRUISER) or
            (tmthing.target.?.type == c.MT_BRUISER and thing.type == c.MT_KNIGHT)))
        {
            // Don't hit some species as originator
            if (thing == tmthing.target) {
                return c.true;
            }

            if (thing.type != c.MT_PLAYER) {
                // Explode, but do no damage.
                // Let players missile other players.
                return c.false;
            }
        }

        if (thing.flags & MF_SHOOTABLE == 0) {
            // didn't do any damage
            return d_main.toDoomBoolean(thing.flags & MF_SOLID == 0);
        }

        // damage / explode
        const damage = tmthing.info.*.damage * (@mod(m_random.P_Random(), 8) + 1);
        p_inter.P_DamageMobj(thing, tmthing, tmthing.target, damage);

        // don't traverse any more
        return c.false;
    }

    // check for special pickup
    if (thing.flags & MF_SPECIAL != 0) {
        const solid = thing.flags & MF_SOLID != 0;
        if (tmflags & MF_PICKUP != 0) {
            // can remove thing
            p_inter.P_TouchSpecialThing(thing, tmthing);
        }
        return d_main.toDoomBoolean(!solid);
    }

    return d_main.toDoomBoolean(thing.flags & MF_SOLID == 0);
}

/// Checks whether `thing` could stand at (x, y). Its current position is
/// ignored. Returns false at the first blocking thing or line.
///
/// Not side-effect free: things are picked up if `thing` has MF_PICKUP, and
/// lost soul slams and missile hits deal damage.
///
/// Sets for the caller:
///   tmfloorz, tmceilingz  floor and ceiling heights allowed at the position
///   tmdropoffz            lowest floor contacted (monsters avoid dropoffs)
///   ceilingline           line that set tmceilingz, if any
///   spechit, numspechit   special lines crossed, for P_TryMove to trigger
pub export fn P_CheckPosition(thing: *MObj, x: fixed_t, y: fixed_t) c.boolean {
    // TODO: Consider refactoring the duplicate code between here and
    // P_TeleportMove, something like
    // `fn setupCheck(thing: *MObj, x: fixed_t, y: fixed_t) void`
    tmthing = thing;
    tmflags = thing.flags;
    tmx = x;
    tmy = y;
    tmbbox = .{
        .top = y + tmthing.radius,
        .bottom = y - tmthing.radius,
        .right = x + tmthing.radius,
        .left = x - tmthing.radius,
    };

    const newsubsec = c.R_PointInSubsector(x, y);
    ceilingline = null;

    // The base floor/ceiling is from the subsector that contains the point.
    // Any contacted lines the step closer together will adjust them.
    tmfloorz = newsubsec.*.sector.*.floorheight;
    tmdropoffz = newsubsec.*.sector.*.floorheight;
    tmceilingz = newsubsec.*.sector.*.ceilingheight;

    c.validcount += 1;
    numspechit = 0;

    if (tmflags & MF_NOCLIP != 0) {
        return c.true;
    }

    // Check things first, possibly picking things up. The bounding box is
    // extended by MAXRADIUS because MObjs are grouped into mapblocks based on
    // their origin point, and can overlap into adjacent blocks by up to
    // MAXRADIUS units.
    {
        const xl = (tmbbox.left - p_setup.bmaporgx - c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        const xh = (tmbbox.right - p_setup.bmaporgx + c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        const yl = (tmbbox.bottom - p_setup.bmaporgy - c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        const yh = (tmbbox.top - p_setup.bmaporgy + c.MAXRADIUS) >> c.MAPBLOCKSHIFT;

        var bx = xl;
        while (bx <= xh) : (bx += 1) {
            var by = yl;
            while (by <= yh) : (by += 1) {
                if (p_maputil.P_BlockThingsIterator(bx, by, PIT_CheckThing) == c.false) {
                    return c.false;
                }
            }
        }
    }

    // check lines
    {
        const xl = (tmbbox.left - p_setup.bmaporgx) >> c.MAPBLOCKSHIFT;
        const xh = (tmbbox.right - p_setup.bmaporgx) >> c.MAPBLOCKSHIFT;
        const yl = (tmbbox.bottom - p_setup.bmaporgy) >> c.MAPBLOCKSHIFT;
        const yh = (tmbbox.top - p_setup.bmaporgy) >> c.MAPBLOCKSHIFT;

        var bx = xl;
        while (bx <= xh) : (bx += 1) {
            var by = yl;
            while (by <= yh) : (by += 1) {
                if (!p_maputil.P_BlockLinesIterator(bx, by, PIT_CheckLine)) {
                    return c.false;
                }
            }
        }
    }

    return c.true;
}

/// Attempt to move to a new position, crossing special lines unless
/// MF_TELEPORT is set.
pub export fn P_TryMove(thing: *MObj, x: fixed_t, y: fixed_t) c.boolean {
    floatok = c.false;
    if (P_CheckPosition(thing, x, y) == c.false) {
        return c.false; // solid wall or thing
    }

    if (thing.flags & MF_NOCLIP == 0) {
        if (tmceilingz - tmfloorz < thing.height) {
            return c.false; // doesn't fit
        }

        floatok = c.true;

        if (thing.flags & MF_TELEPORT == 0 and tmceilingz - thing.z < thing.height) {
            return c.false; // mobj must lower itself to fit
        }

        if (thing.flags & MF_TELEPORT == 0 and tmfloorz - thing.z > 24 * FRACUNIT) {
            return c.false; // too big a step up
        }

        if (thing.flags & (MF_DROPOFF | MF_FLOAT) == 0 and tmfloorz - tmdropoffz > 24 * FRACUNIT) {
            return c.false; // don't stand over a dropoff
        }
    }

    // the move is ok, so link the thing into its new position
    p_maputil.P_UnsetThingPosition(thing);

    const oldx = thing.x;
    const oldy = thing.y;
    thing.floorz = tmfloorz;
    thing.ceilingz = tmceilingz;
    thing.x = x;
    thing.y = y;

    p_maputil.P_SetThingPosition(thing);

    // if any special lines were hit, do the effect
    if (thing.flags & (MF_TELEPORT | MF_NOCLIP) == 0) {
        while (numspechit > 0) {
            numspechit -= 1;

            // see if the line was crossed
            const ld = spechit[numspechit];
            const side = p_maputil.P_PointOnLineSide(thing.x, thing.y, ld);
            const oldside = p_maputil.P_PointOnLineSide(oldx, oldy, ld);
            if (side != oldside) {
                if (ld.special != 0) {
                    c.P_CrossSpecialLine(@intCast(ld - p_setup.lines), oldside, @ptrCast(thing));
                }
            }
        }
    }

    return c.true;
}

/// Takes a valid thing and adjusts the thing.floorz, thing.ceilingz, and
/// possibly thing.z. This is called for all nearby monsters whenever a
/// sector changes height. If the thing doesn't fit, the z will be set to
/// the lowest value and false will be returned.
fn P_ThingHeightClip(thing: *MObj) bool {
    const onfloor = thing.z == thing.floorz;

    _ = P_CheckPosition(thing, thing.x, thing.y);
    // what about stranding a monster partially off an edge?

    thing.floorz = tmfloorz;
    thing.ceilingz = tmceilingz;

    if (onfloor) {
        // walking monsters rise and fall with the floor
        thing.z = thing.floorz;
    } else {
        // don't adjust a floating monster unless forced to
        if (thing.z + thing.height > thing.ceilingz) {
            thing.z = thing.ceilingz - thing.height;
        }
    }

    if (thing.ceilingz - thing.floorz < thing.height) {
        return false;
    }

    return true;
}

//
// SLIDE MOVE
// Allows the player to slide along any angled walls.
//
var bestslidefrac: fixed_t = 0;
var secondslidefrac: fixed_t = 0;

var bestslideline: ?*c.line_t = null;
var secondslideline: ?*c.line_t = null;

var slidemo: *MObj = undefined;

var tmxmove: fixed_t = 0;
var tmymove: fixed_t = 0;

/// Adjusts the xmove / ymove so that the next move will slide along the wall.
fn P_HitSlideLine(ld: *const c.line_t) void {
    if (ld.slopetype == c.ST_HORIZONTAL) {
        tmymove = 0;
        return;
    }

    if (ld.slopetype == c.ST_VERTICAL) {
        tmxmove = 0;
        return;
    }

    const side = p_maputil.P_PointOnLineSide(slidemo.x, slidemo.y, ld);

    var lineangle = c.R_PointToAngle2(0, 0, ld.dx, ld.dy);

    if (side == 1) {
        lineangle +%= c.ANG180;
    }

    const moveangle = c.R_PointToAngle2(0, 0, tmxmove, tmymove);
    var deltaangle = moveangle -% lineangle;

    if (deltaangle > c.ANG180) {
        deltaangle +%= c.ANG180;
    }

    lineangle >>= c.ANGLETOFINESHIFT;
    deltaangle >>= c.ANGLETOFINESHIFT;

    const movelen = p_maputil.P_AproxDistance(tmxmove, tmymove);
    const newlen = FixedMul(movelen, c.finecosine[deltaangle]);

    tmxmove = FixedMul(newlen, c.finecosine[lineangle]);
    tmymove = FixedMul(newlen, c.finesine[lineangle]);
}

fn PTR_SlideTraverse(in: *c.intercept_t) bool {
    if (in.isaline == c.false) {
        I_Error("PTR_SlideTraverse: not a line?");
    }

    const li = in.d.line;

    if (li.*.flags & ML_TWOSIDED == 0) {
        if (p_maputil.P_PointOnLineSide(slidemo.x, slidemo.y, li) != 0) {
            // don't hit the back side
            return true;
        }
    } else {
        // set openrange, opentop, openbottom
        p_maputil.P_LineOpening(li);

        const blocked = p_maputil.openrange < slidemo.height // doesn't fit
        or p_maputil.opentop - slidemo.z < slidemo.height // mobj is too high
        or p_maputil.openbottom - slidemo.z > 24 * FRACUNIT; // too big a step up

        if (!blocked) {
            // this line doesn't block movement
            return true;
        }
    }

    // the line does block movement, see if it is closer than best so far
    if (in.frac < bestslidefrac) {
        secondslidefrac = bestslidefrac;
        secondslideline = bestslideline;
        bestslidefrac = in.frac;
        bestslideline = li;
    }

    return false; // stop
}

/// The momx / momy move is bad, so try to slide along a wall. Find the first
/// line hit, move flush to it, and slide along it.
///
/// This is a kludgy mess.
pub fn P_SlideMove(mo: *MObj) void {
    slidemo = mo;

    // try twice and then do a stair step
    for (0..2) |_| {
        // trace along the three leading corners
        const leadx: fixed_t, const trailx: fixed_t = if (mo.momx > 0) .{
            mo.x + mo.radius,
            mo.x - mo.radius,
        } else .{
            mo.x - mo.radius,
            mo.x + mo.radius,
        };

        const leady: fixed_t, const traily: fixed_t = if (mo.momy > 0) .{
            mo.y + mo.radius,
            mo.y - mo.radius,
        } else .{
            mo.y - mo.radius,
            mo.y + mo.radius,
        };

        bestslidefrac = FRACUNIT + 1;

        _ = p_maputil.P_PathTraverse(leadx, leady, leadx + mo.momx, leady + mo.momy, c.PT_ADDLINES, PTR_SlideTraverse);
        _ = p_maputil.P_PathTraverse(trailx, leady, trailx + mo.momx, leady + mo.momy, c.PT_ADDLINES, PTR_SlideTraverse);
        _ = p_maputil.P_PathTraverse(leadx, traily, leadx + mo.momx, traily + mo.momy, c.PT_ADDLINES, PTR_SlideTraverse);

        // move up to the wall
        if (bestslidefrac == FRACUNIT + 1) {
            // the move most have hit the middle, so stairstep
            break;
        }

        // fudge a bit to make sure it doesn't hit
        bestslidefrac -= 0x800;
        if (bestslidefrac > 0) {
            const newx = FixedMul(mo.momx, bestslidefrac);
            const newy = FixedMul(mo.momy, bestslidefrac);

            if (P_TryMove(mo, mo.x + newx, mo.y + newy) == c.false) {
                // do a stair step
                break;
            }
        }

        // Now continue along the wall. First calculate remainder.
        bestslidefrac = FRACUNIT - (bestslidefrac + 0x800);

        if (bestslidefrac > FRACUNIT) {
            bestslidefrac = FRACUNIT;
        }

        if (bestslidefrac <= 0) {
            return;
        }

        tmxmove = FixedMul(mo.momx, bestslidefrac);
        tmymove = FixedMul(mo.momy, bestslidefrac);

        P_HitSlideLine(bestslideline.?); // clip the moves

        mo.momx = tmxmove;
        mo.momy = tmymove;

        if (P_TryMove(mo, mo.x + tmxmove, mo.y + tmymove) != c.false) {
            // good
            return;
        }
        // otherwise try again or if failed again try the stairstep
    }

    // do a stairstep
    if (P_TryMove(mo, mo.x, mo.y + mo.momy) == c.false) {
        _ = P_TryMove(mo, mo.x + mo.momx, mo.y);
    }
}

/// who got hit (or null)
pub export var linetarget: ?*MObj = null;
var shootthing: *MObj = undefined;

var shootz: fixed_t = 0;

var la_damage: c_int = 0;
pub var attackrange: fixed_t = 0;

var aimslope: fixed_t = 0;

extern var topslope: fixed_t;
extern var bottomslope: fixed_t;

/// Sets linetarget and aimslope when a target is aimed at
fn PTR_AimTraverse(in: *c.intercept_t) bool {
    if (in.isaline != c.false) {
        // shoot a line
        const li = in.d.line;

        if (li.*.flags & ML_TWOSIDED == 0) {
            return false; // stop
        }

        // Crosses a two sided line. A two sided line will restrict the
        // possible target ranges.
        p_maputil.P_LineOpening(li);

        if (p_maputil.openbottom >= p_maputil.opentop) {
            return false; // stop
        }

        const dist = FixedMul(attackrange, in.frac);

        if (li.*.frontsector.*.floorheight != li.*.backsector.*.floorheight) {
            const slope = FixedDiv(p_maputil.openbottom - shootz, dist);
            if (slope > bottomslope) {
                bottomslope = slope;
            }
        }

        if (li.*.frontsector.*.ceilingheight != li.*.backsector.*.ceilingheight) {
            const slope = FixedDiv(p_maputil.opentop - shootz, dist);
            if (slope < topslope) {
                topslope = slope;
            }
        }

        if (topslope <= bottomslope) {
            return false; // stop
        }

        return true; // shot continues
    }

    // shoot a thing
    const th: *MObj = @ptrCast(in.d.thing);
    if (th == shootthing) {
        return true; // can't shoot self
    }

    if (th.flags & MF_SHOOTABLE == 0) {
        return true; // corpse or something
    }

    // check angles to see if the thing can be aimed at
    const dist = FixedMul(attackrange, in.frac);
    var thingtopslope = FixedDiv(th.z + th.height - shootz, dist);

    if (thingtopslope < bottomslope) {
        return true; // shot over the thing
    }

    var thingbottomslope = FixedDiv(th.z - shootz, dist);

    if (thingbottomslope > topslope) {
        return true; // shot under the thing
    }

    // this thing can be hit!
    if (thingtopslope > topslope) {
        thingtopslope = topslope;
    }

    if (thingbottomslope < bottomslope) {
        thingbottomslope = bottomslope;
    }

    aimslope = @divTrunc(thingtopslope + thingbottomslope, 2);
    linetarget = th;

    return false; // don't go any farther
}

fn PTR_ShootTraverse(in: *c.intercept_t) bool {
    if (in.isaline != c.false) {
        const li = in.d.line;

        if (li.*.special != 0) {
            c.P_ShootSpecialLine(@ptrCast(shootthing), li);
        }

        if (li.*.flags & ML_TWOSIDED != 0) {
            // crosses a two sided line
            p_maputil.P_LineOpening(li);

            const dist = FixedMul(attackrange, in.frac);

            const linebottomslope = FixedDiv(p_maputil.openbottom - shootz, dist);
            const hitsbottom = li.*.frontsector.*.floorheight != li.*.backsector.*.floorheight and
                linebottomslope > aimslope;

            const linetopslope = FixedDiv(p_maputil.opentop - shootz, dist);
            const hitstop = li.*.frontsector.*.ceilingheight != li.*.backsector.*.ceilingheight and
                linetopslope < aimslope;

            if (!hitsbottom and !hitstop) {
                return true; // shot continues
            }
        }

        // hit line

        // position a bit closer
        const frac = in.frac - FixedDiv(4 * FRACUNIT, attackrange);
        const x = p_maputil.trace.x + FixedMul(p_maputil.trace.dx, frac);
        const y = p_maputil.trace.y + FixedMul(p_maputil.trace.dy, frac);
        const z = shootz + FixedMul(aimslope, FixedMul(frac, attackrange));

        if (li.*.frontsector.*.ceilingpic == r_sky.skyflatnum) {
            // don't shoot the sky!
            if (z > li.*.frontsector.*.ceilingheight) {
                return false;
            }

            // it's a sky hack wall
            if (li.*.backsector != null and li.*.backsector.*.ceilingpic == r_sky.skyflatnum) {
                return false;
            }
        }

        // Spawn bullet puffs.
        p_mobj.P_SpawnPuff(x, y, z);

        // don't go any farther
        return false;
    }

    // shoot a thing
    const th: *MObj = @ptrCast(in.d.thing);
    if (th == shootthing) {
        return true; // can't shoot self
    }

    if (th.flags & MF_SHOOTABLE == 0) {
        return true; // corpse or something
    }

    // check angles to see if the thing can be aimed
    const dist = FixedMul(attackrange, in.frac);
    const thingtopslope = FixedDiv(th.z + th.height - shootz, dist);

    if (thingtopslope < aimslope) {
        return true; // shot over the thing
    }

    const thingbottomslope = FixedDiv(th.z - shootz, dist);

    if (thingbottomslope > aimslope) {
        return true; // shot under the thing
    }

    // hit thing

    // position a bit closer
    const frac = in.frac - FixedDiv(10 * FRACUNIT, attackrange);

    const x = p_maputil.trace.x + FixedMul(p_maputil.trace.dx, frac);
    const y = p_maputil.trace.y + FixedMul(p_maputil.trace.dy, frac);
    const z = shootz + FixedMul(aimslope, FixedMul(frac, attackrange));

    // Spawn bullet puffs or blood spots, depending on target type.
    if (in.d.thing.*.flags & MF_NOBLOOD != 0) {
        p_mobj.P_SpawnPuff(x, y, z);
    } else {
        p_mobj.P_SpawnBlood(x, y, z, la_damage);
    }

    if (la_damage != 0) {
        p_inter.P_DamageMobj(th, shootthing, shootthing, la_damage);
    }

    // don't go any farther
    return false;
}

pub export fn P_AimLineAttack(th: *MObj, _angle: c.angle_t, distance: fixed_t) fixed_t {
    const angle = _angle >> c.ANGLETOFINESHIFT;
    shootthing = th;

    const x2 = th.x + (distance >> FRACBITS) * c.finecosine[angle];
    const y2 = th.y + (distance >> FRACBITS) * c.finesine[angle];
    shootz = th.z + (th.height >> 1) + 8 * FRACUNIT;

    // can't shoot outside view angles
    topslope = @divTrunc(100 * FRACUNIT, 160);
    bottomslope = @divTrunc(-100 * FRACUNIT, 160);

    attackrange = distance;
    linetarget = null;

    _ = p_maputil.P_PathTraverse(th.x, th.y, x2, y2, c.PT_ADDLINES | c.PT_ADDTHINGS, PTR_AimTraverse);

    if (linetarget != null) {
        return aimslope;
    }

    return 0;
}

/// If damage == 0, it is just a test trace that will leave linetarget set.
pub export fn P_LineAttack(th: *MObj, _angle: c.angle_t, distance: fixed_t, slope: fixed_t, damage: c_int) void {
    const angle = _angle >> c.ANGLETOFINESHIFT;
    shootthing = th;
    la_damage = damage;

    const x2 = th.x + (distance >> FRACBITS) * c.finecosine[angle];
    const y2 = th.y + (distance >> FRACBITS) * c.finesine[angle];
    shootz = th.z + (th.height >> 1) + 8 * FRACUNIT;

    attackrange = distance;
    aimslope = slope;

    _ = p_maputil.P_PathTraverse(th.x, th.y, x2, y2, c.PT_ADDLINES | c.PT_ADDTHINGS, PTR_ShootTraverse);
}

var usething: *MObj = undefined;

fn PTR_UseTraverse(in: *c.intercept_t) bool {
    if (in.d.line.*.special == 0) {
        p_maputil.P_LineOpening(in.d.line);
        if (p_maputil.openrange <= 0) {
            S_StartSound(usething, .noway);

            // can't use through a wall
            return false;
        }

        // not a special line, but keep checking
        return true;
    }

    const side = p_maputil.P_PointOnLineSide(usething.x, usething.y, in.d.line);

    _ = c.P_UseSpecialLine(@ptrCast(usething), in.d.line, side);

    // can't use for more than one special line in a row
    return false;
}

/// Looks for special lines in front of the player to activate.
pub fn P_UseLines(player: *Player) void {
    usething = player.mo.?;

    const angle = player.mo.?.angle >> c.ANGLETOFINESHIFT;

    const x1 = player.mo.?.x;
    const y1 = player.mo.?.y;
    const x2 = x1 + (c.USERANGE >> FRACBITS) * c.finecosine[angle];
    const y2 = y1 + (c.USERANGE >> FRACBITS) * c.finesine[angle];

    _ = p_maputil.P_PathTraverse(x1, y1, x2, y2, c.PT_ADDLINES, PTR_UseTraverse);
}

var bombsource: ?*MObj = undefined;
var bombspot: *MObj = undefined;
var bombdamage: c_int = 0;

/// "bombsource" is the creature that caused the explosion at "bombspot".
fn PIT_RadiusAttack(thing: *MObj) callconv(.c) c.boolean {
    if (thing.flags & MF_SHOOTABLE == 0) {
        return c.true;
    }

    // Boss spider and cyborg take no damage from concussion.
    if (thing.type == c.MT_CYBORG or thing.type == c.MT_SPIDER) {
        return c.true;
    }

    const dx = FixedAbs(thing.x - bombspot.x);
    const dy = FixedAbs(thing.y - bombspot.y);
    const dist = @max(0, (@max(dx, dy) - thing.radius) >> FRACBITS);

    if (dist >= bombdamage) {
        return c.true; // out of range
    }

    if (c.P_CheckSight(@ptrCast(thing), @ptrCast(bombspot)) != c.false) {
        // must be in direct path
        p_inter.P_DamageMobj(thing, bombspot, bombsource, bombdamage - dist);
    }

    return c.true;
}

/// Source is the creature that caused the explosion at spot.
pub export fn P_RadiusAttack(spot: *MObj, source: ?*MObj, damage: c_int) void {
    const dist = (damage + c.MAXRADIUS) << FRACBITS;
    const yh = (spot.y + dist - p_setup.bmaporgy) >> c.MAPBLOCKSHIFT;
    const yl = (spot.y - dist - p_setup.bmaporgy) >> c.MAPBLOCKSHIFT;
    const xh = (spot.x + dist - p_setup.bmaporgx) >> c.MAPBLOCKSHIFT;
    const xl = (spot.x - dist - p_setup.bmaporgx) >> c.MAPBLOCKSHIFT;

    bombspot = spot;
    bombsource = source;
    bombdamage = damage;

    var y = yl;
    while (y <= yh) : (y += 1) {
        var x = xl;
        while (x <= xh) : (x += 1) {
            _ = p_maputil.P_BlockThingsIterator(x, y, PIT_RadiusAttack);
        }
    }
}

var crushchange: bool = false;
var nofit: bool = false;

fn PIT_ChangeSector(thing: *MObj) callconv(.c) c.boolean {
    if (P_ThingHeightClip(thing)) {
        // keep checking
        return c.true;
    }

    // crunch bodies into giblets
    if (thing.health <= 0) {
        _ = p_mobj.P_SetMobjState(thing, c.S_GIBS);

        thing.flags &= ~MF_SOLID;
        thing.height = 0;
        thing.radius = 0;

        // keep checking
        return c.true;
    }

    // crunch dropped items
    if (thing.flags & MF_DROPPED != 0) {
        p_mobj.P_RemoveMobj(thing);

        // keep checking
        return c.true;
    }

    if (thing.flags & MF_SHOOTABLE == 0) {
        // assume it is bloody gibs or something; keep checking
        return c.true;
    }

    nofit = true;

    if (crushchange and @mod(p_tick.leveltime, 4) == 0) {
        p_inter.P_DamageMobj(thing, null, null, 10);

        // spray blood in a random direction
        const mo = p_mobj.P_SpawnMobj(thing.x, thing.y, thing.z + @divTrunc(thing.height, 2), c.MT_BLOOD);
        mo.momx = (m_random.P_Random() - m_random.P_Random()) << 12;
        mo.momy = (m_random.P_Random() - m_random.P_Random()) << 12;
    }

    // keep checking (crush other things)
    return c.true;
}

/// SECTOR HEIGHT CHANGING
/// After modifying a sectors floor or ceiling height, call this routine to
/// adjust the positions of all things that touch the sector.
///
/// If anything doesn't fit anymore, true will be returned. If crunch is
/// true, they will take damage as they are being crushed. If crunch is
/// false, you should set the sector height back the way it was and call
/// P_ChangeSector again to undo the changes.
pub export fn P_ChangeSector(sector: *c.sector_t, crunch: c.boolean) c.boolean {
    nofit = false;
    crushchange = crunch != c.false;

    // re-check heights for all things near the moving sector
    const sectorbbox = BBox.fromArray(&sector.blockbox);
    var x = sectorbbox.left;
    while (x <= sectorbbox.right) : (x += 1) {
        var y = sectorbbox.bottom;
        while (y <= sectorbbox.top) : (y += 1) {
            _ = p_maputil.P_BlockThingsIterator(x, y, PIT_ChangeSector);
        }
    }

    return d_main.toDoomBoolean(nofit);
}
