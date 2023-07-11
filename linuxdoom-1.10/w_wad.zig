const std = @import("std");
const I_Error = @import("i_system.zig").I_Error;
const Z_ChangeTag = @import("z_zone.zig").Z_ChangeTag;
const Z_Malloc = @import("z_zone.zig").Z_Malloc;
const Z_Free = @import("z_zone.zig").Z_Free;
const Z_Tag = @import("z_zone.zig").Z_Tag;

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

fn filelength(handle: std.os.fd_t) c_int {
    const fileinfo = std.os.fstat(handle) catch {
        I_Error("Error fstating");
    };

    return @intCast(c_int, fileinfo.size);
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
            const pathZ = std.heap.raw_c_allocator.dupeZ(u8, path) catch unreachable;
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

    const stdout = std.io.getStdOut().writer();
    const handle = std.os.open(filename, std.os.O.RDONLY, 0) catch {
        stdout.print(" couldn't open {s}\n", .{filename}) catch {};
        return;
    };

    stdout.print(" adding {s}\n", .{filename}) catch {};
    const startlump = numlumps;
    var singleinfo: FileLump = undefined;
    var fileinfo: []FileLump = undefined;

    var arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!std.ascii.eqlIgnoreCase(filename[filename.len - 3 ..], "wad")) {
        // single lump file
        fileinfo = @as(*[1]FileLump, &singleinfo);
        singleinfo.filepos = 0;
        singleinfo.size = filelength(handle);
        ExtractFileBase(filename, &singleinfo.name);
        numlumps += 1;
    } else {
        // WAD file
        var header_bytes: [@sizeOf(WadInfo)]u8 = undefined;
        _ = std.os.read(handle, &header_bytes) catch {
            I_Error("Failed to read WAD header");
        };
        var header = std.mem.bytesAsValue(WadInfo, &header_bytes);
        if (!std.mem.eql(u8, &header.identification, "IWAD")) {
            // Homebrew levels?
            if (!std.mem.eql(u8, &header.identification, "PWAD")) {
                const filenameZ = std.heap.raw_c_allocator.dupeZ(u8, filename) catch unreachable;
                I_Error("Wad file %s doesn't have IWAD or PWAD id", filenameZ.ptr);
            }

            // ???modifiedgame = true;
        }

        header.numlumps = std.mem.littleToNative(c_int, header.numlumps);
        header.infotableofs = std.mem.littleToNative(c_int, header.infotableofs);
        fileinfo = allocator.alloc(FileLump, @intCast(usize, header.numlumps)) catch {
            I_Error("W_AddFile: Alloc lumps failed. numlumps = %d", header.numlumps);
        };

        _ = std.os.lseek_SET(handle, @intCast(u64, header.infotableofs)) catch {
            I_Error("W_AddFile: Failed lseek_SET");
        };
        _ = std.os.read(handle, std.mem.sliceAsBytes(fileinfo)) catch {
            I_Error("Failed to read WAD lump infos");
        };

        numlumps += @intCast(usize, header.numlumps);
    }

    // Fill in lumpinfo
    lumpinfo_slice = std.heap.raw_c_allocator.realloc(lumpinfo_slice, @sizeOf(LumpInfo) * numlumps) catch {
        I_Error("Couldn't realloc lumpinfo");
    };
    lumpinfo = lumpinfo_slice.ptr;

    const storehandle = if (reloadname != null) -1 else handle;

    for (startlump..numlumps) |i| {
        lumpinfo_slice[i].handle = storehandle;
        lumpinfo_slice[i].position = std.mem.littleToNative(c_int, fileinfo[i - startlump].filepos);
        lumpinfo_slice[i].size = std.mem.littleToNative(c_int, fileinfo[i - startlump].size);
        @memcpy(&lumpinfo_slice[i].name, &fileinfo[i - startlump].name);
    }

    if (reloadname != null) {
        _ = std.c.close(handle);
    }
}



//
// W_Reload
// Flushes any of the reloadable lumps in memory
//  and reloads the directory.
//
pub export fn W_Reload() void {
    if (reloadname == null) return;

    const handle = std.os.open(reloadname.?, std.os.O.RDONLY, 0) catch {
        const reloadnameZ = std.heap.raw_c_allocator.dupeZ(u8, reloadname.?) catch unreachable;
        I_Error("W_Reload: couldn't open %s", reloadnameZ.ptr);
    };

    var header_bytes: [@sizeOf(WadInfo)]u8 = undefined;
    _ = std.os.read(handle, &header_bytes) catch {
        I_Error("W_Reload: Failed to read WAD header");
    };
    var header = std.mem.bytesAsValue(WadInfo, &header_bytes);
    header.numlumps = std.mem.littleToNative(c_int, header.numlumps);
    header.infotableofs = std.mem.littleToNative(c_int, header.infotableofs);

    var arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fileinfo = allocator.alloc(FileLump, @intCast(usize, header.numlumps)) catch {
        I_Error("W_Reload: Alloc lumps failed. numlumps = %d", header.numlumps);
    };

    _ = std.os.lseek_SET(handle, @intCast(u64, header.infotableofs)) catch {
        I_Error("W_Reload: Failed lseek_SET");
    };
    _ = std.os.read(handle, std.mem.sliceAsBytes(fileinfo)) catch {
        I_Error("W_Reload: Failed to read WAD lump infos");
    };

    for (reloadlump..@intCast(usize, header.numlumps)) |i| {
        if (lumpcache[i] != null) {
            Z_Free(lumpcache[i].?);
        }

        lumpinfo_slice[i].position = std.mem.littleToNative(c_int, fileinfo[i - reloadlump].filepos);
        lumpinfo_slice[i].size = std.mem.littleToNative(c_int, fileinfo[i - reloadlump].size);
    }

    std.os.close(handle);
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
    lumpinfo_slice = std.heap.raw_c_allocator.alloc(LumpInfo, 0) catch {
        I_Error("W_InitFiles: failed to allocate initial lumpinfo_slice");
    };

    for (filenames) |filename| {
        W_AddFile(filename);
    }

    if (numlumps == 0) {
        I_Error("W_InitFiles: no files found");
    }

    // set up caching
    lumpcache = std.heap.raw_c_allocator.alloc(?*anyopaque, numlumps) catch {
        I_Error("Couldn't allocate lumpcache");
    };

    @memset(lumpcache, null);
}

//
// W_CheckNumForName
// Returns -1 if name not found.
//
pub export fn W_CheckNumForName(name: [*]const u8) c_int {
    var name_upper: [8]u8 = [_]u8{0} ** 8;
    for (&name_upper, 0..) |*c, i| {
        if (name[i] == 0) break;
        c.* = std.ascii.toUpper(name[i]);
    }

    // scan backwards so patch lump files take precedence
    for (0..numlumps) |i| {
        const ir = numlumps - 1 - i;
        if (std.mem.eql(u8, &name_upper, &lumpinfo_slice[ir].name)) {
            return @intCast(c_int, ir);
        }
    }

    // TODO: Switch to using Zig error model and a usize index
    // TFB. Not found.
    return -1;
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
pub export fn W_LumpLength(lump: c_int) c_int {
    if (lump >= numlumps) {
        I_Error("W_LumpLength: %i >= numlumps", lump);
    }

    return lumpinfo_slice[@intCast(usize, lump)].size;
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

    const l = lumpinfo_slice[@intCast(usize, lump)];

    const handle = if (l.handle == -1) blk: {
        // reloadable file, so use open / read / close
        break :blk std.os.open(reloadname.?, std.os.O.RDONLY, 0) catch {
            const reloadnameZ = std.heap.raw_c_allocator.dupeZ(u8, reloadname.?) catch unreachable;
            I_Error("W_ReadLump: couldn't open %s", reloadnameZ.ptr);
        };
    } else l.handle;

    _ = std.os.lseek_SET(handle, @intCast(u64, l.position)) catch {
        const reloadnameZ = std.heap.raw_c_allocator.dupeZ(u8, reloadname.?) catch unreachable;
        I_Error("W_ReadLump: couldn't lseek %s", reloadnameZ.ptr);
    };
    // TODO: Change `dest` to a slice and fix callers to W_ReadLump to pass length of buffer (as slice)
    // const c = std.os.read(handle, dest);
    const c = std.c.read(handle, @ptrCast([*]u8, dest), @intCast(usize, l.size));

    if (c < l.size) {
        I_Error("W_ReadLump: only read %i of %i bytes of lump %i", c, l.size, lump);
    }

    if (l.handle == -1) {
        std.os.close(handle);
    }
}


//
// W_CacheLumpNum
//
pub export fn W_CacheLumpNum(lump: c_int, tag: Z_Tag) *anyopaque {
    if (lump >= numlumps) {
        I_Error("W_CacheLumpNum: %i >= numlumps", lump);
    }

    if (lumpcache[@intCast(usize, lump)] == null) {
        // read the lump in

        // std.debug.print("cache miss on lump {}\n", .{lump});
        _ = Z_Malloc(W_LumpLength(lump), tag, &lumpcache[@intCast(usize, lump)]);
        W_ReadLump(lump, lumpcache[@intCast(usize, lump)].?);
    } else {
        //std.debug.print("cache hit on lump {}\n", .{lump});
        Z_ChangeTag(lumpcache[@intCast(usize, lump)].?, tag);
    }

    return lumpcache[@intCast(usize, lump)].?;
}


//
// W_CacheLumpName
//
pub export fn W_CacheLumpName(name: [*]const u8, tag: Z_Tag) *anyopaque {
    return W_CacheLumpNum(W_GetNumForName(name), tag);
}
