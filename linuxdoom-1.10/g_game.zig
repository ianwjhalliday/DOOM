pub const c = @cImport({
    @cInclude("doomstat.h");
    @cInclude("dstrings.h");
    @cInclude("d_event.h");
    @cInclude("d_player.h");
    @cInclude("d_ticcmd.h");
    @cInclude("am_map.h");
    @cInclude("hu_stuff.h");
    @cInclude("info.h");
    @cInclude("p_local.h");
    @cInclude("p_mobj.h");
    @cInclude("p_saveg.h");
    @cInclude("p_setup.h");
    @cInclude("r_data.h");
    @cInclude("r_draw.h");
    @cInclude("r_main.h");
    @cInclude("tables.h");
});

const fmt = @import("std").fmt;
const io = @import("std").io;
const mem = @import("std").mem;

const i_system = @import("i_system.zig");
const I_BaseTiccmd = i_system.I_BaseTiccmd;
const I_Error = i_system.I_Error;
const I_GetTime = i_system.I_GetTime;
const I_Quit = i_system.I_Quit;

const I_PauseMouseCapture = @import("i_video.zig").I_PauseMouseCapture;
const I_ResumeMouseCapture = @import("i_video.zig").I_ResumeMouseCapture;

const TicCmd = @import("d_ticcmd.zig").TicCmd;

const d_main = @import("d_main.zig");
const Event = d_main.Event;
const D_AdvanceDemo = d_main.D_AdvanceDemo;
const D_PageTicker = d_main.D_PageTicker;

const d_net = @import("d_net.zig");

const f_finale = @import("f_finale.zig");
const F_StartFinale = f_finale.F_StartFinale;
const F_Responder = f_finale.F_Responder;
const F_Ticker = f_finale.F_Ticker;

const hu_stuff = @import("hu_stuff.zig");
const HU_Ticker = hu_stuff.HU_Ticker;
const HU_Responder = hu_stuff.HU_Responder;
const HU_dequeueChatChar = hu_stuff.HU_dequeueChatChar;

const m_argv = @import("m_argv.zig");
const M_CheckParm = m_argv.M_CheckParm;

const m_menu = @import("m_menu.zig");
const M_StartControlPanel = m_menu.M_StartControlPanel;

const m_misc = @import("m_misc.zig");
const M_ReadFile = m_misc.M_ReadFile;
const M_WriteFile = m_misc.M_WriteFile;
const M_ScreenShot = m_misc.M_ScreenShot;

const m_random = @import("m_random.zig");
const M_ClearRandom = m_random.M_ClearRandom;
const P_Random = m_random.P_Random;

// HACK: importing p_tick from p_telept.zig to work around duplicate export issue
// TODO: import p_tick.zig directly once p_spec is converted to zig
const p_tick = @import("p_telept.zig").p_tick;
const P_Ticker = p_tick.P_Ticker;

const player_t = @import("p_user.zig").player_t;

const r_sky = @import("r_sky.zig");

const s_sound = @import("s_sound.zig");
const S_StartSound = s_sound.S_StartSound_Zig;
const S_PauseSound = s_sound.S_PauseSound;
const S_ResumeSound = s_sound.S_ResumeSound;

const Sfx = @import("sounds.zig").Sfx;

const st_stuff = @import("st_stuff.zig");
const ST_Ticker = st_stuff.ST_Ticker;
const ST_Responder = st_stuff.ST_Responder;

const v_video = @import("v_video.zig");

const w_wad = @import("w_wad.zig");
const W_CacheLumpName = w_wad.W_CacheLumpName;
const W_CheckNumForName = w_wad.W_CheckNumForName;

const wi_stuff = @import("wi_stuff.zig");
const WI_Start = wi_stuff.WI_Start;
const WI_Ticker = wi_stuff.WI_Ticker;

const z_zone = @import("z_zone.zig");
const Z_ChangeTag = z_zone.Z_ChangeTag;
const Z_CheckHeap = z_zone.Z_CheckHeap;
const Z_Free = z_zone.Z_Free;

const doomdef = @import("doomdef.zig");
const MAXPLAYERS = doomdef.MAXPLAYERS;
const GameAction = doomdef.GameAction;
const GameState = doomdef.GameState;
const Skill = doomdef.Skill;
const WeaponType = doomdef.WeaponType;

const doomstat = @import("doomstat.zig");

const SAVEGAMESIZE = 0x2c000;
const SAVESTRINGSIZE = 24;

pub var gameaction: GameAction = undefined;
pub var gamestate: GameState = undefined;
pub export var gameskill: Skill = undefined;
export var respawnmonsters: c.boolean = c.false;
pub export var gameepisode: c_int = 0;
pub export var gamemap: c_int = 0;

pub export var paused = false;
var sendpause = false;     // send a pause event next tic
var sendsave = false;      // send a save event next tic
pub var usergame = false;      // ok to save / end game

var timingdemo = false;    // if true, exit with report on completion
pub var nodrawers = false;     // for comparative timing purposes
var starttime: c_int = 0;               // for comparative timing purposes

pub export var viewactive: c.boolean = c.false;

pub export var deathmatch: c.boolean = c.false;    // only if started as net death
pub export var netgame: c.boolean = c.false;       // only true if packets are broadcast
pub export var playeringame: [MAXPLAYERS]c.boolean = undefined;
pub export var players: [MAXPLAYERS]player_t = undefined;

pub export var consoleplayer: usize = 0;           // player taking events and displaying
pub var displayplayer: usize = 0;           // view being displayed
pub export var gametic: c_int = 0;
export var totalkills: c_int = 0;              // for intermission
export var totalitems: c_int = 0;              // for intermission
export var totalsecret: c_int = 0;             // for intermission

export var demonamebuf: [32]u8 = undefined;
var demoname: []const u8 = undefined;
pub var demorecording = false;
pub export var demoplayback: c.boolean = c.false;
var netdemo = false;
// TODO: Convert these demo globals to an io.Reader/Writer
var demobuffer: [*]u8 = undefined;
var demo_p: [*]u8 = undefined;
var demoend: [*]u8 = undefined;
export var singledemo: c.boolean = c.false;     // quit after playing a demo from cmdline

export var precache: c.boolean = c.true;        // if true, load all graphics at start

export var wminfo: c.wbstartstruct_t = undefined;  // parms for world map / intermission

export var consistancy: [MAXPLAYERS][d_net.BACKUPTICS]c_short = undefined;


//
// controls (have defaults)
//
// TODO: Convert these all to unsigned values and remove @intCast usage
export var key_right: c_int = 0;
export var key_left: c_int = 0;

export var key_up: c_int = 0;
export var key_down: c_int = 0;
export var key_strafeleft: c_int = 0;
export var key_straferight: c_int = 0;
export var key_fire: c_int = 0;
export var key_use: c_int = 0;
export var key_strafe: c_int = 0;
export var key_speed: c_int = 0;

export var mousebfire: c_int = 0;
export var mousebstrafe: c_int = 0;
export var mousebforward: c_int = 0;

export var joybfire: c_int = 0;
export var joybstrafe: c_int = 0;
export var joybuse: c_int = 0;
export var joybspeed: c_int = 0;



const MAXPLMOVE = 0x32;

const TURBOTHRESHOLD = 0x32;

export const forwardmove = [_]c_int{0x19, 0x32};
export const sidemove = [_]c_int{0x18, 0x28};
const angleturn = [_]c_short{640, 1280, 320};        // + slow turn

const SLOWTURNTICS = 6;

const NUMKEYS = 256;

var gamekeydown: [NUMKEYS]bool = undefined;
var turnheld: c_int = 0;                            // for accelerative turning

var mousearray: [4]bool = undefined;
// TODO: Unclear why "allow [-1]" is done here, I don't see a use of it. Simplify to just `mousearray` and get rid of the extra element?
var mousebuttons: [*]bool = mousearray[1..].ptr;    // allow [-1]

// mouse values are used once
var mousex: c_int = 0;
var mousey: c_int = 0;

var dclicktime: c_int = 0;
var dclickstate = false;
var dclicks: c_int = 0;
var dclicktime2: c_int = 0;
var dclickstate2 = false;
var dclicks2: c_int = 0;

// joystick values are repeated
var joyxmove: c_int = 0;
var joyymove: c_int = 0;
var joyarray: [5]bool = undefined;
// TODO: Unclear why "allow [-1]" is done here, I don't see a use of it. Simplify to just `joyarray` and get rid of the extra element?
var joybuttons : [*]bool = joyarray[1..].ptr;   // allow [-1]

var savegameslot: c_int = 0;
var savedescription = [_]u8{0} ** SAVESTRINGSIZE;


const BODYQUESIZE = 32;

var bodyque: [BODYQUESIZE]@TypeOf(players[0].mo) = undefined;
export var bodyqueslot: c_int = 0;

// TODO: Remove `statcopy` from codebase
export var statcopy: *anyopaque = undefined;           // for statistics driver


//
// G_BuildTiccmd
// Builds a ticcmd from all of the available inputs
// or reads it from the demo buffer.
// If recording a demo, write it out
//
pub fn G_BuildTiccmd(cmd: *TicCmd) void {
    cmd.* = I_BaseTiccmd().*;   // empty, or external driver

    // TODO: Fix spelling error in "consistancy" across code base
    cmd.consistancy =
        consistancy[@intCast(consoleplayer)][@intCast(@mod(d_net.maketic, d_net.BACKUPTICS))];


    const strafe = gamekeydown[@intCast(key_strafe)] or mousebuttons[@intCast(mousebstrafe)] or joybuttons[@intCast(joybstrafe)];
    const speed: usize = if (gamekeydown[@intCast(key_speed)] or joybuttons[@intCast(joybspeed)]) 1 else 0;

    var forward: c_int = 0;
    var side: c_int = 0;

    // use two stage accelerative turning
    // on the keyboard and joystick
    if (joyxmove < 0
        or joyxmove > 0
        or gamekeydown[@intCast(key_right)]
        or gamekeydown[@intCast(key_left)]) {
        turnheld += d_net.ticdup;
    } else {
        turnheld = 0;
    }

    const tspeed: usize =
        if (turnheld < SLOWTURNTICS)
            2   // slow turn
        else
            speed;

    // let movement keys cancel each other out
    if (strafe) {
        if (gamekeydown[@intCast(key_right)]) {
            // fprintf(stderr, "strafe right\n");
            side += sidemove[speed];
        }
        if (gamekeydown[@intCast(key_left)]) {
            //  fprintf(stderr, "strafe left\n");
            side -= sidemove[speed];
        }
        if (joyxmove > 0) {
            side += sidemove[speed];
        }
        if (joyxmove < 0) {
            side -= sidemove[speed];
        }
    } else {
        if (gamekeydown[@intCast(key_right)]) {
            cmd.angleturn -= angleturn[tspeed];
        }
        if (gamekeydown[@intCast(key_left)]) {
            cmd.angleturn += angleturn[tspeed];
        }
        if (joyxmove > 0) {
            cmd.angleturn -= angleturn[tspeed];
        }
        if (joyxmove < 0) {
            cmd.angleturn += angleturn[tspeed];
        }
    }

    if (gamekeydown[@intCast(key_up)]) {
        // fprintf(stderr, "up\n");
        forward += forwardmove[speed];
    }
    if (gamekeydown[@intCast(key_down)]) {
        // fprintf(stderr, "down\n");
        forward -= forwardmove[speed];
    }
    if (joyymove < 0) {
        forward += forwardmove[speed];
    }
    if (joyymove > 0) {
        forward -= forwardmove[speed];
    }
    if (gamekeydown[@intCast(key_straferight)]) {
        side += sidemove[speed];
    }
    if (gamekeydown[@intCast(key_strafeleft)]) {
        side -= sidemove[speed];
    }

    // buttons
    cmd.chatchar = HU_dequeueChatChar();

    if (gamekeydown[@intCast(key_fire)] or mousebuttons[@intCast(mousebfire)] or joybuttons[@intCast(joybfire)]) {
        cmd.buttons |= @intCast(c.BT_ATTACK);
    }

    if (gamekeydown[@intCast(key_use)] or joybuttons[@intCast(joybuse)]) {
        cmd.buttons |= @intCast(c.BT_USE);
        // clear double clicks if hit use button
        dclicks = 0;
    }

    // chainsaw overrides
    for (0..@intFromEnum(WeaponType.NUMWEAPONS)-1) |i| {
        if (gamekeydown['1'+i]) {
            cmd.buttons |= @intCast(c.BT_CHANGE);
            cmd.buttons |= @intCast(i<<c.BT_WEAPONSHIFT);
            break;
        }
    }

    // mouse
    if (mousebuttons[@intCast(mousebforward)]) {
        forward += forwardmove[speed];
    }

    // forward double click
    if (mousebuttons[@intCast(mousebforward)] != dclickstate and dclicktime > 1) {
        dclickstate = mousebuttons[@intCast(mousebforward)];
        if (dclickstate) {
            dclicks += 1;
        }
        if (dclicks == 2) {
            cmd.buttons |= @intCast(c.BT_USE);
            dclicks = 0;
        } else {
            dclicktime = 0;
        }
    } else {
        dclicktime += d_net.ticdup;
        if (dclicktime > 20) {
            dclicks = 0;
            dclickstate = false;
        }
    }

    // strafe double click
    const bstrafe = mousebuttons[@intCast(mousebstrafe)] or joybuttons[@intCast(joybstrafe)];
    if (bstrafe != dclickstate2 and dclicktime2 > 1) {
        dclickstate2 = bstrafe;
        if (dclickstate2) {
            dclicks2 += 1;
        }
        if (dclicks2 == 2) {
            cmd.buttons |= @intCast(c.BT_USE);
            dclicks2 = 0;
        } else {
            dclicktime2 = 0;
        }
    } else {
        dclicktime2 += d_net.ticdup;
        if (dclicktime2 > 20) {
            dclicks2 = 0;
            dclickstate2 = false;
        }
    }

    forward +|= mousey;
    if (strafe) {
        side +|= mousex*2;
    } else {
        cmd.angleturn -|= @intCast(mousex*0x8);
    }

    mousex = 0;
    mousey = 0;

    if (forward > MAXPLMOVE) {
        forward = MAXPLMOVE;
    } else if (forward < -MAXPLMOVE) {
        forward = -MAXPLMOVE;
    }
    if (side > MAXPLMOVE) {
        side = MAXPLMOVE;
    } else if (side < -MAXPLMOVE) {
        side = -MAXPLMOVE;
    }

    cmd.forwardmove += @intCast(forward);
    cmd.sidemove += @intCast(side);

    // special buttons
    if (sendpause) {
        sendpause = false;
        cmd.buttons = c.BT_SPECIAL | c.BTS_PAUSE;
    }

    if (sendsave) {
        sendsave = false;
        cmd.buttons = @intCast(c.BT_SPECIAL | c.BTS_SAVEGAME | (savegameslot<<c.BTS_SAVESHIFT));
    }
}


//
// G_DoLoadLevel
//
export fn G_DoLoadLevel() void {
    // Set the sky map.
    // First thing, we have a dummy sky texture name,
    //  a flat. The data is in the WAD only because
    //  we look for an actual index, instead of simply
    //  setting one.
    r_sky.skyflatnum = c.R_FlatNumForName(@constCast(r_sky.SKYFLATNAME));

    // DOOM determines the sky texture to be used
    // depending on the current episode, and the game version.
    if (doomstat.gamemode == .Commercial) {
        if (gamemap < 12) {
            r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY1"));
        } else if (gamemap < 21) {
            r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY2"));
        } else {
            r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY3"));
        }
    }

    if (d_main.wipegamestate == .Level) {
        d_main.wipegamestate = .ForceWipe;
    }

    gamestate = .Level;

    for (playeringame, &players) |pig, *player| {
        if (pig != c.false and player.*.playerstate == c.PST_DEAD) {
            player.*.playerstate = c.PST_REBORN;
        }
        for (&player.frags) |*frags| {
            frags.* = 0;
        }
    }

    c.P_SetupLevel(gameepisode, gamemap, 0, @intFromEnum(gameskill));
    displayplayer = consoleplayer;  // view the guy you are playing
    starttime = I_GetTime();
    gameaction = .Nothing;
    Z_CheckHeap();

    // clear cmd building stuff
    for (&gamekeydown) |*gkd| {
        gkd.* = false;
    }
    joyxmove = 0;
    joyymove = 0;
    mousex = 0;
    mousey = 0;
    sendpause = false;
    sendsave = false;
    paused = false;
    for (&mousearray) |*mb| {
        mb.* = false;
    }
    for (&joyarray) |*jb| {
        jb.* = false;
    }
}

extern fn AM_Responder(ev: *Event) c.boolean;

//
// G_Responder
// Get info needed to make ticcmd_ts for the players.
//
pub fn G_Responder(ev: *Event) bool {
    // allow spy mode changes even during the demo
    if (gamestate == .Level and ev.type == .KeyDown
        and ev.data1 == doomdef.KEY_F12
        and (singledemo != c.false or deathmatch == c.false)) {
        // spy mode
        displayplayer = @mod(displayplayer + 1, MAXPLAYERS);
        while (playeringame[displayplayer] == c.false and displayplayer != consoleplayer) {
            displayplayer = @mod(displayplayer + 1, MAXPLAYERS);
        }
        return true;
    }

    // any other key pops up menu if in demos
    if (gameaction == .Nothing and singledemo == c.false and
        (demoplayback != c.false or gamestate == .DemoScreen)) {
        if (ev.type == .KeyDown or
            (ev.type == .Mouse and ev.data1 != 0) or
            (ev.type == .Joystick and ev.data1 != 0)) {
            M_StartControlPanel();
            return true;
        }
        return false;
    }

    if (gamestate == .Level) {
        if (HU_Responder(ev)) {
            return true;        // chat ate the event
        }
        if (ST_Responder(ev) != c.false) {
            return true;        // status window ate it
        }
        if (AM_Responder(ev) != c.false) {
            return true;        // automap ate it
        }
    }

    if (gamestate == .Finale) {
        if (F_Responder(ev)) {
            return true;        // finale ate the event
        }
    }

    switch (ev.type) {
      .KeyDown => {
        if (ev.data1 == doomdef.KEY_PAUSE or ev.data1 == 'p') {
            sendpause = true;
            return true;
        }
        if (ev.data1 < NUMKEYS) {
            gamekeydown[@intCast(ev.data1)] = true;
        }
        return true;    // eat key down events
      },

      .KeyUp => {
        if (ev.data1 < NUMKEYS) {
            gamekeydown[@intCast(ev.data1)] = false;
        }
        return false;   // always let key up events filter down
      },

      .Mouse => {
        mousebuttons[0] = (ev.data1 & 1) != 0;
        mousebuttons[1] = (ev.data1 & 2) != 0;
        mousebuttons[2] = (ev.data1 & 4) != 0;
        mousex = @divTrunc(ev.data2*(m_menu.mouseSensitivity+5), 10);
        mousey = @divTrunc(ev.data3*(m_menu.mouseSensitivity+5), 10);
        return true;    // eat events
      },

      .Joystick => {
        joybuttons[0] = (ev.data1 & 1) != 0;
        joybuttons[1] = (ev.data1 & 2) != 0;
        joybuttons[2] = (ev.data1 & 4) != 0;
        joybuttons[3] = (ev.data1 & 8) != 0;
        joyxmove = ev.data2;
        joyymove = ev.data3;
        return true;    // eat events
      },
    }

    return false;
}


extern var rndindex: c_int;

//
// G_Ticker
// Make TicCmds for the players.
//
pub export fn G_Ticker() void {
    // do player reborns if needed
    for (playeringame, players, 0..) |pig, player, i| {
        if (pig != c.false and player.playerstate == c.PST_REBORN) {
            G_DoReborn(@intCast(i));
        }
    }

    // do things to change the game state
    while (gameaction != .Nothing) {
        switch (gameaction) {
            .LoadLevel => G_DoLoadLevel(),
            .NewGame => G_DoNewGame(),
            .LoadGame => G_DoLoadGame(),
            .SaveGame => G_DoSaveGame(),
            .PlayDemo => G_DoPlayDemo(),
            .Completed => G_DoCompleted(),
            .Victory => F_StartFinale(),
            .WorldDone => G_DoWorldDone(),
            .Screenshot => {
                M_ScreenShot();
                gameaction = .Nothing;
            },
            .Nothing => {},
        }
    }

    // get commands, check consistancy,
    // and build new consistancy check
    const buf: usize = @intCast(@mod(@divTrunc(gametic, d_net.ticdup), d_net.BACKUPTICS));

    for (0..MAXPLAYERS) |i| {
        if (playeringame[i] != c.false) {
            const cmd = &players[i].cmd;

            cmd.* = @as(*@TypeOf(players[i].cmd), @ptrCast(&d_net.netcmds[i][buf])).*;

            if (demoplayback != c.false) {
                // TODO: Remove cast after player_t is ported to zig and .cmd has TicCmd type
                G_ReadDemoTiccmd(@ptrCast(cmd));
            }
            if (demorecording) {
                // TODO: Remove cast after player_t is ported to zig and .cmd has TicCmd type
                G_WriteDemoTiccmd(@ptrCast(cmd));
            }

            // check for turbo cheats
            if (cmd.forwardmove > TURBOTHRESHOLD
                and (gametic&31) == 0 and ((gametic>>5)&3) == i) {
                const S = struct {
                    var turbomessage: [80]u8 = undefined;
                };
                _ = fmt.bufPrintZ(&S.turbomessage, "{s} is turbo!", .{hu_stuff.player_names[i]}) catch unreachable;
                players[consoleplayer].message = &S.turbomessage;
            }

            if (netgame != c.false and !netdemo and @mod(gametic, d_net.ticdup) == 0) {
                if (gametic > d_net.BACKUPTICS
                    and consistancy[i][buf] != cmd.consistancy) {
                    I_Error("consistency failure (%i should be %i)",
                            cmd.consistancy, consistancy[i][buf]);
                }
                if (players[i].mo != null) {
                    consistancy[i][buf] = @truncate(players[i].mo[0].x);
                } else {
                    consistancy[i][buf] = @truncate(rndindex);
                }
            }
        }
    }

    // check for special buttons
    for (0..MAXPLAYERS) |i| {
        if (playeringame[i] != c.false) {
            if (players[i].cmd.buttons & c.BT_SPECIAL != 0) {
                switch (players[i].cmd.buttons & c.BT_SPECIALMASK) {
                    c.BTS_PAUSE => {
                        paused = !paused;
                        if (paused) {
                            I_PauseMouseCapture();
                            S_PauseSound();
                        } else {
                            I_ResumeMouseCapture();
                            S_ResumeSound();
                        }
                    },

                    c.BTS_SAVEGAME => {
                        if (savedescription[0] == 0) {
                            _ = fmt.bufPrintZ(&savedescription, "NET GAME", .{}) catch unreachable;
                        }
                        savegameslot =
                            (players[i].cmd.buttons & c.BTS_SAVEMASK)>>c.BTS_SAVESHIFT;
                        gameaction = .SaveGame;
                    },

                    else => {},
                }
            }
        }
    }

    // do main actions
    switch (gamestate) {
        .Level => {
            P_Ticker();
            ST_Ticker();
            c.AM_Ticker();
            HU_Ticker();
        },
        .Intermission => WI_Ticker(),
        .Finale => F_Ticker(),
        .DemoScreen => D_PageTicker(),
        else => {},
    }
}


//
// PLAYER STRUCTURE FUNCTIONS
// also see P_SpawnPlayer in P_Things
//

//
// G_PlayerFinishLevel
// Can when a player completes a level.
//
export fn G_PlayerFinishLevel(player: usize) void {
    const p = &players[player];

    for (&p.powers) |*power| {
        power.* = 0;
    }
    for (&p.cards) |*card| {
        card.* = 0;
    }
    p.mo[0].flags &= ~c.MF_SHADOW;      // cancel invisibility
    p.extralight = 0;                   // cancel gun flashes
    p.fixedcolormap = 0;                // cancel ir gogles
    p.damagecount = 0;                  // no palette changes
    p.bonuscount = 0;
}


//
// G_PlayerReborn
// Called after a player dies
// almost everything is cleared and initialized
//
export fn G_PlayerReborn(player: c_int) void {
    const frags = players[@intCast(player)].frags;
    const killcount = players[@intCast(player)].killcount;
    const itemcount = players[@intCast(player)].itemcount;
    const secretcount = players[@intCast(player)].secretcount;

    const p = &players[@intCast(player)];
    p.* = mem.zeroes(player_t);

    players[@intCast(player)].frags = frags;
    players[@intCast(player)].killcount = killcount;
    players[@intCast(player)].itemcount = itemcount;
    players[@intCast(player)].secretcount = secretcount;

    p.usedown = c.true;
    p.attackdown = c.true;    // don't do anything immediately
    p.playerstate = c.PST_LIVE;
    p.health = c.MAXHEALTH;
    p.readyweapon = @intFromEnum(WeaponType.Pistol);
    p.pendingweapon = @intFromEnum(WeaponType.Pistol);
    p.weaponowned[@intFromEnum(WeaponType.Fist)] = c.true;
    p.weaponowned[@intFromEnum(WeaponType.Pistol)] = c.true;
    p.ammo[c.am_clip] = 50;
    p.maxammo = c.maxammo;
}

extern fn P_CheckPosition(thing: @TypeOf(players[0].mo), x: c.fixed_t, y: c.fixed_t) c.boolean;
extern fn P_RemoveMobj(th: @TypeOf(players[0].mo)) void;

//
// G_CheckSpot
// Returns false if the player cannot be respawned
// at the given mapthing_t spot
// because something is occupying it
//
export fn G_CheckSpot(playernum: c_int, mthing: *c.mapthing_t) bool {
    if (players[@intCast(playernum)].mo == null) {
        // first spawn of level, before corpses
        for (0..@intCast(playernum)) |i| {
            if (players[i].mo[0].x == @as(c.fixed_t, mthing.x) << c.FRACBITS
                and players[i].mo[0].y == @as(c.fixed_t, mthing.y) << c.FRACBITS) {
                return false;
            }
        }
        return true;
    }

    const x: c.fixed_t = @as(c.fixed_t, mthing.x) << c.FRACBITS;
    const y: c.fixed_t = @as(c.fixed_t, mthing.y) << c.FRACBITS;

    if (P_CheckPosition(players[@intCast(playernum)].mo, x, y) == c.false) {
        return false;
    }

    // flush an old corpse if needed
    const slot: usize = @intCast(@mod(bodyqueslot, BODYQUESIZE));
    if (bodyqueslot >= BODYQUESIZE) {
        P_RemoveMobj(bodyque[slot]);
    }
    bodyque[slot] = players[@intCast(playernum)].mo;
    bodyqueslot += 1;

    // spawn a teleport fog
    const ss = c.R_PointInSubsector(x,y);
    const an: usize = @intCast((c.ANG45 *% @divTrunc(mthing.angle, 45)) >> c.ANGLETOFINESHIFT);

    const mo = c.P_SpawnMobj(x+20*c.finecosine[an], y+20*c.finesine[an]
                      , ss[0].sector[0].floorheight
                      , c.MT_TFOG);

    if (players[consoleplayer].viewz != 1) {
        S_StartSound(mo, .telept);  // don't start sound on first frame
    }

    return true;
}


//
// G_DeathMatchSpawnPlayer
// Spawns a player at one of the random death match spots
// called at level load and each death
//
extern fn P_SpawnPlayer(mthing: *c.mapthing_t) void;

export fn G_DeathMatchSpawnPlayer(playernum: c_int) void {
    const selections = @divTrunc(@intFromPtr(c.deathmatch_p) - @intFromPtr(&c.deathmatchstarts[0]), @sizeOf(c.mapthing_t));
    if (selections < 4) {
        I_Error("Only %i deathmatch spots, 4 required", selections);
    }

    for (0..20) |_| {
        const i = @as(usize, @intCast(P_Random())) % selections;
        if (G_CheckSpot(playernum, &c.deathmatchstarts[i]))
        {
            c.deathmatchstarts[i].type = @intCast(playernum+1);
            P_SpawnPlayer(&c.deathmatchstarts[i]);
            return;
        }
    }

    // no good spot, so the player will probably get stuck
    P_SpawnPlayer(&c.playerstarts[@intCast(playernum)]);
}

//
// G_DoReborn
//
fn G_DoReborn(playernum: c_int) void {
    if (c.netgame == c.false) {
        // reload the level from scratch
        gameaction = .LoadLevel;
    } else {
        // respawn at the start

        // first dissasociate the corpse
        players[@intCast(playernum)].mo[0].player = null;

        // spawn at random spot if in death match
        if (deathmatch != c.false) {
            G_DeathMatchSpawnPlayer(playernum);
            return;
        }

        if (G_CheckSpot(playernum, &c.playerstarts[@intCast(playernum)])) {
            P_SpawnPlayer(&c.playerstarts[@intCast(playernum)]);
            return;
        }

        // try to spawn at one of the other players spots
        for (0..MAXPLAYERS) |i| {
            if (G_CheckSpot(playernum, &c.playerstarts[i])) {
                c.playerstarts[i].type = @intCast(playernum+1);     // fake as other player
                P_SpawnPlayer(&c.playerstarts[i]);
                c.playerstarts[i].type = @intCast(i+1);             // restore
                return;
            }
            // he's going to be inside something.  Too bad.
        }
        P_SpawnPlayer(&c.playerstarts[@intCast(playernum)]);
    }
}


pub fn G_ScreenShot() void {
    gameaction = .Screenshot;
}



// DOOM Par Times
var pars = [4][9]c_int{
    .{30,75,120,90,165,180,180,30,165},
    .{90,90,90,120,90,360,240,30,170},
    .{90,45,90,150,90,90,165,30,135},
    .{0}**9,
};

// DOOM II Par Times
var cpars = [32]c_int{
    30,90,120,120,90,150,120,120,270,90,        //  1-10
    210,150,150,150,210,150,420,150,210,150,    // 11-20
    240,150,180,150,150,300,330,420,300,180,    // 21-30
    120,30                                      // 31-32
};


//
// G_DoCompleted
//
var secretexit = false;
extern var pagename: [*:0]u8;

export fn G_ExitLevel() void {
    secretexit = false;
    gameaction = .Completed;
}

// Here's for the german edition.
export fn G_SecretExitLevel() void {
    // IF NO WOLF3D LEVELS, NO SECRET EXIT!
    if (doomstat.gamemode == .Commercial and W_CheckNumForName("map31") < 0) {
        secretexit = false;
    } else {
        secretexit = true;
    }
    gameaction = .Completed;
}

fn G_DoCompleted() void {
    gameaction = .Nothing;

    for (0..MAXPLAYERS) |i| {
        if (playeringame[i] != c.false) {
            G_PlayerFinishLevel(i);        // take away cards and stuff
        }
    }

    if (c.automapactive != c.false) {
        c.AM_Stop();
    }

    if (doomstat.gamemode != .Commercial)
        switch (gamemap) {
            8 => {
                gameaction = .Victory;
                return;
            },
            9 => {
                for (0..MAXPLAYERS) |i| {
                    players[i].didsecret = c.true;
                }
            },
            else => {},
        };

//#if 0  Hmmm - why?
    if (gamemap == 8 and doomstat.gamemode != .Commercial) {
        // victory
        gameaction = .Victory;
        return;
    }

    if (gamemap == 9 and doomstat.gamemode != .Commercial) {
        // exit secret level
        for (0..MAXPLAYERS) |i| {
            players[i].didsecret = c.true;
        }
    }
//#endif


    wminfo.didsecret = players[consoleplayer].didsecret;
    wminfo.epsd = gameepisode - 1;
    wminfo.last = gamemap - 1;

    // wminfo.next is 0 biased, unlike gamemap
    if (doomstat.gamemode == .Commercial) {
        if (secretexit) {
            switch (gamemap) {
                15 => wminfo.next = 30,
                31 => wminfo.next = 31,
                else => {},
            }
        } else {
            switch (gamemap) {
                31, 32 => wminfo.next = 15,
                else => wminfo.next = gamemap,
            }
        }
    } else {
        if (secretexit) {
            wminfo.next = 8;    // go to secret level
        } else if (gamemap == 9) {
            // returning from secret level
            switch (gameepisode) {
                1 => wminfo.next = 3,
                2 => wminfo.next = 5,
                3 => wminfo.next = 6,
                4 => wminfo.next = 2,
                else => {},
            }
        } else {
            wminfo.next = gamemap;          // go to next level
        }
    }

    wminfo.maxkills = totalkills;
    wminfo.maxitems = totalitems;
    wminfo.maxsecret = totalsecret;
    wminfo.maxfrags = 0;
    if (doomstat.gamemode == .Commercial) {
        wminfo.partime = 35 * cpars[@intCast(gamemap-1)];
    } else {
        wminfo.partime = 35 * pars[@intCast(gameepisode-1)][@intCast(gamemap-1)];
    }
    wminfo.pnum = @intCast(consoleplayer);

    for (0..MAXPLAYERS) |i| {
        wminfo.plyr[i].in = playeringame[i];
        wminfo.plyr[i].skills = players[i].killcount;
        wminfo.plyr[i].sitems = players[i].itemcount;
        wminfo.plyr[i].ssecret = players[i].secretcount;
        wminfo.plyr[i].stime = c.leveltime;
        wminfo.plyr[i].frags = players[i].frags;
    }

    gamestate = .Intermission;
    viewactive = c.false;
    c.automapactive = c.false;

    // NOTE: Not supporting statcopy in zig build
    // if (statcopy) {
    //     memcpy(statcopy, &wminfo, sizeof(wminfo));
    // }

    WI_Start(&wminfo);
}


//
// G_WorldDone
//
pub fn G_WorldDone() void {
    gameaction = .WorldDone;

    if (secretexit) {
        players[consoleplayer].didsecret = c.true;
    }

    if (doomstat.gamemode == .Commercial) {
        const dofinale = switch (gamemap) {
            15, 31 => secretexit,
            6, 11, 20, 30 => true,
            else => false,
        };
        if (dofinale) {
            F_StartFinale();
        }
    }
}

fn G_DoWorldDone() void {
    gamestate = .Level;
    gamemap = wminfo.next+1;
    G_DoLoadLevel();
    gameaction = .Nothing;
    viewactive = c.true;
}



//
// G_InitFromSavegame
// Can be called by the startup code or the menu task.
//
extern var setsizeneeded: c.boolean;
extern fn R_ExecuteSetViewSize() void;

var savenamebuf: [256]u8 = undefined;
var savename: []const u8 = undefined;

pub fn G_LoadGame(name: [:0]const u8) void {
    savename = fmt.bufPrint(&savenamebuf, "{s}", .{name}) catch unreachable;
    gameaction = .LoadGame;
}

const VERSIONSIZE = 16;


extern fn A_BrainAwake(mo: *c.mobj_t) void;
fn G_DoLoadGame() void {
    gameaction = .Nothing;

    const buffer = M_ReadFile(savename);
    defer z_zone.free(buffer);

    var fbs = io.fixedBufferStream(buffer);
    var reader = fbs.reader();

    // skip the description field
    reader.skipBytes(SAVESTRINGSIZE, .{}) catch unreachable;

    var vcheck = [_]u8{0} ** VERSIONSIZE;
    _ = fmt.bufPrintZ(&vcheck, "version {d}", .{c.VERSION}) catch unreachable;
    const version = reader.readBytesNoEof(VERSIONSIZE) catch unreachable;
    if (!mem.eql(u8, &version, &vcheck)) {
        return;
    }

    gameskill = @enumFromInt(reader.readByte() catch unreachable);
    gameepisode = reader.readByte() catch unreachable;
    gamemap = reader.readByte() catch unreachable;
    for (0..MAXPLAYERS) |j| {
        playeringame[j] = reader.readByte() catch unreachable;
    }

    // load a base level
    G_InitNew(gameskill, gameepisode, gamemap);

    // get the times
    const a = @as(c_int, reader.readByte() catch unreachable);
    const b = @as(c_int, reader.readByte() catch unreachable);
    const _c = @as(c_int, reader.readByte() catch unreachable);
    c.leveltime = (a<<16) + (b<<8) + _c;

    // dearchive all the modifications
    // TODO: Eliminate the `save_p` global and pass `reader`
    // to the unarchive functions instead.
    const pos: usize = fbs.getPos() catch unreachable;
    c.save_p = @constCast(&buffer[pos]);
    c.P_UnArchivePlayers();
    c.P_UnArchiveWorld();
    c.P_UnArchiveThinkers();
    c.P_UnArchiveSpecials();

    if (c.save_p.* != 0x1d) {
        I_Error("Bad savegame");
    }

    if (setsizeneeded != c.false) {
        R_ExecuteSetViewSize();
    }

    // draw the pattern into the back screen
    c.R_FillBackScreen();

    // Hack fix for crash on loading save games in map 30
    if (gamemap == 30 and doomstat.gamemode == .Commercial) {
        var thinker = p_tick.thinkercap.next orelse &p_tick.thinkercap;
        while (thinker != &p_tick.thinkercap) : (thinker = thinker.next.?) {
            // not a mobj
            if (thinker.function.acp1 != @as(p_tick.actionf_p1, @ptrCast(&c.P_MobjThinker))) {
                continue;
            }

            const m = @as(*c.mobj_t, @ptrCast(thinker));

            if (m.type == c.MT_BOSSBRAIN) {
                A_BrainAwake(m);
            }
        }
    }
}


//
// G_SaveGame
// Called by the menu task.
// Description is a 24 byte text string
//
pub fn G_SaveGame(slot: c_int, description: [*:0]const u8) void {
    savegameslot = slot;
    _ = fmt.bufPrintZ(&savedescription, "{s}", .{description}) catch unreachable;
    sendsave = true;
}

fn G_DoSaveGame() void {
    var namebuf: [100]u8 = undefined;
    const name =
        if (M_CheckParm("-cdrom") != 0)
            fmt.bufPrint(&namebuf, "c:\\doomdata\\{s}{d}.dsg", .{c.SAVEGAMENAME, savegameslot}) catch unreachable
        else
            fmt.bufPrint(&namebuf, "{s}{d}.dsg", .{c.SAVEGAMENAME, savegameslot}) catch unreachable
        ;

    var buffer = v_video.screens[1][0x4000..0x4000+SAVEGAMESIZE];
    var fbs = io.fixedBufferStream(buffer);
    var writer = fbs.writer();

    _ = writer.write(&savedescription) catch unreachable;

    var version = [_]u8{0} ** VERSIONSIZE;
    _ = fmt.bufPrintZ(&version, "version {d}", .{c.VERSION}) catch unreachable;
    _ = writer.write(&version) catch unreachable;

    _ = writer.writeByte(@intCast(@intFromEnum(gameskill))) catch unreachable;
    _ = writer.writeByte(@intCast(gameepisode)) catch unreachable;
    _ = writer.writeByte(@intCast(gamemap)) catch unreachable;
    for (0..MAXPLAYERS) |i| {
        _ = writer.writeByte(@intCast(playeringame[i])) catch unreachable;
    }
    const lt: u32 = @intCast(c.leveltime);
    _ = writer.writeByte(@truncate(lt>>16)) catch unreachable;
    _ = writer.writeByte(@truncate(lt>>8)) catch unreachable;
    _ = writer.writeByte(@truncate(lt)) catch unreachable;

    // TODO: Use `writer` instead of `save_p` in archive functions
    const pos: usize = fbs.getPos() catch unreachable;
    c.save_p = &buffer[pos];
    c.P_ArchivePlayers();
    c.P_ArchiveWorld();
    c.P_ArchiveThinkers();
    c.P_ArchiveSpecials();

    c.save_p.* = 0x1d;          // consistancy marker
    c.save_p += 1;

    // TODO: buffer overrun is detected during writer api calls;
    // utilize those errors to detect and report this I_Error().
    const length = @intFromPtr(c.save_p) - @intFromPtr(buffer.ptr);
    if (length > SAVEGAMESIZE) {
        I_Error("Savegame buffer overrun");
    }
    _ = M_WriteFile(name, buffer[0..length]);
    gameaction = .Nothing;
    _ = fmt.bufPrintZ(&savedescription, "", .{}) catch unreachable;

    players[consoleplayer].message = c.GGSAVED;

    // draw the pattern into the back screen
    c.R_FillBackScreen ();
}


//
// G_InitNew
// Can be called by the startup code or the menu task,
// consoleplayer, displayplayer, playeringame[] should be set.
//
var d_skill: Skill = undefined;
var d_episode: c_int = 0;
var d_map: c_int = 0;

pub fn G_DeferedInitNew(skill: Skill, episode: c_int, map: c_int) void {
    d_skill = skill;
    d_episode = episode;
    d_map = map;
    gameaction = .NewGame;
}


fn G_DoNewGame() void {
    demoplayback = c.false;
    netdemo = false;
    netgame = c.false;
    deathmatch = c.false;
    for (playeringame[1..]) |*pig| {
        pig.* = c.false;
    }
    d_main.respawnparm = false;
    c.fastparm = c.false;
    d_main.nomonsters = c.false;
    consoleplayer = 0;
    G_InitNew(d_skill, d_episode, d_map);
    gameaction = .Nothing;
}

pub fn G_InitNew(skill: Skill, episode: c_int, map: c_int) void {
    if (paused) {
        paused = false;
        S_ResumeSound();
    }

    var _episode = episode;


    // This was quite messy with SPECIAL and commented parts.
    // Supposedly hacks to make the latest edition work.
    // It might not work properly.
    if (_episode < 1) {
        _episode = 1;
    }

    if (doomstat.gamemode == .Retail) {
        if (_episode > 4) {
            _episode = 4;
        }
    } else if (doomstat.gamemode == .Shareware) {
        if (_episode > 1) {
            _episode = 1; // only start episode 1 on shareware
        }
    } else {
        if (_episode > 3) {
            _episode = 3;
        }
    }


    var _map = map;


    if (_map < 1) {
        _map = 1;
    }

    if (_map > 9 and doomstat.gamemode != .Commercial) {
        _map = 9;
    }

    M_ClearRandom();

    if (skill == .Nightmare or d_main.respawnparm) {
        respawnmonsters = c.true;
    } else {
        respawnmonsters = c.false;
    }

    if (c.fastparm != c.false or (skill == .Nightmare and gameskill != .Nightmare)) {
        for (c.S_SARG_RUN1..c.S_SARG_PAIN2+1) |i| {
            c.states[i].tics >>= 1;
        }
        c.mobjinfo[c.MT_BRUISERSHOT].speed = 20*c.FRACUNIT;
        c.mobjinfo[c.MT_HEADSHOT].speed = 20*c.FRACUNIT;
        c.mobjinfo[c.MT_TROOPSHOT].speed = 20*c.FRACUNIT;
    } else if (skill != .Nightmare and gameskill == .Nightmare) {
        for (c.S_SARG_RUN1..c.S_SARG_PAIN2+1) |i| {
            c.states[i].tics <<= 1;
        }
        c.mobjinfo[c.MT_BRUISERSHOT].speed = 15*c.FRACUNIT;
        c.mobjinfo[c.MT_HEADSHOT].speed = 10*c.FRACUNIT;
        c.mobjinfo[c.MT_TROOPSHOT].speed = 10*c.FRACUNIT;
    }


    // force players to be initialized upon first level load
    for (&players) |*p| {
        p.playerstate = c.PST_REBORN;
    }

    usergame = true;                // will be set false if a demo
    paused = false;
    demoplayback = c.false;
    c.automapactive = c.false;
    viewactive = c.true;
    gameepisode = episode;
    gamemap = _map;
    gameskill = skill;

    viewactive = c.true;

    // set the sky map for the episode
    if (doomstat.gamemode == .Commercial) {
        if (gamemap < 12) {
            r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY1"));
        } else if (gamemap < 21) {
            r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY2"));
        } else {
            r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY3"));
        }
    } else {
        switch (episode) {
            1 => r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY1")),
            2 => r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY2")),
            3 => r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY3")),
            4 => r_sky.skytexture = c.R_TextureNumForName(@constCast("SKY4")),
            else => {},
        }
    }

    G_DoLoadLevel();
}


//
// DEMO RECORDING
//
const DEMOMARKER = 0x80;


fn G_ReadDemoTiccmd(cmd: *TicCmd) void {
    // TODO: Use an io.Reader
    if (demo_p[0] == DEMOMARKER) {
        // end of demo data stream
        _ = G_CheckDemoStatus();
        return;
    }
    cmd.forwardmove = @bitCast(demo_p[0]);
    demo_p += 1;
    cmd.sidemove = @bitCast(demo_p[0]);
    demo_p += 1;
    cmd.angleturn = @bitCast(@as(u16, demo_p[0])<<8);
    demo_p += 1;
    cmd.buttons = demo_p[0];
    demo_p += 1;
}


fn G_WriteDemoTiccmd(cmd: *TicCmd) void {
    if (gamekeydown['q']) {         // press q to end demo recording
        _ = G_CheckDemoStatus();
    }
    // TODO: Use an io.Writer
    demo_p[0] = @bitCast(cmd.forwardmove);
    demo_p += 1;
    demo_p[0] = @bitCast(cmd.sidemove);
    demo_p += 1;
    demo_p[0] = @bitCast(@as(i8, @intCast((cmd.angleturn+128)>>8)));
    demo_p += 1;
    demo_p[0] = cmd.buttons;
    demo_p += 1;
    demo_p -= 4;

    // TODO: Handle buffer overrun via io.Writer
    if (@intFromPtr(demo_p) > @intFromPtr(demoend) - 16) {
        // no more space
        _ = G_CheckDemoStatus();
        return;
    }

    G_ReadDemoTiccmd(cmd);         // make SURE it is exactly the same
}



//
// G_RecordDemo
//
pub fn G_RecordDemo(name: []const u8) void {
    usergame = false;
    demoname = fmt.bufPrintZ(&demonamebuf, "{s}.lmp", .{name}) catch unreachable;
    const i: usize = @intCast(M_CheckParm("-maxdemo"));
    const maxsize: i32 =
        if (i != 0 and i<m_argv.myargc-1)
            (fmt.parseInt(i32, mem.span(m_argv.myargv[i+1]), 0) catch 128)*1024
        else
            0x20000;
    // TODO: Convert to z_zone.alloc() and make demobuffer a slice, eliminate demoend
    demobuffer = @ptrCast(z_zone.Z_Malloc(maxsize, .Static, null));
    demoend = demobuffer + @as(usize, @intCast(maxsize));

    demorecording = true;
}


pub fn G_BeginRecording() void {
    demo_p = demobuffer;

    demo_p[0] = c.VERSION;
    demo_p += 1;
    demo_p[0] = @intCast(@intFromEnum(gameskill));
    demo_p += 1;
    demo_p[0] = @intCast(gameepisode);
    demo_p += 1;
    demo_p[0] = @intCast(gamemap);
    demo_p += 1;
    demo_p[0] = @intCast(deathmatch);
    demo_p += 1;
    demo_p[0] = @intFromBool(d_main.respawnparm);
    demo_p += 1;
    demo_p[0] = @intCast(c.fastparm);
    demo_p += 1;
    demo_p[0] = @intCast(d_main.nomonsters);
    demo_p += 1;
    demo_p[0] = @intCast(consoleplayer);
    demo_p += 1;

    for (playeringame) |pig| {
        demo_p[0] = @intCast(pig);
        demo_p += 1;
    }
}


//
// G_PlayDemo
//

var defdemoname: [*]const u8 = undefined;

pub fn G_DeferedPlayDemo(name: [*]const u8) void {
    defdemoname = name;
    gameaction = .PlayDemo;
}

fn G_DoPlayDemo() void {
    gameaction = .Nothing;
    demobuffer = @ptrCast(W_CacheLumpName(defdemoname, .Static));
    demo_p = demobuffer;
    const demoversion = demo_p[0];
    demo_p += 1;
    if (demoversion != c.VERSION and (c.VERSION == 110 and demoversion != 109)) {
        const stderr = io.getStdErr().writer();
        stderr.print("Demo is from a different game version!\n", .{}) catch {};
        gameaction = .Nothing;
        return;
    }

    const skill: Skill = @enumFromInt(demo_p[0]);
    demo_p += 1;
    const episode: c_int = demo_p[0];
    demo_p += 1;
    const map: c_int = demo_p[0];
    demo_p += 1;
    deathmatch = demo_p[0];
    demo_p += 1;
    d_main.respawnparm = demo_p[0] != 0;
    demo_p += 1;
    c.fastparm = demo_p[0];
    demo_p += 1;
    d_main.nomonsters = demo_p[0];
    demo_p += 1;
    consoleplayer = demo_p[0];
    demo_p += 1;

    for (&playeringame) |*pig| {
        pig.* = demo_p[0];
        demo_p += 1;
    }
    if (playeringame[1] != c.false)
    {
        netgame = c.true;
        netdemo = true;
    }

    // don't spend a lot of time in loadlevel
    precache = c.false;
    G_InitNew(skill, episode, map);
    precache = c.true;

    usergame = false;
    demoplayback = c.true;
}

//
// G_TimeDemo
//
pub fn G_TimeDemo(name: [*]const u8) void {
    nodrawers = M_CheckParm("-nodraw") != 0;
    timingdemo = true;
    d_main.singletics = true;

    defdemoname = name;
    gameaction = .PlayDemo;
}


// ===================
// =
// = G_CheckDemoStatus
// =
// = Called after a death or level completion to allow demos to be cleaned up
// = Returns true if a new demo loop action will take place
// ===================

pub fn G_CheckDemoStatus() bool {
    if (timingdemo) {
        const endtime = I_GetTime();
        I_Error("timed %i gametics in %i realtics", gametic, endtime-starttime);
    }

    if (demoplayback != c.false) {
        if (singledemo != c.false) {
            I_Quit();
        }

        Z_ChangeTag(demobuffer, .Cache);
        demoplayback = c.false;
        netdemo = false;
        netgame = c.false;
        deathmatch = c.false;
        playeringame[1] = c.false;
        playeringame[2] = c.false;
        playeringame[3] = c.false;
        d_main.respawnparm = false;
        c.fastparm = c.false;
        d_main.nomonsters = c.false;
        consoleplayer = 0;
        D_AdvanceDemo();
        return true;
    }

    if (demorecording) {
        demo_p[0] = DEMOMARKER;
        demo_p += 1;
        const len = @intFromPtr(demo_p) - @intFromPtr(demobuffer);
        _ = M_WriteFile(demoname, demobuffer[0..len]);
        Z_Free(demobuffer);
        demorecording = false;
        I_Error("Demo %s recorded", &demonamebuf);
    }

    return false;
}
