const c = @cImport({
    @cInclude("doomstat.h");
});

extern fn P_UpdateSpecials() void;
extern fn P_RespawnSpecials() void;

const player_t = @import("p_user.zig").player_t;
const P_PlayerThink = @import("p_user.zig").P_PlayerThink;
const MAXPLAYERS = @import("doomdef.zig").MAXPLAYERS;

const g_game = @import("g_game.zig");
const m_menu = @import("m_menu.zig");

// TODO: import free from z_zone
extern fn Z_Free(ptr: *anyopaque) void;

export var leveltime: c_int = 0;

//
// THINKERS
// All thinkers should be allocated by Z_Malloc
// so they can be operated on uniformly.
// The actual structures will vary in size,
// but the first element must be Thinker.
//


pub const actionf_v = *const fn (...) callconv(.C) void;
pub const actionf_p1 = *const fn (*anyopaque) callconv(.C) void;
pub const actionf_p2 = *const fn (*anyopaque, *anyopaque) callconv(.C) void;

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
fn removeThinkerSentinel(...) callconv(.C) void {}
pub export fn P_RemoveThinker(thinker: *Thinker) void {
    // FIXME: NOP.
    thinker.function.acv = &removeThinkerSentinel;
}


//
// P_RunThinkers
//
fn P_RunThinkers() void {
    var currentthinker = thinkercap.next orelse &thinkercap;
    while (currentthinker != &thinkercap) {
        if (currentthinker.function.acv == &removeThinkerSentinel) {
            // time to remove it
            currentthinker.next.?.prev = currentthinker.prev;
            currentthinker.prev.?.next = currentthinker.next;
            Z_Free(currentthinker);
        } else {
            if (currentthinker.function.acp1 != null) {
                currentthinker.function.acp1.?(currentthinker);
            }
        }
        currentthinker = currentthinker.next.?;
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
            P_PlayerThink(player);
        }
    }

    P_RunThinkers();
    P_UpdateSpecials();
    P_RespawnSpecials();

    // for par times
    leveltime += 1;
}
