const c = @cImport({
    @cInclude("z_zone.h");
    @cInclude("i_system.h");
    @cInclude("doomdef.h");
});

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
const Z_Tag = enum(c_int) {
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
    const allocation = @alignCast(8, c.I_ZoneBase(&size));

    mainzone = @ptrCast(*MemZone, allocation);
    mainzone.size = size;

    const block = @ptrCast(*MemBlock, allocation + @sizeOf(MemZone));
    mainzone.blocklist.next = block;
    mainzone.blocklist.prev = block;

    mainzone.blocklist.user = @ptrCast(*?*anyopaque, mainzone);
    mainzone.blocklist.tag = Z_Tag.Static;
    mainzone.rover = block;

    block.prev = &mainzone.blocklist;
    block.next = &mainzone.blocklist;
    block.user = null;
    block.size = mainzone.size - @sizeOf(MemZone);
}

/// You can pass `null` user if the tag is < Z_Tag.PurgeLevel
export fn Z_Malloc(requested_size: i32, tag: Z_Tag, user: ?*?*anyopaque) *anyopaque {
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

    if (base.prev.user == null)
        base = base.prev;

    var rover = base;
    const start = base.prev;

    while (true) {
        if (rover == start) {
            // scanned all the way around the list
            c.I_Error(@constCast("Z_Malloc: failed on allocation of %i bytes"), size);
        }

        if (rover.user != null) {
            if (@enumToInt(rover.tag) < @enumToInt(Z_Tag.PurgeLevel)) {
                // hit a block that can't be purged,
                // so move base past it
                base = rover.next;
                rover = rover.next;
            } else {
                // free the rover block (adding the size to base)

                // the rover can be the base block
                base = base.prev;
                c.Z_Free(@ptrCast([*]u8, rover) + @sizeOf(MemBlock));
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
        const newblock = @ptrCast(*MemBlock, @alignCast(@alignOf(MemBlock), @ptrCast([*]u8, base) + @intCast(usize, size)));
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
        @ptrCast(*[*]u8, user).* = @ptrCast([*]u8, base) + @sizeOf(MemBlock);
    } else {
        if (@enumToInt(tag) >= @enumToInt(Z_Tag.PurgeLevel)) {
            c.I_Error(@constCast("Z_Malloc: an owner is required for purgable blocks"));
        }

        // mark as in-use, but unowned
        // NOTE: Original doom source uses `2` but that is not aligned. To
        // avoid zig compiler complaint use the pointer alignment value instead.
        base.user = @intToPtr(?*?*anyopaque, alignment);
    }
    base.tag = tag;

    // next allocation will start looking here
    mainzone.rover = base.next;

    base.id = ZONEID;

    return @ptrCast(*anyopaque, @ptrCast([*]u8, base) + @sizeOf(MemBlock));
}

export fn Z_ChangeTag(ptr: *anyopaque, tag: Z_Tag) void {
    // TODO: Alignment is off, should be 8, prob results in inefficient access
    // to the allocations or their MemBlock headers. Consider fixing allocation
    // alignment. Might automatically fix itself once all the code is zig.
    // However then blocks will possibly require double the size? Also why is
    // `user` a pointer? Consider also maybe the header could be smaller and/or
    // look at how prboom redid the zone memory allocator.
    const block = &(@ptrCast([*]align(4) MemBlock, @alignCast(4, ptr)) - 1)[0];

    if (block.id != ZONEID) {
        // TODO: Restore line number display on this I_Error() call (consider stack trace in all I_Error() calls)
        c.I_Error(@constCast("Z_ChangeTag: freed a pointer without ZONEID"));
    }

    if (@enumToInt(tag) >= @enumToInt(Z_Tag.PurgeLevel) and @ptrToInt(block.user) < 0x100) {
        c.I_Error(@constCast("Z_ChangeTag: an owner is required for purgable blocks"));
    }

    block.tag = tag;
}
