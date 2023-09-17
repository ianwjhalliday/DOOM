const c = @cImport({
    @cInclude("doomtype.h");
    @cInclude("d_event.h");
});

const std = @import("std");
const cWriter = std.io.cWriter;

const TicCmd = @import("d_ticcmd.zig").TicCmd;

const i_net = @import("i_net.zig");
const I_NetCmd = i_net.I_NetCmd;
const I_InitNetwork = i_net.I_InitNetwork;

const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const I_GetTime = i_system.I_GetTime;
const I_WaitVBL = i_system.I_WaitVBL;

const i_video = @import("i_video.zig");
const I_StartTic = i_video.I_StartTic;

const doomdef = @import("doomdef.zig");
const MAXPLAYERS = doomdef.MAXPLAYERS;
const KEY_ESCAPE = doomdef.KEY_ESCAPE;
const VERSION = doomdef.VERSION;

const d_main = @import("d_main.zig");
const D_DoAdvanceDemo = d_main.D_DoAdvanceDemo;
const D_ProcessEvents = d_main.D_ProcessEvents;

const g_game = @import("g_game.zig");
const G_BuildTiccmd = g_game.G_BuildTiccmd;
const G_CheckDemoStatus = g_game.G_CheckDemoStatus;
const G_Ticker = g_game.G_Ticker;

//
// Network play related stuff.
// There is a data struct that stores network
//  communication related stuff, and another
//  one that defines the actual packets to
//  be transmitted.
//

pub const DOOMCOM_ID: c_long = 0x12345678;

// Max computers/players in a game.
pub const MAXNETNODES = 8;

// Networking and tick handling related.
pub const BACKUPTICS = 12;

pub const CMD_SEND = 1;
pub const CMD_GET = 2;

//
// Network packet data.
//
pub const DoomData = extern struct {
    // High bit is retransmit request.
    checksum: c_uint,
    // Only valid if NCMD_RETRANSMIT.
    retransmitfrom: u8,

    starttic: u8,
    player: u8,
    numtics: u8,
    cmds: [BACKUPTICS]TicCmd,
};

pub const DoomCom = extern struct {
    // Supposed to be DOOMCOM_ID?
    id: c_long,

    // DOOM executes an int to execute commands.
    intnum: c_short,
    // Communication between DOOM and the driver.
    // Is CMD_SEND or CMD_GET.
    command: c_short,
    // Is dest for send, set by get (-1 = no packet).
    remotenode: c_short,

    // Number of bytes in doomdata to be sent
    datalength: c_short,

    // Info common to all nodes.
    // Console is allways node 0.
    numnodes: c_short,
    // Flag: 1 = no duplication, 2-5 = dup for slow nets.
    ticdup: c_short,
    // Flag: 1 = send a backup tic in every packet.
    extratics: c_short,
    // Flag: 1 = deathmatch.
    deathmatch: c_short,
    // Flag: -1 = new game, 0-5 = load savegame
    savegame: c_short,
    episode: c_short, // 1-3
    map: c_short, // 1-9
    skill: c_short, // 1-5

    // Info specific to this node.
    consoleplayer: c_short,
    numplayers: c_short,

    // These are related to the 3-display mode,
    //  in which two drones looking left and right
    //  were used to render two additional views
    //  on two additional computers.
    // Probably not operational anymore.
    // 1 = left, 0 = center, -1 = right
    angleoffset: c_short,
    // 1 = drone
    drone: c_short,

    // The packet data to be sent.
    data: DoomData,
};

const NCMD_EXIT = 0x80000000;
const NCMD_RETRANSMIT = 0x40000000;
const NCMD_SETUP = 0x20000000;
const NCMD_KILL = 0x10000000; // kill game
const NCMD_CHECKSUM = 0x0fffffff;

pub var doomcom: *DoomCom = undefined;
pub var netbuffer: *DoomData = undefined;

//
// NETWORKING
//
// gametic is the tic about to (or currently being) run
// maketic is the tick that hasn't had control made for it yet
// nettics[] has the maketics for all players
//
// a gametic cannot be run until nettics[] > gametic for all players
//
const RESENDCOUNT = 10;
const PL_DRONE = 0x80; // bit flag in doomdata.player

var localcmds: [BACKUPTICS]TicCmd = undefined;

pub var netcmds: [MAXPLAYERS][BACKUPTICS]TicCmd = undefined;
var nettics: [MAXNETNODES]c_int = undefined;
var nodeingame: [MAXNETNODES]bool = undefined; // set false as nodes leave game
var remoteresend: [MAXNETNODES]bool = undefined; // set when local needs tics
var resendto: [MAXNETNODES]c_int = undefined; // set when remote needs tics
var resendcount: [MAXNETNODES]c_int = undefined;

var nodeforplayer: [MAXPLAYERS]c_int = undefined;

pub var maketic: c_int = undefined;
var lastnettic: c_int = undefined;
var skiptics: c_int = undefined;
pub var ticdup: c_int = undefined;
var maxsend: c_int = undefined; // BACKUPTICS/(2*ticdup)-1

var reboundpacket: bool = undefined;
var reboundstore: DoomData = undefined;

//
//
//
fn NetbufferSize() usize {
    const assert = std.debug.assert;

    const maxsize = @sizeOf(DoomData);
    const cmdsoffset = @offsetOf(DoomData, "cmds");
    comptime {
        assert(@divTrunc(maxsize - cmdsoffset, @sizeOf(TicCmd)) == BACKUPTICS);
    }

    assert(netbuffer.numtics <= BACKUPTICS);
    return cmdsoffset + @sizeOf(TicCmd) * netbuffer.numtics;
}

//
// Checksum
//
fn NetbufferChecksum() c_uint {
    // unsigned         c;
    // int              i,l;

    // c = 0x1234567;

    // FIXME -endianess?
    // #ifdef NORMALUNIX
    // TODO: Looks like this func was not implemented in original open source
    // release. Is it required?
    return 0; // byte order problems
    // #endif

    // l = (NetbufferSize () - (intptr_t)&(((doomdata_t *)0).retransmitfrom))/4;
    // for (i=0 ; i<l ; i++)
    // c += ((unsigned *)&netbuffer.retransmitfrom)[i] * (i+1);

    // return c & NCMD_CHECKSUM;
}

//
//
//
fn ExpandTics(low: c_int) c_int {
    const lowbytemask: c_int = 0xff;
    const delta = low - (maketic & lowbytemask);

    if (delta >= -64 and delta <= 64) {
        return (maketic & ~lowbytemask) + low;
    }

    if (delta > 64) {
        return (maketic & ~lowbytemask) - 256 + low;
    }

    if (delta < -64) {
        return (maketic & ~lowbytemask) + 256 + low;
    }

    I_Error("ExpandTics: strange value %i at maketic %i", low, maketic);
    return 0;
}

//
// HSendPacket
//
fn HSendPacket(node: usize, flags: c_uint) void {
    netbuffer.checksum = NetbufferChecksum() | flags;

    if (node == 0) {
        reboundstore = netbuffer.*;
        reboundpacket = true;
        return;
    }

    if (g_game.demoplayback != c.false) {
        return;
    }

    if (g_game.netgame == c.false) {
        I_Error("Tried to transmit to another node");
    }

    doomcom.command = CMD_SEND;
    doomcom.remotenode = @intCast(node);
    doomcom.datalength = @intCast(NetbufferSize());

    if (d_main.debugfile != null) {
        const realretrans =
            if (netbuffer.checksum & NCMD_RETRANSMIT != 0)
            ExpandTics(netbuffer.retransmitfrom)
        else
            -1;

        const w = cWriter(d_main.debugfile.?);
        w.print("send ({} + {}, R {}) [{}] ", .{
            ExpandTics(netbuffer.starttic),
            netbuffer.numtics,
            realretrans,
            doomcom.datalength,
        }) catch unreachable;

        const nbbytes = std.mem.asBytes(netbuffer);
        for (0..@intCast(doomcom.datalength)) |i| {
            w.print("{} ", .{nbbytes[i]}) catch unreachable;
        }

        w.print("\n", .{}) catch unreachable;
    }

    I_NetCmd();
}

//
// HGetPacket
// Returns false if no packet is waiting
//
fn HGetPacket() bool {
    if (reboundpacket) {
        netbuffer.* = reboundstore;
        doomcom.remotenode = 0;
        reboundpacket = false;
        return true;
    }

    if (g_game.netgame == c.false) {
        return false;
    }

    if (g_game.demoplayback != c.false) {
        return false;
    }

    doomcom.command = CMD_GET;
    I_NetCmd();

    if (doomcom.remotenode == -1) {
        return false;
    }

    if (doomcom.datalength != @as(c_short, @intCast(NetbufferSize()))) {
        if (d_main.debugfile != null) {
            const w = cWriter(d_main.debugfile.?);
            w.print("bad packet length {}\n", .{doomcom.datalength}) catch unreachable;
        }
        return false;
    }

    if (NetbufferChecksum() != (netbuffer.checksum & NCMD_CHECKSUM)) {
        if (d_main.debugfile != null) {
            const w = cWriter(d_main.debugfile.?);
            w.print("bad packet checksum\n", .{}) catch unreachable;
        }
        return false;
    }

    if (d_main.debugfile != null) {
        const w = cWriter(d_main.debugfile.?);

        if (netbuffer.checksum & NCMD_SETUP != 0) {
            w.print("setup packet\n", .{}) catch unreachable;
        } else {
            const realretrans =
                if (netbuffer.checksum & NCMD_RETRANSMIT != 0)
                ExpandTics(netbuffer.retransmitfrom)
            else
                -1;

            w.print("get {} = ({} + {}, R {})[{}] ", .{ doomcom.remotenode, ExpandTics(netbuffer.starttic), netbuffer.numtics, realretrans, doomcom.datalength }) catch unreachable;

            const nbbytes = std.mem.asBytes(netbuffer);
            for (0..@intCast(doomcom.datalength)) |i| {
                w.print("{} ", .{nbbytes[i]}) catch unreachable;
            }
            w.print("\n", .{}) catch unreachable;
        }
    }
    return true;
}


//
// GetPackets
//
// char    exitmsg[80];

fn GetPackets() void {
    while (HGetPacket()) {
        if (netbuffer.checksum & NCMD_SETUP != 0) {
            continue;           // extra setup packet
        }

        const netconsole = netbuffer.player & ~@as(u8, PL_DRONE);
        const netnode = doomcom.remotenode;

        // to save bytes, only the low byte of tic numbers are sent
        // Figure out what the rest of the bytes are
        const realstart = ExpandTics(netbuffer.starttic);
        const realend = realstart + netbuffer.numtics;

        // check for exiting the game
        if (netbuffer.checksum & NCMD_EXIT != 0) {
            if (!nodeingame[@intCast(netnode)]) {
                continue;
            }

            nodeingame[@intCast(netnode)] = false;
            g_game.playeringame[netconsole] = c.false;

            const S = struct {
                var exitmsg: [79:0]u8 = undefined;
            };
            _ = std.fmt.bufPrintZ(&S.exitmsg, "Player {} left the game", .{1 + netconsole}) catch unreachable;
            g_game.players[g_game.consoleplayer].message = &S.exitmsg;

            if (g_game.demorecording) {
                _ = G_CheckDemoStatus();
            }
            continue;
        }

        // check for a remote game kill
        if (netbuffer.checksum & NCMD_KILL != 0) {
            I_Error("Killed by network driver");
        }

        nodeforplayer[netconsole] = netnode;

        // check for retransmit request
        if (resendcount[@intCast(netnode)] <= 0
            and netbuffer.checksum & NCMD_RETRANSMIT != 0) {
            resendto[@intCast(netnode)] = ExpandTics(netbuffer.retransmitfrom);
            if (d_main.debugfile != null) {
                const w = cWriter(d_main.debugfile.?);
                w.print("retransmit from {}\n", .{resendto[@intCast(netnode)]}) catch unreachable;
            }
            resendcount[@intCast(netnode)] = RESENDCOUNT;
        } else {
            resendcount[@intCast(netnode)] -= 1;
        }

        // check for out of order / duplicated packet
        if (realend == nettics[@intCast(netnode)]) {
            continue;
        }

        if (realend < nettics[@intCast(netnode)]) {
            if (d_main.debugfile != null) {
                const w = cWriter(d_main.debugfile.?);
                w.print("out of order packet ({} + {})\n", .{
                    realstart,
                    netbuffer.numtics,
                }) catch unreachable;
            }
            continue;
        }

        // check for a missed packet
        if (realstart > nettics[@intCast(netnode)]) {
            // stop processing until the other system resends the missed tics
            if (d_main.debugfile != null) {
                const w = cWriter(d_main.debugfile.?);
                w.print("missed tics from {} ({} - {})\n", .{
                    netnode,
                    realstart,
                    nettics[@intCast(netnode)],
                }) catch unreachable;
            }
            remoteresend[@intCast(netnode)] = true;
            continue;
        }

        // update command store from the packet
        remoteresend[@intCast(netnode)] = false;

        const start = nettics[@intCast(netnode)] - realstart;

        for (@intCast(nettics[@intCast(netnode)])..@intCast(realend), @intCast(start)..) |idst, isrc| {
            netcmds[netconsole][idst % BACKUPTICS] = netbuffer.cmds[isrc];
        }
        nettics[@intCast(netnode)] = realend;
    }
}


//
// NetUpdate
// Builds ticcmds for console player,
// sends out a packet
//
var gametime: c_int = undefined;

pub export fn NetUpdate() void {
    // check time
    const nowtime = @divTrunc(I_GetTime(), ticdup);
    var newtics = nowtime - gametime;
    gametime = nowtime;

    if (newtics <= 0) {
        // nothing new to update
        // listen for other packets
        GetPackets();
        return;
    }

    if (skiptics <= newtics) {
        newtics -= skiptics;
        skiptics = 0;
    } else {
        skiptics -= newtics;
        newtics = 0;
    }


    netbuffer.player = @intCast(g_game.consoleplayer);

    // build new ticcmds for console player
    const gameticdiv = @divTrunc(g_game.gametic, ticdup);
    for (0..@intCast(newtics)) |_| {
        I_StartTic();
        D_ProcessEvents();
        if (maketic - gameticdiv >= BACKUPTICS/2-1) {
            break;          // can't hold any more
        }

        //std.debug.print("mk:{} ", .{maketic});
        G_BuildTiccmd(&localcmds[@intCast(@mod(maketic, BACKUPTICS))]);
        maketic += 1;
    }


    if (d_main.singletics) {
        return;         // singletic update is syncronous
    }

    // send the packet to the other nodes
    for (0..@intCast(doomcom.numnodes)) |i| {
        if (nodeingame[i]) {
            const realstart = resendto[i];
            netbuffer.starttic = @truncate(@as(usize, @intCast(realstart)));
            netbuffer.numtics = @intCast(maketic - realstart);
            if (netbuffer.numtics > BACKUPTICS) {
                I_Error("NetUpdate: netbuffer.numtics > BACKUPTICS");
            }

            resendto[i] = maketic - doomcom.extratics;

            for (0..netbuffer.numtics) |j| {
                netbuffer.cmds[j] =
                    localcmds[(@as(usize, @intCast(realstart)) + j) % BACKUPTICS];
            }

            if (remoteresend[i]) {
                netbuffer.retransmitfrom = @intCast(nettics[i]);
                HSendPacket(i, NCMD_RETRANSMIT);
            } else {
                netbuffer.retransmitfrom = 0;
                HSendPacket(i, 0);
            }
        }
    }

    // listen for other packets
    GetPackets();
}



//
// CheckAbort
//
fn CheckAbort() void {
    const stoptic = I_GetTime() + 2;
    while (I_GetTime() < stoptic) {
        I_StartTic();
    }

    I_StartTic();
    while (d_main.eventtail != d_main.eventhead)
        : (d_main.eventtail = (1 + d_main.eventtail) & (c.MAXEVENTS-1)) {
        const ev = &d_main.events[d_main.eventtail];
        if (ev.type == .KeyDown and ev.data1 == KEY_ESCAPE) {
            I_Error("Network game synchronization aborted.");
        }
    }
}


//
// D_ArbitrateNetStart
//
fn D_ArbitrateNetStart() void {
    var gotinfo = [_]bool{false} ** MAXNETNODES;
    d_main.autostart = true;

    const stdout = std.io.getStdOut().writer();
    if (doomcom.consoleplayer != 0) {
        // listen for setup info from key player
        stdout.print("listening for network start info...\n", .{}) catch unreachable;
        while (true) {
            CheckAbort();
            if (!HGetPacket()) {
                continue;
            }

            if (netbuffer.checksum & NCMD_SETUP != 0) {
                if (netbuffer.player != VERSION) {
                    I_Error("Different DOOM versions cannot play a net game!");
                }
                d_main.startskill = @enumFromInt(netbuffer.retransmitfrom & 15);
                g_game.deathmatch = (netbuffer.retransmitfrom & 0xc0) >> 6;
                d_main.nomonsters = d_main.toDoomBoolean(netbuffer.retransmitfrom & 0x20 > 0);
                d_main.respawnparm = netbuffer.retransmitfrom & 0x10 > 0;
                d_main.startmap = netbuffer.starttic & 0x3f;
                d_main.startepisode = netbuffer.starttic >> 6;
                return;
            }
        }
    } else {
        // key player, send the setup info
        stdout.print("sending network start info...\n", .{}) catch unreachable;

        var i: usize = 0;
        while (i < doomcom.numnodes) {
            CheckAbort();
            i = 0;
            while (i < doomcom.numnodes) : (i += 1) {
                netbuffer.retransmitfrom = @intCast(@intFromEnum(d_main.startskill));
                if (g_game.deathmatch != 0) {
                    netbuffer.retransmitfrom |= @intCast(g_game.deathmatch<<6);
                }
                if (d_main.nomonsters != c.false) {
                    netbuffer.retransmitfrom |= 0x20;
                }
                if (d_main.respawnparm) {
                    netbuffer.retransmitfrom |= 0x10;
                }
                netbuffer.starttic = @truncate(@as(usize, @intCast(d_main.startepisode * 64 + d_main.startmap)));
                netbuffer.player = VERSION;
                netbuffer.numtics = 0;
                HSendPacket(i, NCMD_SETUP);
            }

// #if 1
            i = 10;
            while (i > 0 and HGetPacket()) : (i -= 1) {
                if (netbuffer.player & 0x7f < MAXNETNODES) {
                    gotinfo[netbuffer.player & 0x7f] = true;
                }
            }
// #else
//             while (HGetPacket()) {
//                 gotinfo[netbuffer.player & 0x7f] = true;
//             }
// #endif

            i = 1;
            while (i < doomcom.numnodes) : (i += 1) {
                if (!gotinfo[i]) {
                    break;
                }
            }
        }
    }
}

//
// D_CheckNetGame
// Works out player numbers among the net participants
//
extern var viewangleoffset: c_int;

pub fn D_CheckNetGame() void {
    for (0..MAXNETNODES) |i| {
        nodeingame[i] = false;
        nettics[i] = 0;
        remoteresend[i] = false;        // set when local needs tics
        resendto[i] = 0;                // which tic to start sending
    }

    // I_InitNetwork sets doomcom and netgame
    I_InitNetwork();
    if (doomcom.id != DOOMCOM_ID) {
        I_Error("Doomcom buffer invalid!");
    }

    netbuffer = &doomcom.data;
    g_game.consoleplayer = @intCast(doomcom.consoleplayer);
    g_game.displayplayer = @intCast(doomcom.consoleplayer);

    if (g_game.netgame != c.false) {
        D_ArbitrateNetStart();
    }

    const stdout = std.io.getStdOut().writer();
    stdout.print("startskill {}  deathmatch: {}  startmap: {}  startepisode: {}\n", .{
        @intFromEnum(d_main.startskill),
        g_game.deathmatch,
        d_main.startmap,
        d_main.startepisode,
    }) catch unreachable;

    // read values out of doomcom
    ticdup = doomcom.ticdup;
    maxsend = @divTrunc(BACKUPTICS, 2 * ticdup) - 1;
    if (maxsend < 1) {
        maxsend = 1;
    }

    for (0..@intCast(doomcom.numplayers)) |i| {
        g_game.playeringame[i] = c.true;
    }

    for (0..@intCast(doomcom.numnodes)) |i| {
        nodeingame[i] = true;
    }

    stdout.print("player {} of {} ({} nodes)\n", .{
        g_game.consoleplayer + 1,
        doomcom.numplayers,
        doomcom.numnodes,
    }) catch unreachable;
}


//
// D_QuitNetGame
// Called before quitting to leave a net game
// without hanging the other players
//
pub fn D_QuitNetGame() void {
    if (d_main.debugfile != null) {
        _ = std.c.fclose(d_main.debugfile.?);
    }

    if (g_game.netgame == c.false
        or g_game.usergame == c.false
        // or g_game.consoleplayer == -1  // TODO: Bug? Is is possible for consoleplayer to be set to -1?
        or g_game.demoplayback != c.false) {
        return;
    }

    // send a bunch of packets for security
    netbuffer.player = @intCast(g_game.consoleplayer);
    netbuffer.numtics = 0;

    for (0..4) |i| {
        _ = i;
        for (1..@intCast(doomcom.numnodes)) |j| {
            if (nodeingame[j]) {
                HSendPacket(j, NCMD_EXIT);
            }
        }
        I_WaitVBL(1);
    }
}



//
// TryRunTics
//
var frameon: c_int = undefined;
var frameskip = [_]bool{false} ** 4;
var oldnettics: c_int = undefined;

extern fn M_Ticker() void;

pub fn TryRunTics() void {
    const S = struct {
        var oldentertics: c_int = 0;
    };

    // get real tics
    const entertic = @divTrunc(I_GetTime(), ticdup);
    const realtics = entertic - S.oldentertics;
    S.oldentertics = entertic;

    // get available tics
    NetUpdate();

    var lowtic: c_int = std.math.maxInt(c_int);
    for (0..@intCast(doomcom.numnodes)) |i| {
        if (nodeingame[i] and nettics[i] < lowtic) {
            lowtic = nettics[i];
        }
    }
    const availabletics = lowtic - @divTrunc(g_game.gametic, ticdup);

    // decide how many tics to run
    var counts =
        if (realtics < availabletics-1)
            realtics + 1
        else if (realtics < availabletics)
            realtics
        else
            availabletics;

    if (counts < 1) {
        counts = 1;
    }

    frameon += 1;

    if (d_main.debugfile != null) {
        const w = cWriter(d_main.debugfile.?);
        w.print("=======real: {}  avail: {}  game: {}\n", .{
            realtics, availabletics, counts
        }) catch unreachable;
    }

    if (g_game.demoplayback == c.false) {
        // ideally nettics[0] should be 1 - 3 tics above lowtic
        // if we are consistantly slower, speed up time
        var i: usize = 0;
        while (i < MAXPLAYERS) : (i += 1) {
            if (g_game.playeringame[i] != c.false) {
                break;
            }
        }
        if (g_game.consoleplayer == i)
        {
            // the key player does not adapt
        } else {
            if (nettics[0] <= nettics[@intCast(nodeforplayer[i])]) {
                gametime -= 1;
                // std.debug.print("-", .{});
            }
            frameskip[@intCast(frameon & 3)] = oldnettics > nettics[@intCast(nodeforplayer[i])];
            oldnettics = nettics[0];
            if (frameskip[0] and frameskip[1] and frameskip[2] and frameskip[3]) {
                skiptics = 1;
                // std.debug.print("+", {});
            }
        }
    }

    // wait for new tics if needed
    while (lowtic < @divTrunc(g_game.gametic, ticdup) + counts)
    {
        NetUpdate();
        lowtic = std.math.maxInt(c_int);

        for (0..@intCast(doomcom.numnodes)) |i| {
            if (nodeingame[i] and nettics[i] < lowtic) {
                lowtic = nettics[i];
            }
        }

        if (lowtic < @divTrunc(g_game.gametic, ticdup)) {
            I_Error("TryRunTics: lowtic < gametic");
        }

        // don't stay in here forever -- give the menu a chance to work
        if (@divTrunc(I_GetTime(), ticdup) - entertic >= 20) {
            M_Ticker();
            return;
        }
    }

    // run the count * ticdup dics
    while (counts > 0) : (counts -= 1) {
        for (0..@intCast(ticdup)) |i| {
            if (@divTrunc(g_game.gametic, ticdup) > lowtic) {
                I_Error("gametic>lowtic");
            }

            if (d_main.advancedemo) {
                D_DoAdvanceDemo();
            }

            M_Ticker();
            G_Ticker();
            g_game.gametic += 1;

            // modify command for duplicated tics
            if (i != ticdup-1) {
                const buf = @mod(@divTrunc(g_game.gametic, ticdup), BACKUPTICS);
                for (0..MAXPLAYERS) |j| {
                    const cmd = &netcmds[j][@intCast(buf)];
                    cmd.chatchar = 0;
                    if (cmd.buttons & c.BT_SPECIAL != 0) {
                        cmd.buttons = 0;
                    }
                }
            }
        }

        NetUpdate();    // check for new console commands
    }
}
