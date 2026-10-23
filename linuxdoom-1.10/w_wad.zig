const std = @import("std");
const i_system = @import("i_system.zig");
const m_swap = @import("m_swap.zig");
const LONG = m_swap.LONG;
const I_Error = @import("i_system.zig").I_Error;
const z_zone = @import("z_zone.zig");
const Z_ChangeTag = z_zone.Z_ChangeTag;
const Z_Free = z_zone.Z_Free;
const Z_Tag = z_zone.Z_Tag;

const WadInfo = extern struct {
    identification: [4]u8,
    numlumps: c_int,
    infotableofs: c_int,
};

const FileLump = extern struct {
    filepos: c_int,
    size: c_int,
    name: [8]u8,
};

const LumpInfo = extern struct {
    name: [8]u8,
    handle: c_int,
    position: c_int,
    size: c_int,
};

// Location of each lump on disk.
var lumpinfo_slice: []LumpInfo = undefined;
pub export var lumpinfo: ?[*]LumpInfo = null;
var numlumps: usize = 0;
var lumpcache: []?*anyopaque = undefined;

var reloadlump: usize = 0;
var reloadname: ?[]const u8 = null;

fn filelength(file: std.Io.File) c_int {
    const length = file.length(i_system.io) catch {
        I_Error("Error fstating");
    };

    return @intCast(length);
}

fn ExtractFileBase(path: []const u8, dest: []u8) void {
    var i = path.len - 1;

    // back up until a \ or / or the start
    while (i > 0 and path[i - 1] != '\\' and path[i - 1] != '/') {
        i -= 1;
    }

    // copy up to eight characters
    @memset(dest[0..8], 0);
    var length: usize = 0;

    while (i < path.len and path[i] != '.') {
        length += 1;
        if (length == 9) {
            const pathZ = std.heap.c_allocator.dupeSentinel(u8, path, 0) catch unreachable;
            I_Error("Filename base of %s >8 chars", pathZ.ptr);
        }

        dest[length - 1] = std.ascii.toUpper(path[i]);
        i += 1;
    }
}

//
// LUMP BASED ROUTINES.
//

//
// W_AddFile
// All files are optional, but at least one file must be
//  found (PWAD, if all required lumps are present).
// Files with a .wad extension are wadlink files
//  with multiple lumps.
// Other files are single lumps with the base filename
//  for the lump name.
//
// If filename starts with a tilde, the file is handled
//  specially to allow map reloads.
// But: the reload feature is a fragile hack...

pub fn W_AddFile(_filename: []const u8) void {
    // open the file and add to directory

    const filename = if (_filename[0] == '~') blk: {
        // handle reload indicator.
        reloadname = _filename[1..];
        reloadlump = numlumps;
        break :blk _filename[1..];
    } else _filename;

    const stdout = i_system.stdout();
    const file = std.Io.Dir.cwd().openFile(i_system.io, filename, .{}) catch {
        stdout.print(" couldn't open {s}\n", .{filename}) catch {};
        return;
    };

    stdout.print(" adding {s}\n", .{filename}) catch {};
    const startlump = numlumps;
    var singleinfo: FileLump = undefined;
    var fileinfo: []FileLump = undefined;

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!std.ascii.eqlIgnoreCase(filename[filename.len - 3 ..], "wad")) {
        // single lump file
        fileinfo = @as(*[1]FileLump, &singleinfo);
        singleinfo.filepos = 0;
        singleinfo.size = filelength(file);
        ExtractFileBase(filename, &singleinfo.name);
        numlumps += 1;
    } else {
        // WAD file
        var header_bytes: [@sizeOf(WadInfo)]u8 = undefined;
        _ = file.readPositionalAll(i_system.io, &header_bytes, 0) catch {
            I_Error("Failed to read WAD header");
        };
        var header = std.mem.bytesAsValue(WadInfo, &header_bytes);
        if (!std.mem.eql(u8, &header.identification, "IWAD")) {
            // Homebrew levels?
            if (!std.mem.eql(u8, &header.identification, "PWAD")) {
                const filenameZ = std.heap.c_allocator.dupeSentinel(u8, filename, 0) catch unreachable;
                I_Error("Wad file %s doesn't have IWAD or PWAD id", filenameZ.ptr);
            }

            // ???modifiedgame = true;
        }

        header.numlumps = LONG(header.numlumps);
        header.infotableofs = LONG(header.infotableofs);
        fileinfo = allocator.alloc(FileLump, @intCast(header.numlumps)) catch {
            I_Error("W_AddFile: Alloc lumps failed. numlumps = %d", header.numlumps);
        };

        _ = file.readPositionalAll(i_system.io, std.mem.sliceAsBytes(fileinfo), @intCast(header.infotableofs)) catch {
            I_Error("Failed to read WAD lump infos");
        };

        numlumps += @intCast(header.numlumps);
    }

    // Fill in lumpinfo
    lumpinfo_slice = std.heap.c_allocator.realloc(lumpinfo_slice, @sizeOf(LumpInfo) * numlumps) catch {
        I_Error("Couldn't realloc lumpinfo");
    };
    lumpinfo = lumpinfo_slice.ptr;

    const storehandle = if (reloadname != null) -1 else file.handle;

    for (startlump..numlumps) |i| {
        lumpinfo_slice[i].handle = storehandle;
        lumpinfo_slice[i].position = LONG(fileinfo[i - startlump].filepos);
        lumpinfo_slice[i].size = LONG(fileinfo[i - startlump].size);
        @memcpy(&lumpinfo_slice[i].name, &fileinfo[i - startlump].name);
    }

    if (reloadname != null) {
        file.close(i_system.io);
    }
}



//
// W_Reload
// Flushes any of the reloadable lumps in memory
//  and reloads the directory.
//
pub fn W_Reload() void {
    if (reloadname == null) return;

    const file = std.Io.Dir.cwd().openFile(i_system.io, reloadname.?, .{}) catch {
        const reloadnameZ = std.heap.c_allocator.dupeSentinel(u8, reloadname.?, 0) catch unreachable;
        I_Error("W_Reload: couldn't open %s", reloadnameZ.ptr);
    };

    var header_bytes: [@sizeOf(WadInfo)]u8 = undefined;
    _ = file.readPositionalAll(i_system.io, &header_bytes, 0) catch {
        I_Error("W_Reload: Failed to read WAD header");
    };
    var header = std.mem.bytesAsValue(WadInfo, &header_bytes);
    header.numlumps = LONG(header.numlumps);
    header.infotableofs = LONG(header.infotableofs);

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fileinfo = allocator.alloc(FileLump, @intCast(header.numlumps)) catch {
        I_Error("W_Reload: Alloc lumps failed. numlumps = %d", header.numlumps);
    };

    _ = file.readPositionalAll(i_system.io, std.mem.sliceAsBytes(fileinfo), @intCast(header.infotableofs)) catch {
        I_Error("W_Reload: Failed to read WAD lump infos");
    };

    for (reloadlump..reloadlump + @as(usize, @intCast(header.numlumps))) |i| {
        if (lumpcache[i] != null) {
            Z_Free(lumpcache[i].?);
        }

        lumpinfo_slice[i].position = LONG(fileinfo[i - reloadlump].filepos);
        lumpinfo_slice[i].size = LONG(fileinfo[i - reloadlump].size);
    }

    file.close(i_system.io);
}


//
// W_InitMultipleFiles
// Pass a null terminated list of files to use.
// All files are optional, but at least one file
//  must be found.
// Files with a .wad extension are idlink files
//  with multiple lumps.
// Other files are single lumps with the base filename
//  for the lump name.
// Lump names can appear multiple times.
// The name searcher looks backwards, so a later file
//  does override all earlier ones.
//
pub fn W_InitMultipleFiles(filenames: [][]const u8) void {
    // open all the files, load headers, and count lumps
    numlumps = 0;

    // will be reallocated as lumps are added
    lumpinfo_slice = std.heap.c_allocator.alloc(LumpInfo, 0) catch {
        I_Error("W_InitFiles: failed to allocate initial lumpinfo_slice");
    };

    for (filenames) |filename| {
        W_AddFile(filename);
    }

    if (numlumps == 0) {
        I_Error("W_InitFiles: no files found");
    }

    // set up caching
    lumpcache = std.heap.c_allocator.alloc(?*anyopaque, numlumps) catch {
        I_Error("Couldn't allocate lumpcache");
    };

    @memset(lumpcache, null);
}

//
// W_CheckNumForName
// Returns -1 if name not found.
//
pub export fn W_CheckNumForName(name: [*]const u8) c_int {
    var name_upper: [8]u8 = @splat(0);
    for (&name_upper, 0..) |*c, i| {
        if (name[i] == 0) break;
        c.* = std.ascii.toUpper(name[i]);
    }

    // scan backwards so patch lump files take precedence
    for (0..numlumps) |i| {
        const ir = numlumps - 1 - i;
        if (std.mem.eql(u8, &name_upper, &lumpinfo_slice[ir].name)) {
            return @intCast(ir);
        }
    }

    // TODO: Switch to using Zig error model and a usize index
    // TFB. Not found.
    return -1;
}

pub fn W_GetNumForNameFmt(comptime name_fmt: []const u8, args: anytype) c_int {
    var namebuf: [9]u8 = undefined;
    const name = std.fmt.bufPrintSentinel(&namebuf, name_fmt, args, 0) catch unreachable;
    return W_GetNumForName(name.ptr);
}

//
// W_GetNumForName
// Calls W_CheckNumForName, but bombs out if not found.
//
pub export fn W_GetNumForName(name: [*]const u8) c_int {
    const i = W_CheckNumForName(name);

    if (i == -1) {
        I_Error("W_GetNumForName: %.8s not found!", name);
    }

    return i;
}

//
// W_LumpLength
// Returns the buffer size needed to load the given lump.
//
export fn W_LumpLength(lump: c_int) c_int {
    if (lump >= numlumps) {
        I_Error("W_LumpLength: %i >= numlumps", lump);
    }

    return lumpinfo_slice[@intCast(lump)].size;
}

pub fn W_LumpLengthZig(lump: c_int) usize {
    return @intCast(W_LumpLength(lump));
}

//
// W_ReadLump
// Loads the lump into the given buffer,
//  which must be >= W_LumpLength().
//
pub export fn W_ReadLump(lump: c_int, dest: *anyopaque) void {
    if (lump >= numlumps) {
        I_Error("W_ReadLump: %i >= numlumps", lump);
    }

    const l = lumpinfo_slice[@intCast(lump)];

    const file: std.Io.File = if (l.handle == -1) blk: {
        // reloadable file, so use open / read / close
        break :blk std.Io.Dir.cwd().openFile(i_system.io, reloadname.?, .{}) catch {
            const reloadnameZ = std.heap.c_allocator.dupeSentinel(u8, reloadname.?, 0) catch unreachable;
            I_Error("W_ReadLump: couldn't open %s", reloadnameZ.ptr);
        };
    } else .{ .handle = l.handle, .flags = .{ .nonblocking = false } };
    defer if (l.handle == -1) file.close(i_system.io);

    // TODO: Change `dest` to a slice and fix callers to W_ReadLump to pass length of buffer (as slice)
    const buffer = @as([*]u8, @ptrCast(dest))[0..@intCast(l.size)];
    const count = file.readPositionalAll(i_system.io, buffer, @intCast(l.position)) catch 0;

    if (count < l.size) {
        I_Error("W_ReadLump: only read %i of %i bytes of lump %i", @as(c_int, @intCast(count)), l.size, lump);
    }
}


//
// W_CacheLumpNum
//
export fn W_CacheLumpNum(lump: c_int, tag: Z_Tag) *anyopaque {
    if (lump >= numlumps) {
        I_Error("W_CacheLumpNum: %i >= numlumps", lump);
    }

    if (lumpcache[@intCast(lump)] == null) {
        // read the lump in

        // std.debug.print("cache miss on lump {}\n", .{lump});
        _ = z_zone.alloc(u8, @intCast(W_LumpLength(lump)), tag, &lumpcache[@intCast(lump)]);
        W_ReadLump(lump, lumpcache[@intCast(lump)].?);
    } else {
        //std.debug.print("cache hit on lump {}\n", .{lump});
        Z_ChangeTag(lumpcache[@intCast(lump)].?, tag);
    }

    return lumpcache[@intCast(lump)].?;
}

pub fn W_CacheLumpNumZig(comptime T: type, lump: c_int, tag: Z_Tag) T {
    return @ptrCast(@alignCast(W_CacheLumpNum(lump, tag)));
}


//
// W_CacheLumpName
//
export fn W_CacheLumpName(name: [*]const u8, tag: Z_Tag) *anyopaque {
    return W_CacheLumpNum(W_GetNumForName(name), tag);
}

pub fn W_CacheLumpNameZig(comptime T: type, name: []const u8, tag: Z_Tag) T {
    return @ptrCast(@alignCast(W_CacheLumpNum(W_GetNumForName(name.ptr), tag)));
}

pub fn W_CacheLumpNameFmt(comptime T: type, comptime name_fmt: []const u8, args: anytype, tag: Z_Tag) T {
    return @ptrCast(@alignCast(W_CacheLumpNum(W_GetNumForNameFmt(name_fmt, args), tag)));
}
