const c = @cImport({
    @cInclude("doomstat.h");
    @cInclude("dstrings.h");
});

const std = @import("std");

const doomdef = @import("doomdef.zig");
const doomstat = @import("doomstat.zig");
const d_main = @import("d_main.zig");
const Event = d_main.Event;
const g_game = @import("g_game.zig");
const hu_lib = @import("hu_lib.zig");
const m_menu = @import("m_menu.zig");
const s_sound = @import("s_sound.zig");
const S_StartSound = s_sound.S_StartSound_Zig;
const w_wad = @import("w_wad.zig");
const W_CacheLumpName = w_wad.W_CacheLumpName;

//
// Globally visible constants.
//
pub const HU_FONTSTART = '!';   // the first font characters
pub const HU_FONTEND = '_';     // the last font characters

// Calculate # of glyphs in font.
pub const HU_FONTSIZE = HU_FONTEND - HU_FONTSTART + 1;

//
// Locally used constants, shortcuts.
//
const HU_BROADCAST = 5;

const HU_MSGREFRESH = doomdef.KEY_ENTER;
const HU_MSGX = 0;
const HU_MSGY = 0;
const HU_MSGWIDTH = 64;     // in characters
const HU_MSGHEIGHT = 1;     // in lines

const HU_MSGTIMEOUT = 4 * doomdef.TICRATE;

fn HU_TITLE() []const u8 { return mapnames[@intCast((g_game.gameepisode-1)*9+g_game.gamemap-1)]; }
fn HU_TITLE2() []const u8 { return mapnames2[@intCast(g_game.gamemap-1)]; }
fn HU_TITLEP() []const u8 { return mapnamesp[@intCast(g_game.gamemap-1)]; }
fn HU_TITLET() []const u8 { return mapnamest[@intCast(g_game.gamemap-1)]; }
const HU_TITLEHEIGHT = 1;
const HU_TITLEX = 0;
fn HU_TITLEY() c_short { return 167 - std.mem.littleToNative(c_short, hu_font[0].height); }

const HU_INPUTTOGGLE = 't';
const HU_INPUTX = HU_MSGX;
fn HU_INPUTY() c_short { return HU_MSGY + HU_MSGHEIGHT*(std.mem.littleToNative(c_short, hu_font[0].height) + 1); }
const HU_INPUTWIDTH = 64;
const HU_INPUTHEIGHT = 1;

pub var chat_macros = [_][*:0]const u8{
    c.HUSTR_CHATMACRO0,
    c.HUSTR_CHATMACRO1,
    c.HUSTR_CHATMACRO2,
    c.HUSTR_CHATMACRO3,
    c.HUSTR_CHATMACRO4,
    c.HUSTR_CHATMACRO5,
    c.HUSTR_CHATMACRO6,
    c.HUSTR_CHATMACRO7,
    c.HUSTR_CHATMACRO8,
    c.HUSTR_CHATMACRO9,
};

pub const player_names = [_][]const u8{
    c.HUSTR_PLRGREEN,
    c.HUSTR_PLRINDIGO,
    c.HUSTR_PLRBROWN,
    c.HUSTR_PLRRED,
};


pub export var hu_font: [HU_FONTSIZE]*hu_lib.c.patch_t = undefined;
var plr: *@TypeOf(g_game.players[0]) = undefined;
var w_title: hu_lib.HudTextLine = undefined;
pub var chat_on = false;
var w_chat: hu_lib.HudIText = undefined;
var always_off = false;
var chat_dest = [_]u8{0} ** doomdef.MAXPLAYERS;
var w_inputbuffer: [doomdef.MAXPLAYERS]hu_lib.HudIText = undefined;

var message_on = false;
pub var message_dontfuckwithme = false;
var message_nottobefuckedwith = false;

var w_message: hu_lib.HudSText = undefined;
var message_counter: c_int = 0;

var headsupactive = false;

//
// Builtin map names.
// The actual names can be found in DStrings.h.
//

const mapnames = [_][]const u8{
    // DOOM shareware/registered/retail (Ultimate) names.

    c.HUSTR_E1M1,
    c.HUSTR_E1M2,
    c.HUSTR_E1M3,
    c.HUSTR_E1M4,
    c.HUSTR_E1M5,
    c.HUSTR_E1M6,
    c.HUSTR_E1M7,
    c.HUSTR_E1M8,
    c.HUSTR_E1M9,

    c.HUSTR_E2M1,
    c.HUSTR_E2M2,
    c.HUSTR_E2M3,
    c.HUSTR_E2M4,
    c.HUSTR_E2M5,
    c.HUSTR_E2M6,
    c.HUSTR_E2M7,
    c.HUSTR_E2M8,
    c.HUSTR_E2M9,

    c.HUSTR_E3M1,
    c.HUSTR_E3M2,
    c.HUSTR_E3M3,
    c.HUSTR_E3M4,
    c.HUSTR_E3M5,
    c.HUSTR_E3M6,
    c.HUSTR_E3M7,
    c.HUSTR_E3M8,
    c.HUSTR_E3M9,

    c.HUSTR_E4M1,
    c.HUSTR_E4M2,
    c.HUSTR_E4M3,
    c.HUSTR_E4M4,
    c.HUSTR_E4M5,
    c.HUSTR_E4M6,
    c.HUSTR_E4M7,
    c.HUSTR_E4M8,
    c.HUSTR_E4M9,

    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL",
    "NEWLEVEL"
};

const mapnames2 = [_][]const u8 {
    // DOOM 2 map names.

    c.HUSTR_1,
    c.HUSTR_2,
    c.HUSTR_3,
    c.HUSTR_4,
    c.HUSTR_5,
    c.HUSTR_6,
    c.HUSTR_7,
    c.HUSTR_8,
    c.HUSTR_9,
    c.HUSTR_10,
    c.HUSTR_11,

    c.HUSTR_12,
    c.HUSTR_13,
    c.HUSTR_14,
    c.HUSTR_15,
    c.HUSTR_16,
    c.HUSTR_17,
    c.HUSTR_18,
    c.HUSTR_19,
    c.HUSTR_20,

    c.HUSTR_21,
    c.HUSTR_22,
    c.HUSTR_23,
    c.HUSTR_24,
    c.HUSTR_25,
    c.HUSTR_26,
    c.HUSTR_27,
    c.HUSTR_28,
    c.HUSTR_29,
    c.HUSTR_30,
    c.HUSTR_31,
    c.HUSTR_32,
};

const mapnamesp = [_][]const u8{
    // Plutonia WAD map names.

    c.PHUSTR_1,
    c.PHUSTR_2,
    c.PHUSTR_3,
    c.PHUSTR_4,
    c.PHUSTR_5,
    c.PHUSTR_6,
    c.PHUSTR_7,
    c.PHUSTR_8,
    c.PHUSTR_9,
    c.PHUSTR_10,
    c.PHUSTR_11,

    c.PHUSTR_12,
    c.PHUSTR_13,
    c.PHUSTR_14,
    c.PHUSTR_15,
    c.PHUSTR_16,
    c.PHUSTR_17,
    c.PHUSTR_18,
    c.PHUSTR_19,
    c.PHUSTR_20,

    c.PHUSTR_21,
    c.PHUSTR_22,
    c.PHUSTR_23,
    c.PHUSTR_24,
    c.PHUSTR_25,
    c.PHUSTR_26,
    c.PHUSTR_27,
    c.PHUSTR_28,
    c.PHUSTR_29,
    c.PHUSTR_30,
    c.PHUSTR_31,
    c.PHUSTR_32,
};

const mapnamest = [_][]const u8{
    // TNT WAD map names.

    c.THUSTR_1,
    c.THUSTR_2,
    c.THUSTR_3,
    c.THUSTR_4,
    c.THUSTR_5,
    c.THUSTR_6,
    c.THUSTR_7,
    c.THUSTR_8,
    c.THUSTR_9,
    c.THUSTR_10,
    c.THUSTR_11,

    c.THUSTR_12,
    c.THUSTR_13,
    c.THUSTR_14,
    c.THUSTR_15,
    c.THUSTR_16,
    c.THUSTR_17,
    c.THUSTR_18,
    c.THUSTR_19,
    c.THUSTR_20,

    c.THUSTR_21,
    c.THUSTR_22,
    c.THUSTR_23,
    c.THUSTR_24,
    c.THUSTR_25,
    c.THUSTR_26,
    c.THUSTR_27,
    c.THUSTR_28,
    c.THUSTR_29,
    c.THUSTR_30,
    c.THUSTR_31,
    c.THUSTR_32,
};

var shiftxform: []const u8 = undefined;

const french_shiftxform = [_]u8{
    0,
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
    31,
    ' ', '!', '"', '#', '$', '%', '&',
    '"', // shift-'
    '(', ')', '*', '+',
    '?', // shift-,
    '_', // shift--
    '>', // shift-.
    '?', // shift-/
    '0', // shift-0
    '1', // shift-1
    '2', // shift-2
    '3', // shift-3
    '4', // shift-4
    '5', // shift-5
    '6', // shift-6
    '7', // shift-7
    '8', // shift-8
    '9', // shift-9
    '/',
    '.', // shift-;
    '<',
    '+', // shift-=
    '>', '?', '@',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '[', // shift-[
    '!', // shift-backslash - OH MY GOD DOES WATCOM SUCK
    ']', // shift-]
    '"', '_',
    '\'', // shift-`
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '{', '|', '}', '~', 127,
};

const english_shiftxform = [_]u8{
    0,
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
    31,
    ' ', '!', '"', '#', '$', '%', '&',
    '"', // shift-'
    '(', ')', '*', '+',
    '<', // shift-,
    '_', // shift--
    '>', // shift-.
    '?', // shift-/
    ')', // shift-0
    '!', // shift-1
    '@', // shift-2
    '#', // shift-3
    '$', // shift-4
    '%', // shift-5
    '^', // shift-6
    '&', // shift-7
    '*', // shift-8
    '(', // shift-9
    ':',
    ':', // shift-;
    '<',
    '+', // shift-=
    '>', '?', '@',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '[', // shift-[
    '!', // shift-backslash - OH MY GOD DOES WATCOM SUCK
    ']', // shift-]
    '"', '_',
    '\'', // shift-`
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '{', '|', '}', '~', 127,
};

const frenchKeyMap = [128]u8{
    0,
    1,2,3,4,5,6,7,8,9,10,
    11,12,13,14,15,16,17,18,19,20,
    21,22,23,24,25,26,27,28,29,30,
    31,
    ' ','!','"','#','$','%','&','%','(',')','*','+',';','-',':','!',
    '0','1','2','3','4','5','6','7','8','9',':','M','<','=','>','?',
    '@','Q','B','C','D','E','F','G','H','I','J','K','L',',','N','O',
    'P','A','R','S','T','U','V','Z','X','Y','W','^','\\','$','^','_',
    '@','Q','B','C','D','E','F','G','H','I','J','K','L',',','N','O',
    'P','A','R','S','T','U','V','Z','X','Y','W','^','\\','$','^',127,
};

fn ForeignTranslation(ch: u8) u8 {
    return if (ch < 128) frenchKeyMap[ch] else ch;
}

pub fn HU_Init() void {
    shiftxform =
        if (doomstat.language == .French)
            &french_shiftxform
        else
            &english_shiftxform;

    // load the heads-up font
    var buffer = [_]u8{0} ** 9;
    for (0..HU_FONTSIZE) |i| {
        const lumpname = std.fmt.bufPrintZ(&buffer, "STCFN{d:0>3}", .{i + HU_FONTSTART}) catch unreachable;
        hu_font[i] = @ptrCast(@alignCast(W_CacheLumpName(lumpname.ptr, .Static)));
    }
}

fn HU_Stop() void {
    headsupactive = false;
}

pub export fn HU_Start() void {
    if (headsupactive) {
        HU_Stop();
    }

    plr = &g_game.players[g_game.consoleplayer];
    message_on = false;
    message_dontfuckwithme = false;
    message_nottobefuckedwith = false;
    chat_on = false;

    // create the message widget
    hu_lib.HUlib_initSText(
        &w_message,
        HU_MSGX,
        HU_MSGY,
        HU_MSGHEIGHT,
        &hu_font,
        HU_FONTSTART,
        &message_on,
    );

    // create the map title widget
    hu_lib.HUlib_initTextLine(
        &w_title,
        HU_TITLEX,
        HU_TITLEY(),
        &hu_font,
        HU_FONTSTART
    );

    const s = switch (doomstat.gamemode) {
        .Shareware,
        .Registered,
        .Retail, => HU_TITLE(),

        .Commercial,
        .Indetermined => HU_TITLE2(),
    };

    for (s) |ch| {
        _ = hu_lib.HUlib_addCharToTextLine(&w_title, ch);
    }

    // create the chat widget
    hu_lib.HUlib_initIText(
        &w_chat,
        HU_INPUTX,
        HU_INPUTY(),
        &hu_font,
        HU_FONTSTART,
        &chat_on,
    );

    // create the inputbuffer widgets
    for (0..doomdef.MAXPLAYERS) |i| {
        hu_lib.HUlib_initIText(&w_inputbuffer[i], 0, 0, &hu_font, 0, &always_off);
    }

    headsupactive = true;
}

pub fn HU_Drawer() void {
    hu_lib.HUlib_drawSText(&w_message);
    hu_lib.HUlib_drawIText(&w_chat);
    if (c.automapactive != c.false) {
        hu_lib.HUlib_drawTextLine(&w_title, false);
    }
}

pub fn HU_Erase() void {
    hu_lib.HUlib_eraseSText(&w_message);
    hu_lib.HUlib_eraseIText(&w_chat);
    hu_lib.HUlib_eraseTextLine(&w_title);
}

pub fn HU_Ticker() void {
    // tick down message counter if message is up
    if (message_counter != 0) {
        message_counter -= 1;
        if (message_counter == 0) {
            message_on = false;
            message_nottobefuckedwith = false;
        }
    }

    if (m_menu.showMessages != 0 or message_dontfuckwithme) {
        // display message if necessary
        if ((plr.message != null and !message_nottobefuckedwith) or
            (plr.message != null and message_dontfuckwithme)) {
            hu_lib.HUlib_addMessageToSText(&w_message, "", std.mem.span(plr.message));
            plr.message = null;
            message_on = true;
            message_counter = HU_MSGTIMEOUT;
            message_nottobefuckedwith = message_dontfuckwithme;
            message_dontfuckwithme = false;
        }
    }

    // check for incoming chat characters
    if (g_game.netgame != c.false) {
        for (0..doomdef.MAXPLAYERS) |i| {
            if (g_game.playeringame[i] == c.false) {
                continue;
            }

            var ch = g_game.players[i].cmd.chatchar;
            if (i != g_game.consoleplayer and ch != 0) {
                if (ch <= HU_BROADCAST) {
                    chat_dest[i] = ch;
                } else {
                    if (ch >= 'a' and ch <= 'z') {
                        ch = shiftxform[ch];
                    }

                    const rc = hu_lib.HUlib_keyInIText(&w_inputbuffer[i], ch);
                    if (rc and ch == doomdef.KEY_ENTER) {
                        if (w_inputbuffer[i].l.len != 0
                            and (chat_dest[i] == g_game.consoleplayer + 1
                                or chat_dest[i] == HU_BROADCAST)) {
                            hu_lib.HUlib_addMessageToSText(&w_message, player_names[i], w_inputbuffer[i].l.l[0..w_inputbuffer[i].l.len:0]);
                            message_nottobefuckedwith = true;
                            message_on = true;
                            message_counter = HU_MSGTIMEOUT;
                            if (doomstat.gamemode == .Commercial) {
                                S_StartSound(null, .radio);
                            } else {
                                S_StartSound(null, .tink);
                            }
                        }
                        hu_lib.HUlib_resetIText(&w_inputbuffer[i]);
                    }
                }
                g_game.players[i].cmd.chatchar = 0;
            }
        }
    }
}

const QUEUESIZE = 128;

var chatchars = [_]u8{0} ** QUEUESIZE;
var head: usize = 0;
var tail: usize = 0;

fn HU_queueChatChar(ch: u8) void {
    if (head + 1 % QUEUESIZE == tail) {
    //if (((head + 1) & (QUEUESIZE - 1)) == tail) {
        plr.message = c.HUSTR_MSGU;
    } else {
        chatchars[head] = ch;
        head = (head + 1) % QUEUESIZE;
    }
}

pub fn HU_dequeueChatChar() u8 {
    var ch: u8 = 0;

    if (head != tail) {
        ch = chatchars[tail];
        tail = (tail + 1) % QUEUESIZE;
    }

    return ch;
}

pub fn HU_Responder(ev: *Event) bool {
    const S = struct {
        var lastmessage: [hu_lib.HU_MAXLINELENGTH:0]u8 = undefined;
        var shiftdown = false;
        var altdown = false;
        var destination_keys = [_]u8{
            c.HUSTR_KEYGREEN,
            c.HUSTR_KEYINDIGO,
            c.HUSTR_KEYBROWN,
            c.HUSTR_KEYRED,
        };
        var num_nobrainers: c_int = 0;
    };

    var numplayers: usize = 0;
    for (0..doomdef.MAXPLAYERS) |i| {
        if (g_game.playeringame[i] != c.false) {
            numplayers += 1;
        }
    }

    if (ev.data1 == doomdef.KEY_RSHIFT) {
        S.shiftdown = ev.type == .KeyDown;
        return false;
    } else if (ev.data1 == doomdef.KEY_RALT or ev.data1 == doomdef.KEY_LALT) {
        S.altdown = ev.type == .KeyDown;
        return false;
    }

    if (ev.type != .KeyDown) {
        return false;
    }

    var eatkey = false;
    if (!chat_on) {
        if (ev.data1 == HU_MSGREFRESH) {
            message_on = true;
            message_counter = HU_MSGTIMEOUT;
            eatkey = true;
        } else if (g_game.netgame != c.false and ev.data1 == HU_INPUTTOGGLE) {
            chat_on = true;
            eatkey = true;
            hu_lib.HUlib_resetIText(&w_chat);
            HU_queueChatChar(HU_BROADCAST);
        } else if (g_game.netgame != c.false and numplayers > 2) {
            for (0..doomdef.MAXPLAYERS) |i| {
                if (ev.data1 == S.destination_keys[i]) {
                    if (g_game.playeringame[i] != c.false and i != g_game.consoleplayer) {
                        chat_on = true;
                        eatkey = true;
                        hu_lib.HUlib_resetIText(&w_chat);
                        HU_queueChatChar(@intCast(i+1));
                        break;
                    } else if (i == g_game.consoleplayer) {
                        S.num_nobrainers += 1;

                        if (S.num_nobrainers < 3) {
                            plr.message = c.HUSTR_TALKTOSELF1;
                        } else if (S.num_nobrainers < 6) {
                            plr.message = c.HUSTR_TALKTOSELF2;
                        } else if (S.num_nobrainers < 9) {
                            plr.message = c.HUSTR_TALKTOSELF3;
                        } else if (S.num_nobrainers < 32) {
                            plr.message = c.HUSTR_TALKTOSELF4;
                        } else {
                            plr.message = c.HUSTR_TALKTOSELF5;
                        }
                    }
                }
            }
        }
    } else {
        var ch: u8 = @intCast(ev.data1);

        // send a macro
        if (S.altdown) {
            if (ch < '0' or ch > '9') {
                return false;
            }
            ch = ch - '0';

            const macromessage = std.mem.span(chat_macros[@intCast(ch)]);

            // kill last message with a '\n'
            HU_queueChatChar(doomdef.KEY_ENTER); // DEBUG!!!

            // send the macro message
            for (macromessage) |mch| {
                HU_queueChatChar(mch);
            }
            HU_queueChatChar(doomdef.KEY_ENTER);

            // leave chat mode and notify that it was sent
            chat_on = false;
            _ = std.fmt.bufPrintZ(&S.lastmessage, "{s}", .{macromessage}) catch unreachable;
            plr.message = &S.lastmessage;
            eatkey = true;
        } else {
            if (doomstat.language == .French) {
                ch = ForeignTranslation(ch);
            }

            if (S.shiftdown or (ch >= 'a' and ch <= 'z')) {
                ch = shiftxform[ch];
            }

            eatkey = hu_lib.HUlib_keyInIText(&w_chat, ch);
            if (eatkey) {
                HU_queueChatChar(ch);
            }

            if (ch == doomdef.KEY_ENTER) {
                chat_on = false;
                if (w_chat.l.len != 0) {
                    const msg = w_chat.l.l[0..w_chat.l.len:0];
                    _ = std.fmt.bufPrintZ(&S.lastmessage, "{s}", .{msg}) catch unreachable;
                    plr.message = &S.lastmessage;
                }
            } else if (ch == doomdef.KEY_ESCAPE) {
                chat_on = false;
            }
        }
    }

    return eatkey;
}
