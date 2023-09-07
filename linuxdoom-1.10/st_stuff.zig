pub const c = @cImport({
    @cInclude("doomdef.h");
    @cInclude("doomstat.h");
    @cInclude("dstrings.h");
    @cInclude("d_event.h");
    @cInclude("d_items.h");
    @cInclude("d_player.h");
    @cInclude("tables.h");
    @cInclude("am_map.h");
    @cInclude("g_game.h");
    @cInclude("p_inter.h");
    @cInclude("r_main.h");
    @cInclude("sounds.h");
    @cInclude("s_sound.h");
});

extern fn V_CopyRect(srcx: c_int, srcy: c_int, srcscrn: c_int, width: c_int, height: c_int, destx: c_int, desty: c_int, destscr: c_int) void;
extern fn V_DrawPatch(x: c_int, y: c_int, scrn: c_int, patch: *c.patch_t) void;

const fmt = @import("std").fmt;

const d_main = @import("d_main.zig");
const Event = d_main.Event;

const m_cheat = @import("m_cheat.zig");
const CheatSeq = m_cheat.CheatSeq;
const cht_CheckCheat = m_cheat.cht_CheckCheat;
const cht_GetParam = m_cheat.cht_GetParam;

const M_Random = @import("m_random.zig").M_Random;

const st_lib = @import("st_lib.zig");
const StNumber = st_lib.StNumber;
const StPercent = st_lib.StPercent;
const StMultIcon = st_lib.StMultIcon;
const StBinIcon = st_lib.StBinIcon;
const BG = st_lib.BG;
const FG = st_lib.FG;
const STlib_init = st_lib.STlib_init;
const STlib_initNum = st_lib.STlib_initNum;
const STlib_initPercent = st_lib.STlib_initPercent;
const STlib_initMultIcon = st_lib.STlib_initMultIcon;
const STlib_initBinIcon = st_lib.STlib_initBinIcon;
const STlib_updateNum = st_lib.STlib_updateNum;
const STlib_updatePercent = st_lib.STlib_updatePercent;
const STlib_updateMultIcon = st_lib.STlib_updateMultIcon;
const STlib_updateBinIcon = st_lib.STlib_updateBinIcon;

const I_SetPalette = @import("i_video.zig").I_SetPalette;

const w_wad = @import("w_wad.zig");
const W_CacheLumpName = w_wad.W_CacheLumpName;
const W_CacheLumpNum = w_wad.W_CacheLumpNum;
const W_GetNumForName = w_wad.W_GetNumForName;

const z_zone = @import("z_zone.zig");
const Z_ChangeTag = z_zone.Z_ChangeTag;
const Z_Malloc = z_zone.Z_Malloc;

// Size of statusbar.
// Now sensitive for scaling.
pub const ST_HEIGHT = 32 * c.SCREEN_MUL;
pub const ST_WIDTH = c.SCREENWIDTH;
pub const ST_Y = (c.SCREENHEIGHT - ST_HEIGHT);

//
// STATUS BAR DATA
//

// Palette indices.
// For damage/bonus red-/gold-shifts
const STARTREDPALS = 1;
const STARTBONUSPALS = 9;
const NUMREDPALS = 8;   // BUG: There are actually 9 and 5 palettes
const NUMBONUSPALS = 4; // for red and bonus. Could fix this if desired.
// Radiation suit, green shift.
const RADIATIONPAL = 13;

// Location of status bar
const ST_X = 0;

const ST_FX = 143;

// Number of status faces.
const ST_NUMPAINFACES = 5;
const ST_NUMSTRAIGHTFACES = 3;
const ST_NUMTURNFACES = 2;
const ST_NUMSPECIALFACES = 3;

const ST_FACESTRIDE = (ST_NUMSTRAIGHTFACES + ST_NUMTURNFACES + ST_NUMSPECIALFACES);

const ST_NUMEXTRAFACES = 2;

const ST_NUMFACES = (ST_FACESTRIDE * ST_NUMPAINFACES + ST_NUMEXTRAFACES);

const ST_TURNOFFSET = (ST_NUMSTRAIGHTFACES);
const ST_OUCHOFFSET = (ST_TURNOFFSET + ST_NUMTURNFACES);
const ST_EVILGRINOFFSET = (ST_OUCHOFFSET + 1);
const ST_RAMPAGEOFFSET = (ST_EVILGRINOFFSET + 1);
const ST_GODFACE = (ST_NUMPAINFACES * ST_FACESTRIDE);
const ST_DEADFACE = (ST_GODFACE + 1);

const ST_FACESX = 143;
const ST_FACESY = 168;

const ST_EVILGRINCOUNT = (2 * c.TICRATE);
const ST_STRAIGHTFACECOUNT = (c.TICRATE / 2);
const ST_TURNCOUNT = (1 * c.TICRATE);
const ST_OUCHCOUNT = (1 * c.TICRATE);
const ST_RAMPAGEDELAY = (2 * c.TICRATE);

const ST_MUCHPAIN = 20;

// Location and size of statistics,
//  justified according to widget type.
// Problem is, within which space? STbar? Screen?
// Note: this could be read in by a lump.
//       Problem is, is the stuff rendered
//       into a buffer,
//       or into the frame buffer?

// AMMO number pos.
const ST_AMMOWIDTH = 3;
const ST_AMMOX = 44;
const ST_AMMOY = 171;

// HEALTH number pos.
const ST_HEALTHX = 90;
const ST_HEALTHY = 171;

// Weapon pos.
const ST_ARMSX = 111;
const ST_ARMSY = 172;
const ST_ARMSBGX = 104;
const ST_ARMSBGY = 168;
const ST_ARMSXSPACE = 12;
const ST_ARMSYSPACE = 10;

// Frags pos.
const ST_FRAGSX = 138;
const ST_FRAGSY = 171;
const ST_FRAGSWIDTH = 2;

// ARMOR number pos.
const ST_ARMORX = 221;
const ST_ARMORY = 171;

// Key icon positions.
const ST_KEY0WIDTH = 8;
const ST_KEY0X = 239;
const ST_KEY0Y = 171;
const ST_KEY1X = 239;
const ST_KEY1Y = 181;
const ST_KEY2X = 239;
const ST_KEY2Y = 191;

// Ammunition counter.
const ST_AMMO0WIDTH = 3;
const ST_AMMO0X = 288;
const ST_AMMO0Y = 173;
const ST_AMMO1WIDTH = ST_AMMO0WIDTH;
const ST_AMMO1X = 288;
const ST_AMMO1Y = 179;
const ST_AMMO2WIDTH = ST_AMMO0WIDTH;
const ST_AMMO2X = 288;
const ST_AMMO2Y = 191;
const ST_AMMO3WIDTH = ST_AMMO0WIDTH;
const ST_AMMO3X = 288;
const ST_AMMO3Y = 185;

// Indicate maximum ammunition.
// Only needed because backpack exists.
const ST_MAXAMMO0WIDTH = 3;
const ST_MAXAMMO0X = 314;
const ST_MAXAMMO0Y = 173;
const ST_MAXAMMO1WIDTH = ST_MAXAMMO0WIDTH;
const ST_MAXAMMO1X = 314;
const ST_MAXAMMO1Y = 179;
const ST_MAXAMMO2WIDTH = ST_MAXAMMO0WIDTH;
const ST_MAXAMMO2X = 314;
const ST_MAXAMMO2Y = 191;
const ST_MAXAMMO3WIDTH = ST_MAXAMMO0WIDTH;
const ST_MAXAMMO3X = 314;
const ST_MAXAMMO3Y = 185;

// Dimensions given in characters.
const ST_MSGWIDTH = 52;

// main player in game
var plyr: *c.player_t = undefined;

// ST_Start() has just been called
var st_firsttime = false;

// lump number for PLAYPAL
var lu_palette: c_int = 0;

// whether left-side main status bar is active
var st_statusbaron = false;

// !deathmatch
var st_notdeathmatch = false;

// !deathmatch && st_statusbaron
var st_armson = false;

// !deathmatch
var st_fragson = false;

// main bar left
var sbar: *c.patch_t = undefined;

// 0-9, tall numbers
var tallnum: [10]*c.patch_t = undefined;

// tall % sign
var tallpercent: *c.patch_t = undefined;

// 0-9, short, yellow (,different!) numbers
var shortnum: [10]*c.patch_t = undefined;

// 3 key-cards, 3 skulls
var keys: [c.NUMCARDS]*c.patch_t = undefined;

// face status patches
var faces: [ST_NUMFACES]*c.patch_t = undefined;

// face background
var faceback: *c.patch_t = undefined;

// main bar right
var armsbg: *c.patch_t = undefined;

// weapon ownership patches
var arms: [6][2]*c.patch_t = undefined;

// ready-weapon widget
var w_ready: StNumber = undefined;

// in deathmatch only, summary of frags stats
var w_frags: StNumber = undefined;

// health widget
var w_health: StPercent = undefined;

// arms background
var w_armsbg: StBinIcon = undefined;

// weapon ownership widgets
var w_arms: [6]StMultIcon = undefined;

// face status widget
var w_faces: StMultIcon = undefined;

// keycard widgets
var w_keyboxes: [3]StMultIcon = undefined;

// armor widget
var w_armor: StPercent = undefined;

// ammo widgets
var w_ammo: [4]StNumber = undefined;

// max ammo widgets
var w_maxammo: [4]StNumber = undefined;

// number of frags so far in deathmatch
var st_fragscount: c_int = 0;

// used to use appopriately pained face
var st_oldhealth: c_int = -1;

// used for evil grin
// TODO: Convert to bool when player_t::weaponowned is converted to bool
var oldweaponsowned = [_]c.boolean{c.false} ** c.NUMWEAPONS;

// count until face changes
var st_facecount: c_int = 0;

// current face index, used by w_faces
var st_faceindex: c_int = 0;

// holds key-type for each key box on bar
var keyboxes = [_]c_int{0} ** 3;

// a random number per tick
var st_randomnumber: c_int = 0;

// Massive bunches of cheat shit
//  to keep it from being easy to figure them out.
// Yeah, right...
var cheat_mus_seq = [_]u8{ 0xb2, 0x26, 0xb6, 0xae, 0xea, 1, 0, 0, 0xff };

var cheat_choppers_seq = [_]u8{
    0xb2, 0x26, 0xe2, 0x32, 0xf6, 0x2a, 0x2a, 0xa6, 0x6a, 0xea, 0xff, // id...
};

var cheat_god_seq = [_]u8{
    0xb2, 0x26, 0x26, 0xaa, 0x26, 0xff, // iddqd
};

var cheat_ammo_seq = [_]u8{
    0xb2, 0x26, 0xf2, 0x66, 0xa2, 0xff, // idkfa
};

var cheat_ammonokey_seq = [_]u8{
    0xb2, 0x26, 0x66, 0xa2, 0xff, // idfa
};

// Smashing Pumpkins Into Samml Piles Of Putried Debris.
var cheat_noclip_seq = [_]u8{
    0xb2, 0x26, 0xea, 0x2a, 0xb2, // idspispopd
    0xea, 0x2a, 0xf6, 0x2a, 0x26,
    0xff,
};

//
var cheat_commercial_noclip_seq = [_]u8{
    0xb2, 0x26, 0xe2, 0x36, 0xb2, 0x2a, 0xff, // idclip
};

var cheat_powerup_seq = [7][10]u8{
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0x6e, 0xff }, // beholdv
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0xea, 0xff }, // beholds
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0xb2, 0xff }, // beholdi
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0x6a, 0xff }, // beholdr
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0xa2, 0xff }, // beholda
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0x36, 0xff }, // beholdl
    .{ 0xb2, 0x26, 0x62, 0xa6, 0x32, 0xf6, 0x36, 0x26, 0xff, 0x00 }, // behold
};

var cheat_clev_seq = [_]u8{
    0xb2, 0x26, 0xe2, 0x36, 0xa6, 0x6e, 1, 0, 0, 0xff, // idclev
};

// my position cheat
var cheat_mypos_seq = [_]u8{
    0xb2, 0x26, 0xb6, 0xba, 0x2a, 0xf6, 0xea, 0xff, // idmypos
};

// Now what?
var cheat_mus = CheatSeq{ .sequence=&cheat_mus_seq, .p=null };
var cheat_god = CheatSeq{ .sequence=&cheat_god_seq, .p=null };
var cheat_ammo = CheatSeq{ .sequence=&cheat_ammo_seq, .p=null };
var cheat_ammonokey = CheatSeq{ .sequence=&cheat_ammonokey_seq, .p=null };
var cheat_noclip = CheatSeq{ .sequence=&cheat_noclip_seq, .p=null };
var cheat_commercial_noclip = CheatSeq{ .sequence=&cheat_commercial_noclip_seq, .p=null };

var cheat_powerup = [7]CheatSeq{
    .{ .sequence=&cheat_powerup_seq[0], .p=null },
    .{ .sequence=&cheat_powerup_seq[1], .p=null },
    .{ .sequence=&cheat_powerup_seq[2], .p=null },
    .{ .sequence=&cheat_powerup_seq[3], .p=null },
    .{ .sequence=&cheat_powerup_seq[4], .p=null },
    .{ .sequence=&cheat_powerup_seq[5], .p=null },
    .{ .sequence=&cheat_powerup_seq[6], .p=null },
};

var cheat_choppers = CheatSeq{ .sequence=&cheat_choppers_seq, .p=null };
var cheat_clev = CheatSeq{ .sequence=&cheat_clev_seq, .p=null };
var cheat_mypos = CheatSeq{ .sequence=&cheat_mypos_seq, .p=null };

//
// STATUS BAR CODE
//
fn ST_refreshBackground() void {
    if (st_statusbaron) {
        V_DrawPatch(ST_X, 0, BG, sbar);

        if (c.netgame != c.false) {
            V_DrawPatch(ST_FX, 0, BG, faceback);
        }

        V_CopyRect(ST_X, 0, BG, ST_WIDTH, ST_HEIGHT, ST_X, ST_Y, FG);
    }
}


// Respond to keyboard input events,
//  intercept cheats.
pub export fn ST_Responder(ev: *Event) c.boolean {
  // Filter automap on/off.
  if (ev.type == .KeyUp
      and (@as(c_uint, @bitCast(ev.data1)) & 0xffff0000) == c.AM_MSGHEADER) {
    switch (ev.data1) {
      c.AM_MSGENTERED => {
        st_firsttime = true;
      },
      c.AM_MSGEXITED => {
        //      fprintf(stderr, "AM exited\n");
      },
      else => {},
    }
  }

  // if a user keypress...
  else if (ev.type == .KeyDown) {
    if (c.netgame == c.false) {
      // b. - enabled for more debug fun.
      // if (gameskill != sk_nightmare)

      // 'dqd' cheat for toggleable god mode
      if (cht_CheckCheat(&cheat_god, @intCast(ev.data1)) != 0) {
        plyr.cheats ^= c.CF_GODMODE;
        if (plyr.cheats & c.CF_GODMODE != 0)
        {
          if (plyr.mo != null) {
            plyr.mo[0].health = 100;
          }

          plyr.health = 100;
          plyr.message = c.STSTR_DQDON;
        }
        else {
          plyr.message = c.STSTR_DQDOFF;
        }
      }
      // 'fa' cheat for killer fucking arsenal
      else if (cht_CheckCheat(&cheat_ammonokey, @intCast(ev.data1)) != 0) {
        plyr.armorpoints = 200;
        plyr.armortype = 2;

        for (&plyr.weaponowned) |*w| {
            w.* = c.true;
        }

        for (&plyr.ammo, plyr.maxammo) |*a, ma| {
            a.* = ma;
        }

        plyr.message = c.STSTR_FAADDED;
      }
      // 'kfa' cheat for key full ammo
      else if (cht_CheckCheat(&cheat_ammo, @intCast(ev.data1)) != 0) {
        plyr.armorpoints = 200;
        plyr.armortype = 2;

        for (&plyr.weaponowned) |*w| {
            w.* = c.true;
        }

        for (&plyr.ammo, plyr.maxammo) |*a, ma| {
            a.* = ma;
        }

        for (&plyr.cards) |*card| {
          card.* = c.true;
        }

        plyr.message = c.STSTR_KFAADDED;
      }
      // 'mus' cheat for changing music
      else if (cht_CheckCheat(&cheat_mus, @intCast(ev.data1)) != 0) {
        var buf = [_]u8{0} ** 3;

        plyr.message = c.STSTR_MUS;
        cht_GetParam(&cheat_mus, &buf);

        if (c.gamemode == c.commercial)
        {
          const musnum = c.mus_runnin + @as(c_int, buf[0]-'0')*10 + buf[1]-'0' - 1;

          if ((@as(c_int, buf[0]-'0')*10 + buf[1]-'0') > 35) {
            plyr.message = c.STSTR_NOMUS;
          } else {
            c.S_ChangeMusic(musnum, 1);
          }
        }
        else
        {
          const musnum = c.mus_e1m1 + @as(c_int, buf[0]-'1')*9 + (buf[1]-'1');

          if ((@as(c_int, buf[0]-'1')*9 + buf[1]-'1') > 31) {
            plyr.message = c.STSTR_NOMUS;
          } else {
            c.S_ChangeMusic(musnum, 1);
          }
        }
      }
      // Simplified, accepting both "noclip" and "idspispopd".
      // no clipping mode cheat
      else if (cht_CheckCheat(&cheat_noclip, @intCast(ev.data1)) != 0
               or cht_CheckCheat(&cheat_commercial_noclip, @intCast(ev.data1)) != 0)
      {
        plyr.cheats ^= c.CF_NOCLIP;

        if (plyr.cheats & c.CF_NOCLIP != 0) {
          plyr.message = c.STSTR_NCON;
        } else {
          plyr.message = c.STSTR_NCOFF;
        }
      }
      // 'behold?' power-up cheats
      for (cheat_powerup[0..6], 0..) |*cheat, i| {
        if (cht_CheckCheat(cheat, @intCast(ev.data1)) != 0)
        {
          // TODO: Convert `powers` to bool
          if (plyr.powers[i] == 0) {
            _ = c.P_GivePower(plyr, @intCast(i));
          } else if (i != c.pw_strength) {
            plyr.powers[i] = 1;
          } else {
            plyr.powers[i] = 0;
          }

          plyr.message = c.STSTR_BEHOLDX;
        }
      }

      // 'behold' power-up menu
      if (cht_CheckCheat(&cheat_powerup[6], @intCast(ev.data1)) != 0)
      {
        plyr.message = c.STSTR_BEHOLD;
      }
      // 'choppers' invulnerability & chainsaw
      else if (cht_CheckCheat(&cheat_choppers, @intCast(ev.data1)) != 0)
      {
        plyr.weaponowned[c.wp_chainsaw] = c.true;
        plyr.powers[c.pw_invulnerability] = c.true;
        plyr.message = c.STSTR_CHOPPERS;
      }
      // 'mypos' for player position
      else if (cht_CheckCheat(&cheat_mypos, @intCast(ev.data1)) != 0)
      {
        const S = struct {
            var buf: [ST_MSGWIDTH]u8 = undefined;
        };
        _ = fmt.bufPrintZ(&S.buf, "ang=0x{x};x,y=(0x{x},0x{x})", .{
            @as(c_uint, @bitCast(c.players[@intCast(c.consoleplayer)].mo[0].angle)),
            @as(c_uint, @bitCast(c.players[@intCast(c.consoleplayer)].mo[0].x)),
            @as(c_uint, @bitCast(c.players[@intCast(c.consoleplayer)].mo[0].y)),
        }) catch unreachable;
        plyr.message = &S.buf;
      }
    }

    // 'clev' change-level cheat
    if (cht_CheckCheat(&cheat_clev, @intCast(ev.data1)) != 0)
    {
      var buf = [_]u8{0} ** 3;
      var epsd: c_int = undefined;
      var map: c_int = undefined;

      cht_GetParam(&cheat_clev, &buf);

      if (c.gamemode == c.commercial)
      {
        epsd = 1;
        map = @as(c_int, buf[0] - '0')*10 + buf[1] - '0';
      }
      else
      {
        epsd = buf[0] - '0';
        map = buf[1] - '0';
      }

      // Catch invalid maps.
      if (epsd < 1) {
        return c.false;
      }

      if (map < 1) {
        return c.false;
      }

      // Ohmygod - this is not going to work.
      if ((c.gamemode == c.retail)
          and ((epsd > 4) or (map > 9))) {
        return c.false;
      }

      if ((c.gamemode == c.registered)
          and ((epsd > 3) or (map > 9))) {
        return c.false;
      }

      if ((c.gamemode == c.shareware)
          and ((epsd > 1) or (map > 9))) {
        return c.false;
      }

      if ((c.gamemode == c.commercial)
        and (( epsd > 1) or (map > 34))) {
        return c.false;
      }

      // So be it.
      plyr.message = c.STSTR_CLEV;
      c.G_DeferedInitNew(c.gameskill, epsd, map);
    }
  }
  return c.false;
}



fn ST_calcPainOffset() c_int {
    const S = struct {
        var lastcalc: c_int = 0;
        var oldhealth: c_int = -1;
    };

    const health = if (plyr.health > 100) 100 else plyr.health;

    if (health != S.oldhealth)
    {
        S.lastcalc = ST_FACESTRIDE * @divTrunc(((100 - health) * ST_NUMPAINFACES), 101);
        S.oldhealth = health;
    }
    return S.lastcalc;
}


//
// This is a not-very-pretty routine which handles
//  the face states and their timing.
// the precedence of expressions is:
//  dead > evil grin > turned head > straight ahead
//
fn ST_updateFaceWidget() void {
    const S = struct {
        var lastattackdown: c_int = -1;
        var priority: c_int = 0;
    };

    if (S.priority < 10) {
        // dead
        if (plyr.health == 0) {
            S.priority = 9;
            st_faceindex = ST_DEADFACE;
            st_facecount = 1;
        }
    }

    if (S.priority < 9) {
        if (plyr.bonuscount != 0) {
            // picking up bonus
            var doevilgrin = false;

            for (&oldweaponsowned, plyr.weaponowned) |*oldweap, plyrweap| {
                if (oldweap.* != plyrweap)
                {
                    doevilgrin = true;
                    oldweap.* = plyrweap;
                }
            }

            if (doevilgrin)
            {
                // evil grin if just picked up weapon
                S.priority = 8;
                st_facecount = ST_EVILGRINCOUNT;
                st_faceindex = ST_calcPainOffset() + ST_EVILGRINOFFSET;
            }
        }
    }

    if (S.priority < 8) {
        if (plyr.damagecount != 0
            and plyr.attacker != null
            and plyr.attacker != plyr.mo) {
            // being attacked
            S.priority = 7;

            if (plyr.health - st_oldhealth > ST_MUCHPAIN) {
                st_facecount = ST_TURNCOUNT;
                st_faceindex = ST_calcPainOffset() + ST_OUCHOFFSET;
            } else {
                const badguyangle = c.R_PointToAngle2(
                    plyr.mo[0].x,
                    plyr.mo[0].y,
                    plyr.attacker[0].x,
                    plyr.attacker[0].y
                );
                var diffang: c.angle_t = undefined;
                var lookright = false;

                if (badguyangle > plyr.mo[0].angle) {
                    // whether right or left
                    diffang = badguyangle - plyr.mo[0].angle;
                    lookright = diffang > c.ANG180;
                } else {
                    // whether left or right
                    diffang = plyr.mo[0].angle - badguyangle;
                    lookright = diffang <= c.ANG180;
                } // confusing, aint it?


                st_facecount = ST_TURNCOUNT;
                st_faceindex = ST_calcPainOffset();

                if (diffang < c.ANG45) {
                    // head-on
                    st_faceindex += ST_RAMPAGEOFFSET;
                } else if (lookright) {
                    // turn face right
                    st_faceindex += ST_TURNOFFSET;
                } else {
                    // turn face left
                    st_faceindex += ST_TURNOFFSET+1;
                }
            }
        }
    }

    if (S.priority < 7) {
        // getting hurt because of your own damn stupidity
        if (plyr.damagecount != 0) {
            if (plyr.health - st_oldhealth > ST_MUCHPAIN) {
                S.priority = 7;
                st_facecount = ST_TURNCOUNT;
                st_faceindex = ST_calcPainOffset() + ST_OUCHOFFSET;
            } else {
                S.priority = 6;
                st_facecount = ST_TURNCOUNT;
                st_faceindex = ST_calcPainOffset() + ST_RAMPAGEOFFSET;
            }
        }
    }

    if (S.priority < 6) {
        // rapid firing
        if (plyr.attackdown != 0) {
            if (S.lastattackdown == -1) {
                S.lastattackdown = ST_RAMPAGEDELAY;
            } else {
                S.lastattackdown -= 1;
                if (S.lastattackdown == 0) {
                    S.priority = 5;
                    st_faceindex = ST_calcPainOffset() + ST_RAMPAGEOFFSET;
                    st_facecount = 1;
                    S.lastattackdown = 1;
                }
            }
        } else {
            S.lastattackdown = -1;
        }
    }

    if (S.priority < 5)
    {
        // invulnerability
        if ((plyr.cheats & c.CF_GODMODE) != 0
            or plyr.powers[c.pw_invulnerability] != 0)
        {
            S.priority = 4;

            st_faceindex = ST_GODFACE;
            st_facecount = 1;
        }
    }

    // look left or look right if the facecount has timed out
    if (st_facecount == 0)
    {
        st_faceindex = ST_calcPainOffset() + @mod(st_randomnumber, 3);
        st_facecount = ST_STRAIGHTFACECOUNT;
        S.priority = 0;
    }

    st_facecount -= 1;
}

fn ST_updateWidgets() void {
    const S = struct {
        var largeammo: c_int = 1994; // means "n/a"
    };

    // must redirect the pointer if the ready weapon has changed.
    //  if (w_ready.data != plyr.readyweapon)
    //  {
    if (c.weaponinfo[plyr.readyweapon].ammo == c.am_noammo) {
        w_ready.num = &S.largeammo;
    } else {
        w_ready.num = &plyr.ammo[c.weaponinfo[plyr.readyweapon].ammo];
    }
    //{
    // static int tic=0;
    // static int dir=-1;
    // if (!(tic&15))
    //   plyr.ammo[c.weaponinfo[plyr.readyweapon].ammo]+=dir;
    // if (plyr.ammo[c.weaponinfo[plyr.readyweapon].ammo] == -100)
    //   dir = 1;
    // tic++;
    // }
    w_ready.data = @intCast(plyr.readyweapon);

    // if (*w_ready.on)
    //  STlib_updateNum(&w_ready, true);
    // refresh weapon change
    //  }

    // update keycard multiple widgets
    for (0..3) |i| {
        keyboxes[i] = if (plyr.cards[i] != 0) @intCast(i) else -1;

        if (plyr.cards[i+3] != c.false) {
            keyboxes[i] = @intCast(i+3);
        }
    }

    // refresh everything if this is him coming back to life
    ST_updateFaceWidget();

    // used by the w_armsbg widget
    st_notdeathmatch = c.deathmatch == 0;

    // used by w_arms[] widgets
    st_armson = st_statusbaron and c.deathmatch == 0;

    // used by w_frags widget
    st_fragson = c.deathmatch != 0 and st_statusbaron;
    st_fragscount = 0;

    for (0..c.MAXPLAYERS) |i| {
        if (i != c.consoleplayer) {
            st_fragscount += plyr.frags[i];
        } else {
            st_fragscount -= plyr.frags[i];
        }
    }
}

pub export fn ST_Ticker() void {
    st_randomnumber = M_Random();
    ST_updateWidgets();
    st_oldhealth = plyr.health;
}

var st_palette: c_int = 0;

fn ST_doPaletteStuff() void {
    var cnt = plyr.damagecount;

    if (plyr.powers[c.pw_strength] != 0) {
        // slowly fade the berzerk out
        const bzc = 12 - (plyr.powers[c.pw_strength]>>6);

        if (bzc > cnt) {
            cnt = bzc;
        }
    }

    var palette: c_int = undefined;
    if (cnt != 0) {
        palette = (cnt+7)>>3;

        if (palette >= NUMREDPALS) {
            palette = NUMREDPALS-1;
        }

        palette += STARTREDPALS;
    } else if (plyr.bonuscount != 0) {
        palette = (plyr.bonuscount+7)>>3;

        if (palette >= NUMBONUSPALS) {
            palette = NUMBONUSPALS-1;
        }

        palette += STARTBONUSPALS;
    } else if (plyr.powers[c.pw_ironfeet] > 4*32
              or plyr.powers[c.pw_ironfeet]&8 != 0) {
        palette = RADIATIONPAL;
    } else {
        palette = 0;
    }

    if (palette != st_palette) {
        st_palette = palette;
        const pal = @as([*]u8, @ptrCast(W_CacheLumpNum(lu_palette, .Cache))) + @as(usize, @intCast(palette*768));
        I_SetPalette(pal);
    }
}

fn ST_drawWidgets(refresh: bool) void {
    // used by w_arms[] widgets
    st_armson = st_statusbaron and c.deathmatch == 0;

    // used by w_frags widget
    st_fragson = c.deathmatch != 0 and st_statusbaron;

    STlib_updateNum(&w_ready, refresh);

    for (&w_ammo, &w_maxammo) |*ammo, *maxammo| {
        STlib_updateNum(ammo, refresh);
        STlib_updateNum(maxammo, refresh);
    }

    STlib_updatePercent(&w_health, refresh);
    STlib_updatePercent(&w_armor, refresh);

    STlib_updateBinIcon(&w_armsbg, refresh);

    for (&w_arms) |*arm| {
        STlib_updateMultIcon(arm, refresh);
    }

    STlib_updateMultIcon(&w_faces, refresh);

    for (&w_keyboxes) |*keybox| {
        STlib_updateMultIcon(keybox, refresh);
    }

    STlib_updateNum(&w_frags, refresh);
}

fn ST_doRefresh() void {
    st_firsttime = false;

    // draw status bar background to off-screen buff
    ST_refreshBackground();

    // and refresh all widgets
    ST_drawWidgets(true);
}

fn ST_diffDraw() void {
    // update all widgets
    ST_drawWidgets(false);
}

pub fn ST_Drawer(fullscreen: bool, refresh: bool) void {
    st_statusbaron = !fullscreen or c.automapactive != c.false;
    st_firsttime = st_firsttime or refresh;

    // Do red-/gold-shifts from damage/items
    ST_doPaletteStuff();

    // If just after ST_Start(), refresh all
    if (st_firsttime) {
        ST_doRefresh();
    // Otherwise, update as little as possible
    } else {
        ST_diffDraw();
    }
}

fn ST_loadGraphics() void {
    var namebuf = [_]u8{0} ** 9;

    // Load the numbers, tall and short
    for (0..10) |i| {
        _ = fmt.bufPrintZ(&namebuf, "STTNUM{d}", .{ i }) catch unreachable;
        tallnum[i] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));

        _ = fmt.bufPrintZ(&namebuf, "STYSNUM{d}", .{ i }) catch unreachable;
        shortnum[i] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));
    }

    // Load percent key.
    //Note: why not load STMINUS here, too?
    tallpercent = @ptrCast(@alignCast(W_CacheLumpName("STTPRCNT", .Static)));

    // key cards
    for (0..c.NUMCARDS) |i| {
        _ = fmt.bufPrintZ(&namebuf, "STKEYS{d}", .{ i }) catch unreachable;
        keys[i] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));
    }

    // arms background
    armsbg = @ptrCast(@alignCast(W_CacheLumpName("STARMS", .Static)));

    // arms ownership widgets
    for (0..6) |i| {
        _ = fmt.bufPrintZ(&namebuf, "STGNUM{d}", .{ i+2 }) catch unreachable;

        // gray #
        arms[i][0] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));

        // yellow #
        arms[i][1] = shortnum[i+2];
    }

    // face backgrounds for different color players
    _ = fmt.bufPrintZ(&namebuf, "STFB{d}", .{ c.consoleplayer }) catch unreachable;
    faceback = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));

    // status bar background bits
    sbar = @ptrCast(@alignCast(W_CacheLumpName("STBAR", .Static)));

    // face states
    var facenum: usize = 0;
    for (0..ST_NUMPAINFACES) |i| {
        for (0..ST_NUMSTRAIGHTFACES) |j| {
            _ = fmt.bufPrintZ(&namebuf, "STFST{d}{d}", .{ i, j }) catch unreachable;
            faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));
            facenum += 1;
        }
        _ = fmt.bufPrintZ(&namebuf, "STFTR{d}0", .{ i }) catch unreachable;
        faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));        // turn right
        facenum += 1;
        _ = fmt.bufPrintZ(&namebuf, "STFTL{d}0", .{ i }) catch unreachable;
        faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));        // turn left
        facenum += 1;
        _ = fmt.bufPrintZ(&namebuf, "STFOUCH{d}", .{ i }) catch unreachable;
        faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));       // ouch!
        facenum += 1;
        _ = fmt.bufPrintZ(&namebuf, "STFEVL{d}", .{ i }) catch unreachable;
        faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));        // evil grin ;)
        facenum += 1;
        _ = fmt.bufPrintZ(&namebuf, "STFKILL{d}", .{ i }) catch unreachable;
        faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName(&namebuf, .Static)));       // pissed off
        facenum += 1;
    }
    faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName("STFGOD0", .Static)));
    facenum += 1;
    faces[facenum] = @ptrCast(@alignCast(W_CacheLumpName("STFDEAD0", .Static)));
    facenum += 1;
}

fn ST_loadData() void {
    lu_palette = W_GetNumForName("PLAYPAL");
    ST_loadGraphics();
}

fn ST_unloadGraphics() void {
    // unload the numbers, tall and short
    for (tallnum, shortnum) |tn, sn| {
        Z_ChangeTag(tn, .Cache);
        Z_ChangeTag(sn, .Cache);
    }
    // unload tall percent
    Z_ChangeTag(tallpercent, .Cache);

    // unload arms background
    Z_ChangeTag(armsbg, .Cache);

    // unload gray #'s
    for (arms) |arm| {
        Z_ChangeTag(arm[0], .Cache);
    }

    // unload the key cards
    for (keys) |key| {
        Z_ChangeTag(key, .Cache);
    }

    Z_ChangeTag(sbar, .Cache);
    Z_ChangeTag(faceback, .Cache);

    for (faces) |face| {
        Z_ChangeTag(face, .Cache);
    }

    // Note: nobody ain't seen no unloading
    //   of stminus yet. Dude.
}

// TODO: This is never called, remove?
fn ST_unloadData() void {
    ST_unloadGraphics();
}

fn ST_initData() void {
    st_firsttime = true;
    plyr = &c.players[@intCast(c.consoleplayer)];

    st_statusbaron = true;

    st_faceindex = 0;
    st_palette = -1;

    st_oldhealth = -1;

    for (&oldweaponsowned, plyr.weaponowned) |*oldweap, plyrweap| {
        oldweap.* = plyrweap;
    }

    for (&keyboxes) |*kb| {
        kb.* = -1;
    }

    STlib_init();
}



fn ST_createWidgets() void {
    // TODO:
    // BUG: ammo type will be noammo when fist or chainsaw is the active
    // weapon from previous level; this results in trying to access
    // plyr.ammo[5] which is invalid. Looks like this was a bug in the original
    // source. This would just end up accessing the maxammo[0] entry. In Zig
    // the array access is checked in debug builds and crashes.

    // ready weapon ammo
    STlib_initNum(&w_ready,
                  ST_AMMOX,
                  ST_AMMOY,
                  &tallnum,
                  &plyr.ammo[c.weaponinfo[plyr.readyweapon].ammo],
                  &st_statusbaron,
                  ST_AMMOWIDTH );

    // the last weapon type
    w_ready.data = @intCast(plyr.readyweapon);

    // health percentage
    STlib_initPercent(&w_health,
                      ST_HEALTHX,
                      ST_HEALTHY,
                      &tallnum,
                      &plyr.health,
                      &st_statusbaron,
                      tallpercent);

    // arms background
    STlib_initBinIcon(&w_armsbg,
                      ST_ARMSBGX,
                      ST_ARMSBGY,
                      armsbg,
                      &st_notdeathmatch,
                      &st_statusbaron);

    // weapons owned
    for (&w_arms, 0..) |*arm, i| {
        STlib_initMultIcon(arm,
                           @intCast(ST_ARMSX+(i%3)*ST_ARMSXSPACE),
                           @intCast(ST_ARMSY+(i/3)*ST_ARMSYSPACE),
                           &arms[i],
                           @ptrCast(&plyr.weaponowned[i+1]),
                           &st_armson);
    }

    // frags sum
    STlib_initNum(&w_frags,
                  ST_FRAGSX,
                  ST_FRAGSY,
                  &tallnum,
                  &st_fragscount,
                  &st_fragson,
                  ST_FRAGSWIDTH);

    // faces
    STlib_initMultIcon(&w_faces,
                       ST_FACESX,
                       ST_FACESY,
                       &faces,
                       &st_faceindex,
                       &st_statusbaron);

    // armor percentage - should be colored later
    STlib_initPercent(&w_armor,
                      ST_ARMORX,
                      ST_ARMORY,
                      &tallnum,
                      &plyr.armorpoints,
                      &st_statusbaron,
                      tallpercent);

    // keyboxes 0-2
    STlib_initMultIcon(&w_keyboxes[0],
                       ST_KEY0X,
                       ST_KEY0Y,
                       &keys,
                       &keyboxes[0],
                       &st_statusbaron);

    STlib_initMultIcon(&w_keyboxes[1],
                       ST_KEY1X,
                       ST_KEY1Y,
                       &keys,
                       &keyboxes[1],
                       &st_statusbaron);

    STlib_initMultIcon(&w_keyboxes[2],
                       ST_KEY2X,
                       ST_KEY2Y,
                       &keys,
                       &keyboxes[2],
                       &st_statusbaron);

    // ammo count (all four kinds)
    STlib_initNum(&w_ammo[0],
                  ST_AMMO0X,
                  ST_AMMO0Y,
                  &shortnum,
                  &plyr.ammo[0],
                  &st_statusbaron,
                  ST_AMMO0WIDTH);

    STlib_initNum(&w_ammo[1],
                  ST_AMMO1X,
                  ST_AMMO1Y,
                  &shortnum,
                  &plyr.ammo[1],
                  &st_statusbaron,
                  ST_AMMO1WIDTH);

    STlib_initNum(&w_ammo[2],
                  ST_AMMO2X,
                  ST_AMMO2Y,
                  &shortnum,
                  &plyr.ammo[2],
                  &st_statusbaron,
                  ST_AMMO2WIDTH);

    STlib_initNum(&w_ammo[3],
                  ST_AMMO3X,
                  ST_AMMO3Y,
                  &shortnum,
                  &plyr.ammo[3],
                  &st_statusbaron,
                  ST_AMMO3WIDTH);

    // max ammo count (all four kinds)
    STlib_initNum(&w_maxammo[0],
                  ST_MAXAMMO0X,
                  ST_MAXAMMO0Y,
                  &shortnum,
                  &plyr.maxammo[0],
                  &st_statusbaron,
                  ST_MAXAMMO0WIDTH);

    STlib_initNum(&w_maxammo[1],
                  ST_MAXAMMO1X,
                  ST_MAXAMMO1Y,
                  &shortnum,
                  &plyr.maxammo[1],
                  &st_statusbaron,
                  ST_MAXAMMO1WIDTH);

    STlib_initNum(&w_maxammo[2],
                  ST_MAXAMMO2X,
                  ST_MAXAMMO2Y,
                  &shortnum,
                  &plyr.maxammo[2],
                  &st_statusbaron,
                  ST_MAXAMMO2WIDTH);

    STlib_initNum(&w_maxammo[3],
                  ST_MAXAMMO3X,
                  ST_MAXAMMO3Y,
                  &shortnum,
                  &plyr.maxammo[3],
                  &st_statusbaron,
                  ST_MAXAMMO3WIDTH);

}

var st_stopped = true;

pub export fn ST_Start() void {
    if (!st_stopped) {
        ST_Stop();
    }

    ST_initData();
    ST_createWidgets();
    st_stopped = false;
}

fn ST_Stop() void {
    if (st_stopped) {
        return;
    }

    I_SetPalette(@ptrCast(W_CacheLumpNum(lu_palette, .Cache)));
    st_stopped = true;
}

extern var screens: [5][*]u8;
pub fn ST_Init() void {
    ST_loadData();
    screens[4] = @ptrCast(Z_Malloc(ST_WIDTH*ST_HEIGHT, .Static, null));
}
