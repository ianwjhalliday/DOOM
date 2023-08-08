const c = @cImport({
    @cInclude("info.h");
    @cInclude("p_local.h");
    @cInclude("p_mobj.h");
    @cInclude("r_defs.h");
    @cInclude("r_state.h");
    @cInclude("s_sound.h");
    @cInclude("sounds.h");
});

const p_tick = @import("p_tick.zig");


//
// TELEPORTATION
//
pub export fn EV_Teleport(line: *c.line_t, side: c_int, thing: *c.mobj_t) c_int {

    // don't teleport missiles
    if (thing.flags & c.MF_MISSILE != 0) {
        return 0;
    }

    // Don't teleport if hit back of line,
    //  so you can get out of teleporter.
    if (side == 1) {
        return 0;
    }

    const tag = line.tag;
    for (0..@intCast(c.numsectors)) |i| {
        if (c.sectors[i].tag != tag) continue;

        var thinker = p_tick.thinkercap.next orelse &p_tick.thinkercap;
        while (thinker != &p_tick.thinkercap) : (thinker = thinker.next.?) {
            // not a mobj
            if (thinker.function.acp1 != @as(p_tick.actionf_p1, @ptrCast(&c.P_MobjThinker))) {
                continue;
            }

            const m = @as(*c.mobj_t, @ptrCast(thinker));

            // not a teleportman
            if (m.type != c.MT_TELEPORTMAN) continue;

            const sector = m.subsector.*.sector;

            // wrong sector
            if (sector != &c.sectors[i]) continue;

            const oldx = thing.x;
            const oldy = thing.y;
            const oldz = thing.z;

            if (c.P_TeleportMove(thing, m.x, m.y) == 0) {
                return 0;
            }

            thing.z = thing.floorz; // FIXME: not needed?

            if (thing.player != null) {
                thing.player.*.viewz = thing.z + thing.player.*.viewheight;
            }

            // spawn teleport fog at source and destination
            const fog1 = c.P_SpawnMobj(oldx, oldy, oldz, c.MT_TFOG);
            c.S_StartSound(fog1, c.sfx_telept);
            const an = m.angle >> c.ANGLETOFINESHIFT;
            const fog2 = c.P_SpawnMobj(m.x + 20 * c.finecosine[an], m.y + 20 * c.finesine[an], thing.z, c.MT_TFOG);

            // emit sound, where?
            c.S_StartSound(fog2, c.sfx_telept);

            // don't move for a bit
            if (thing.player != null) {
                thing.reactiontime = 18;
            }

            thing.angle = m.angle;
            thing.momx = 0;
            thing.momy = 0;
            thing.momz = 0;
            return 1;
        }
    }
    return 0;
}
