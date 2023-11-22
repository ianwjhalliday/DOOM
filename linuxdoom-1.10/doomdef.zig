
//
// Global parameters/defines.
//
// DOOM version
pub const VERSION = 110;


// Game mode handling - identify IWAD version
//  to handle IWAD dependend animations etc.
pub const GameMode = enum(c_uint) {
  Shareware,    // DOOM 1 shareware, E1, M9
  Registered,   // DOOM 1 registered, E3, M27
  Commercial,   // DOOM 2 retail, E1 M34
  // DOOM 2 german edition not handled
  Retail,       // DOOM 1 retail, E4, M36
  Indetermined  // Well, no IWAD found.
};


// Identify language to use, software localization.
pub const Language = enum(c_uint) {
  English,
  French,
  German,
  Unknown
};


// If rangecheck is undefined,
// most parameter validation debugging code will not be compiled
pub const RANGECHECK = true;


//
// For resize of screen, at start of game.
// It will not work dynamically, see visplanes.
//
// TODO: Unused
pub const BASE_WIDTH = 320;

// It is educational but futile to change this
//  scaling e.g. to 2. Drawing of status bar,
//  menues etc. is tied to the scale implied
//  by the graphics.
pub const SCREEN_MUL = 1;
// TODO: Unused
pub const INV_ASPECT_RATIO = 0.625; // 0.75, ideally

pub const SCREENWIDTH = 320;
//SCREEN_MUL*BASE_WIDTH //320
pub const SCREENHEIGHT = 200;
//(int)(SCREEN_MUL*BASE_WIDTH*INV_ASPECT_RATIO) //200




// The maximum number of players, multiplayer/networking.
pub const MAXPLAYERS = 4;

// State updates, number of tics / second.
pub const TICRATE = 35;

// The current state of the game: whether we are
// playing, gazing at the intermission screen,
// the game final animation, or a demo. 
pub const GameState = enum {
    Level,
    Intermission,
    Finale,
    DemoScreen,
    ForceWipe,
    ForceRedraw
};

pub const GameAction = enum {
    Nothing,
    LoadLevel,
    NewGame,
    LoadGame,
    SaveGame,
    PlayDemo,
    Completed,
    Victory,
    WorldDone,
    Screenshot
};

//
// Difficulty/skill settings/filters.
//

// Skill flags.
// TODO: Convert to ... what is Zig's way to do bit flags?
// Although it appears these thre aren't used and MTF_AMBUSH is only read.
// Guess these are set in written in map editor only.
pub const MTF_EASY = 1;
pub const MTF_NORMAL = 2;
pub const MTF_HARD = 4;

// Deaf monsters/do not react to sound.
pub const MTF_AMBUSH = 8;

pub const Skill = enum(c_uint) {
    Baby,
    Easy,
    Medium,
    Hard,
    Nightmare
};




//
// Key cards.
//
pub const Card = enum(c_uint) {
    BlueCard,
    YellowCard,
    RedCard,
    BlueSkull,
    YellowSkull,
    RedSkull,

    NUMCARDS
};



// The defined weapons,
//  including a marker indicating
//  user has not changed weapon.
pub const WeaponType = enum(c_uint) {
    Fist,
    Pistol,
    Shotgun,
    Chaingun,
    Missile,
    Plasma,
    Bfg,
    Chainsaw,
    SuperShotgun,

    NUMWEAPONS,

    // No pending weapon change.
    NoChange
};


// Ammunition types defined.
pub const AmmoType = enum(c_uint) {
    Clip,       // Pistol / chaingun ammo.
    Shell,      // Shotgun / double barreled shotgun.
    Cell,       // Plasma rifle, BFG.
    Missile,    // Missile launcher.

    NUMAMMO,

    NoAmmo      // Unlimited for chainsaw / fist.
};


// Power up artifacts.
pub const PowerType = enum(c_uint) {
    Invulnerability,
    Strength,
    Invisibility,
    IronFeet,
    AllMap,
    Infrared,

    NUMPOWERS
};



//
// Power up durations,
//  how many seconds till expiration,
//  assuming TICRATE is 35 ticks/second.
//
pub const PowerDuration = enum(c_uint) {
    InvulnTics  = (30*TICRATE),
    InvisTics   = (60*TICRATE),
    InfraTics   = (120*TICRATE),
    IronTics    = (60*TICRATE)
};




//
// DOOM keyboard definition.
// This is the stuff configured by Setup.Exe.
// Most key data are simple ascii (uppercased).
//
pub const KEY_RIGHTARROW = 0xae;
pub const KEY_LEFTARROW = 0xac;
pub const KEY_UPARROW = 0xad;
pub const KEY_DOWNARROW = 0xaf;
pub const KEY_ESCAPE = 27;
pub const KEY_ENTER = 13;
pub const KEY_TAB = 9;
pub const KEY_F1 = 0x80+0x3b;
pub const KEY_F2 = 0x80+0x3c;
pub const KEY_F3 = 0x80+0x3d;
pub const KEY_F4 = 0x80+0x3e;
pub const KEY_F5 = 0x80+0x3f;
pub const KEY_F6 = 0x80+0x40;
pub const KEY_F7 = 0x80+0x41;
pub const KEY_F8 = 0x80+0x42;
pub const KEY_F9 = 0x80+0x43;
pub const KEY_F10 = 0x80+0x44;
pub const KEY_F11 = 0x80+0x57;
pub const KEY_F12 = 0x80+0x58;

pub const KEY_BACKSPACE = 127;
pub const KEY_PAUSE = 0xff;

pub const KEY_EQUALS = 0x3d;
pub const KEY_MINUS = 0x2d;

pub const KEY_RSHIFT = 0x80+0x36;
pub const KEY_RCTRL = 0x80+0x1d;
pub const KEY_RALT = 0x80+0x38;

pub const KEY_LALT = KEY_RALT;



