const c = @import("c");

const d_main = @import("d_main.zig");
const doomdata = @import("doomdata.zig");
const m_fixed = @import("m_fixed.zig");
const FRACBITS = m_fixed.FRACBITS;
const FixedDiv = m_fixed.FixedDiv;
const fixed_t = m_fixed.fixed_t;
const p_maputil = @import("p_maputil.zig");
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const p_setup = @import("p_setup.zig");

var sightzstart: fixed_t = 0; // eye z of looker
pub var topslope: fixed_t = 0;
pub var bottomslope: fixed_t = 0; // slopes to top and bottom of target

var strace: c.divline_t = undefined; // from t1 to t2
var t2x: fixed_t = 0;
var t2y: fixed_t = 0;

/// Returns side 0 (front), 1 (back), or 2 (on).
fn P_DivlineSide(x: fixed_t, y: fixed_t, node: *const c.divline_t) usize {
    if (node.dx == 0) {
        if (x == node.x) {
            return 2;
        }

        if (x <= node.x) {
            return if (node.dy > 0) 1 else 0;
        }

        return if (node.dy < 0) 1 else 0;
    }

    if (node.dy == 0) {
        // BUG: Is this a copy-paste bug? Shouldn't it be y == node.y?
        if (x == node.y) {
            return 2;
        }

        if (y <= node.y) {
            return if (node.dx < 0) 1 else 0;
        }

        return if (node.dx > 0) 1 else 0;
    }

    const dx = x - node.x;
    const dy = y - node.y;

    const left = (node.dy >> FRACBITS) * (dx >> FRACBITS);
    const right = (node.dx >> FRACBITS) * (dy >> FRACBITS);

    if (right < left) {
        return 0; // front side
    }

    if (left == right) {
        return 2;
    }

    return 1; // back side
}

/// Returns true if strace crosses the given subsector successfully.
fn P_CrossSubsector(num: usize) bool {
    const sub = &p_setup.subsectors[num];

    // check lines
    const start: usize = @intCast(sub.firstline);
    const end: usize = @intCast(sub.firstline + sub.numlines);

    for (p_setup.segs[start..end]) |*seg| {
        const line = seg.linedef;

        // already checked other side?
        if (line.*.validcount == c.validcount) {
            continue;
        }

        line.*.validcount = c.validcount;

        const v1 = line.*.v1.*;
        const v2 = line.*.v2.*;
        var s1 = P_DivlineSide(v1.x, v1.y, &strace);
        var s2 = P_DivlineSide(v2.x, v2.y, &strace);

        // line isn't crossed?
        if (s1 == s2) {
            continue;
        }

        const divl: c.divline_t = .{
            .x = v1.x,
            .y = v1.y,
            .dx = v2.x - v1.x,
            .dy = v2.y - v1.y,
        };
        s1 = P_DivlineSide(strace.x, strace.y, &divl);
        s2 = P_DivlineSide(t2x, t2y, &divl);

        // line isn't crossed?
        if (s1 == s2) {
            continue;
        }

        // stop because it is not two sided anyway
        // might do this after updating validcount?
        if (line.*.flags & doomdata.ML_TWOSIDED == 0) {
            return false;
        }

        // crosses a two sided line
        const front = seg.frontsector.*;
        const back = seg.backsector.*;

        // no wall to block sight with?
        if (front.floorheight == back.floorheight and front.ceilingheight == back.ceilingheight) {
            continue;
        }

        // possible occluder because of ceiling or floor height differences
        const opentop = @min(front.ceilingheight, back.ceilingheight);
        const openbottom = @max(front.floorheight, back.floorheight);

        // quick test for totally closed doors
        if (openbottom >= opentop) {
            return false; // stop
        }

        const frac = p_maputil.P_InterceptVector(&strace, &divl);

        if (front.floorheight != back.floorheight) {
            const slope = FixedDiv(openbottom - sightzstart, frac);
            if (slope > bottomslope) {
                bottomslope = slope;
            }
        }

        if (front.ceilingheight != back.ceilingheight) {
            const slope = FixedDiv(opentop - sightzstart, frac);
            if (slope < topslope) {
                topslope = slope;
            }
        }

        if (topslope <= bottomslope) {
            return false; // stop
        }
    }

    // passed the subsector ok
    return true;
}

/// Returns true if strace crosses the given node successfully.
fn P_CrossBSPNode(bspnum: c_int) bool {
    if (bspnum & c.NF_SUBSECTOR != 0) {
        return if (bspnum == -1)
            P_CrossSubsector(0)
        else
            P_CrossSubsector(@intCast(bspnum & ~c.NF_SUBSECTOR));
    }

    const bsp = &p_setup.nodes[@intCast(bspnum)];

    // decide which side the start point is on
    const dl: c.divline_t = .{ .x = bsp.x, .y = bsp.y, .dx = bsp.dx, .dy = bsp.dy };
    var side = P_DivlineSide(strace.x, strace.y, &dl);
    if (side == 2) {
        side = 0; // an "on" should cross both sides
    }

    // cross the starting side
    if (!P_CrossBSPNode(bsp.children[side])) {
        return false;
    }

    // the partition plane is crossed here
    if (side == P_DivlineSide(t2x, t2y, &dl)) {
        // the line doesn't touch the other side
        return true;
    }

    // cross the ending side
    return P_CrossBSPNode(bsp.children[side ^ 1]);
}

/// Returns true if a straight line between t1 and t2 is unobstructed.
/// Uses REJECT.
pub export fn P_CheckSight(t1: *MObj, t2: *MObj) c.boolean {
    // First check for trivial rejection.

    // Determine subsector entries in REJECT table.
    const s1 = t1.subsector.sector - p_setup.sectors;
    const s2 = t2.subsector.sector - p_setup.sectors;
    const pnum = s1 * p_setup.sectors_slice.len + s2;
    const bytenum = pnum >> 3;
    const bitnum = @as(u8, 1) << @intCast(pnum & 7);

    // Check in REJECT table.
    if (p_setup.rejectmatrix[bytenum] & bitnum != 0) {
        // can't possibly be connected
        return c.false;
    }

    // An unobstructed LOS is possible. Now look from eyes of t1 to any part
    // of t2.
    c.validcount += 1;

    sightzstart = t1.z + t1.height - (t1.height >> 2);
    topslope = t2.z + t2.height - sightzstart;
    bottomslope = t2.z - sightzstart;

    strace.x = t1.x;
    strace.y = t1.y;
    t2x = t2.x;
    t2y = t2.y;
    strace.dx = t2.x - t1.x;
    strace.dy = t2.y - t1.y;

    // the head node is the last node output
    return d_main.toDoomBoolean(P_CrossBSPNode(p_setup.numnodes - 1));
}
