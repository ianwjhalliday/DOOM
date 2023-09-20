// Emacs style mode select   -*- C++ -*- 
//-----------------------------------------------------------------------------
//
// $Id:$
//
// Copyright (C) 1993-1996 by id Software, Inc.
//
// This source is available for distribution and/or modification
// only under the terms of the DOOM Source Code License as
// published by id Software. All rights reserved.
//
// The source is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// FITNESS FOR A PARTICULAR PURPOSE. See the DOOM Source Code License
// for more details.
//
// $Log:$
//
// DESCRIPTION:
//	System interface for sound.
//
//-----------------------------------------------------------------------------

// static const char
// rcsid[] = "$Id: i_unix.c,v 1.5 1997/02/03 22:45:10 b1 Exp $";

#include <stdio.h>

#include "i_system.h"
#include "sounds.h"
#include "w_wad.h"
#include "doomstat.h"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#define TSF_IMPLEMENTATION
#include "tsf.h"

#define SAMPLERATE 11025

typedef struct {
    int handle;
    uint8_t volL;
    uint8_t volR;
    uint8_t* samples;
    uint16_t sampleRate;
    uint32_t sampleCount;
    uint32_t samplesPlayed;
} playingsfx_t;

#define NUMPLAYINGSOUNDS 16
static playingsfx_t playingSounds[NUMPLAYINGSOUNDS];
static int nextSoundHandle = 0;

static ma_device device;

void sfx_data(void* data, uint16_t* sampleRate, uint32_t* sampleCount, uint8_t** samples)
{
    // *formatNum = ((uint16*)data)[0]; // always 3, not needed
    *sampleRate = ((uint16_t*)data)[1]; // always 11025 except for super shotgun and item respawn which are 22050
    *sampleCount = ((uint32_t*)data)[1];
    *samples = ((uint8_t*)data) + 8; // This includes 16 padding bytes before and after the sound
}

uint32_t min(uint32_t a, uint32_t b)
{
    return a < b ? a : b;
}

void panVolumeToLR(int sep, int vol, uint8_t* volL, uint8_t* volR)
{
    int left = (254 - sep) * vol / 127 / 2;
    int right = sep * vol / 127 / 2;
    *volL = (uint8_t)left;
    *volR = (uint8_t)right;
}

void MUS_RenderSongSamples(int16_t* output, ma_uint32 frameCount);

void I_MADataCallback(ma_device* device, void* output, const void* input, ma_uint32 frameCount)
{
    MUS_RenderSongSamples(output, frameCount);

    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
    {
        if (playingSounds[i].handle == -1)
            continue;

        // To avoid issues with multi-threading read/write we use a copy here
        playingsfx_t playingSound = playingSounds[i];

        int16_t* out = (int16_t*)output;
        uint8_t* samples = playingSound.samples;
        uint16_t sampleRate = playingSound.sampleRate;
        uint32_t sampleCount = playingSound.sampleCount;
        uint32_t samplesPlayed = playingSound.samplesPlayed;
        uint32_t framesToCopy = min(frameCount, sampleCount - samplesPlayed);

        uint8_t* samplesStart = samples + samplesPlayed;
        uint8_t* samplesEnd = samplesStart + framesToCopy;

        uint8_t volL = playingSound.volL;
        uint8_t volR = playingSound.volR;

        for (uint8_t* sample = samplesStart; sample < samplesEnd; sample++)
        {
            int16_t sample16 = (*sample - 128) << 8;
            // volumes are values 0 through 15 hence divide by 15
            // FIX: Clipping can occur with 8 simultaneous sounds
            // It might be better to mix to a int32 buffer to allow
            // overlapping sounds the chance to cancel out and then
            // copy it over to the output buffer with a clip pass.
            // Alternatively could try scaling down the volume overall.
            // Chocolate Doom scales sounds by 0.65 to avoid clipping.
            // Use that here for now albeit it makes the game quieter.
            *out++ += (int16_t)(sample16 * ((float)volL / 15) * 0.65);
            *out++ += (int16_t)(sample16 * ((float)volR / 15) * 0.65);

            // HACK: a few sound effects are double sample rate so
            // drop every other sample to match 11025
            if (sampleRate == 22050)
                sample++;
        }

        samplesPlayed += framesToCopy;
        if (samplesPlayed >= sampleCount)
            playingSounds[i].handle = -1; // Sound finished playing, free the slot
        else
            playingSounds[i].samplesPlayed = samplesPlayed; // Else update the slot
    }
}

void I_InitMusic(void);
void I_InitSound(void)
{
    ma_device_config deviceConfig;

    fprintf(stderr, "I_InitSound\n");

    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
        playingSounds[i].handle = -1;

    deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format   = ma_format_s16;
    deviceConfig.playback.channels = 2;
    deviceConfig.sampleRate        = SAMPLERATE;
    deviceConfig.dataCallback      = I_MADataCallback;

    if (ma_device_init(NULL, &deviceConfig, &device) != MA_SUCCESS) {
        I_Error("I_InitSound: Failed to open playback device.\n");
    }

    if (ma_device_start(&device) != MA_SUCCESS) {
        ma_device_uninit(&device);
        I_Error("I_InitSound: Failed to start playback device.\n");
    }

    I_InitMusic();
}

void I_ShutdownSound(void)
{
    ma_device_uninit(&device);
}

// I_SetChannels I_UpdateSound and I_SubmitSound are unused in this implementation
void I_SetChannels(void) {}
void I_UpdateSound(void) {}
void I_SubmitSound(void) {}

void I_SetSfxVolume(int volume) {}

int I_StartSound(int id, int vol, int sep, int pitch, int priority)
{
    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
    {
        playingsfx_t* playingSound = &playingSounds[i];

        // Look for available slot
        if (playingSound->handle != -1)
            continue;

        sfx_data(S_sfx[id].data,
            &playingSound->sampleRate,
            &playingSound->sampleCount,
            &playingSound->samples);
        playingSound->samplesPlayed = 0;
        panVolumeToLR(sep, vol, &playingSound->volL, &playingSound->volR);
        // priority is ignored here; it is used in s_sound.c

        // Set handle last to avoid callback picking up the new sound before it
        // is fully initialized (because callback is on a separate thread).
        playingSound->handle = nextSoundHandle++;

        return playingSound->handle;
    }

    // Failed to find an available slot. Sound is dropped.
    fprintf(stderr, "I_StartSound: Failed to get playingSounds slot\n");
    return -1;
}

void I_StopSound(int handle)
{
    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
        if (playingSounds[i].handle == handle)
            playingSounds[i].handle = -1;
}

int I_SoundIsPlaying(int handle)
{
    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
        if (playingSounds[i].handle == handle)
            return 1;

    return 0;
}

void I_UpdateSoundParams(int handle, int vol, int sep, int pitch)
{
    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
        if (playingSounds[i].handle == handle)
            panVolumeToLR(sep, vol, &playingSounds[i].volL, &playingSounds[i].volR);
}

//
// Gets the sound lump for digital sounds.
//
// The reason this is I_ code is because there are alternatively PC Speaker
// sound lumps that were for the PC Speaker sound option.
//
// The "ds" prefix denotes digital sound lumps. "dp" prefix is PC Speaker.
//
int I_GetSfxLumpNum(sfxinfo_t* sfx)
{
    char namebuf[9];
    sprintf(namebuf, "ds%s", sfx->link ? sfx->link->name : sfx->name);
    return W_GetNumForName(namebuf);
}

tsf* soundfont = NULL;

void I_InitMusic(void)
{
    const char* sfFile = "soundfont/Roland SC-55 Presets.sf2";
    //const char* sfFile = "soundfont/Yamaha DB50XG Presets.sf2";
    //const char* sfFile = "soundfont/AWE64 Gold Presets.sf2";

    fprintf(stderr, "I_InitMusic\n");

    soundfont = tsf_load_filename(sfFile);
    if (!soundfont)
    {
        fprintf(stderr, "I_InitMusic: Failed to load soundfont '%s'. Music will not play.\n", sfFile);
    }

    tsf_set_output(soundfont, TSF_STEREO_INTERLEAVED, SAMPLERATE, snd_MusicVolume / 15.0 * 0.65);
}

void I_ShutdownMusic(void)
{
    tsf_close(soundfont);
}

void I_SetMusicVolume(int volume)
{
    tsf_set_volume(soundfont, volume / 15.0 * 0.65);
}

typedef struct {
    const char id[4]; // Valid data starts with "MUS" 0x1A
    uint16_t scoreLength;
    uint16_t scoreStart;
    uint16_t channelsPrimary;
    uint16_t channelsSecondary;
    uint16_t instrumentCount;
    uint16_t dummy;
    uint16_t* instruments;
} musheader_t;

typedef enum
{
    mus_releasenote     = 0,
    mus_playnote        = 1,
    mus_pitchwheel      = 2,
    mus_sysevent        = 3,
    mus_changectrllr    = 4,
    mus_unknown1        = 5,
    mus_scoreend        = 6,
    mus_unknown2        = 7,
} museventtype_t;

typedef struct {
    museventtype_t type;
    int channel;
    int data1;
    int data2;
    int delayTicks; // 140 Hz ticks
} musevent_t;

typedef struct {
    int handle;
    musheader_t* musheader;
    byte* firstEvent;
    byte* nextEvent;
    boolean loop;
    boolean playing;
    int delayFrames;
} song_t;

static int nextSongHandle = 0;

song_t currentSong; // Only one plays at a time

#define MUS_NUM_CHANNELS 16
int channelVol[MUS_NUM_CHANNELS];

// Map MUS channel to MIDI adjusting for percussion channel
int MUS_MapChannel(int channel)
{
    if (channel == 15)
        return 9;
    if (channel >= 9)
        return channel + 1;
    return channel;
}

int controllerMap[] =
{
    // MUS Change controller events (0-9)
    0,          // Instrument (patch, program) number
    0,          // (or 32?)    Bank select: 0 by default
    1,          // Modulation pot (frequency vibrato depth)
    7,          // Volume: 0-silent, ~100-normal, 127-loud
    10,         // Pan (balance) pot: 0-left, 64-center (default), 127-right
    11,         // Expression pot
    91,         // Reverb depth
    93,         // Chorus depth
    64,         // Sustain pedal (hold)
    67,         // Soft pedal
    // MUS System Events (10-14)
    120,        // All sounds off
    123,        // All notes off
    126,        // Mono
    127,        // Poly
    121,        // Reset all controllers
};

musevent_t MUS_ParseEvent(byte** eventstream)
{
    byte* p = *eventstream;

    int b = *p++;
    boolean last    = (b & 0b10000000) ? true : false;
    int eventtype   = (b & 0b01110000) >> 4;
    int channel     = (b & 0b00001111);
    int data1 = -1;
    int data2 = -1;
    int delayTickBits;
    int delayTicks = 0;

    if (eventtype <= mus_changectrllr)
        data1 = *p++;

    if (eventtype == mus_playnote && data1 & 0b10000000)
    {
        data1 &= 0b01111111;
        data2 = *p++;
    }

    if (eventtype == mus_changectrllr)
        data2 = *p++;

    while (last)
    {
        b = *p++;
        last            = b & 0b10000000 ? true : false;
        delayTickBits   = b & 0b01111111;

        delayTicks = delayTickBits + (delayTicks << 7);
    }

    *eventstream = p;
    musevent_t event = { eventtype, channel, data1, data2, delayTicks };
    return event;
}

void MUS_RenderSongSamples(int16_t* output, ma_uint32 frameCount)
{
    if (currentSong.handle == -1 || !currentSong.playing)
        return;

    // copy song and channel volumes locally because of multithreading
    song_t song = currentSong;
    int chVol[MUS_NUM_CHANNELS];
    memcpy(chVol, channelVol, MUS_NUM_CHANNELS*sizeof(int));

    // While still playing and still more frames to output
    while (song.playing && frameCount)
    {
        // Process events until one has a non-zero time delay
        while (song.delayFrames == 0)
        {
            musevent_t event = MUS_ParseEvent(&song.nextEvent);
            int channel = MUS_MapChannel(event.channel);

            switch (event.type)
            {
                case mus_releasenote:
                    tsf_channel_note_off(soundfont, channel, event.data1);
                    break;

                case mus_playnote:
                    if (event.data2 >= 0)
                        chVol[event.channel] = event.data2;
                    tsf_channel_note_on(soundfont, channel, event.data1, chVol[event.channel] / 127.0);
                    break;

                case mus_pitchwheel:
                    tsf_channel_set_pitchwheel(soundfont, channel, event.data1 * 64);
                    break;

                case mus_sysevent:
                    if (event.data1 >= 10 && event.data1 <= 14)
                    {
                        int numChannels = song.musheader->channelsPrimary + song.musheader->channelsSecondary;
                        int val = event.data1 == 12 ? numChannels : 0;
                        tsf_channel_midi_control(soundfont, channel, controllerMap[event.data1], val);
                    }
                    break;

                case mus_changectrllr:
                    if (event.data1 == 0)
                    {
                        // HACK: when channels are setup, clear all sounds to turn off notes still playing
                        // from previous looping track. Do this for every channel since not every song uses
                        // the same number of channels.
                        for (int ch = 0; ch < MUS_NUM_CHANNELS; ch += 1)
                            tsf_channel_midi_control(soundfont, ch, 120, 0);

                        tsf_channel_set_bank_preset(soundfont, channel, channel == 9 ? 128 : 0, event.data2);
                    }
                    else if (event.data1 >= 1 && event.data1 <= 9)
                        tsf_channel_midi_control(soundfont, channel, controllerMap[event.data1], event.data2);
                    break;

                case mus_scoreend:
                case mus_unknown1:
                case mus_unknown2:
                    break;
            }

            song.delayFrames = event.delayTicks / 140.0 * SAMPLERATE;

            if (event.type == mus_scoreend)
            {
                if (song.loop)
                    song.nextEvent = song.firstEvent;
                else
                    song.playing = false;
                break;
            }
        }

        // Render out current state until delayTicks worth of frames is rendered or output is full
        int renderCount = min(song.delayFrames, frameCount);
        tsf_render_short(soundfont, output, renderCount, 0);

        frameCount -= renderCount;
        song.delayFrames -= renderCount;
        output += renderCount * 2;
    }

    if (currentSong.handle == song.handle)
    {
        // still the same song, update globals
        currentSong.playing = song.playing;
        currentSong.nextEvent = song.nextEvent;
        currentSong.delayFrames = song.delayFrames;
        memcpy(channelVol, chVol, MUS_NUM_CHANNELS*sizeof(int));
    }
}

void I_PlaySong(int handle, int looping)
{
    if (currentSong.handle == -1)
        return;

    currentSong.playing = false;

    for (int i = 0; i < MUS_NUM_CHANNELS; i += 1)
        channelVol[i] = 127; // start channels at max volume

    currentSong.nextEvent = currentSong.firstEvent;
    currentSong.loop = looping ? true : false;
    currentSong.delayFrames = 0;
    currentSong.playing = true;
}

void I_PauseSong(int handle)
{
    if (currentSong.handle == -1)
        return;

    currentSong.playing = false;
}

void I_ResumeSong(int handle)
{
    if (currentSong.handle == -1)
        return;

    currentSong.playing = true;
}

void I_StopSong(int handle)
{
    if (currentSong.handle == -1)
        return;

    currentSong.playing = false;
}

void I_UnRegisterSong(int handle)
{
    if (currentSong.handle != handle)
        return;

    currentSong.playing = false;
    currentSong.handle = -1;
    currentSong.musheader = NULL;
    currentSong.firstEvent = NULL;
    currentSong.nextEvent = NULL;
}

int I_RegisterSong(byte* data)
{
    musheader_t* musheader = (musheader_t*)data;
    if (musheader->id[0] != 'M' ||
        musheader->id[1] != 'U' ||
        musheader->id[2] != 'S' ||
        musheader->id[3] != 0x1A)
        return -1;

    int handle = nextSongHandle++;
    currentSong.playing = false;
    currentSong.loop = false;
    currentSong.delayFrames = 0;
    currentSong.musheader = musheader;
    currentSong.firstEvent = data + musheader->scoreStart;
    currentSong.nextEvent = currentSong.firstEvent;
    currentSong.handle = handle;

    return handle;
}
