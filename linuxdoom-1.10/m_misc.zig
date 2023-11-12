const c = @cImport({
    @cInclude("doomtype.h");
    @cInclude("doomstat.h");
    @cInclude("dstrings.h");
});

const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;
const zone = @import("z_zone.zig");
const g_game = @import("g_game.zig");
const I_Error = @import("i_system.zig").I_Error;
const I_ReadScreen = @import("i_video.zig").I_ReadScreen;
const M_CheckParm = @import("m_argv.zig").M_CheckParm;
const m_argv = @import("m_argv.zig");
const m_menu = @import("m_menu.zig");
const s_sound = @import("s_sound.zig");
const W_CacheLumpName = @import("w_wad.zig").W_CacheLumpName;
const doomdef = @import("doomdef.zig");
const SCREENWIDTH = doomdef.SCREENWIDTH;
const SCREENHEIGHT = doomdef.SCREENHEIGHT;

extern var basedefault: [1023:0]u8;
extern var screens: [5][*]u8;

//
// M_WriteFile
//
pub fn M_WriteFile(name: []const u8, source: []const u8) bool {
    const flags = os.O.WRONLY | os.O.CREAT | os.O.TRUNC;
    const handle = os.open(name, flags, 0o666) catch {
        return false;
    };
    defer os.close(handle);

    const count = os.write(handle, source) catch {
        return false;
    };
    if (count < source.len) {
        return false;
    }

    return true;
}


//
// M_ReadFile
//
pub fn M_ReadFile(name: []const u8) []u8 {
    const handle = os.open(name, os.O.RDONLY, 0o666) catch {
        I_Error("Couldn't read file %s", name.ptr);
    };

    const fileinfo = os.fstat(handle) catch {
        I_Error("Couldn't read file %s", name.ptr);
    };

    const length: c_int = @intCast(fileinfo.size);
    const buf = zone.alloc(u8, @intCast(length), .Static, null);

    const count = os.read(handle, buf) catch {
        I_Error("Couldn't read file %s", name.ptr);
    };
    if (count < length) {
        I_Error("Couldn't read file %s", name.ptr);
    }

    return buf;
}


//
// DEFAULTS
//
export var usemouse: c_int = 0;
export var usejoystick: c_int = 0;

extern var key_right: c_int;
extern var key_left: c_int;
extern var key_up: c_int;
extern var key_down: c_int;

extern var key_strafeleft: c_int;
extern var key_straferight: c_int;

extern var key_fire: c_int;
extern var key_use: c_int;
extern var key_strafe: c_int;
extern var key_speed: c_int;

extern var mousebfire: c_int;
extern var mousebstrafe: c_int;
extern var mousebforward: c_int;

extern var joybfire: c_int;
extern var joybstrafe: c_int;
extern var joybuse: c_int;
extern var joybspeed: c_int;

extern var usegamma: c_int;

// machine-independent sound params
extern var numChannels: c_int;

extern var chat_macros: [10][*:0]const u8;

pub const Default = struct {
    name: [*:0]const u8,
    location: *c_int,
    defaultvalue: Value,

    const Value = union(enum) {
        int: c_int,
        str: [*:0]const u8,
    };

    pub fn int(name: [*:0]const u8, location: *c_int, defaultvalue: c_int) Default {
        return Default{
            .name = name,
            .location = location,
            .defaultvalue = Value{.int = defaultvalue},
        };
    }

    pub fn str(name: [*:0]const u8, location: *[*:0]const u8, defaultvalue: [*:0]const u8) Default {
        return Default{
            .name = name,
            .location = @ptrCast(location),
            .defaultvalue = Value{.str = defaultvalue},
        };
    }
};

const defaults = [_]Default{
    Default.int("mouse_sensitivity", &m_menu.mouseSensitivity, 5),
    Default.int("sfx_volume", &s_sound.snd_SfxVolume, 8),
    Default.int("music_volume", &s_sound.snd_MusicVolume, 8),
    Default.int("show_messages", &m_menu.showMessages, 1),

    // #ifdef NORMALUNIX
    Default.int("key_right", &key_right, doomdef.KEY_RIGHTARROW),
    Default.int("key_left", &key_left, doomdef.KEY_LEFTARROW),
    Default.int("key_up", &key_up, doomdef.KEY_UPARROW),
    Default.int("key_down", &key_down, doomdef.KEY_DOWNARROW),
    Default.int("key_strafeleft", &key_strafeleft, ','),
    Default.int("key_straferight", &key_straferight, '.'),

    Default.int("key_fire", &key_fire, doomdef.KEY_RCTRL),
    Default.int("key_use", &key_use, ' '),
    Default.int("key_strafe", &key_strafe, doomdef.KEY_RALT),
    Default.int("key_speed", &key_speed, doomdef.KEY_RSHIFT),
    // #endif

    Default.int("use_mouse", &usemouse, 1),
    Default.int("mouseb_fire", &mousebfire, 0),
    Default.int("mouseb_strafe", &mousebstrafe, 1),
    Default.int("mouseb_forward", &mousebforward, 2),

    Default.int("use_joystick", &usejoystick, 0),
    Default.int("joyb_fire", &joybfire, 0),
    Default.int("joyb_strafe", &joybstrafe, 1),
    Default.int("joyb_use", &joybuse, 3),
    Default.int("joyb_speed", &joybspeed, 2),

    Default.int("screenblocks", &m_menu.screenblocks, 9),
    Default.int("detaillevel", &m_menu.detailLevel, 0),

    Default.int("snd_channels", &numChannels, 3),

    Default.int("usegamma", &usegamma, 0),

    Default.str("chatmacro0", &chat_macros[0], c.HUSTR_CHATMACRO0),
    Default.str("chatmacro1", &chat_macros[1], c.HUSTR_CHATMACRO1),
    Default.str("chatmacro2", &chat_macros[2], c.HUSTR_CHATMACRO2),
    Default.str("chatmacro3", &chat_macros[3], c.HUSTR_CHATMACRO3),
    Default.str("chatmacro4", &chat_macros[4], c.HUSTR_CHATMACRO4),
    Default.str("chatmacro5", &chat_macros[5], c.HUSTR_CHATMACRO5),
    Default.str("chatmacro6", &chat_macros[6], c.HUSTR_CHATMACRO6),
    Default.str("chatmacro7", &chat_macros[7], c.HUSTR_CHATMACRO7),
    Default.str("chatmacro8", &chat_macros[8], c.HUSTR_CHATMACRO8),
    Default.str("chatmacro9", &chat_macros[9], c.HUSTR_CHATMACRO9),
};

var defaultfile: []const u8 = undefined;

//
// M_SaveDefaults
//
pub fn M_SaveDefaults() void {
    const stderr = io.getStdErr().writer();
    stderr.print("M_SaveDefaults: Saving to '{s}'\n", .{defaultfile}) catch {};

    const f = fs.cwd().createFile(defaultfile, .{}) catch {
        return; // can't write the file, but don't complain
    };
    defer f.close();

    var buf_stream = io.bufferedWriter(f.writer());
    const st = buf_stream.writer();
    defer buf_stream.flush() catch {};

    for (defaults) |default| {
        switch (default.defaultvalue) {
            .int => st.print("{s}\t\t{}\n", .{default.name, default.location.*}) catch {},
            .str => st.print("{s}\t\t\"{s}\"\n", .{default.name, @as(*[*:0]const u8, @ptrCast(@alignCast(default.location))).*}) catch {},
        }
    }
}

//
// M_LoadDefaults
//
pub fn M_LoadDefaults() void {
    // set everything to base values
    for (defaults) |default| {
        switch (default.defaultvalue) {
            .int => |i| default.location.* = i,
            .str => |s| @as(*[*:0]const u8, @ptrCast(@alignCast(default.location))).* = s,
        }
    }

    // check for a custom default file
    const arg_i: usize = @intCast(M_CheckParm("-config"));
    if (arg_i > 0 and arg_i < m_argv.myargc - 1) {
        defaultfile = mem.span(m_argv.myargv[arg_i + 1]);
        io.getStdOut().writer().print("\tdefault file: {s}\n", .{defaultfile}) catch {};
    } else {
        defaultfile = mem.span(@as([*:0]u8, &basedefault));
    }

    const stderr = io.getStdErr().writer();

    // read the file in, overriding any set defaults
    if (fs.cwd().openFile(defaultfile, .{})) |f| {
        defer f.close();

        var buf_stream = io.bufferedReader(f.reader());
        const st = buf_stream.reader();

        var line: [256]u8 = undefined;
        var line_fbs = io.fixedBufferStream(&line);
        const writer = line_fbs.writer();

        while (true) {
            line_fbs.reset();

            // Grab a line at at time and split it into the name and the value
            st.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => stderr.print("M_LoadDefaults: error reading file: {s}\n", .{defaultfile}) catch {},
            };
            var it = mem.tokenizeAny(u8, line_fbs.getWritten(), " \t");

            const name = it.next() orelse { break; };
            const value = it.rest();

            const default = for (&defaults) |*d| {
                if (mem.eql(u8, mem.span(d.name), name)) break d;
            } else {
                continue; // skip unknown default name
            };

            if (value[0] == '"') {
                // get a string default
                const s = std.heap.raw_c_allocator.dupeZ(u8, value[1..value.len-1]) catch unreachable;
                @as(*[*:0]const u8, @ptrCast(@alignCast(default.location))).* = s;
            } else {
                // assume an integer default
                const i = std.fmt.parseInt(c_int, value, 0) catch {
                    stderr.print("M_LoadDefaults: couldn't parse integer: '{s}'\n", .{value}) catch {};
                    continue;
                };
                default.location.* = i;
            }
        }
    } else |_| {
        stderr.print("M_LoadDefaults: couldn't open file: {s}\n", .{defaultfile}) catch {};
    }
}

const PCX = extern struct {
    manufacturer: u8,
    version: u8,
    encoding: u8,
    bits_per_pixel: u8,

    xmin: u16,
    ymin: u16,
    xmax: u16,
    ymax: u16,

    hres: u16,
    vres: u16,

    palette: [48]u8,

    reserved: u8,
    color_planes: u8,
    bytes_per_line: u16,
    palette_type: u16,

    filler: [58]u8,
    data: u8,   // unbounded
};


//
// WritePCXfile
//
fn WritePCXfile(filename: []const u8, data: [*]const u8, width: c_int, height: c_int, palette: [*]const u8) void {
    // PCX has alignment 2 so alloc a u16 buffer rather than a u8 buffer
    var pcx_buffer = zone.alloc(u16, @intCast(width*height+500), .Static, null);
    defer zone.free(pcx_buffer);

    const pcx: *PCX = @ptrCast(pcx_buffer.ptr);
    pcx.manufacturer = 0x0a;    // PCX id
    pcx.version = 5;            // 256 color
    pcx.encoding = 1;           // uncompressed
    pcx.bits_per_pixel = 8;     // 256 color
    pcx.xmin = 0;
    pcx.ymin = 0;
    pcx.xmax = mem.nativeToLittle(u16, @as(u16, @intCast(width-1)));
    pcx.ymax = mem.nativeToLittle(u16, @as(u16, @intCast(height-1)));
    pcx.hres = mem.nativeToLittle(u16, @as(u16, @intCast(width)));
    pcx.vres = mem.nativeToLittle(u16, @as(u16, @intCast(height)));
    @memset(&pcx.palette, 0);
    pcx.color_planes = 1;       // chunky image
    pcx.bytes_per_line = mem.nativeToLittle(u16, @as(u16, @intCast(width)));
    pcx.palette_type = mem.nativeToLittle(u16, @as(u16, @intCast(2)));  // not a grey scale
    @memset(&pcx.filler, 0);


    // pack the image
    var pack: [*]u8 = @ptrCast(&pcx.data);
    for (data[0..@intCast(width*height)]) |d| {
        if (d & 0xc0 == 0xc0) {
            pack[0] = 0xc1;
            pack += 1;
        }
        pack[0] = d;
        pack += 1;
    }

    // write the palette
    pack[0] = 0x0c; // palette ID byte
    pack += 1;
    for (palette[0..768]) |p| {
        pack[0] = p;
        pack += 1;
    }

    // write output file
    const length = @intFromPtr(pack) - @intFromPtr(pcx_buffer.ptr);
    _ = M_WriteFile(filename, mem.sliceAsBytes(pcx_buffer)[0..length]);
}

//
// M_ScreenShot
//
pub fn M_ScreenShot() void {
    // munge planar buffer to linear
    const linear = screens[2];
    I_ReadScreen(linear);

    // find a file name to save it to
    var lbmname: [12]u8 = undefined;
    var name: []u8 = undefined;
    for (0..100) |i| {
        name = std.fmt.bufPrint(&lbmname, "DOOM{d:0>2}.pcx", .{i}) catch unreachable;
        os.access(name, 0) catch {
            break;  // file doesn't exist
        };
    } else {
        I_Error("M_ScreenShot: Couldn't create a PCX");
    }

    WritePCXfile(name, linear, SCREENWIDTH, SCREENHEIGHT, @ptrCast(W_CacheLumpName("PLAYPAL", .Cache)));

    // TODO: message field should be []const u8, remove @constCast here
    g_game.players[g_game.consoleplayer].message = @constCast("screen shot");
}
