const c = @import("c");

const S_StartSound = @import("s_sound.zig").S_StartSound_Zig;
const p_map = @import("p_map.zig");
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const MF_MISSILE = p_mobj.MF_MISSILE;
const P_SpawnMobj = p_mobj.P_SpawnMobj;
const p_setup = @import("p_setup.zig");
pub const p_tick = @import("p_tick.zig");


//
// TELEPORTATION
//
pub fn EV_Teleport(line: *c.line_t, side: c_int, thing: *MObj) bool {

    // don't teleport missiles
    if (thing.flags & MF_MISSILE != 0) {
        return false;
    }

    // Don't teleport if hit back of line,
    //  so you can get out of teleporter.
    if (side == 1) {
        return false;
    }

    const tag = line.tag;
    for (0..@intCast(c.numsectors)) |i| {
        if (p_setup.sectors[i].tag != tag) continue;

        var it = p_tick.mobj_thinkers();
        while (it.next()) |m| {
            // not a teleportman
            if (m.type != c.MT_TELEPORTMAN) continue;

            const sector = m.subsector.*.sector;

            // wrong sector
            if (sector != &p_setup.sectors[i]) continue;

            const oldx = thing.x;
            const oldy = thing.y;
            const oldz = thing.z;

            if (!p_map.P_TeleportMove(thing, m.x, m.y)) {
                return false;
            }

            thing.z = thing.floorz; // FIXME: not needed?

            if (thing.player != null) {
                thing.player.?.viewz = thing.z + thing.player.?.viewheight;
            }

            // spawn teleport fog at source and destination
            const fog1 = P_SpawnMobj(oldx, oldy, oldz, c.MT_TFOG);
            S_StartSound(fog1, .telept);
            const an = m.angle >> c.ANGLETOFINESHIFT;
            const fog2 = P_SpawnMobj(m.x + 20 * c.finecosine[an], m.y + 20 * c.finesine[an], thing.z, c.MT_TFOG);

            // emit sound, where?
            S_StartSound(fog2, .telept);

            // don't move for a bit
            if (thing.player != null) {
                thing.reactiontime = 18;
            }

            thing.angle = m.angle;
            thing.momx = 0;
            thing.momy = 0;
            thing.momz = 0;
            return true;
        }
    }
    return false;
}
