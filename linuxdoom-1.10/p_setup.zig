pub const c = @cImport({
    @cInclude("doomdata.h");
    @cInclude("info.h");
    @cInclude("r_data.h");
    @cInclude("r_defs.h");
    @cInclude("r_things.h");
    @cInclude("p_local.h");
    @cInclude("p_mobj.h");
    @cInclude("p_spec.h");
    @cInclude("m_bbox.h");
    @cInclude("tables.h");
});

const std = @import("std");

const d_main = @import("d_main.zig");
const doomdef = @import("doomdef.zig");
const MAXPLAYERS = doomdef.MAXPLAYERS;
const Skill = doomdef.Skill;
const doomstat = @import("doomstat.zig");
const m_fixed = @import("m_fixed.zig");
const fixed_t = m_fixed.fixed_t;
const FixedDiv = m_fixed.FixedDiv;
const FRACBITS = m_fixed.FRACBITS;
const g_game = @import("g_game.zig");
const G_DeathMatchSpawnPlayer = g_game.G_DeathMatchSpawnPlayer;
const i_system = @import("i_system.zig");
const I_Error = i_system.I_Error;
const m_swap = @import("m_swap.zig");
const SHORT = m_swap.SHORT;
const USHORT = m_swap.USHORT;
const p_mobj = @import("p_mobj.zig");
const MObj = p_mobj.MObj;
const P_SpawnMapThing = p_mobj.P_SpawnMapThing;
const p_tick = @import("p_tick.zig");
const P_InitThinkers = p_tick.P_InitThinkers;
const s_sound = @import("s_sound.zig");
const S_Start = s_sound.S_Start;
const w_wad = @import("w_wad.zig");
const W_CacheLumpNum = w_wad.W_CacheLumpNumZig;
const W_GetNumForName = w_wad.W_GetNumForName;
const W_LumpLength = w_wad.W_LumpLengthZig;
const W_Reload = w_wad.W_Reload;
const z_zone = @import("z_zone.zig");



//
// MAP related Lookup tables.
// Store VERTEXES, LINEDEFS, SIDEDEFS, etc.
//
pub var vertexes: []c.vertex_t = undefined;

var segs_slice: []c.seg_t = undefined;
export var segs: [*]c.seg_t = undefined;

export var numsectors: c_int = undefined;
export var sectors: [*]c.sector_t = undefined;
var sectors_slice: []c.sector_t = undefined;

export var numsubsectors: c_int = undefined;
export var subsectors: [*]c.subsector_t = undefined;
var subsectors_slice: []c.subsector_t = undefined;

export var numnodes: c_int = undefined;
export var nodes: [*]c.node_t = undefined;
var nodes_slice: []c.node_t = undefined;

export var numlines: c_int = undefined;
export var lines: [*]c.line_t = undefined;
var lines_slice: []c.line_t = undefined;

export var numsides: c_int = undefined;
export var sides: [*]c.side_t = undefined;
var sides_slice: []c.side_t = undefined;


// BLOCKMAP
// Created from axis aligned bounding box
// of the map, a rectangular array of
// blocks of size ...
// Used to speed up collision detection
// by spatial subdivision in 2D.
//
// Blockmap size.
export var bmapwidth: c_int = undefined;
export var bmapheight: c_int = undefined;       // size in mapblocks
export var blockmap: [*]c_short = undefined;    // int for larger maps
// offsets in blockmap are from here
export var blockmaplump: [*]c_short = undefined;
// origin of block map
export var bmaporgx: fixed_t = undefined;
export var bmaporgy: fixed_t = undefined;
// for thing chains
var blocklinks_slice: []?[*]MObj = undefined;
export var blocklinks: [*]?[*]MObj = undefined;


// REJECT
// For fast sight rejection.
// Speeds up enemy AI by skipping detailed
//  LineOf Sight calculation.
// Without special effect, this could be
//  used as a PVS lookup as well.
//
export var rejectmatrix: [*]u8 = undefined;


// Maintain single and multi player starting spots.
const MAX_DEATHMATCH_STARTS = 10;

pub var deathmatchstarts: [MAX_DEATHMATCH_STARTS]c.mapthing_t = undefined;
pub var deathmatch_p: [*]c.mapthing_t = undefined;
pub var playerstarts: [MAXPLAYERS]c.mapthing_t = undefined;



//
// P_LoadVertexes
//
fn P_LoadVertexes(lump: c_int) void {
    // Determine number of lumps:
    //  total lump length / vertex record length.
    const numvertexes = @divTrunc(W_LumpLength(lump), @sizeOf(c.mapvertex_t));

    // Allocate zone memory for buffer.
    vertexes = z_zone.alloc(c.vertex_t, numvertexes, .Level, null);

    // Load data into cache.
    const ml = W_CacheLumpNum([*]c.mapvertex_t, lump, .Static);
    defer z_zone.Z_Free(ml);

    // Copy and convert vertex coordinates,
    // internal representation as fixed.
    for (vertexes, 0..) |*li, i| {
        li.*.x = @as(fixed_t, SHORT(ml[i].x)) << FRACBITS;
        li.*.y = @as(fixed_t, SHORT(ml[i].y)) << FRACBITS;
    }
}


//
// P_LoadSegs
//
fn P_LoadSegs(lump: c_int) void {
    const numsegs = @divTrunc(W_LumpLength(lump), @sizeOf(c.mapseg_t));

    segs_slice = z_zone.alloc(c.seg_t, numsegs, .Level, null);
    @memset(segs_slice, std.mem.zeroes(c.seg_t));
    segs = segs_slice.ptr;

    const ml = W_CacheLumpNum([*]c.mapseg_t, lump, .Static);
    defer z_zone.Z_Free(ml);

    for (segs_slice, 0..) |*li, i| {
        li.*.v1 = &vertexes[@intCast(SHORT(ml[i].v1))];
        li.*.v2 = &vertexes[@intCast(SHORT(ml[i].v2))];

        li.*.angle = @as(c.angle_t, @as(c_ushort, @bitCast(SHORT(ml[i].angle)))) << 16;
        li.*.offset = @as(fixed_t, SHORT(ml[i].offset)) << 16;

        const linedef = SHORT(ml[i].linedef);
        const ldef = &lines_slice[@intCast(linedef)];
        const side = SHORT(ml[i].side);
        li.*.linedef = ldef;
        li.*.sidedef = &sides[@intCast(ldef.sidenum[@intCast(side)])];
        li.*.frontsector = sides[@intCast(ldef.sidenum[@intCast(side)])].sector;

        if (ldef.flags & c.ML_TWOSIDED != 0) {
            li.*.backsector = sides[@intCast(ldef.sidenum[@intCast(side ^ 1)])].sector;
        } else {
            li.*.backsector = 0;
        }
    }
}


//
// P_LoadSubsectors
//
fn P_LoadSubsectors(lump: c_int) void {
    numsubsectors = @intCast(@divTrunc(W_LumpLength(lump), @sizeOf(c.mapsubsector_t)));

    subsectors_slice = z_zone.alloc(c.subsector_t, @intCast(numsubsectors), .Level, null);
    @memset(subsectors_slice, std.mem.zeroes(c.subsector_t));
    subsectors = subsectors_slice.ptr;

    const ms = W_CacheLumpNum([*]c.mapsubsector_t, lump, .Static);
    defer z_zone.Z_Free(ms);

    for (subsectors_slice, 0..) |*ss, i| {
        ss.numlines = SHORT(ms[i].numsegs);
        ss.firstline = SHORT(ms[i].firstseg);
    }
}


//
// P_LoadSectors
//
fn P_LoadSectors(lump: c_int) void {
    numsectors = @intCast(@divTrunc(W_LumpLength(lump), @sizeOf(c.mapsector_t)));

    sectors_slice = z_zone.alloc(c.sector_t, @intCast(numsectors), .Level, null);
    @memset(sectors_slice, std.mem.zeroes(c.sector_t));
    sectors = sectors_slice.ptr;

    const ms = W_CacheLumpNum([*]c.mapsector_t, lump, .Static);
    defer z_zone.Z_Free(ms);

    for (sectors_slice, 0..) |*ss, i| {
        ss.floorheight = @as(fixed_t, SHORT(ms[i].floorheight)) << FRACBITS;
        ss.ceilingheight = @as(fixed_t, SHORT(ms[i].ceilingheight)) << FRACBITS;
        ss.floorpic = @intCast(c.R_FlatNumForName(&ms[i].floorpic));
        ss.ceilingpic = @intCast(c.R_FlatNumForName(&ms[i].ceilingpic));
        ss.lightlevel = SHORT(ms[i].lightlevel);
        ss.special = SHORT(ms[i].special);
        ss.tag = SHORT(ms[i].tag);
        ss.thinglist = null;
    }
}



//
// P_LoadNodes
//
fn P_LoadNodes(lump: c_int) void {
    numnodes = @intCast(@divTrunc(W_LumpLength(lump), @sizeOf(c.mapnode_t)));

    nodes_slice = z_zone.alloc(c.node_t, @intCast(numnodes), .Level, null);
    nodes = nodes_slice.ptr;

    const mn = W_CacheLumpNum([*]c.mapnode_t, lump, .Static);
    defer z_zone.Z_Free(mn);

    for (nodes_slice, 0..) |*no, i| {
        no.x = @as(fixed_t, SHORT(mn[i].x)) << FRACBITS;
        no.y = @as(fixed_t, SHORT(mn[i].y)) << FRACBITS;
        no.dx = @as(fixed_t, SHORT(mn[i].dx)) << FRACBITS;
        no.dy = @as(fixed_t, SHORT(mn[i].dy)) << FRACBITS;
        for (0..2) |j| {
            no.children[j] = USHORT(mn[i].children[j]);
            for (0..4) |k| {
                no.bbox[j][k] = @as(fixed_t, SHORT(mn[i].bbox[j][k])) << FRACBITS;
            }
        }
    }
}


//
// P_LoadThings
//
fn P_LoadThings(lump: c_int) void {
    const numthings = @divTrunc(W_LumpLength(lump), @sizeOf(c.mapthing_t));
    const mt = W_CacheLumpNum([*]c.mapthing_t, lump, .Static);
    defer z_zone.Z_Free(mt);

    for (0..numthings) |i| {
        // Do not spawn cool, new monsters if !commercial
        const spawn = if (doomstat.gamemode != .Commercial)
            switch (mt[i].type) {
                68, // Arachnotron
                64, // Archvile
	        88, // Boss Brain
	        89, // Boss Shooter
	        69, // Hell Knight
	        67, // Mancubus
	        71, // Pain Elemental
	        65, // Former Human Commando
	        66, // Revenant
	        84, // Wolf SS
                => false,
                else => true,
            }
        else true;

        if (!spawn) {
            // TODO: Was this a bug? Comment below sorta suggests it was
            // meant to ignore Doom 2 monsters but spawn everything else.
            break;
        }

        // Do spawn all other stuff.
        mt[i].x = SHORT(mt[i].x);
        mt[i].y = SHORT(mt[i].y);
        mt[i].angle = SHORT(mt[i].angle);
        mt[i].type = SHORT(mt[i].type);
        mt[i].options = SHORT(mt[i].options);

        P_SpawnMapThing(@ptrCast(&mt[i]));
    }
}


//
// P_LoadLineDefs
// Also counts secret lines for intermissions.
//
fn P_LoadLineDefs(lump: c_int) void {
    numlines = @intCast(@divTrunc(W_LumpLength(lump), @sizeOf(c.maplinedef_t)));
    lines_slice = z_zone.alloc(c.line_t, @intCast(numlines), .Level, null);
    @memset(lines_slice, std.mem.zeroes(c.line_t));
    lines = lines_slice.ptr;

    const mld = W_CacheLumpNum([*]c.maplinedef_t, lump, .Static);
    defer z_zone.Z_Free(mld);

    for (lines_slice, 0..) |*ld, i| {
        ld.*.flags = SHORT(mld[i].flags);
        ld.*.special = SHORT(mld[i].special);
        ld.*.tag = SHORT(mld[i].tag);
        ld.*.v1 = &vertexes[@intCast(SHORT(mld[i].v1))];
        ld.*.v2 = &vertexes[@intCast(SHORT(mld[i].v2))];
        const v1 = ld.*.v1;
        const v2 = ld.*.v2;
        ld.*.dx = v2.*.x - v1.*.x;
        ld.*.dy = v2.*.y - v1.*.y;

        if (ld.*.dx == 0) {
            ld.*.slopetype = c.ST_VERTICAL;
        } else if (ld.*.dy == 0) {
            ld.*.slopetype = c.ST_HORIZONTAL;
        } else if (FixedDiv(ld.*.dy, ld.*.dx) > 0) {
            ld.*.slopetype = c.ST_POSITIVE;
        } else {
            ld.*.slopetype = c.ST_NEGATIVE;
        }

        if (v1.*.x < v2.*.x) {
            ld.*.bbox[c.BOXLEFT] = v1.*.x;
            ld.*.bbox[c.BOXRIGHT] = v2.*.x;
        } else {
            ld.*.bbox[c.BOXLEFT] = v2.*.x;
            ld.*.bbox[c.BOXRIGHT] = v1.*.x;
        }

        if (v1.*.y < v2.*.y) {
            ld.*.bbox[c.BOXBOTTOM] = v1.*.y;
            ld.*.bbox[c.BOXTOP] = v2.*.y;
        } else {
            ld.*.bbox[c.BOXBOTTOM] = v2.*.y;
            ld.*.bbox[c.BOXTOP] = v1.*.y;
        }

        ld.*.sidenum[0] = SHORT(mld[i].sidenum[0]);
        ld.*.sidenum[1] = SHORT(mld[i].sidenum[1]);

        ld.*.frontsector = if (ld.*.sidenum[0] != -1)
            sides_slice[@intCast(ld.*.sidenum[0])].sector
        else
            0;

        ld.*.backsector = if (ld.*.sidenum[1] != -1)
            sides_slice[@intCast(ld.*.sidenum[1])].sector
        else
            0;
    }
}


//
// P_LoadSideDefs
//
fn P_LoadSideDefs(lump: c_int) void {
    numsides = @intCast(@divTrunc(W_LumpLength(lump), @sizeOf(c.mapsidedef_t)));
    sides_slice = z_zone.alloc(c.side_t, @intCast(numsides), .Level, null);
    @memset(sides_slice, std.mem.zeroes(c.side_t));
    sides = sides_slice.ptr;

    const msd = W_CacheLumpNum([*]c.mapsidedef_t, lump, .Static);
    defer z_zone.Z_Free(msd);

    for (sides_slice, 0..) |*sd, i| {
        sd.*.textureoffset = @as(fixed_t, SHORT(msd[i].textureoffset)) << FRACBITS;
        sd.*.rowoffset = @as(fixed_t, SHORT(msd[i].rowoffset)) << FRACBITS;
        sd.*.toptexture = @intCast(c.R_TextureNumForName(&msd[i].toptexture));
        sd.*.bottomtexture = @intCast(c.R_TextureNumForName(&msd[i].bottomtexture));
        sd.*.midtexture = @intCast(c.R_TextureNumForName(&msd[i].midtexture));
        sd.*.sector = &sectors[@intCast(SHORT(msd[i].sector))];
    }
}


//
// P_LoadBlockMap
//
fn P_LoadBlockMap(lump: c_int) void {
    blockmaplump = W_CacheLumpNum([*]c_short, lump, .Level);
    blockmap = blockmaplump + 4;
    const count = @divTrunc(W_LumpLength(lump), 2);

    for (0..count) |i| {
        blockmaplump[i] = SHORT(blockmaplump[i]);
    }

    bmaporgx = @as(fixed_t, blockmaplump[0]) << FRACBITS;
    bmaporgy = @as(fixed_t, blockmaplump[1]) << FRACBITS;
    bmapwidth = blockmaplump[2];
    bmapheight = blockmaplump[3];

    // clear out mobj chains
    blocklinks_slice = z_zone.alloc(?[*]MObj, @intCast(bmapwidth * bmapheight), .Level, null);
    @memset(blocklinks_slice, null);
    blocklinks = blocklinks_slice.ptr;
}



//
// P_GroupLines
// Builds sector line lists and subsector sector numbers.
// Finds block bounding boxes for sectors.
//
fn P_GroupLines() void {
    // look up sector number for each subsector
    for (subsectors_slice) |*ss| {
        const seg = &segs_slice[@intCast(ss.*.firstline)];
        ss.*.sector = seg.*.sidedef[0].sector;
    }

    // count number of lines in each sector
    var total: usize = 0;
    for (lines_slice) |li| {
        total += 1;
        li.frontsector[0].linecount += 1;

        if (li.backsector != 0 and li.backsector != li.frontsector) {
            total += 1;
            li.backsector[0].linecount += 1;
        }
    }

    // build line tables for each sector
    const linebuffer_slice = z_zone.alloc([*c]c.line_t, total, .Level, null);
    var linebuffer = linebuffer_slice.ptr;

    for (sectors_slice) |*sector| {
        var bbox: [4]fixed_t = undefined;
        c.M_ClearBox(&bbox);
        sector.lines = linebuffer;

        var j: usize = 0;
        for (lines_slice) |*li| {
            if (li.frontsector == sector or li.backsector == sector) {
                linebuffer[j] = li;
                j += 1;
                c.M_AddToBox(&bbox, li.v1.*.x, li.v1.*.y);
                c.M_AddToBox(&bbox, li.v2.*.x, li.v2.*.y);
            }
        }
        if (j != sector.*.linecount) {
            I_Error("P_GroupLines: miscounted");
        }
        linebuffer += j;

        // set the degenmobj_t to the middle of the bounding box
        sector.*.soundorg.x = @divTrunc(bbox[c.BOXRIGHT] + bbox[c.BOXLEFT], 2);
        sector.*.soundorg.y = @divTrunc(bbox[c.BOXTOP] + bbox[c.BOXBOTTOM], 2);

        // adjust bounding box to map blocks
        const blocktop = (bbox[c.BOXTOP] - bmaporgy + c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        sector.*.blockbox[c.BOXTOP] = @min(blocktop, bmapheight - 1);

        const blockbottom = (bbox[c.BOXBOTTOM] - bmaporgy - c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        sector.*.blockbox[c.BOXBOTTOM] = @max(blockbottom, 0);

        const blockright = (bbox[c.BOXRIGHT] - bmaporgx + c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        sector.*.blockbox[c.BOXRIGHT] = @min(blockright, bmapwidth - 1);

        const blockleft = (bbox[c.BOXLEFT] - bmaporgx - c.MAXRADIUS) >> c.MAPBLOCKSHIFT;
        sector.*.blockbox[c.BOXLEFT] = @max(blockleft, 0);
    }
}



//
// P_SetupLevel
//
pub fn P_SetupLevel(episode: c_int, map: c_int) void {
    g_game.totalkills = 0;
    g_game.totalitems = 0;
    g_game.totalsecret = 0;
    g_game.wminfo.maxfrags = 0;
    g_game.wminfo.partime = 180;
    for (&g_game.players) |*player| {
        player.*.killcount = 0;
        player.*.secretcount = 0;
        player.*.itemcount = 0;
    }

    // Initial height of PointOfView
    // will be set by player think.
    g_game.players[g_game.consoleplayer].viewz = 1;

    // Make sure all sounds are stopped before Z_FreeTags.
    S_Start();

    if (false and d_main.debugfile != null) {
        z_zone.Z_FreeTags(.Level, .Cache);
        z_zone.Z_FileDumpHeap(d_main.debugfile);
    } else {
        z_zone.Z_FreeTags(.Level, .PurgeLevel);
    }

    P_InitThinkers();

    // if working with a development map, reload it
    W_Reload();

    // find map name
    var lumpnamebuf = [_]u8{0} ** 9;
    const lumpname = if (doomstat.gamemode == .Commercial)
        std.fmt.bufPrintZ(&lumpnamebuf, "map{d:0>2}", .{@as(c_uint, @intCast(map))}) catch unreachable
    else
        std.fmt.bufPrintZ(&lumpnamebuf, "e{}m{}", .{episode, map}) catch unreachable;

    const lumpnum = W_GetNumForName(lumpname.ptr);

    p_tick.leveltime = 0;

    // note: most of this ordering is important
    P_LoadBlockMap(lumpnum + c.ML_BLOCKMAP);
    P_LoadVertexes(lumpnum + c.ML_VERTEXES);
    P_LoadSectors(lumpnum + c.ML_SECTORS);
    P_LoadSideDefs(lumpnum + c.ML_SIDEDEFS);

    P_LoadLineDefs(lumpnum + c.ML_LINEDEFS);
    P_LoadSubsectors(lumpnum + c.ML_SSECTORS);
    P_LoadNodes(lumpnum + c.ML_NODES);
    P_LoadSegs(lumpnum + c.ML_SEGS);

    rejectmatrix = W_CacheLumpNum([*]u8, lumpnum + c.ML_REJECT, .Level);
    P_GroupLines();

    g_game.bodyqueslot = 0;
    deathmatch_p = &deathmatchstarts;
    P_LoadThings(lumpnum + c.ML_THINGS);

    // if deatchmatch, randomly spawn the active players
    if (g_game.deathmatch != 0) {
        for (&g_game.players, g_game.playeringame, 0..) |*player, ingame, i| {
            if (ingame != 0) {
                player.*.mo = null;
                G_DeathMatchSpawnPlayer(i);
            }
        }
    }

    // clear special respawning que
    p_mobj.iquehead = 0;
    p_mobj.iquetail = 0;

    // set up world state
    c.P_SpawnSpecials();

    // preload graphics
    if (g_game.precache) {
        c.R_PrecacheLevel();
    }

    if (false) {
        const stdout = std.io.getStdOut().writer();
        stdout.print("free memory: 0x{x}\n", .{z_zone.Z_FreeMemory()}) catch unreachable;
    }
}



//
// P_Init
//
pub fn P_Init() void {
    c.P_InitSwitchList();
    c.P_InitPicAnims();
    c.R_InitSprites(&c.sprnames);
}
