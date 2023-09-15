// NOTE: This file hasn't been tested. The original code hadn't been tested either.
// It has only been translated more or less 1:1 and made to compile.

const c = @cImport({
    @cInclude("arpa/inet.h");
    @cInclude("netdb.h");
    @cInclude("doomstat.h");
    @cInclude("d_net.h");
});

const std = @import("std");
const mem = std.mem;
const os = std.os;

const I_Error = @import("i_system.zig").I_Error;
const m_argv = @import("m_argv.zig");
const M_CheckParm = @import("m_argv.zig").M_CheckParm;

//
// NETWORKING
//

// IPPORT_USERRESERVED + 0x1d
var DOOMPORT: u16 = 5000 + 0x1d;

var sendsocket: os.socket_t = undefined;
var insocket: os.socket_t = undefined;

var sendaddress: [c.MAXNETNODES]os.sockaddr.in = undefined;


//
// UDPsocket
//
fn UDPsocket() os.socket_t {
    // allocate a socket
    return os.socket(os.AF.INET, os.SOCK.DGRAM, os.IPPROTO.UDP) catch |err| {
        I_Error("can't create socket: %s", @errorName(err).ptr);
    };
}


//
// BindToLocalPort
//
fn BindToLocalPort(s: os.socket_t, port: u16) void {
    const address = os.sockaddr.in{
        .port = port,
        .addr = 0,
    };

    os.bind(s, @ptrCast(&address), address.len) catch |err| {
        I_Error("BindToPort: bind: %s", @errorName(err).ptr);
    };
}


extern var doomcom: *c.doomcom_t;
extern var netbuffer: *c.doomdata_t;

//
// PacketSend
//
fn PacketSend() void {
    var sw = c.doomdata_t{
        // byte swap
        .checksum = mem.nativeToBig(c_uint, netbuffer.checksum),
        .player = netbuffer.player,
        .retransmitfrom = netbuffer.retransmitfrom,
        .starttic = netbuffer.starttic,
        .numtics = netbuffer.numtics,
        .cmds = undefined,
    };

    for (0..netbuffer.numtics) |i| {
        sw.cmds[i] = netbuffer.cmds[i];
        sw.cmds[i].angleturn = mem.nativeToBig(c_short, sw.cmds[i].angleturn);
        sw.cmds[i].consistancy = mem.nativeToBig(c_short, sw.cmds[i].consistancy);
    }

    //std.debug.print("sending {}\n", .{gametic});
    _ = os.sendto(
        sendsocket,
        mem.asBytes(&sw)[0..@intCast(doomcom.datalength)],
        0,
        @ptrCast(&sendaddress[@intCast(doomcom.remotenode)]),
        sendaddress[@intCast(doomcom.remotenode)].len
    ) catch { // |err|
        // I_Error("SendPacket error: %s", @errorName(err).ptr);
    };
}


//
// PacketGet
//
fn PacketGet() void {
    var fromaddress = os.sockaddr.in{.port = 0, .addr = 0};
    var sl: os.socklen_t = @sizeOf(os.sockaddr.in);
    var sw: c.doomdata_t = undefined;

    const rc = os.recvfrom(
        insocket,
        mem.asBytes(&sw),
        0,
        @ptrCast(&fromaddress),
        &sl
    ) catch |err| {
        if (err != error.WouldBlock) {
            I_Error("GetPacket: %s", @errorName(err).ptr);
        }
        doomcom.remotenode = -1;               // no packet
        return;
    };

    const S = struct { var first = true; };
    if (S.first) {
        const stdout = std.io.getStdOut().writer();
        stdout.print("len={}:p=[0x{x} 0x{x}] \n", .{
            rc,
            mem.bytesAsValue(c_int, mem.asBytes(&sw)[0..4]).*,
            mem.bytesAsValue(c_int, mem.asBytes(&sw)[4..8]).*,
        }) catch unreachable;
        S.first = false;
    }

    // find remote node number
    for (0..@intCast(doomcom.numnodes)) |i| {
        if (fromaddress.addr == sendaddress[i].addr) {
            doomcom.remotenode = @intCast(i);   // good packet from a game player
            break;
        }
    } else {
        // packet is not from one of the players (new game broadcast)
        doomcom.remotenode = -1;                // no packet
        return;
    }

    doomcom.datalength = @intCast(rc);

    // byte swap
    netbuffer.checksum = mem.bigToNative(u32, sw.checksum);
    netbuffer.player = sw.player;
    netbuffer.retransmitfrom = sw.retransmitfrom;
    netbuffer.starttic = sw.starttic;
    netbuffer.numtics = sw.numtics;

    for (0..netbuffer.numtics) |i| {
        netbuffer.cmds[i] = sw.cmds[i];
        netbuffer.cmds[i].angleturn = mem.bigToNative(i16, sw.cmds[i].angleturn);
        netbuffer.cmds[i].consistancy = mem.bigToNative(i16, sw.cmds[i].consistancy);
    }
}


//
// I_InitNetwork
//
pub export fn I_InitNetwork() void {
    // struct hostent*     hostentry;      // host information entry

    doomcom = std.heap.raw_c_allocator.create(c.doomcom_t) catch unreachable;
    doomcom.* = std.mem.zeroes(c.doomcom_t);

    // set up for network
    var i = M_CheckParm("-dup");
    if (i != 0 and i < m_argv.myargc-1) {
        doomcom.ticdup = m_argv.myargv[@intCast(i+1)][0]-'0';
        if (doomcom.ticdup < 1) {
            doomcom.ticdup = 1;
        }
        if (doomcom.ticdup > 9) {
            doomcom.ticdup = 9;
        }
    } else {
        doomcom.ticdup = 1;
    }

    if (M_CheckParm("-extratic") != 0) {
        doomcom.extratics = 1;
    } else {
        doomcom.extratics = 0;
    }

    const p = M_CheckParm("-port");
    if (p != 0 and p < m_argv.myargc-1) {
        DOOMPORT = std.fmt.parseInt(u16, mem.span(m_argv.myargv[@intCast(p+1)]), 0) catch {
            I_Error("Couldn't parse value for -port: '%s'\n", m_argv.myargv[@intCast(p+1)]);
        };
        const stdout = std.io.getStdOut().writer();
        stdout.print("using alternate port {}\n", .{DOOMPORT}) catch unreachable;
    }

    // parse network game options,
    //  -net <consoleplayer> <host> <host> ...
    i = M_CheckParm("-net");
    if (i == 0) {
        // single player game
        c.netgame = c.false;
        doomcom.id = c.DOOMCOM_ID;
        doomcom.numplayers = 1;
        doomcom.numnodes = 1;
        doomcom.deathmatch = c.false;
        doomcom.consoleplayer = 0;
        return;
    }

    c.netgame = c.true;

    // parse player number and host list
    doomcom.consoleplayer = m_argv.myargv[@intCast(i+1)][0]-'1';

    doomcom.numnodes = 1;      // this node for sure

    i += 1;
    i += 1; // Not a typo, original C code had i++ before the loop and
            // ++i in the while condition expression
    while (i < m_argv.myargc and m_argv.myargv[@intCast(i)][0] != '-') : (i += 1) {
        sendaddress[@intCast(doomcom.numnodes)].family = os.AF.INET;
        sendaddress[@intCast(doomcom.numnodes)].port = mem.nativeToBig(u16, DOOMPORT);
        if (m_argv.myargv[@intCast(i)][0] == '.') {
            sendaddress[@intCast(doomcom.numnodes)].addr
                = c.inet_addr(m_argv.myargv[@intCast(i)]+1);
        } else {
            const hostentry = c.gethostbyname(m_argv.myargv[@intCast(i)]);
            if (hostentry == null) {
                I_Error("gethostbyname: couldn't find %s", m_argv.myargv[@intCast(i)]);
            }
            sendaddress[@intCast(doomcom.numnodes)].addr
                = mem.bytesAsValue(u32, hostentry[0].h_addr_list[0][0..4]).*;
        }
        doomcom.numnodes += 1;
    }

    doomcom.id = c.DOOMCOM_ID;
    doomcom.numplayers = doomcom.numnodes;

    // build message to receive
    var trueval = c.true;   // NOTE: CAREFUL! Doom's `true` is a c_uint whereas Zig's is a byte
    insocket = UDPsocket();
    BindToLocalPort(insocket, mem.nativeToBig(u16, DOOMPORT));
    // TODO: FIONBIO is apparently not standard across platforms so instead
    // it is recommended to use fnctl(..., O_NONBLOCK, ...) instead. Will it
    // work here if we do this following?
    // std.c.fcntl(insocket, std.os.O.NONBLOCK, &trueval);
    _ = std.c.ioctl(insocket, std.os.linux.T.FIONBIO, &trueval);

    sendsocket = UDPsocket();
}


pub export fn I_NetCmd() void {
    if (doomcom.command == c.CMD_SEND) {
        PacketSend();
    } else if (doomcom.command == c.CMD_GET) {
        PacketGet();
    } else {
        I_Error("Bad net cmd: %i\n", doomcom.command);
    }
}
