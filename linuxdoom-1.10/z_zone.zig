const I_Error = @import("i_system.zig").I_Error;
const I_ZoneBase = @import("i_system.zig").I_ZoneBase;

//
// ZONE MEMORY ALLOCATION
//
// There is never any space between memblocks,
//  and there will never be two contiguous free memblocks.
// The rover can be left pointing at a non-empty block.
//
// It is of no value to free a cachable block,
//  because it will get overwritten automatically if needed.
//

const ZONEID = 0x1d4a11;

//
// ZONE MEMORY
// PU - purge tags.
// Tags < 100 are not overwritten until freed.
pub const Z_Tag = enum(c_int) {
    Undefined = 0,
    Static = 1,     // static entire execution time
    Sound = 2,      // static while playing
    Music = 3,      // static while playing
    Dave = 4,       // anything else Dave wants static
    Level = 50,     // static until level exited
    LevSpec = 51,   // a special thinker in a level
    // Tags >= 100 are purgable whenever needed.
    PurgeLevel = 100,
    Cache = 101,
};

const MemBlock = extern struct {
    size: i32,
    user: ?*?*anyopaque, // null if a free block
    tag: Z_Tag,
    id: i32,
    next: *MemBlock,
    prev: *MemBlock,

    fn fromPtr(ptr: *anyopaque) *MemBlock {
        return &(@as([*]MemBlock, @ptrCast(@alignCast(ptr))) - 1)[0];
    }

    fn toOpaquePtr(self: *MemBlock) *anyopaque {
        return @as([*]u8, @ptrCast(self)) + @sizeOf(MemBlock);
    }
};

const MemZone = extern struct {
    // total bytes malloced, including header
    size: i32,
    // start / end cap for linked list
    blocklist: MemBlock,
    rover: *MemBlock,
};

export var mainzone: *MemZone = undefined;

export fn Z_Init() void {
    var size: i32 = undefined;

    mainzone = @ptrCast(@alignCast(I_ZoneBase(&size)));
    mainzone.size = size;

    const block: *MemBlock = @ptrCast(@as([*]MemZone, @as(*[1]MemZone, mainzone)) + 1);
    mainzone.blocklist.next = block;
    mainzone.blocklist.prev = block;

    mainzone.blocklist.user = @ptrCast(mainzone);
    mainzone.blocklist.tag = Z_Tag.Static;
    mainzone.rover = block;

    block.prev = &mainzone.blocklist;
    block.next = &mainzone.blocklist;
    block.user = null;
    block.tag = .Undefined;
    block.size = mainzone.size - @sizeOf(MemZone);
}

pub fn alloc(comptime T: type, n: usize, tag: Z_Tag, user: ?*?*anyopaque) []T {
    const requested_size = @sizeOf(T) * n;
    const bytes = Z_Malloc(@intCast(requested_size), tag, user);
    return @as([*]T, @ptrCast(@alignCast(bytes)))[0..n];
}

pub fn free(slice: anytype) void {
    const ArgType = @TypeOf(slice);
    const info = @typeInfo(ArgType).Pointer;
    if (info.size != .Slice) {
        @compileError("expected slice argument, found " ++ @typeName(ArgType));
    }
    Z_Free(slice.ptr);
}

/// You can pass `null` user if the tag is < Z_Tag.PurgeLevel
pub export fn Z_Malloc(requested_size: i32, tag: Z_Tag, user: ?*?*anyopaque) *anyopaque {
    // TODO: `requested_size` should be `usize` once all code is zig
    const MINFRAGMENT = 64;

    // NOTE: Original doom source hardcoded 4 byte alignment. Switching to
    // correct alignment on the host architecture. However this will increase
    // block allocation size on modern 64 bit architectures.
    // TODO: Measure allocation sizes with and without this change.
    const alignment = @typeInfo(**anyopaque).Pointer.alignment;
    var size = (requested_size + alignment - 1) & ~@as(i32, alignment - 1);

    // scan through the block list,
    // looking for the first free block
    // of sufficient size,
    // throwing out any purgable blocks along the way.

    // account for size of block header
    size += @sizeOf(MemBlock);

    // if there is a free block behind the rover,
    //  back up over them
    var base = mainzone.rover;

    if (base.prev.user == null) {
        base = base.prev;
    }

    var rover = base;
    const start = base.prev;

    while (true) {
        if (rover == start) {
            // scanned all the way around the list
            I_Error("Z_Malloc: failed on allocation of %i bytes", size);
        }

        if (rover.user != null) {
            if (@intFromEnum(rover.tag) < @intFromEnum(Z_Tag.PurgeLevel)) {
                // hit a block that can't be purged,
                // so move base past it
                base = rover.next;
                rover = rover.next;
            } else {
                // free the rover block (adding the size to base)

                // the rover can be the base block
                base = base.prev;
                Z_Free(rover.toOpaquePtr());
                base = base.next;
                rover = base.next;
            }
        } else {
            rover = rover.next;
        }

        if (!(base.user != null or base.size < size)) break;
    }

    // found a block big enough
    const extra = base.size - size;

    if (extra > MINFRAGMENT) {
        // there will be a free fragment after the allocated block
        const newblock: *MemBlock = @ptrFromInt(@intFromPtr(base) + @as(usize, @intCast(size)));
        newblock.size = extra;

        // null indicates free block.
        newblock.user = null;
        newblock.tag = .Undefined;
        newblock.prev = base;
        newblock.next = base.next;
        newblock.next.prev = newblock;

        base.next = newblock;
        base.size = size;
    }

    if (user != null) {
        // mark as an in-use block
        base.user = user;
        @as(*[*]u8, @ptrCast(user)).* = @as([*]u8, @ptrCast(base)) + @sizeOf(MemBlock);
    } else {
        if (@intFromEnum(tag) >= @intFromEnum(Z_Tag.PurgeLevel)) {
            I_Error("Z_Malloc: an owner is required for purgable blocks");
        }

        // mark as in-use, but unowned
        // NOTE: Original doom source uses `2` but that is not aligned. To
        // avoid zig compiler complaint use the pointer alignment value instead.
        base.user = @ptrFromInt(alignment);
    }
    base.tag = tag;

    // next allocation will start looking here
    mainzone.rover = base.next;

    base.id = ZONEID;

    return @ptrCast(@as([*]u8, @ptrCast(base)) + @sizeOf(MemBlock));
}

pub export fn Z_Free(ptr: *anyopaque) void {
    var block = MemBlock.fromPtr(ptr);

    if (block.id != ZONEID) {
        I_Error("Z_Free: freed a pointer without ZONEID");
    }

    if (@intFromPtr(block.user) > 0x100) {
        // smaller values are not pointers
        // Note: OS-dependend?

        // TODO: So this set's the owner's own pointer to null. Investigate if
        // there is a better way.

        // clear the user's mark
        block.user.?.* = null;
    }

    // mark as free
    block.user = null;
    block.tag = .Undefined;
    block.id = 0;

    var other = block.prev;

    if (other.user == null) {
        // merge with previous free block
        other.size += block.size;
        other.next = block.next;
        other.next.prev = other;

        if (block == mainzone.rover) {
            mainzone.rover = other;
        }

        block = other;
    }

    other = block.next;
    if (other.user == null) {
        // merge the next free block onto the end
        block.size += other.size;
        block.next = other.next;
        block.next.prev = block;

        if (other == mainzone.rover) {
            mainzone.rover = block;
        }
    }
}

pub export fn Z_ChangeTag(ptr: *anyopaque, tag: Z_Tag) void {
    const block = MemBlock.fromPtr(ptr);

    if (block.id != ZONEID) {
        // TODO: Restore line number display on this I_Error() call (consider stack trace in all I_Error() calls)
        I_Error("Z_ChangeTag: freed a pointer without ZONEID");
    }

    if (@intFromEnum(tag) >= @intFromEnum(Z_Tag.PurgeLevel) and @intFromPtr(block.user) < 0x100) {
        I_Error("Z_ChangeTag: an owner is required for purgable blocks");
    }

    block.tag = tag;
}

export fn Z_FreeTags(lowtag: Z_Tag, hightag: Z_Tag) void {
    var block = mainzone.blocklist.next;
    var next: *MemBlock = undefined;

    while (block != &mainzone.blocklist) : (block = next) {
        // get link before freeing
        next = block.next;

        // free block?
        if (block.user == null) {
            continue;
        }

        if (@intFromEnum(block.tag) >= @intFromEnum(lowtag)
            and @intFromEnum(block.tag) <= @intFromEnum(hightag)) {
            Z_Free(block.toOpaquePtr());
        }
    }
}

// Debugging Utilities

// TODO: Zig converted Z_DumpHeap is untested
export fn Z_DumpHeap(lowtag: Z_Tag, hightag: Z_Tag) void {
    const print = @import("std").debug.print;

    print("zone size: {}  location: {}\n", .{mainzone.size, mainzone});
    print("tag range: {} to {}\n", .{lowtag, hightag});

    var block = mainzone.blocklist.next;
    while (true) : (block = block.next) {
        if (@intFromEnum(block.tag) >= @intFromEnum(lowtag)
            and @intFromEnum(block.tag) <= @intFromEnum(hightag)) {
            print("block:{}    size:{:7}    user:{?}    tag:{:3}\n",
                .{block, block.size, block.user, block.tag});
        }

        if (block.next == &mainzone.blocklist) {
            // all blocks have been hit
            break;
        }

        if (@intFromPtr(block) + @as(usize, @intCast(block.size)) != @intFromPtr(block.next)) {
            print("ERROR: block size does not touch the next block\n", .{});
        }

        if (block.next.prev != block) {
            print("ERROR: next block doesn't have proper back link\n", .{});
        }

        if (block.user == null and block.next.user == null) {
            print("ERROR: two consecutive free blocks\n", .{});
        }
    }
}

const FILE = @import("std").c.FILE;
extern "c" fn fprintf(noalias stream: *FILE, format: [*:0]const u8, ...) c_int;

// TODO: Zig converted Z_FileDumpHeap is untested
// TODO: Switch from C fprintf to zig file writer
export fn Z_FileDumpHeap(f: *FILE) void {
    _ = fprintf(f, "zone size: %i  location: %p\n", mainzone.size, mainzone);

    var block = mainzone.blocklist.next;
    while (true) : (block = block.next) {
        _ = fprintf(f, "block:%p    size:%7i    user:%p    tag:%3i\n",
            block, block.size, block.user, block.tag);

        if (block.next == &mainzone.blocklist) {
            // all blocks have been hit
            break;
        }

        if (@intFromPtr(block) + @as(usize, @intCast(block.size)) != @intFromPtr(block.next)) {
            _ = fprintf(f, "ERROR: block size does not touch the next block\n");
        }

        if (block.next.prev != block) {
            _ = fprintf(f, "ERROR: next block doesn't have proper back link\n");
        }

        if (block.user == null and block.next.user == null) {
            _ = fprintf(f, "ERROR: two consecutive free blocks\n");
        }
    }
}

export fn Z_CheckHeap() void {
    var block = mainzone.blocklist.next;
    while (true) : (block = block.next) {
        if (block.next == &mainzone.blocklist) {
            // all blocks have been hit
            break;
        }

        if (@intFromPtr(block) + @as(usize, @intCast(block.size)) != @intFromPtr(block.next)) {
            I_Error("Z_CheckHeap: block size does not touch the next block\n");
        }

        if (block.next.prev != block) {
            I_Error("Z_CheckHeap: next block doesn't have proper back link\n");
        }

        if (block.user == null and block.next.user == null) {
            I_Error("Z_CheckHeap: two consecutive free blocks\n");
        }
    }
}

// TODO: Zig converted Z_FreeMemory is untested
export fn Z_FreeMemory() c_int {
    var free_count: c_int = 0;

    var block = mainzone.blocklist.next;
    while (block != &mainzone.blocklist) : (block = block.next) {
        if (block.user == null or @intFromEnum(block.tag) >= @intFromEnum(Z_Tag.PurgeLevel)) {
            free_count += block.size;
        }
    }
    return free_count;
}
