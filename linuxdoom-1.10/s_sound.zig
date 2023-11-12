const c = @cImport({
    @cInclude("i_sound.h");
    @cInclude("p_mobj.h");
    @cInclude("r_main.h");
    @cInclude("tables.h");
});

const std = @import("std");

const doomstat = @import("doomstat.zig");

const g_game = @import("g_game.zig");

const I_Error = @import("i_system.zig").I_Error;

const m_fixed = @import("m_fixed.zig");
const FixedMul = m_fixed.FixedMul;
const FRACBITS = m_fixed.FRACBITS;

const M_Random = @import("m_random.zig").M_Random;

const sounds = @import("sounds.zig");
const SfxInfo = sounds.SfxInfo;
const MusicInfo = sounds.MusicInfo;
const Sfx = sounds.Sfx;
const Music = sounds.Music;

const w_wad = @import("w_wad.zig");
const W_CacheLumpNum = w_wad.W_CacheLumpNum;
const W_GetNumForName = w_wad.W_GetNumForName;

const z_zone = @import("z_zone.zig");

// when to clip out sounds
// Does not fit the large outdoor areas.
const S_CLIPPING_DIST = 1200 * 0x10000;

// Distance tp origin when sounds should be maxed out.
// This should relate to movement clipping resolution
// (see BLOCKMAP handling).
// Originally: (200*0x10000).
const S_CLOSE_DIST = 160 * 0x10000;


const S_ATTENUATOR = (S_CLIPPING_DIST - S_CLOSE_DIST) >> FRACBITS;

// Adjustable by menu.
const NORM_PITCH = 128;
const NORM_PRIORITY = 64;
const NORM_SEP = 128;

const S_STEREO_SWING = 96 * 0x10000;


const Channel = struct {
    sfxinfo: ?*SfxInfo,
    origin: ?*anyopaque,
    handle: c_int,
};


// the set of channels available
var channels: []Channel = undefined;

// These are not used, but should be (menu).
// Maximum volume of a sound effect.
// Internal default is max out of 0-15.
pub var snd_SfxVolume: c_int = 15;

// Maximum volume of music. Useless so far.
pub var snd_MusicVolume: c_int = 15;



// whether songs are mus_paused
var mus_paused = false;

// music currently being played
var mus_playing: ?*MusicInfo = null;

// following is set
//  by the defaults code in M_misc:
// number of channels available
export var numChannels: c_int = undefined;



//
// Initializes sound stuff, including volume
// Sets channels, SFX and music volume,
//  allocates channel buffer, sets S_sfx lookup.
//
pub fn S_Init(sfxVolume: c_int, musicVolume: c_int) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("S_Init: default sfx volume {}\n", .{sfxVolume}) catch {};

    // Whatever these did with DMX, these are rather dummies now.
    c.I_SetChannels();

    S_SetSfxVolume(sfxVolume);
    S_SetMusicVolume(musicVolume);

    // Allocating the internal channels for mixing
    // (the maximum numer of sounds rendered
    // simultaneously) within zone memory.
    channels = z_zone.alloc(Channel, @intCast(numChannels), .Static, null);

    // Free all channels for use
    for (channels) |*ch| {
        ch.* = Channel{
            .sfxinfo = null,
            .origin = null,
            .handle = 0,
        };
    }

    // no sounds are playing, and they are not mus_paused
    mus_paused = false;
}



//
// Per level startup code.
// Kills playing sounds at start of level,
//  determines music if any, changes music.
//
export fn S_Start() void {
    // kill all playing sounds at start of level
    //  (trust me - a good idea)
    for (channels, 0..) |ch, cnum| {
        if (ch.sfxinfo != null) {
            S_StopChannel(@intCast(cnum));
        }
    }

    // start new music for the level
    mus_paused = false;

    const mnum =
        if (doomstat.gamemode == .Commercial)
            @intFromEnum(Music.runnin) + g_game.gamemap - 1
        else if (g_game.gameepisode < 4)
            @intFromEnum(Music.e1m1) + (g_game.gameepisode-1)*9 + g_game.gamemap-1
        else @intFromEnum(switch (g_game.gamemap - 1) {
            // Song - Who? - Where?
            0 => Music.e3m4,    // American     e4m1
            1 => Music.e3m2,    // Romero       e4m2
            2 => Music.e3m3,    // Shawn        e4m3
            3 => Music.e1m5,    // American     e4m4
            4 => Music.e2m7,    // Tim  e4m5
            5 => Music.e2m4,    // Romero       e4m6
            6 => Music.e2m6,    // J.Anderson   e4m7 CHIRON.WAD
            7 => Music.e2m5,    // Shawn        e4m8
            8 => Music.e1m9,    // Tim          e4m9
            else => unreachable,
        });

    S_ChangeMusic(mnum, c.true);
}



fn S_StartSoundAtVolume(origin_p: ?*anyopaque, sfx_id: c_int, volume_p: c_int) void {
    // Debug.
    //fprintf( stderr,
    //         "S_StartSoundAtVolume: playing sound %d (%s)\n",
    //         sfx_id, S_sfx[sfx_id].name );*/

    // check for bogus sound #
    if (sfx_id < 1 or sfx_id >= @intFromEnum(Sfx.NUMSFX)) {
        I_Error("Bad sfx #: %d", sfx_id);
    }

    var sfx = &sounds.S_sfx[@intCast(sfx_id)];

    // Initialize sound parameters
    var pitch: c_int = NORM_PITCH;
    var priority: c_int = NORM_PRIORITY;
    var volume: c_int = volume_p;

    if (sfx.link != 0) {
        if (sfx.link < @intFromPtr(&sounds.S_sfx[0])) {
            // Convert zig's offset to actual address
            sfx.link = @intFromPtr(&sounds.S_sfx[sfx.link]);
        }
        pitch = sfx.pitch;
        priority = sfx.priority;
        volume += sfx.volume;

        if (volume < 1) {
            return;
        }

        if (volume > snd_SfxVolume) {
            volume = snd_SfxVolume;
        }
    }


    // Check to see if it is audible,
    //  and if not, modify the params
    const origin: ?*c.mobj_t = @ptrCast(@alignCast(origin_p));
    var sep: c_int = NORM_SEP;

    if (origin != null and origin != @as(*c.mobj_t, @ptrCast(&g_game.players[g_game.consoleplayer].mo[0]))) {
        const rc = S_AdjustSoundParams(
            @ptrCast(&g_game.players[g_game.consoleplayer].mo[0]),
            origin.?,
            &volume,
            &sep,
            &pitch
        );

        if (!rc) {
            return;
        }

        if (origin.?.x == g_game.players[g_game.consoleplayer].mo[0].x
            and origin.?.y == g_game.players[g_game.consoleplayer].mo[0].y) {
            sep = NORM_SEP;
        }
    }

    // hacks to vary the sfx pitches
    if (sfx_id >= @intFromEnum(Sfx.sawup) and sfx_id <= @intFromEnum(Sfx.sawhit)) {
        pitch += 8 - @mod(M_Random(), 16);
        pitch = @min(@max(pitch , 0), 255);
    } else if (sfx_id != @intFromEnum(Sfx.itemup) and sfx_id != @intFromEnum(Sfx.tink)) {
        pitch += 16 - @mod(M_Random(), 32);
        pitch = @min(@max(pitch , 0), 255);
    }

    // kill old sound
    S_StopSound(origin);

    // try to find a channel
    const cnum = S_getChannel(origin, sfx);

    if (cnum < 0) {
        return;
    }

    // get lumpnum if necessary
    if (sfx.lumpnum < 0) {
        sfx.lumpnum = c.I_GetSfxLumpNum(@ptrCast(sfx));
    }

    // cache data if necessary
    if (sfx.data == null) {
        sfx.data = @ptrCast(W_CacheLumpNum(sfx.lumpnum, .Music));
    }

    // increase the usefulness
    sfx.usefulness += 1;
    if (sfx.usefulness < 1) {
        sfx.usefulness = 1;
    }

    // Assigns the handle to one of the channels in the
    //  mix/output buffer.
    channels[@intCast(cnum)].handle = c.I_StartSound(
        sfx_id,
        //sfx.data,
        volume,
        sep,
        pitch,
        priority
    );
}


pub fn S_StartSound_Zig(origin: ?*anyopaque, sfx_id: Sfx) void {
    S_StartSound(origin, @intFromEnum(sfx_id));
}

export fn S_StartSound(origin: ?*anyopaque, sfx_id: c_int) void {
    S_StartSoundAtVolume(origin, sfx_id, snd_SfxVolume);
}



pub export fn S_StopSound(origin: ?*anyopaque) void {
    for (channels, 0..) |ch, cnum| {
        _ = ch;
        if (channels[cnum].sfxinfo != null and channels[cnum].origin == origin) {
            S_StopChannel(@intCast(cnum));
            break;
        }
    }
}



//
// Stop and resume music, during game PAUSE.
//
pub fn S_PauseSound() void {
    if (mus_playing != null and !mus_paused) {
        c.I_PauseSong(mus_playing.?.handle);
        mus_paused = true;
    }
}

pub fn S_ResumeSound() void {
    if (mus_playing != null and mus_paused) {
        c.I_ResumeSong(mus_playing.?.handle);
        mus_paused = false;
    }
}


//
// Updates music & sounds
//
pub fn S_UpdateSounds(listener_p: ?*anyopaque) void {
    for (channels, 0..) |ch, cnum| {
        if (ch.sfxinfo != null) {
            const sfx = ch.sfxinfo.?;

            if (c.I_SoundIsPlaying(ch.handle) != 0) {
                // initialize parameters
                var volume: c_int = snd_SfxVolume;
                var pitch: c_int = NORM_PITCH;
                var sep: c_int = NORM_SEP;

                if (sfx.link != 0) {
                    pitch = sfx.pitch;
                    volume += sfx.volume;
                    if (volume < 1) {
                        S_StopChannel(@intCast(cnum));
                        continue;
                    } else if (volume > snd_SfxVolume) {
                        volume = snd_SfxVolume;
                    }
                }

                // check non-local sounds for distance clipping
                //  or modify their params
                if (ch.origin != null and listener_p != ch.origin) {
                    const listener: *c.mobj_t = @ptrCast(@alignCast(listener_p));
                    const audible = S_AdjustSoundParams(
                        listener,
                        @ptrCast(@alignCast(ch.origin)),
                        &volume,
                        &sep,
                        &pitch);

                    if (!audible) {
                        S_StopChannel(@intCast(cnum));
                    } else {
                        c.I_UpdateSoundParams(ch.handle, volume, sep, pitch);
                    }
                }
            } else {
                // if channel is allocated but sound has stopped,
                //  free it
                S_StopChannel(@intCast(cnum));
            }
        }
    }
}


pub fn S_SetMusicVolume(volume: c_int) void {
    if (volume < 0 or volume > 127) {
        I_Error("Attempt to set music volume at %d", volume);
    }

    c.I_SetMusicVolume(volume);
    snd_MusicVolume = volume;
}



pub fn S_SetSfxVolume(volume: c_int) void {
    if (volume < 0 or volume > 127) {
        I_Error("Attempt to set sfx volume at %d", volume);
    }

    snd_SfxVolume = volume;
}

//
// Starts some music with the music id found in sounds.h.
//
pub export fn S_StartMusic(m_id: c_int) void {
    S_ChangeMusic(m_id, c.false);
}

pub export fn S_ChangeMusic(musicnum: c_int, looping: c_int) void {
    if (musicnum <= @intFromEnum(Music.None) or musicnum >= @intFromEnum(Music.NUMMUSIC)) {
        I_Error("Bad music number %d", musicnum);
        return;
    }

    const music = &sounds.S_music[@intCast(musicnum)];

    if (mus_playing == music) {
        return;
    }

    // shutdown old music
    S_StopMusic();

    // get lumpnum if neccessary
    if (music.lumpnum == 0) {
        var namebuf: [9]u8 = undefined;
        _ = std.fmt.bufPrintZ(&namebuf, "d_{s}", .{music.name}) catch unreachable;
        music.lumpnum = W_GetNumForName(&namebuf);
    }

    // load & register it
    music.data = @ptrCast(W_CacheLumpNum(music.lumpnum, .Music));
    music.handle = c.I_RegisterSong(music.data);

    // play it
    c.I_PlaySong(music.handle, looping);

    mus_playing = music;
}


fn S_StopMusic() void {
    if (mus_playing != null) {
        if (mus_paused) {
            c.I_ResumeSong(mus_playing.?.handle);
        }

        c.I_StopSong(mus_playing.?.handle);
        c.I_UnRegisterSong(mus_playing.?.handle);
        z_zone.Z_ChangeTag(@constCast(mus_playing.?.data), .Cache);

        mus_playing.?.data = null;
        mus_playing = null;
    }
}



fn S_StopChannel(cnum: c_int) void {
    const ch = &channels[@intCast(cnum)];

    if (ch.sfxinfo != null) {
        // stop the sound playing
        if (c.I_SoundIsPlaying(ch.handle) != 0) {
            c.I_StopSound(ch.handle);
        }

        // degrade usefulness of sound data
        ch.sfxinfo.?.usefulness -= 1;

        ch.sfxinfo = null;
    }
}



//
// Changes volume, stereo-separation, and pitch variables
//  from the norm of a sound effect to be played.
// If the sound is not audible, returns a 0.
// Otherwise, modifies parameters and returns 1.
//
fn S_AdjustSoundParams(listener: *c.mobj_t, source: *c.mobj_t, vol: *c_int, sep: *c_int, pitch: *c_int) bool {
    _ = pitch;
    // calculate the distance to sound origin
    //  and clip it if necessary
    const adx = std.math.absInt(listener.x - source.x) catch unreachable;
    const ady = std.math.absInt(listener.y - source.y) catch unreachable;

    // From _GG1_ p.428. Appox. eucledian distance fast.
    var approx_dist = adx + ady - ((if (adx < ady) adx else ady) >> 1);

    if (g_game.gamemap != 8 and approx_dist > S_CLIPPING_DIST) {
        return false;
    }

    // angle of source to listener
    var angle = c.R_PointToAngle2(listener.x,
                            listener.y,
                            source.x,
                            source.y);

    if (angle > listener.angle) {
        angle = angle - listener.angle;
    } else {
        angle = angle + (0xffffffff - listener.angle);
    }

    angle >>= c.ANGLETOFINESHIFT;

    // stereo separation
    sep.* = 128 - (FixedMul(S_STEREO_SWING, c.finesine[angle]) >> FRACBITS);

    // volume calculation
    if (approx_dist < S_CLOSE_DIST) {
        vol.* = snd_SfxVolume;
    } else if (g_game.gamemap == 8) {
        if (approx_dist > S_CLIPPING_DIST) {
            approx_dist = S_CLIPPING_DIST;
        }

        vol.* =
            15 + @divTrunc(
                (snd_SfxVolume - 15) * ((S_CLIPPING_DIST - approx_dist) >> FRACBITS),
                S_ATTENUATOR);
    } else {
        // distance effect
        vol.* = @divTrunc(
            snd_SfxVolume * ((S_CLIPPING_DIST - approx_dist) >> FRACBITS),
            S_ATTENUATOR);
    }

    return vol.* > 0;
}




//
// S_getChannel :
//   If none available, return -1.  Otherwise channel #.
//
fn S_getChannel(origin: ?*anyopaque, sfxinfo: *SfxInfo) c_int {
    // Find an open channel
    const cnum = for (channels, 0..) |ch, cn| {
        if (ch.sfxinfo == null or origin != null and ch.origin == origin) {
            break cn;
        }
    } else for (channels, 0..) |ch, cn| {
        // None available. Look for lower priority.
        if (ch.sfxinfo.?.priority >= sfxinfo.priority) {
            // Kick out lower priority.
            break cn;
        }
    } else {
        // FUCK!  No lower priority.  Sorry, Charlie.    
        return -1;
    };

    const ch = &channels[cnum];
    if (ch.sfxinfo != null) {
        S_StopChannel(@intCast(cnum));
    }

    // channel is decided to be cnum.
    ch.sfxinfo = sfxinfo;
    ch.origin = origin;

    return @intCast(cnum);
}
