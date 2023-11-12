const c = @cImport({
    @cInclude("doomtype.h");
    @cInclude("doomstat.h");
    @cInclude("dstrings.h");
    @cInclude("hu_stuff.h");
    @cInclude("r_defs.h");
    @cInclude("r_main.h");
    @cInclude("v_video.h");
});

const std = @import("std");
const fmt = std.fmt;
const io = std.io;
const mem = std.mem;
const os = std.os;

const d_main = @import("d_main.zig");
const D_StartTitle = d_main.D_StartTitle;
const doomdef = @import("doomdef.zig");
const doomstat = @import("doomstat.zig");
const g_game = @import("g_game.zig");
const G_DeferedInitNew = g_game.G_DeferedInitNew;
const G_LoadGame = g_game.G_LoadGame;
const G_SaveGame = g_game.G_SaveGame;
const G_ScreenShot = g_game.G_ScreenShot;
const i_system = @import("i_system.zig");
const I_GetTime = i_system.I_GetTime;
const I_Quit = i_system.I_Quit;
const I_WaitVBL = i_system.I_WaitVBL;
const i_video = @import("i_video.zig");
const I_PauseMouseCapture = i_video.I_PauseMouseCapture;
const I_ResumeMouseCapture = i_video.I_ResumeMouseCapture;
const I_SetPalette = i_video.I_SetPalette;
const M_CheckParm = @import("m_argv.zig").M_CheckParm;
const s_sound = @import("s_sound.zig");
const S_SetMusicVolume = s_sound.S_SetMusicVolume;
const S_SetSfxVolume = s_sound.S_SetSfxVolume;
const S_StartSound = s_sound.S_StartSound_Zig;
const W_CacheLumpName = @import("w_wad.zig").W_CacheLumpName;

const Event = d_main.Event;
const Sfx = @import("sounds.zig").Sfx;
const Skill = doomdef.Skill;
const Z_Tag = @import("z_zone.zig").Z_Tag;

const SCREENWIDTH = doomdef.SCREENWIDTH;

extern var hu_font: [c.HU_FONTSIZE]*c.patch_t;
extern var message_dontfuckwithme: c.boolean;

extern var chat_on: c.boolean;          // in heads-up code

//
// defaulted values
//
pub var mouseSensitivity: c_int = 0;       // has default

// Show messages has default, 0 = off, 1 = on
// TODO: Would be easier if this is usize for array indexing
pub export var showMessages: c_int = 0;


// Blocky mode, has default, 0 = high, 1 = normal
// TODO: Would be easier if this is a usize for array indexing
pub export var detailLevel: c_int = 0;
pub export var screenblocks: c_int = 0;        // has default

// temp for screenblocks (0-9)
var screenSize: c_int = 0;

// -1 = no quicksave slot picked!
var quickSaveSlot: c_int = 0;

 // 1 = message to be printed
var messageToPrint = false;
// ...and here is the message string!
var messageString: [:0]const u8 = undefined;

var messageLastMenuActive = false;

// timed message = no input from user
var messageNeedsInput = false;

var messageRoutine: ?*const fn (response: c_int) void = undefined;

const SAVESTRINGSIZE = 24;

var gammamsg = [5][*:0]const u8{
    c.GAMMALVL0,
    c.GAMMALVL1,
    c.GAMMALVL2,
    c.GAMMALVL3,
    c.GAMMALVL4
};

// we are going to be entering a savegame string
var saveStringEnter: c_int = 0;
var saveSlot: u8 = 0;        // which slot to save in
var saveCharIndex: u8 = 0;   // which char we're editing

// old save description before edit
var saveOldString: [SAVESTRINGSIZE-1:0]u8 = undefined;

pub var inhelpscreens = false;
pub var menuactive = false;

const SKULLXOFF = 32;
const LINEHEIGHT = 16;

var savegamestrings: [10][SAVESTRINGSIZE-1:0]u8 = undefined;

var endstring: [160]u8 = undefined;

fn W_CacheLumpNameAsPatch(name: [*]const u8, tag: Z_Tag) *c.patch_t {
    return @ptrCast(@alignCast(W_CacheLumpName(name, tag)));
}


//
// MENU TYPEDEFS
//
const MenuItem = struct {
    // 0 = no cursor here, 1 = ok, 2 = arrows ok
    status: c_short,

    name: [*:0]const u8,

    // choice = menu item #.
    // if status = 2,
    //   choice=0:leftarrow,1:rightarrow
    routine: ?*const fn (choice: c_int) void,

    // hotkey in menu
    alphaKey: u8,
};



const Menu = struct {
    numitems: u16,              // # of menu items
    prevMenu: ?*Menu,           // previous menu
    menuitems: [*]MenuItem,     // menu items
    routine: *const fn () void, // draw routine
    x: u16,
    y: u16,                     // x,y of menu
    lastOn: u16,                // last item user was on in menu
};

var itemOn: u16 = 0;            // menu item skull is on
var skullAnimCounter: c_short = 0;  // skull animation counter
var whichSkull: usize = 0;          // which skull to draw

// graphic name of skulls
const skullName = [2][*:0]const u8{"M_SKULL1","M_SKULL2"};

// current menudef
var currentMenu: *Menu = &MainDef;



//
// DOOM MENU
//
const MainMenuEnum = enum(c_int) {
    Newgame = 0,
    Options,
    LoadGame,
    SaveGame,
    ReadThis,
    QuitDoom,
    MainMenuCount,
};

var MainMenu = [_]MenuItem{
    .{.status = 1, .name = "M_NGAME", .routine = &M_NewGame, .alphaKey = 'n'},
    .{.status = 1, .name = "M_OPTION", .routine = &M_Options, .alphaKey = 'o'},
    .{.status = 1, .name = "M_LOADG", .routine = &M_LoadGame, .alphaKey = 'l'},
    .{.status = 1, .name = "M_SAVEG", .routine = &M_SaveGame, .alphaKey = 's'},
    // Another hickup with Special edition.
    .{.status = 1, .name = "M_RDTHIS", .routine = &M_ReadThis, .alphaKey = 'r'},
    .{.status = 1, .name = "M_QUITG", .routine = &M_QuitDOOM, .alphaKey = 'q'},
};

var MainDef = Menu{
    .numitems = @intFromEnum(MainMenuEnum.MainMenuCount),
    .prevMenu = null,
    .menuitems = &MainMenu,
    .routine = &M_DrawMainMenu,
    .x = 97,
    .y = 64,
    .lastOn = 0,
};


//
// EPISODE SELECT
//
const Episodes = enum(c_int) {
    Ep1,
    Ep2,
    Ep3,
    Ep4,
    EpisodesCount,
};

var EpisodeMenu = [_]MenuItem{
    .{.status = 1, .name = "M_EPI1", .routine = &M_Episode, .alphaKey = 'k'},
    .{.status = 1, .name = "M_EPI2", .routine = &M_Episode, .alphaKey = 't'},
    .{.status = 1, .name = "M_EPI3", .routine = &M_Episode, .alphaKey = 'i'},
    .{.status = 1, .name = "M_EPI4", .routine = &M_Episode, .alphaKey = 't'}
};

var EpiDef = Menu{
    .numitems = @intFromEnum(Episodes.EpisodesCount),
    .prevMenu = &MainDef,
    .menuitems = &EpisodeMenu,
    .routine = &M_DrawEpisode,
    .x = 48,
    .y = 63,
    .lastOn = @intFromEnum(Episodes.Ep1),
};


//
// NEW GAME
//
const NewGameEnum = enum(c_int) {
    KillThings,
    TooRough,
    HurtMe,
    Violence,
    Nightmare,
    NewGameCount,
};

var NewGameMenu = [_]MenuItem{
    .{.status = 1, .name = "M_JKILL", .routine = &M_ChooseSkill, .alphaKey = 'i'},
    .{.status = 1, .name = "M_ROUGH", .routine = &M_ChooseSkill, .alphaKey = 'h'},
    .{.status = 1, .name = "M_HURT", .routine = &M_ChooseSkill, .alphaKey = 'h'},
    .{.status = 1, .name = "M_ULTRA", .routine = &M_ChooseSkill, .alphaKey = 'u'},
    .{.status = 1, .name = "M_NMARE", .routine = &M_ChooseSkill, .alphaKey = 'n'}
};

var NewDef = Menu{
    .numitems = @intFromEnum(NewGameEnum.NewGameCount),
    .prevMenu = &EpiDef,
    .menuitems = &NewGameMenu,
    .routine = &M_DrawNewGame,
    .x = 48,
    .y = 63,
    .lastOn = @intFromEnum(NewGameEnum.HurtMe),
};



//
// OPTIONS MENU
//
const OptionsEnum = enum(c_int) {
    EndGame,
    Messages,
    Detail,
    ScrnSize,
    Option_empty1,
    MouseSens,
    Option_empty2,
    SoundVol,
    OptionsCount,
};

var OptionsMenu = [_]MenuItem{
    .{.status = 1, .name = "M_ENDGAM", .routine = &M_EndGame, .alphaKey = 'e'},
    .{.status = 1, .name = "M_MESSG", .routine = &M_ChangeMessages, .alphaKey = 'm'},
    .{.status = 1, .name = "M_DETAIL", .routine = &M_ChangeDetail, .alphaKey = 'g'},
    .{.status = 2, .name = "M_SCRNSZ", .routine = &M_SizeDisplay, .alphaKey = 's'},
    .{.status = -1, .name =  "", .routine = null, .alphaKey = 0},
    .{.status = 2, .name = "M_MSENS", .routine = &M_ChangeSensitivity, .alphaKey = 'm'},
    .{.status = -1, .name =  "", .routine = null, .alphaKey = 0},
    .{.status = 1, .name = "M_SVOL", .routine = &M_Sound, .alphaKey = 's'}
};

var OptionsDef = Menu{
    .numitems = @intFromEnum(OptionsEnum.OptionsCount),
    .prevMenu = &MainDef,
    .menuitems = &OptionsMenu,
    .routine = &M_DrawOptions,
    .x = 60,
    .y = 37,
    .lastOn = 0,
};


//
// Read This! MENU 1 & 2
//
const ReadEnum1 = enum(c_int) {
    RdThsEmpty1,
    ReadCount,
};

var ReadMenu1 = [_]MenuItem{
    .{.status = 1, .name = "", .routine = &M_ReadThis2, .alphaKey = 0}
};

var ReadDef1 = Menu{
    .numitems = @intFromEnum(ReadEnum1.ReadCount),
    .prevMenu = &MainDef,
    .menuitems = &ReadMenu1,
    .routine = &M_DrawReadThis1,
    .x = 280,
    .y = 185,
    .lastOn = 0,
};

const ReadEnum2 = enum {
    RdThsEmpty2,
    ReadCount,
};

var ReadMenu2 = [_]MenuItem{
    .{.status = 1, .name = "", .routine = &M_FinishReadThis, .alphaKey = 0}
};

var ReadDef2 = Menu{
    .numitems = @intFromEnum(ReadEnum2.ReadCount),
    .prevMenu = &ReadDef1,
    .menuitems = &ReadMenu2,
    .routine = &M_DrawReadThis2,
    .x = 330,
    .y = 175,
    .lastOn = 0,
};


//
// SOUND VOLUME MENU
//
const SoundEnum = enum(c_int) {
    SfxVol,
    Sfx_empty1,
    MusicVol,
    Sfx_empty2,
    SoundCount,
};

var SoundMenu = [_]MenuItem{
    .{.status = 2, .name = "M_SFXVOL", .routine = &M_SfxVol, .alphaKey = 's'},
    .{.status = -1, .name = "", .routine = null, .alphaKey = 0},
    .{.status = 2, .name = "M_MUSVOL", .routine = &M_MusicVol, .alphaKey = 'm'},
    .{.status = -1, .name = "", .routine = null, .alphaKey = 0}
};

var SoundDef = Menu{
    .numitems = @intFromEnum(SoundEnum.SoundCount),
    .prevMenu = &OptionsDef,
    .menuitems = &SoundMenu,
    .routine = &M_DrawSound,
    .x = 80,
    .y = 64,
    .lastOn = 0,
};


//
// LOAD GAME MENU
//
const LoadEnum = enum(c_int) {
    Load1,
    Load2,
    Load3,
    Load4,
    Load5,
    Load6,
    LoadCount,
};

var LoadMenu = [_]MenuItem{
    .{.status = 1, .name = "", .routine = &M_LoadSelect, .alphaKey = '1'},
    .{.status = 1, .name = "", .routine = &M_LoadSelect, .alphaKey = '2'},
    .{.status = 1, .name = "", .routine = &M_LoadSelect, .alphaKey = '3'},
    .{.status = 1, .name = "", .routine = &M_LoadSelect, .alphaKey = '4'},
    .{.status = 1, .name = "", .routine = &M_LoadSelect, .alphaKey = '5'},
    .{.status = 1, .name = "", .routine = &M_LoadSelect, .alphaKey = '6'},
};

var LoadDef = Menu{
    .numitems = @intFromEnum(LoadEnum.LoadCount),
    .prevMenu = &MainDef,
    .menuitems = &LoadMenu,
    .routine = &M_DrawLoad,
    .x = 80,
    .y = 54,
    .lastOn = 0,
};


//
// SAVE GAME MENU
//
var SaveMenu = [_]MenuItem{
    .{.status = 1, .name = "", .routine = &M_SaveSelect, .alphaKey = '1'},
    .{.status = 1, .name = "", .routine = &M_SaveSelect, .alphaKey = '2'},
    .{.status = 1, .name = "", .routine = &M_SaveSelect, .alphaKey = '3'},
    .{.status = 1, .name = "", .routine = &M_SaveSelect, .alphaKey = '4'},
    .{.status = 1, .name = "", .routine = &M_SaveSelect, .alphaKey = '5'},
    .{.status = 1, .name = "", .routine = &M_SaveSelect, .alphaKey = '6'}
};

var SaveDef = Menu{
    .numitems = @intFromEnum(LoadEnum.LoadCount),
    .prevMenu = &MainDef,
    .menuitems = &SaveMenu,
    .routine = &M_DrawSave,
    .x = 80,
    .y = 54,
    .lastOn = 0,
};


//
// M_ReadSaveStrings
//  read the strings from the savegame files
//
fn M_ReadSaveStrings() void {
    var namebuf: [256]u8 = undefined;

    for (0..@intFromEnum(LoadEnum.LoadCount)) |i| {
        const name =
            if (M_CheckParm("-cdrom") != 0)
                fmt.bufPrintZ(&namebuf, "c:\\doomdata\\" ++ c.SAVEGAMENAME ++ "{}.dsg", .{i}) catch unreachable
            else
                fmt.bufPrintZ(&namebuf, c.SAVEGAMENAME ++ "{}.dsg", .{i}) catch unreachable;

        const handle = os.open(name, os.O.RDONLY, 0o666) catch {
            _ = fmt.bufPrintZ(&savegamestrings[i], "{s}", .{c.EMPTYSTRING}) catch unreachable;
            LoadMenu[i].status = 0;
            continue;
        };

        _ = os.read(handle, &savegamestrings[i]) catch unreachable;
        os.close(handle);
        LoadMenu[i].status = 1;
    }
}


//
// M_LoadGame & Cie.
//
fn M_DrawLoad() void {
    c.V_DrawPatchDirect(72, 28, 0, W_CacheLumpNameAsPatch("M_LOADG", .Cache));
    for (0..@intFromEnum(LoadEnum.LoadCount)) |i| {
        M_DrawSaveLoadBorder(LoadDef.x,LoadDef.y+LINEHEIGHT*@as(u16, @intCast(i)));
        M_WriteText(LoadDef.x,LoadDef.y+LINEHEIGHT*@as(u16, @intCast(i)),&savegamestrings[i]);
    }
}



//
// Draw border for the savegame description
//
fn M_DrawSaveLoadBorder(x: u16, y: u16) void {
    c.V_DrawPatchDirect(x-8, y+7, 0, W_CacheLumpNameAsPatch("M_LSLEFT", .Cache));

    for (0..24) |i| {
        c.V_DrawPatchDirect(x+8*@as(u8, @intCast(i)), y+7, 0, W_CacheLumpNameAsPatch("M_LSCNTR", .Cache));
    }

    c.V_DrawPatchDirect(x+8*24, y+7, 0, W_CacheLumpNameAsPatch("M_LSRGHT", .Cache));
}



//
// User wants to load this game
//
fn M_LoadSelect(choice: c_int) void {
    var namebuf: [256]u8 = undefined;

    const name =
        if (M_CheckParm("-cdrom") != 0)
            fmt.bufPrintZ(&namebuf, "c:\\doomdata\\" ++ c.SAVEGAMENAME ++ "{}.dsg", .{choice}) catch unreachable
        else
            fmt.bufPrintZ(&namebuf, c.SAVEGAMENAME ++ "{}.dsg", .{choice}) catch unreachable;

    G_LoadGame(name);
    M_ClearMenus();
}

//
// Selected from DOOM menu
//
fn M_LoadGame(choice: c_int) void {
    _ = choice;
    if (g_game.netgame != c.false) {
        M_StartMessage(c.LOADNET, null, false);
        return;
    }

    M_SetupNextMenu(&LoadDef);
    M_ReadSaveStrings();
}


//
//  M_SaveGame & Cie.
//
fn M_DrawSave() void {
    c.V_DrawPatchDirect(72, 28, 0, W_CacheLumpNameAsPatch("M_SAVEG", .Cache));
    for (0..@intFromEnum(LoadEnum.LoadCount)) |i| {
        M_DrawSaveLoadBorder(LoadDef.x, LoadDef.y+LINEHEIGHT*@as(u16, @intCast(i)));
        M_WriteText(LoadDef.x, LoadDef.y+LINEHEIGHT*@as(u16, @intCast(i)), &savegamestrings[i]);
    }

    if (saveStringEnter != 0) {
        const i = M_StringWidth(&savegamestrings[saveSlot]);
        M_WriteText(LoadDef.x + i, LoadDef.y+LINEHEIGHT*saveSlot, "_");
    }
}

//
// M_Responder calls this when user is finished
//
fn M_DoSave(slot: c_int) void {
    G_SaveGame(slot, &savegamestrings[@intCast(slot)]);
    M_ClearMenus();

    // PICK QUICKSAVE SLOT YET?
    if (quickSaveSlot == -2) {
        quickSaveSlot = slot;
    }
}

//
// User wants to save. Start string input for M_Responder
//
fn M_SaveSelect(_choice: c_int) void {
    // we are going to be intercepting all chars
    saveStringEnter = 1;

    const choice: u8 = @intCast(_choice);
    saveSlot = @intCast(choice);
    mem.copy(u8, &saveOldString, &savegamestrings[choice]);
    var name = std.mem.sliceTo(&savegamestrings[choice], 0);
    if (std.mem.eql(u8, name, c.EMPTYSTRING)) {
        savegamestrings[choice][0] = 0;
        name = std.mem.sliceTo(&savegamestrings[choice], 0);
    }
    saveCharIndex = @intCast(name.len);
}

//
// Selected from DOOM menu
//
fn M_SaveGame (choice: c_int) void {
    _ = choice;
    if (!g_game.usergame) {
        M_StartMessage(c.SAVEDEAD, null, false);
        return;
    }

    if (g_game.gamestate != .Level) {
        return;
    }

    M_SetupNextMenu(&SaveDef);
    M_ReadSaveStrings();
}



//
//      M_QuickSave
//
var tempstring: [79:0]u8 = undefined;

fn M_QuickSaveResponse(ch: c_int) void {
    if (ch == 'y') {
        M_DoSave(quickSaveSlot);
        S_StartSound(null, .swtchx);
    }
}

fn M_QuickSave() void {
    if (!g_game.usergame) {
        S_StartSound(null, .oof);
        return;
    }

    if (g_game.gamestate != .Level) {
        return;
    }

    if (quickSaveSlot < 0) {
        M_StartControlPanel();
        M_ReadSaveStrings();
        M_SetupNextMenu(&SaveDef);
        quickSaveSlot = -2;     // means to pick a slot now
        return;
    }

    // TODO: Switch to using the string slice in M_StartMessage()
    _ = fmt.bufPrintZ(&tempstring, c.QSPROMPT, .{savegamestrings[@intCast(quickSaveSlot)]}) catch unreachable;
    M_StartMessage(&tempstring, &M_QuickSaveResponse, true);
}



//
// M_QuickLoad
//
fn M_QuickLoadResponse(ch: c_int) void {
    if (ch == 'y') {
        M_LoadSelect(quickSaveSlot);
        S_StartSound(null, .swtchx);
    }
}


fn M_QuickLoad() void {
    if (g_game.netgame != c.false) {
        M_StartMessage(c.QLOADNET, null, false);
        return;
    }

    if (quickSaveSlot < 0)
    {
        M_StartMessage(c.QSAVESPOT, null, false);
        return;
    }

    _ = fmt.bufPrintZ(&tempstring, c.QLPROMPT, .{savegamestrings[@intCast(quickSaveSlot)]}) catch unreachable;
    M_StartMessage(&tempstring, &M_QuickLoadResponse, true);
}




//
// Read This Menus
// Had a "quick hack to fix romero bug"
//
fn M_DrawReadThis1() void {
    inhelpscreens = true;
    switch (doomstat.gamemode) {
        .Commercial => {
            c.V_DrawPatchDirect(0, 0, 0, W_CacheLumpNameAsPatch("HELP", .Cache));
        },
        .Shareware, .Registered, .Retail => {
            c.V_DrawPatchDirect(0, 0, 0, W_CacheLumpNameAsPatch("HELP1", .Cache));
        },
        .Indetermined => {},
    }
}



//
// Read This Menus - optional second page.
//
fn M_DrawReadThis2() void {
    inhelpscreens = true;
    switch (doomstat.gamemode) {
      .Retail, .Commercial => {
        // This hack keeps us from having to change menus.
        c.V_DrawPatchDirect(0, 0, 0, W_CacheLumpNameAsPatch("CREDIT", .Cache));
      },
      .Shareware, .Registered => {
        c.V_DrawPatchDirect(0, 0, 0, W_CacheLumpNameAsPatch("HELP2", .Cache));
      },
      .Indetermined => {},
    }
}


//
// Change Sfx & Music volumes
//
fn M_DrawSound() void {
    c.V_DrawPatchDirect(60, 38, 0, W_CacheLumpNameAsPatch("M_SVOL", .Cache));

    const sfx_pos = @intFromEnum(SoundEnum.SfxVol);
    const music_pos = @intFromEnum(SoundEnum.MusicVol);

    M_DrawThermo(SoundDef.x, SoundDef.y+LINEHEIGHT*(sfx_pos+1),
                 16, s_sound.snd_SfxVolume);

    M_DrawThermo(SoundDef.x, SoundDef.y+LINEHEIGHT*(music_pos+1),
                 16, s_sound.snd_MusicVolume);
}

fn M_Sound(choice: c_int) void {
    _ = choice;
    M_SetupNextMenu(&SoundDef);
}

fn M_SfxVol(choice: c_int) void {
    switch (choice) {
        0 => {
            if (s_sound.snd_SfxVolume != 0) {
                s_sound.snd_SfxVolume -= 1;
            }
        },
        1 => {
            if (s_sound.snd_SfxVolume < 15) {
                s_sound.snd_SfxVolume += 1;
            }
        },
        else => {},
    }

    S_SetSfxVolume(s_sound.snd_SfxVolume);
}

fn M_MusicVol(choice: c_int) void {
    switch (choice) {
        0 => {
            if (s_sound.snd_MusicVolume != 0) {
                s_sound.snd_MusicVolume -= 1;
            }
        },
        1 => {
            if (s_sound.snd_MusicVolume < 15) {
                s_sound.snd_MusicVolume += 1;
            }
        },
        else => {},
    }

    S_SetMusicVolume(s_sound.snd_MusicVolume);
}




//
// M_DrawMainMenu
//
fn M_DrawMainMenu() void {
    c.V_DrawPatchDirect(94, 2, 0, W_CacheLumpNameAsPatch("M_DOOM", .Cache));
}




//
// M_NewGame
//
fn M_DrawNewGame() void {
    c.V_DrawPatchDirect(96, 14, 0, W_CacheLumpNameAsPatch("M_NEWG", .Cache));
    c.V_DrawPatchDirect(54, 38, 0, W_CacheLumpNameAsPatch("M_SKILL", .Cache));
}

fn M_NewGame(choice: c_int) void {
    _ = choice;
    if (g_game.netgame != c.false and g_game.demoplayback == c.false) {
        M_StartMessage(c.NEWGAME, null, false);
        return;
    }

    if (doomstat.gamemode == .Commercial) {
        M_SetupNextMenu(&NewDef);
    } else {
        M_SetupNextMenu(&EpiDef);
    }
}


//
//      M_Episode
//
var epi: c_int = undefined;

fn M_DrawEpisode() void {
    c.V_DrawPatchDirect(54, 38, 0, W_CacheLumpNameAsPatch("M_EPISOD", .Cache));
}

fn M_VerifyNightmare(ch: c_int) void {
    if (ch != 'y') {
        return;
    }

    G_DeferedInitNew(.Nightmare, epi+1, 1);
    M_ClearMenus ();
}

fn M_ChooseSkill(choice: c_int) void {
    const skill: Skill = @enumFromInt(choice);
    if (skill == .Nightmare)
    {
        M_StartMessage(c.NIGHTMARE, &M_VerifyNightmare, true);
        return;
    }

    G_DeferedInitNew(skill, epi+1, 1);
    M_ClearMenus();
}

fn M_Episode(choice: c_int) void {
    if (doomstat.gamemode == .Shareware and choice > 0) {
        M_StartMessage(c.SWSTRING, null, false);
        M_SetupNextMenu(&ReadDef1);
        return;
    }

    epi = choice;
    // Yet another hack...
    if (doomstat.gamemode == .Registered and choice > 2) {
        const stderr = io.getStdErr().writer();
        stderr.print("M_Episode: 4th episode requires UltimateDOOM\n", .{}) catch {};
        epi = 0;
    }

    M_SetupNextMenu(&NewDef);
}



//
// M_Options
//
const detailNames = [2][*:0]const u8{"M_GDHIGH", "M_GDLOW"};
const msgNames = [2][*:0]const u8{"M_MSGOFF", "M_MSGON"};


fn M_DrawOptions() void {
    c.V_DrawPatchDirect(108, 15, 0, W_CacheLumpNameAsPatch("M_OPTTTL", .Cache));

    const detail_pos = @intFromEnum(OptionsEnum.Detail);
    const messages_pos = @intFromEnum(OptionsEnum.Messages);
    const mousesens_pos = @intFromEnum(OptionsEnum.MouseSens);
    const scrnsize_pos = @intFromEnum(OptionsEnum.ScrnSize);

    c.V_DrawPatchDirect(OptionsDef.x + 175, OptionsDef.y+LINEHEIGHT*detail_pos, 0,
                       W_CacheLumpNameAsPatch(detailNames[@intCast(detailLevel)], .Cache));

    c.V_DrawPatchDirect(OptionsDef.x + 120, OptionsDef.y+LINEHEIGHT*messages_pos, 0,
                       W_CacheLumpNameAsPatch(msgNames[@intCast(showMessages)], .Cache));

    M_DrawThermo(OptionsDef.x, OptionsDef.y+LINEHEIGHT*(mousesens_pos+1),
                 10, mouseSensitivity);

    M_DrawThermo(OptionsDef.x, OptionsDef.y+LINEHEIGHT*(scrnsize_pos+1),
                 9, screenSize);
}

fn M_Options(choice: c_int) void {
    _ = choice;
    M_SetupNextMenu(&OptionsDef);
}



//
//      Toggle messages on/off
//
fn M_ChangeMessages(choice: c_int) void {
    _ = choice;
    showMessages = 1 - showMessages;

    if (showMessages == 0) {
        g_game.players[g_game.consoleplayer].message = c.MSGOFF;
    } else {
        g_game.players[g_game.consoleplayer].message = c.MSGON ;
    }

    message_dontfuckwithme = c.true;
}


//
// M_EndGame
//
fn M_EndGameResponse(ch: c_int) void {
    if (ch != 'y') {
        return;
    }

    currentMenu.lastOn = itemOn;
    M_ClearMenus();
    D_StartTitle();
}

fn M_EndGame(choice: c_int) void {
    _ = choice;

    if (!g_game.usergame) {
        S_StartSound(null, .oof);
        return;
    }

    if (g_game.netgame != c.false) {
        M_StartMessage(c.NETEND, null, false);
        return;
    }

    M_StartMessage(c.ENDGAME, &M_EndGameResponse, true);
}




//
// M_ReadThis
//
fn M_ReadThis(choice: c_int) void {
    _ = choice;
    M_SetupNextMenu(&ReadDef1);
}

fn M_ReadThis2(choice: c_int) void {
    _ = choice;
    M_SetupNextMenu(&ReadDef2);
}

fn M_FinishReadThis(choice: c_int) void {
    _ = choice;
    M_SetupNextMenu(&MainDef);
}




//
// M_QuitDOOM
//
const quitsounds = [_]Sfx{
    .pldeth,
    .dmpain,
    .popain,
    .slop,
    .telept,
    .posit1,
    .posit3,
    .sgtatk,
};

const quitsounds2 = [_]Sfx{
    .vilact,
    .getpow,
    .boscub,
    .slop,
    .skeswg,
    .kntdth,
    .bspact,
    .sgtatk,
};



fn M_QuitResponse(ch: c_int) void {
    if (ch != 'y') {
        return;
    }

    if (g_game.netgame == c.false) {
        if (doomstat.gamemode == .Commercial) {
            S_StartSound(null, quitsounds2[@intCast((g_game.gametic>>2)&7)]);
        } else {
            S_StartSound(null, quitsounds[@intCast((g_game.gametic>>2)&7)]);
        }
        I_WaitVBL(105);
    }

    I_Quit();
}




fn M_QuitDOOM(choice: c_int) void {
    _ = choice;
    // We pick index 0 which is language sensitive,
    // or one at random, between 1 and maximum number.

    const endstr =
        if (doomstat.language != .English)
            fmt.bufPrintZ(&endstring, "{s}\n\n" ++ c.DOSY, .{c.endmsg[0]}) catch unreachable
        else
            fmt.bufPrintZ(&endstring, "{s}\n\n" ++ c.DOSY, .{c.endmsg[@intCast(@mod(g_game.gametic, c.NUM_QUITMESSAGES-2)+1)]}) catch unreachable;

    M_StartMessage(endstr, &M_QuitResponse, true);
}




fn M_ChangeSensitivity(choice: c_int) void {
    switch (choice) {
      0 => {
        if (mouseSensitivity > 0) {
            mouseSensitivity -= 1;
        }
      },
      1 => {
        if (mouseSensitivity < 9)
            mouseSensitivity += 1;
      },
      else => unreachable,
    }
}




fn M_ChangeDetail(choice: c_int) void {
    _ = choice;
    detailLevel = 1 - detailLevel;

    // FIXME - does not work. Remove anyway?
    const stderr = io.getStdErr().writer();
    stderr.print("M_ChangeDetail: low detail mode n.a.\n", .{}) catch {};

    // R_SetViewSize (screenblocks, detailLevel);
    //
    // if (!detailLevel) {
    //     g_game.players[g_game.consoleplayer].message = c.DETAILHI;
    // } else {
    //     g_game.players[g_game.consoleplayer].message = c.DETAILLO;
    // }
}




fn M_SizeDisplay(choice: c_int) void {
    switch (choice) {
        0 => {
            if (screenSize > 0) {
                screenblocks -= 1;
                screenSize -= 1;
            }
        },
        1 => {
            if (screenSize < 8) {
                screenblocks += 1;
                screenSize += 1;
            }
        },
        else => {},
    }


    c.R_SetViewSize(screenblocks, detailLevel);
}



//
//      Menu Functions
//
fn M_DrawThermo(x: c_int, y: c_int, thermWidth: usize, thermDot: c_int) void {
    var xx = x;
    c.V_DrawPatchDirect(xx, y, 0, W_CacheLumpNameAsPatch("M_THERML", .Cache));

    xx += 8;
    for (0..thermWidth) |_| {
        c.V_DrawPatchDirect(xx, y, 0, W_CacheLumpNameAsPatch("M_THERMM", .Cache));
        xx += 8;
    }

    c.V_DrawPatchDirect(xx, y, 0, W_CacheLumpNameAsPatch("M_THERMR", .Cache));

    c.V_DrawPatchDirect(x + 8 + thermDot*8, y, 0, W_CacheLumpNameAsPatch("M_THERMO", .Cache));
}



fn M_DrawEmptyCell(menu: *Menu, item: c_int) void {
    c.V_DrawPatchDirect(menu.x - 10, menu.y+item*LINEHEIGHT - 1, 0,
                      W_CacheLumpNameAsPatch("M_CELL1", .Cache));
}

fn M_DrawSelCell(menu: *Menu, item: c_int) void {
    c.V_DrawPatchDirect(menu.x - 10, menu.y+item*LINEHEIGHT - 1, 0,
                      W_CacheLumpNameAsPatch("M_CELL2", .Cache));
}


fn M_StartMessage(string: [:0]const u8, routine: ?*const fn (response: c_int) void, input: bool) void {
    messageLastMenuActive = menuactive;
    messageToPrint = true;
    messageString = string;
    messageRoutine = routine;
    messageNeedsInput = input;
    menuactive = true;
    return;
}



fn M_StopMessage() void {
    menuactive = messageLastMenuActive;
    messageToPrint = false;
}



//
// Find string width from hu_font chars
//
fn M_StringWidth(string: [*:0]const u8) u16 {
    var w: u16 = 0;

    for (mem.span(string)) |ch| {
        const fc = @as(i32, std.ascii.toUpper(ch)) - c.HU_FONTSTART;
        w +=
            if (fc < 0 or fc >= c.HU_FONTSIZE)
                4
            else
                @intCast(mem.littleToNative(c_short, hu_font[@intCast(fc)].width));
    }

    return w;
}



//
//      Find string height from hu_font chars
//
fn M_StringHeight(string: [*:0]const u8) c_int {
    const height = mem.littleToNative(c_short, hu_font[0].height);

    var h = height;
    for (mem.span(string)) |ch| {
        if (ch == '\n') {
            h += height;
        }
    }

    return h;
}


//
//      Write a string using the hu_font
//
fn M_WriteText(x: u16, y: u16, string: [*:0]const u8) void {
    var cx = x;
    var cy = y;

    for (mem.span(string)) |ch| {
        if (ch == '\n') {
            cx = x;
            cy += 12;
            continue;
        }

        const fch = @as(i32, std.ascii.toUpper(ch)) - c.HU_FONTSTART;
        if (fch < 0 or fch >= c.HU_FONTSIZE) {
            cx += 4;
            continue;
        }

        const w: u16 = @intCast(mem.littleToNative(c_short, hu_font[@intCast(fch)].width));
        if (cx + w > SCREENWIDTH) {
            break;
        }

        c.V_DrawPatchDirect(cx, cy, 0, hu_font[@intCast(fch)]);
        cx += w;
    }
}




//
// CONTROL PANEL
//

//
// M_Responder
//
pub fn M_Responder(ev: *Event) bool {
    const S = struct {
        var joywait: c_int = 0;
        var mousewait: c_int = 0;
        var mousey: c_int = 0;
        var lasty: c_int = 0;
        var mousex: c_int = 0;
        var lastx: c_int = 0;
    };

    var ch: c_int = -1;

    if (ev.type == .Joystick and S.joywait < I_GetTime()) {
        if (ev.data3 == -1) {
            ch = doomdef.KEY_UPARROW;
            S.joywait = I_GetTime() + 5;
        } else if (ev.data3 == 1) {
            ch = doomdef.KEY_DOWNARROW;
            S.joywait = I_GetTime() + 5;
        }

        if (ev.data2 == -1) {
            ch = doomdef.KEY_LEFTARROW;
            S.joywait = I_GetTime() + 2;
        } else if (ev.data2 == 1) {
            ch = doomdef.KEY_RIGHTARROW;
            S.joywait = I_GetTime() + 2;
        }

        if (ev.data1 & 1 != 0) {
            ch = doomdef.KEY_ENTER;
            S.joywait = I_GetTime() + 5;
        }

        if (ev.data1 & 2 != 0) {
            ch = doomdef.KEY_BACKSPACE;
            S.joywait = I_GetTime() + 5;
        }
    } else if (ev.type == .Mouse and S.mousewait < I_GetTime()) {
        S.mousey += ev.data3;
        if (S.mousey < S.lasty-30) {
            ch = doomdef.KEY_DOWNARROW;
            S.mousewait = I_GetTime() + 5;
            S.lasty -= 30;
            S.mousey = S.lasty;
        } else if (S.mousey > S.lasty+30) {
            ch = doomdef.KEY_UPARROW;
            S.mousewait = I_GetTime() + 5;
            S.lasty += 30;
            S.mousey = S.lasty;
        }

        S.mousex += ev.data2;
        if (S.mousex < S.lastx-30) {
            ch = doomdef.KEY_LEFTARROW;
            S.mousewait = I_GetTime() + 5;
            S.lastx -= 30;
            S.mousex = S.lastx;
        } else if (S.mousex > S.lastx+30) {
            ch = doomdef.KEY_RIGHTARROW;
            S.mousewait = I_GetTime() + 5;
            S.lastx += 30;
            S.mousex = S.lastx;
        }

        if (ev.data1 & 1 != 0) {
            ch = doomdef.KEY_ENTER;
            S.mousewait = I_GetTime() + 15;
        }

        if (ev.data1 & 2 != 0) {
            ch = doomdef.KEY_BACKSPACE;
            S.mousewait = I_GetTime() + 15;
        }
    } else if (ev.type == .KeyDown) {
        ch = ev.data1;
    }

    if (ch == -1) {
        return false;
    }


    // Save Game string input
    if (saveStringEnter != 0) {
        switch (ch) {
          doomdef.KEY_BACKSPACE => {
            if (saveCharIndex > 0)
            {
                saveCharIndex -= 1;
                savegamestrings[saveSlot][saveCharIndex] = 0;
            }
          },

          doomdef.KEY_ESCAPE => {
            saveStringEnter = 0;
            mem.copy(u8, &savegamestrings[saveSlot], &saveOldString);
          },

          doomdef.KEY_ENTER => {
            saveStringEnter = 0;
            if (savegamestrings[saveSlot][0] != 0)
                M_DoSave(saveSlot);
          },

          else => {
            ch = @as(c_int, std.ascii.toUpper(@intCast(ch)));
            if (ch != 32 and (ch-c.HU_FONTSTART < 0 or ch-c.HU_FONTSTART >= c.HU_FONTSIZE)) {
                // do nothing but eat the event still
            } else if (ch >= 32 and ch <= 127 and
                saveCharIndex < SAVESTRINGSIZE-1 and
                M_StringWidth(&savegamestrings[saveSlot]) < (SAVESTRINGSIZE-2)*8) {
                savegamestrings[saveSlot][saveCharIndex] = @intCast(ch);
                saveCharIndex += 1;
                savegamestrings[saveSlot][saveCharIndex] = 0;
            }
          },
        }
        return true;
    }

    // Take care of any messages that need input
    if (messageToPrint) {
        if (messageNeedsInput and
            !(ch == ' ' or ch == 'n' or ch == 'y' or ch == doomdef.KEY_ESCAPE)) {
            return false;
        }

        menuactive = messageLastMenuActive;
        messageToPrint = false;
        if (messageRoutine != null) {
            messageRoutine.?(ch);
        }

        menuactive = false;
        S_StartSound(null, .swtchx);
        return true;
    }

    if (d_main.devparm and ch == doomdef.KEY_F1) {
        G_ScreenShot();
        return true;
    }


    // F-Keys
    if (!menuactive) switch (ch) {
      doomdef.KEY_MINUS => {         // Screen size down
        if (c.automapactive != c.false or chat_on != c.false) {
            return false;
        }
        M_SizeDisplay(0);
        S_StartSound(null, .stnmov);
        return true;
      },

      doomdef.KEY_EQUALS => {        // Screen size up
        if (c.automapactive != c.false or chat_on != c.false) {
            return false;
        }
        M_SizeDisplay(1);
        S_StartSound(null, .stnmov);
        return true;
      },

      doomdef.KEY_F1 => {            // Help key
        M_StartControlPanel();

        currentMenu =
            if (doomstat.gamemode == .Retail)
              &ReadDef2
            else
              &ReadDef1;

        itemOn = 0;
        S_StartSound(null, .swtchn);
        return true;
      },

      doomdef.KEY_F2 => {            // Save
        M_StartControlPanel();
        S_StartSound(null, .swtchn);
        M_SaveGame(0);
        return true;
      },

      doomdef.KEY_F3 => {            // Load
        M_StartControlPanel();
        S_StartSound(null, .swtchn);
        M_LoadGame(0);
        return true;
      },

      doomdef.KEY_F4 => {            // Sound Volume
        M_StartControlPanel();
        currentMenu = &SoundDef;
        itemOn = @intFromEnum(SoundEnum.SfxVol);
        S_StartSound(null, .swtchn);
        return true;
      },

      doomdef.KEY_F5 => {            // Detail toggle
        M_ChangeDetail(0);
        S_StartSound(null, .swtchn);
        return true;
      },

      doomdef.KEY_F6 => {            // Quicksave
        S_StartSound(null, .swtchn);
        M_QuickSave();
        return true;
      },

      doomdef.KEY_F7 => {            // End game
        S_StartSound(null, .swtchn);
        M_EndGame(0);
        return true;
      },

      doomdef.KEY_F8 => {            // Toggle messages
        M_ChangeMessages(0);
        S_StartSound(null, .swtchn);
        return true;
      },

      doomdef.KEY_F9 => {            // Quickload
        S_StartSound(null, .swtchn);
        M_QuickLoad();
        return true;
      },

      doomdef.KEY_F10 => {           // Quit DOOM
        S_StartSound(null, .swtchn);
        M_QuitDOOM(0);
        return true;
      },

      'g',
      doomdef.KEY_F11 => {           // gamma toggle
        c.usegamma += 1;
        if (c.usegamma > 4) {
            c.usegamma = 0;
        }
        g_game.players[g_game.consoleplayer].message = gammamsg[@intCast(c.usegamma)];
        I_SetPalette(@ptrCast(W_CacheLumpName("PLAYPAL", .Cache)));
        return true;
      },

      else => {},
    };


    // Pop-up menu?
    if (!menuactive) {
        if (ch == doomdef.KEY_ESCAPE) {
            M_StartControlPanel();
            S_StartSound(null, .swtchn);
            return true;
        }
        return false;
    }


    // Keys usable within menu
    switch (ch) {
      doomdef.KEY_DOWNARROW => {
        while (true) {
            if (itemOn+1 > currentMenu.numitems-1) {
                itemOn = 0;
            } else {
                itemOn += 1;
            }
            S_StartSound(null, .pstop);

            if (currentMenu.menuitems[itemOn].status != -1)
                break;
        }
        return true;
      },

      doomdef.KEY_UPARROW => {
        while (true) {
            if (itemOn == 0) {
                itemOn = currentMenu.numitems-1;
            } else {
                itemOn -= 1;
            }
            S_StartSound(null, .pstop);

            if (currentMenu.menuitems[itemOn].status != -1)
                break;
        }
        return true;
      },

      doomdef.KEY_LEFTARROW => {
        if (currentMenu.menuitems[itemOn].routine != null and
            currentMenu.menuitems[itemOn].status == 2) {
            S_StartSound(null, .stnmov);
            currentMenu.menuitems[itemOn].routine.?(0);
        }
        return true;
      },

      doomdef.KEY_RIGHTARROW => {
        if (currentMenu.menuitems[itemOn].routine != null and
            currentMenu.menuitems[itemOn].status == 2) {
            S_StartSound(null, .stnmov);
            currentMenu.menuitems[itemOn].routine.?(1);
        }
        return true;
      },

      doomdef.KEY_ENTER => {
        if (currentMenu.menuitems[itemOn].routine != null and
            currentMenu.menuitems[itemOn].status != 0) {
            currentMenu.lastOn = itemOn;
            if (currentMenu.menuitems[itemOn].status == 2) {
                currentMenu.menuitems[itemOn].routine.?(1);      // right arrow
                S_StartSound(null, .stnmov);
            } else {
                currentMenu.menuitems[itemOn].routine.?(itemOn);
                S_StartSound(null, .pistol);
            }
        }
        return true;
      },

      doomdef.KEY_ESCAPE => {
        currentMenu.lastOn = itemOn;
        M_ClearMenus();
        S_StartSound(null, .swtchx);
        return true;
      },

      doomdef.KEY_BACKSPACE => {
        currentMenu.lastOn = itemOn;
        if (currentMenu.prevMenu != null) {
            currentMenu = currentMenu.prevMenu.?;
            itemOn = currentMenu.lastOn;
            S_StartSound(null, .swtchn);
        }
        return true;
      },

      else => {
        for (itemOn+1..currentMenu.numitems) |i| {
            if (currentMenu.menuitems[i].alphaKey == ch) {
                itemOn = @intCast(i);
                S_StartSound(null, .pstop);
                return true;
            }
        }

        for (0..itemOn) |i| {
            if (currentMenu.menuitems[i].alphaKey == ch) {
                itemOn = @intCast(i);
                S_StartSound(null, .pstop);
                return true;
            }
        }
      },
    }

    return false;
}



//
// M_StartControlPanel
//
pub fn M_StartControlPanel() void {
    // intro might call this repeatedly
    if (menuactive) {
        return;
    }

    I_PauseMouseCapture();
    menuactive = true;
    currentMenu = &MainDef;         // JDC
    itemOn = currentMenu.lastOn;    // JDC
}


//
// M_Drawer
// Called after the view has been rendered,
// but before it has been blitted.
//
pub fn M_Drawer() void {
    inhelpscreens = false;

    // Horiz. & Vertically center string and print it.
    if (messageToPrint) {
        var stringbuf: [40-1:0]u8 = undefined;
        var start: usize = 0;
        var y = 100 - @as(u16, @intCast(@divTrunc(M_StringHeight(messageString), 2)));
        while (messageString[start] != 0) {
            var l = messageString[start..].len;
            for (0..l) |i| {
                if (messageString[start+i] == '\n') {
                    @memset(&stringbuf, 0);
                    mem.copy(u8, &stringbuf, messageString[start..start+i]);
                    start += i+1;
                    l = i;
                    break;
                }
            }

            if (l == messageString[start..].len) {
                mem.copy(u8, &stringbuf, messageString[start..start+l]);
                start += l;
            }

            const x: u16 = @intCast(160 - @divTrunc(M_StringWidth(&stringbuf), 2));
            M_WriteText(x, y, &stringbuf);
            y += @intCast(mem.littleToNative(c_short, hu_font[0].height));
        }
        return;
    }

    if (!menuactive) {
        return;
    }

    currentMenu.routine();      // call Draw routine

    // DRAW MENU
    const x = currentMenu.x;
    var y = currentMenu.y;
    const max = currentMenu.numitems;

    for (0..max) |i| {
        if (currentMenu.menuitems[i].name[0] != 0) {
            c.V_DrawPatchDirect(
                x, y, 0,
                W_CacheLumpNameAsPatch(currentMenu.menuitems[i].name, .Cache)
            );
        }
        y += LINEHEIGHT;
    }


    // DRAW SKULL
    c.V_DrawPatchDirect(x - SKULLXOFF, currentMenu.y - 5 + itemOn*LINEHEIGHT, 0,
                        W_CacheLumpNameAsPatch(skullName[whichSkull], .Cache));

}


//
// M_ClearMenus
//
fn M_ClearMenus() void {
    menuactive = false;
    I_ResumeMouseCapture();
    // if (!netgame && usergame && paused)
    //       sendpause = true;
}



//
// M_SetupNextMenu
//
fn M_SetupNextMenu(menudef: *Menu) void {
    currentMenu = menudef;
    itemOn = currentMenu.lastOn;
}


//
// M_Ticker
//
pub fn M_Ticker() void {
    skullAnimCounter -= 1;
    if (skullAnimCounter <= 0) {
        whichSkull ^= 1;
        skullAnimCounter = 8;
    }
}


//
// M_Init
//
pub fn M_Init() void {
    currentMenu = &MainDef;
    menuactive = false;
    itemOn = currentMenu.lastOn;
    whichSkull = 0;
    skullAnimCounter = 10;
    screenSize = screenblocks - 3;
    messageToPrint = false;
    messageString = "";
    messageLastMenuActive = menuactive;
    quickSaveSlot = -1;

    // Here we could catch other version dependencies,
    //  like HELP1/2, and four episodes.


    switch (doomstat.gamemode) {
      .Commercial => {
        // This is used because DOOM 2 had only one HELP
        //  page. I use CREDIT as second page now, but
        //  kept this hack for educational purposes.
        MainMenu[@intFromEnum(MainMenuEnum.ReadThis)] = MainMenu[@intFromEnum(MainMenuEnum.QuitDoom)];
        MainDef.numitems -= 1;
        MainDef.y += 8;
        NewDef.prevMenu = &MainDef;
        ReadDef1.routine = M_DrawReadThis1;
        ReadDef1.x = 330;
        ReadDef1.y = 165;
        ReadMenu1[0].routine = M_FinishReadThis;
      },
      .Shareware,
        // Episode 2 and 3 are handled,
        //  branching to an ad screen.
      .Registered => {
        // We need to remove the fourth episode.
        EpiDef.numitems -= 1;
      },
      .Retail,
        // We are fine.
      .Indetermined => {},
    }
}

