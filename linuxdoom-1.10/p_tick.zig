const c = @import("c");

const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const p_spec = @import("p_spec.zig");
const p_user = @import("p_user.zig");

const g_game = @import("g_game.zig");
const m_menu = @import("m_menu.zig");
const z_zone = @import("z_zone.zig");

pub export var leveltime: c_int = 0;

//
// THINKERS
// All thinkers should be allocated by Z_Malloc
// so they can be operated on uniformly.
// The actual structures will vary in size,
// but the first element must be Thinker.
//


pub const actionf_v = *const fn (...) callconv(.c) void;
pub const actionf_p1 = *const fn (*anyopaque) callconv(.c) void;
pub const actionf_p2 = *const fn (*anyopaque, *anyopaque) callconv(.c) void;

/// The think function pointer P_RunThinkers will call with the thinker
/// pointer. Taking `f` as a C-convention `*T` function makes a wrong
/// signature or calling convention a compile error, which @ptrCast hides.
pub fn thinkFn(comptime T: type, f: *const fn (*T) callconv(.c) void) actionf_p1 {
    return @ptrCast(f);
}

pub const ActionFn = extern union {
    acp1: ?actionf_p1,
    acv: ?actionf_v,
    acp2: ?actionf_p2,
};

// Doubly linked list of actors.
pub const Thinker = extern struct {
    prev: ?*Thinker,
    next: ?*Thinker,
    function: ActionFn,
};


// Both the head and tail of the thinker list.
pub export var thinkercap = Thinker{
    .next = null,
    .prev = null,
    .function = ActionFn{.acv = null},
};

/// Iterates live and pending-removal thinkers. `next` is read before the
/// current thinker is returned, so the caller may free it. A thinker added
/// while on the last one is not visited, which differs from vanilla's
/// loops. P_RunThinkers depends on that difference, so it stays hand-written.
pub const ThinkerIterator = struct {
    cur: *Thinker,

    pub fn next(it: *ThinkerIterator) ?*Thinker {
        const th = it.cur;
        if (th == &thinkercap) return null;
        it.cur = th.next.?;
        return th;
    }
};

pub fn thinkers() ThinkerIterator {
    return .{ .cur = thinkercap.next orelse &thinkercap };
}

pub const MObjThinkerIterator = struct {
    inner: ThinkerIterator,

    pub fn next(it: *MObjThinkerIterator) ?*MObj {
        while (it.inner.next()) |th| {
            if (th.function.acp1 == p_mobj.mobj_thinker) return @ptrCast(th);
        }
        return null;
    }
};

pub fn mobj_thinkers() MObjThinkerIterator {
    return .{ .inner = thinkers() };
}


//
// P_InitThinkers
//
pub export fn P_InitThinkers() void {
    thinkercap.prev = &thinkercap;
    thinkercap.next = &thinkercap;
}


//
// P_AddThinker
// Adds a new thinker at the end of the list.
//
pub export fn P_AddThinker(thinker: *Thinker) void {
    thinkercap.prev.?.next = thinker;
    thinker.next = &thinkercap;
    thinker.prev = thinkercap.prev;
    thinkercap.prev = thinker;
}


//
// P_RemoveThinker
// Deallocation is lazy -- it will not actually be freed
// until its thinking turn comes up.
//
fn removeThinkerSentinel(...) callconv(.c) void {}
pub export fn P_RemoveThinker(thinker: *Thinker) void {
    thinker.function.acv = &removeThinkerSentinel;
}

pub fn isRemoved(thinker: *const Thinker) bool {
    return thinker.function.acv == &removeThinkerSentinel;
}

//
// P_RunThinkers
//
fn P_RunThinkers() void {
    var currentthinker = thinkercap.next orelse &thinkercap;
    while (currentthinker != &thinkercap) {
        if (isRemoved(currentthinker)) {
            // time to remove it
            const next = currentthinker.next.?;
            currentthinker.next.?.prev = currentthinker.prev;
            currentthinker.prev.?.next = currentthinker.next;
            z_zone.destroy(currentthinker);
            currentthinker = next;
        } else {
            if (currentthinker.function.acp1) |think| think(currentthinker);
            currentthinker = currentthinker.next.?;
        }
    }
}


//
// P_Ticker
//
// Called by C_Ticker,
// can call G_PlayerExited.
// Carries out all thinking of monsters and players.
//
pub fn P_Ticker() void {
    // run the tic
    if (g_game.paused) {
        return;
    }

    // pause if in menu and at least one tic has been run
    if (g_game.netgame == c.false
        and m_menu.menuactive
        and g_game.demoplayback == c.false
        and g_game.players[g_game.consoleplayer].viewz != 1) {
        return;
    }

    for (&g_game.players, 0..) |*player, i| {
        if (c.playeringame[i] != c.false) {
            p_user.P_PlayerThink(player);
        }
    }

    P_RunThinkers();
    p_spec.P_UpdateSpecials();
    p_mobj.P_RespawnSpecials();

    // for par times
    leveltime += 1;
}
