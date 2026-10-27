const c = @import("c");
const std = @import("std");

const m_bbox = @import("m_bbox.zig");
const BBox = m_bbox.BBox;
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FixedAbs = m_fixed.FixedAbs;
const FixedDiv = m_fixed.FixedDiv;
const FixedMul = m_fixed.FixedMul;
const FRACBITS = m_fixed.FRACBITS;
const FRACUNIT = m_fixed.FRACUNIT;
const p_mobj = @import("p_mobj.zig");
const MF_NOBLOCKMAP = p_mobj.MF_NOBLOCKMAP;
const MF_NOSECTOR = p_mobj.MF_NOSECTOR;
const MObj = p_mobj.MObj;
const p_setup = @import("p_setup.zig");

/// Gives an estimation of distance (not exact)
pub export fn P_AproxDistance(dx: fixed_t, dy: fixed_t) fixed_t {
    const adx = FixedAbs(dx);
    const ady = FixedAbs(dy);
    if (adx < ady) {
        return adx + ady - (adx >> 1);
    }
    return adx + ady - (ady >> 1);
}

/// Returns 0 (front side) or 1 (back side)
pub fn P_PointOnLineSide(x: fixed_t, y: fixed_t, line: *const c.line_t) c_int {
    if (line.dx == 0) {
        if (x <= line.v1.*.x) {
            return @intFromBool(line.dy > 0);
        }
        return @intFromBool(line.dy < 0);
    }

    if (line.dy == 0) {
        if (y <= line.v1.*.y) {
            return @intFromBool(line.dx < 0);
        }
        return @intFromBool(line.dx > 0);
    }

    const dx = x - line.v1.*.x;
    const dy = y - line.v1.*.y;

    const left = FixedMul(line.dy >> FRACBITS, dx);
    const right = FixedMul(dy, line.dx >> FRACBITS);

    if (right < left) {
        return 0; // front side
    }
    return 1; // back side
}

/// Considers the line to be infinite
/// Returns 0 (front side) or 1 (back side), or -1 if box crosses the line.
pub fn P_BoxOnLineSide(tmbox: *const BBox, ld: *const c.line_t) c_int {
    const p1: c_int, const p2: c_int = switch (ld.slopetype) {
        c.ST_HORIZONTAL => blk: {
            const flip = ld.dx < 0;
            break :blk .{
                @intFromBool(flip != (tmbox.top > ld.v1.*.y)),
                @intFromBool(flip != (tmbox.bottom > ld.v1.*.y)),
            };
        },

        c.ST_VERTICAL => blk: {
            const flip = ld.dy < 0;
            break :blk .{
                @intFromBool(flip != (tmbox.right < ld.v1.*.x)),
                @intFromBool(flip != (tmbox.left < ld.v1.*.x)),
            };
        },

        c.ST_POSITIVE => .{
            P_PointOnLineSide(tmbox.left, tmbox.top, ld),
            P_PointOnLineSide(tmbox.right, tmbox.bottom, ld),
        },

        c.ST_NEGATIVE => .{
            P_PointOnLineSide(tmbox.right, tmbox.top, ld),
            P_PointOnLineSide(tmbox.left, tmbox.bottom, ld),
        },

        else => unreachable,
    };

    return if (p1 == p2) p1 else -1;
}

/// Returns 0 (front side) or 1 (back side)
fn P_PointOnDivlineSide(x: fixed_t, y: fixed_t, line: *const c.divline_t) c_int {
    if (line.dx == 0) {
        return if (x <= line.x) @intFromBool(line.dy > 0) else @intFromBool(line.dy < 0);
    }
    if (line.dy == 0) {
        return if (y <= line.y) @intFromBool(line.dx < 0) else @intFromBool(line.dx > 0);
    }

    const dx = x - line.x;
    const dy = y - line.y;

    // try to quickly decide by looking at sign bits
    if ((line.dy ^ line.dx ^ dx ^ dy) < 0) {
        if ((line.dy ^ dx) < 0) {
            return 1; // (left is negative)
        }
        return 0;
    }

    const left = FixedMul(line.dy >> 8, dx >> 8);
    const right = FixedMul(dy >> 8, line.dx >> 8);

    if (right < left) {
        return 0; // front side
    }
    return 1; // back side
}

fn P_MakeDivline(li: *const c.line_t, dl: *c.divline_t) void {
    dl.x = li.v1.*.x;
    dl.y = li.v1.*.y;
    dl.dx = li.dx;
    dl.dy = li.dy;
}

/// Returns the fractional intercept point along the first divline.
/// This is only called by the addthings and addlines traversers.
pub fn P_InterceptVector(v2: *const c.divline_t, v1: *const c.divline_t) fixed_t {
    const den = FixedMul(v1.dy >> 8, v2.dx) - FixedMul(v1.dx >> 8, v2.dy);

    if (den == 0) {
        return 0;
    }

    const num = FixedMul((v1.x - v2.x) >> 8, v1.dy) + FixedMul((v2.y - v1.y) >> 8, v1.dx);

    return FixedDiv(num, den);
}

pub var opentop: fixed_t = 0;
pub var openbottom: fixed_t = 0;
pub export var openrange: fixed_t = 0;
pub var lowfloor: fixed_t = 0;

/// Sets opentop and openbottom to the window through a two sided line.
pub export fn P_LineOpening(linedef: *const c.line_t) void {
    if (linedef.sidenum[1] == -1) {
        // single sided line
        openrange = 0;
        return;
    }

    const front = linedef.frontsector;
    const back = linedef.backsector;

    opentop = @min(front.*.ceilingheight, back.*.ceilingheight);

    if (front.*.floorheight > back.*.floorheight) {
        openbottom = front.*.floorheight;
        lowfloor = back.*.floorheight;
    } else {
        openbottom = back.*.floorheight;
        lowfloor = front.*.floorheight;
    }

    openrange = opentop - openbottom;
}

/// Unlinks a thing from block map and sectors. On each position change,
/// BLOCKMAP and other lookups maintaining lists of things inside these
/// structures need to be updated.
pub export fn P_UnsetThingPosition(thing: *MObj) void {
    if (thing.flags & MF_NOSECTOR == 0) {
        // inert things don't need to be in blockmap?
        // unlink from subsector
        if (thing.snext != null) {
            thing.snext.?.sprev = thing.sprev;
        }

        if (thing.sprev != null) {
            thing.sprev.?.snext = thing.snext;
        } else {
            thing.subsector.sector.*.thinglist = @ptrCast(thing.snext);
        }
    }

    if (thing.flags & MF_NOBLOCKMAP == 0) {
        // inert things don't need to be in blockmap
        // unlink from block map
        if (thing.bnext != null) {
            thing.bnext.?.bprev = thing.bprev;
        }

        if (thing.bprev != null) {
            thing.bprev.?.bnext = thing.bnext;
        } else {
            const blockx = (thing.x - p_setup.bmaporgx) >> c.MAPBLOCKSHIFT;
            const blocky = (thing.y - p_setup.bmaporgy) >> c.MAPBLOCKSHIFT;

            if (blockx >= 0 and blockx < p_setup.bmapwidth and blocky >= 0 and blocky < p_setup.bmapheight) {
                p_setup.blocklinks[@intCast(blocky * p_setup.bmapwidth + blockx)] = thing.bnext;
            }
        }
    }
}

/// Links a thing into both a block and a subsector based on it's x y.
pub export fn P_SetThingPosition(thing: *MObj) void {
    // link into subsector
    const ss = c.R_PointInSubsector(thing.x, thing.y);
    thing.subsector = ss;

    if (thing.flags & MF_NOSECTOR == 0) {
        // invisible things don't go into the sector links
        const sec = ss.*.sector;

        thing.sprev = null;
        thing.snext = @ptrCast(sec.*.thinglist);

        if (sec.*.thinglist != null) {
            sec.*.thinglist.*.sprev = @ptrCast(thing);
        }

        sec.*.thinglist = @ptrCast(thing);
    }

    // link into blockmap
    if (thing.flags & MF_NOBLOCKMAP == 0) {
        // inert things don't need to be in blockmap
        const blockx = (thing.x - p_setup.bmaporgx) >> c.MAPBLOCKSHIFT;
        const blocky = (thing.y - p_setup.bmaporgy) >> c.MAPBLOCKSHIFT;

        if (blockx >= 0 and blockx < p_setup.bmapwidth and blocky >= 0 and blocky < p_setup.bmapheight) {
            const link = &p_setup.blocklinks[@intCast(blocky * p_setup.bmapwidth + blockx)];
            thing.bprev = null;
            thing.bnext = link.*;
            if (link.* != null) {
                link.*.?.bprev = thing;
            }
            link.* = thing;
        } else {
            // thing is off the map
            thing.bnext = null;
            thing.bprev = null;
        }
    }
}

//
// BLOCK MAP ITERATORS
// For each line/thing in the given mapblock,
// call the passed PIT_* function.
// If the function returns false,
// exit with false without checking anything else.
//

pub const LineVisitor = *const fn (*c.line_t) bool;
pub const ThingVisitor = *const fn (*MObj) callconv(.c) c.boolean;

/// The validcount flags are used to avoid checking lines that are marked in
/// multiple mapblocks, so increment validcount before the first call to
/// P_BlockLinesIterator, then make one or more calls to it.
pub fn P_BlockLinesIterator(x: c_int, y: c_int, func: LineVisitor) bool {
    if (x < 0 or y < 0 or x >= p_setup.bmapwidth or y >= p_setup.bmapheight) {
        return true;
    }

    const offset: usize = @intCast(p_setup.blockmap[@intCast(y * p_setup.bmapwidth + x)]);
    const list: [*:-1]const c_short = @ptrCast(p_setup.blockmaplump + offset);

    for (std.mem.span(list)) |linenum| {
        const ld = &p_setup.lines[@intCast(linenum)];

        if (ld.validcount == c.validcount) {
            continue; // line has already been checked
        }

        ld.validcount = c.validcount;

        if (!func(ld)) {
            return false;
        }
    }

    return true; // everything was checked
}

pub export fn P_BlockThingsIterator(x: c_int, y: c_int, func: ThingVisitor) c.boolean {
    if (x < 0 or y < 0 or x >= p_setup.bmapwidth or y >= p_setup.bmapheight) {
        return c.true;
    }

    var link = p_setup.blocklinks[@intCast(y * p_setup.bmapwidth + x)];
    while (link) |mobj| : (link = mobj.bnext) {
        if (func(mobj) == c.false) {
            return c.false;
        }
    }

    return c.true; // everything was checked
}

//
// INTERCEPT ROUTINES
//
const MAXINTERCEPTS = 128;
var intercepts: [MAXINTERCEPTS]c.intercept_t = undefined;
var intercept_n: usize = 0;

pub var trace: c.divline_t = undefined;
var earlyout = false;

/// Looks for lines in the given block that intercept the given trace to add
/// to the intercepts list.
///
/// A line is crossed if its endpoints are on opposite sides of the trace.
/// Returns true if earlyout and a solid line hit.
fn PIT_AddLineIntercepts(ld: *c.line_t) bool {
    // avoid precision problems with two routines
    const s1: c_int, const s2: c_int = if (trace.dx > FRACUNIT * 16 or trace.dy > FRACUNIT * 16 or trace.dx < -FRACUNIT * 16 or trace.dy < -FRACUNIT * 16) .{
        P_PointOnDivlineSide(ld.v1.*.x, ld.v1.*.y, &trace),
        P_PointOnDivlineSide(ld.v2.*.x, ld.v2.*.y, &trace),
    } else .{
        P_PointOnLineSide(trace.x, trace.y, ld),
        P_PointOnLineSide(trace.x + trace.dx, trace.y + trace.dy, ld),
    };

    if (s1 == s2) {
        return true; // line isn't crossed
    }

    // hit the line
    var dl: c.divline_t = .{};
    P_MakeDivline(ld, &dl);
    const frac = P_InterceptVector(&trace, &dl);

    if (frac < 0) {
        return true; // behind source
    }

    // try to early out the check
    if (earlyout and frac < FRACUNIT and ld.backsector == null) {
        return false; // stop checking
    }

    intercepts[intercept_n] = .{
        .frac = frac,
        .isaline = c.true,
        .d = .{ .line = ld },
    };
    intercept_n += 1;

    return true; // continue
}

fn PIT_AddThingIntercepts(thing: *MObj) callconv(.c) c.boolean {
    // check a corner to corner cross section for hit
    const x1 = thing.x - thing.radius;
    const x2 = thing.x + thing.radius;
    const tracepositive = (trace.dx ^ trace.dy) > 0;
    const y1, const y2 = if (tracepositive) .{
        thing.y + thing.radius,
        thing.y - thing.radius,
    } else .{
        thing.y - thing.radius,
        thing.y + thing.radius,
    };

    const s1 = P_PointOnDivlineSide(x1, y1, &trace);
    const s2 = P_PointOnDivlineSide(x2, y2, &trace);

    if (s1 == s2) {
        return c.true; // line isn't crossed
    }

    const dl = c.divline_t{
        .x = x1,
        .y = y1,
        .dx = x2 - x1,
        .dy = y2 - y1,
    };

    const frac = P_InterceptVector(&trace, &dl);

    if (frac < 0) {
        return c.true; // behind source
    }

    intercepts[intercept_n] = .{
        .frac = frac,
        .isaline = c.false,
        .d = .{ .thing = @ptrCast(thing) },
    };
    intercept_n += 1;

    return c.true; // keep going
}

pub const Traverser = *const fn (*c.intercept_t) bool;

/// Returns true if the traverser function returns true for all lines.
fn P_TraverseIntercepts(func: Traverser, maxfrac: fixed_t) bool {
    var in: *c.intercept_t = undefined;

    for (0..intercept_n) |_| {
        var dist: fixed_t = std.math.maxInt(fixed_t);

        for (intercepts[0..intercept_n]) |*scan| {
            if (scan.frac < dist) {
                dist = scan.frac;
                in = scan;
            }
        }

        if (dist > maxfrac) {
            return true; // checked everything in range
        }

        if (!func(in)) {
            return false; // don't bother going farther
        }

        in.frac = std.math.maxInt(fixed_t);
    }

    return true; // everything was traversed
}

fn onBlockBoundary(v: fixed_t, origin: fixed_t) bool {
    return @mod(v - origin, c.MAPBLOCKSIZE) == 0;
}

/// Position within the current block as a fraction of a block (0..FRACUNIT)
fn fracInBlock(v: fixed_t) fixed_t {
    return @mod(v, c.MAPBLOCKSIZE) >> c.MAPBTOFRAC;
}

/// Traces a line from x1,y1 to x2,y2, calling the traverser function for
/// each. Returns true if the traverser function returns true for all lines.
pub fn P_PathTraverse(_x1: fixed_t, _y1: fixed_t, _x2: fixed_t, _y2: fixed_t, flags: c_int, trav: Traverser) bool {
    var x1 = _x1;
    var y1 = _y1;
    var x2 = _x2;
    var y2 = _y2;

    // TODO: earlyout, intercepts and intercept_n, appear to be context from
    // this function call down only, so they could probably be put in a struct
    // and made a stack context here, instead of global, passed down to the
    // functions that use them.
    // TODO: Also, it looks like PT_EARLYOUT is never used other than this
    // flags read here, so might be the case earlyout is never set true.

    earlyout = flags & c.PT_EARLYOUT != 0;

    c.validcount += 1;
    intercept_n = 0;

    if (onBlockBoundary(x1, p_setup.bmaporgx)) {
        x1 += FRACUNIT; // don't side exactly on a line
    }

    if (onBlockBoundary(y1, p_setup.bmaporgy)) {
        y1 += FRACUNIT; // don't side exactly on a line
    }

    trace = .{
        .x = x1,
        .y = y1,
        .dx = x2 - x1,
        .dy = y2 - y1,
    };

    x1 -= p_setup.bmaporgx;
    y1 -= p_setup.bmaporgy;
    const xt1 = x1 >> c.MAPBLOCKSHIFT;
    const yt1 = y1 >> c.MAPBLOCKSHIFT;

    x2 -= p_setup.bmaporgx;
    y2 -= p_setup.bmaporgy;
    const xt2 = x2 >> c.MAPBLOCKSHIFT;
    const yt2 = y2 >> c.MAPBLOCKSHIFT;

    const mapxstep: c_int, const xpartial, const ystep = if (xt2 > xt1) .{
        1, FRACUNIT - fracInBlock(x1), FixedDiv(y2 - y1, FixedAbs(x2 - x1))
    } else if (xt2 < xt1) .{
        -1, fracInBlock(x1), FixedDiv(y2 - y1, FixedAbs(x2 - x1))
    } else .{
        0, FRACUNIT, 256 * FRACUNIT
    };

    var yintercept = (y1 >> c.MAPBTOFRAC) + FixedMul(xpartial, ystep);

    const mapystep: c_int, const ypartial, const xstep = if (yt2 > yt1) .{
        1, FRACUNIT - fracInBlock(y1), FixedDiv(x2 - x1, FixedAbs(y2 - y1))
    } else if (yt2 < yt1) .{
        -1, fracInBlock(y1), FixedDiv(x2 - x1, FixedAbs(y2 - y1))
    } else .{
        0, FRACUNIT, 256 * FRACUNIT
    };

    var xintercept = (x1 >> c.MAPBTOFRAC) + FixedMul(ypartial, xstep);

    // Step through map blocks. Count is present to prevent a round off
    // error from skipping the break.
    var mapx = xt1;
    var mapy = yt1;

    for (0..64) |_| {
        if (flags & c.PT_ADDLINES != 0) {
            if (!P_BlockLinesIterator(mapx, mapy, PIT_AddLineIntercepts)) {
                return false; // early out
            }
        }

        if (flags & c.PT_ADDTHINGS != 0) {
            if (P_BlockThingsIterator(mapx, mapy, PIT_AddThingIntercepts) == c.false) {
                return false; // early out
            }
        }

        if (mapx == xt2 and mapy == yt2) {
            break;
        }

        if ((yintercept >> FRACBITS) == mapy) {
            yintercept += ystep;
            mapx += mapxstep;
        } else if ((xintercept >> FRACBITS) == mapx) {
            xintercept += xstep;
            mapy += mapystep;
        }
    }

    // go through the sorted list
    return P_TraverseIntercepts(trav, FRACUNIT);
}
