const zone = @import("z_zone.zig");
const M_Random = @import("m_random.zig").M_Random;
const I_ReadScreen = @import("i_video.zig").I_ReadScreen;
const v_video = @import("v_video.zig");
const V_DrawBlock = v_video.V_DrawBlock;
const V_MarkRect = v_video.V_MarkRect;

pub const WipeStyle = enum {
    // simple gradual pixel change for 8-bit only
    ColorXForm,

    // weird screen melt
    Melt,
};

// when zero, stop the wipe
var go = false;

var wipe_scr_start: [*]u8 = undefined;
var wipe_scr_end: [*]u8 = undefined;
var wipe_scr: [*]u8 = undefined;

fn wipe_shittyColMajorXform(array: [*]c_short, width: usize, height: usize) void {
    const dest = zone.alloc(c_short, width * height, .Static, null);
    defer zone.free(dest);

    for (0..height) |y| {
        for (0..width) |x| {
            dest[x * height + y] = array[y * width + x];
        }
    }

    @memcpy(array, dest);
}

fn wipe_initColorXForm(width: u32, height: u32) void {
    @memcpy(wipe_scr, wipe_scr_start[0 .. width * height]);
}

fn wipe_doColorXForm(width: u32, height: u32, ticks: usize) bool {
    var changed = false;

    var w = wipe_scr;
    const e = wipe_scr_end;

    for (0..width * height) |i| {
        if (w[i] > e[i]) {
            w[i] = @truncate(@max(w[i] -| ticks, e[i]));
            changed = true;
        } else if (w[i] < e[i]) {
            w[i] = @truncate(@min(w[i] +| ticks, e[i]));
            changed = true;
        }
    }

    return !changed;
}

fn wipe_exitColorXForm() void {}

var cols: []i32 = undefined;

fn wipe_initMelt(width: u32, height: u32) void {
    // copy start screen to main screen
    @memcpy(wipe_scr, wipe_scr_start[0 .. width * height]);

    // makes this wipe faster (in theory)
    // to have stuff in column-major format
    wipe_shittyColMajorXform(@ptrCast(@alignCast(wipe_scr_start)), width / 2, height);
    wipe_shittyColMajorXform(@ptrCast(@alignCast(wipe_scr_end)), width / 2, height);

    // setup initial column positions
    // (y<0 => not ready to scroll yet)
    cols = zone.alloc(i32, width, .Static, null);
    cols[0] = -@mod(M_Random(), 16);
    for (1..width) |i| {
        const r = @mod(M_Random(), 3) - 1;
        cols[i] = cols[i - 1] + r;
        if (cols[i] > 0) {
            cols[i] = 0;
        } else if (cols[i] == -16) {
            cols[i] = -15;
        }
    }
}

fn wipe_doMelt(width: u32, height: u32, ticks: usize) bool {
    var done = true;
    const halfwidth = width / 2;

    for (0..ticks) |_| {
        for (0..halfwidth) |i| {
            if (cols[i] < 0) {
                cols[i] += 1;
                done = false;
            } else if (cols[i] < height) {
                var dy = if (cols[i] < 16) cols[i] + 1 else 8;

                if (cols[i] + dy >= height) {
                    dy = @as(i32, @intCast(height)) - cols[i];
                }

                const se = @as([*]c_short, @ptrCast(@alignCast(wipe_scr_end))) + i * height + @as(usize, @intCast(cols[i]));
                const de = @as([*]c_short, @ptrCast(@alignCast(wipe_scr))) + @as(usize, @intCast(cols[i])) * halfwidth + i;

                var idx: usize = 0;
                for (0..@intCast(dy)) |j| {
                    de[idx] = se[j];
                    idx += halfwidth;
                }

                cols[i] += dy;
                const ss = @as([*]c_short, @ptrCast(@alignCast(wipe_scr_start))) + i * height;
                const ds = @as([*]c_short, @ptrCast(@alignCast(wipe_scr))) + @as(usize, @intCast(cols[i])) * halfwidth + i;
                idx = 0;
                for (0..height - @as(usize, @intCast(cols[i]))) |j| {
                    ds[idx] = ss[j];
                    idx += halfwidth;
                }

                done = false;
            }
        }
    }

    return done;
}

fn wipe_exitMelt() void {
    zone.free(cols);
}

pub fn StartScreen() void {
    wipe_scr_start = v_video.screens[2];
    I_ReadScreen(wipe_scr_start);
}

pub fn EndScreen(x: u32, y: u32, width: u32, height: u32) void {
    wipe_scr_end = v_video.screens[3];
    I_ReadScreen(wipe_scr_end);
    V_DrawBlock(x, y, 0, width, height, wipe_scr_start); // restore start scr.
}

pub fn ScreenWipe(wipe: WipeStyle, width: u32, height: u32, ticks: usize) bool {
    // initial stuff
    if (!go) {
        go = true;
        wipe_scr = v_video.screens[0];
        switch (wipe) {
            .ColorXForm => wipe_initColorXForm(width, height),
            .Melt => wipe_initMelt(width, height),
        }
    }

    // do a piece of wipe-in
    V_MarkRect(0, 0, width, height);
    const rc = switch (wipe) {
        .ColorXForm => wipe_doColorXForm(width, height, ticks),
        .Melt => wipe_doMelt(width, height, ticks),
    };

    // final stuff
    if (rc) {
        go = false;
        switch (wipe) {
            .ColorXForm => wipe_exitColorXForm(),
            .Melt => wipe_exitMelt(),
        }
    }

    return !go;
}
