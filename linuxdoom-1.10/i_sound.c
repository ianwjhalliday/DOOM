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

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

typedef struct {
    int handle;
    int vol;
    int sep;
    int pitch;
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

void I_MADataCallback(ma_device* device, void* output, const void* input, ma_uint32 frameCount)
{
    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
    {
        if (playingSounds[i].handle == -1)
            continue;

        // To avoid issues with multi-threading read/write we use a copy here
        playingsfx_t playingSound = playingSounds[i];

        uint8_t* out = (uint8_t*)output;
        uint8_t* samples = playingSound.samples;
        uint32_t sampleCount = playingSound.sampleCount;
        uint32_t samplesPlayed = playingSound.samplesPlayed;
        uint32_t framesToCopy = min(frameCount, sampleCount - samplesPlayed);

        uint8_t* samplesStart = samples + samplesPlayed;
        uint8_t* samplesEnd = samplesStart + framesToCopy;

        for (uint8_t* sample = samplesStart; sample < samplesEnd; sample++)
        {
            // TODO: Mixing, volume, panning
            *out++ = *sample;
            *out++ = *sample;
        }

        samplesPlayed += framesToCopy;
        if (samplesPlayed >= sampleCount)
            playingSounds[i].handle = -1; // Sound finished playing, free the slot
        else
            playingSounds[i].samplesPlayed = samplesPlayed; // Else update the slot
    }
}

void I_InitSound(void)
{
    ma_device_config deviceConfig;

    fprintf(stderr, "I_InitSound\n");

    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
        playingSounds[i].handle = -1;

    deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format   = ma_format_u8;
    deviceConfig.playback.channels = 2;
    deviceConfig.sampleRate        = 11025;
    deviceConfig.dataCallback      = I_MADataCallback;

    if (ma_device_init(NULL, &deviceConfig, &device) != MA_SUCCESS) {
        I_Error("I_InitSound: Failed to open playback device.\n");
    }

    if (ma_device_start(&device) != MA_SUCCESS) {
        ma_device_uninit(&device);
        I_Error("I_InitSound: Failed to start playback device.\n");
    }
}

void I_ShutdownSound(void)
{
    ma_device_uninit(&device);
}

// I_SetChannels I_UpdateSound and I_SubmitSound are unused in this implementation
void I_SetChannels(void) {}
void I_UpdateSound(void) {}
void I_SubmitSound(void) {}

// TODO: Use these functions or use globals snd_SfxVolume and snd_MusicVolume directly?
void I_SetSfxVolume(int volume) {}
void I_SetMusicVolume(int volume) {}

int
I_StartSound
( int		id,
  int		vol,
  int		sep,
  int		pitch,
  int		priority )
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
        playingSound->vol = vol;
        playingSound->sep = sep;
        playingSound->pitch = pitch;
        // priority ignored

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

void
I_UpdateSoundParams
( int	handle,
  int	vol,
  int	sep,
  int	pitch)
{
    for (uint32_t i = 0; i < NUMPLAYINGSOUNDS; i += 1)
        if (playingSounds[i].handle == handle)
        {
            playingSounds[i].vol = vol;
            playingSounds[i].sep = sep;
            playingSounds[i].pitch = pitch;
        }
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
    sprintf(namebuf, "ds%s", sfx->name);
    return W_GetNumForName(namebuf);
}

void I_InitMusic(void)
{
    // TODO: This isn't called
}

void I_ShutdownMusic(void)
{
    // TODO:
}

void I_PlaySong(int handle, int looping)
{
    // TODO:
}

void I_PauseSong(int handle)
{
    // TODO:
}

void I_ResumeSong(int handle)
{
    // TODO:
}

void I_StopSong(int handle)
{
    // TODO:
}

void I_UnRegisterSong(int handle)
{
    // TODO:
}

int I_RegisterSong(void* data)
{
    // TODO:
    return -1;
}
