const c = @import("c");

const std = @import("std");

const doomdef = @import("doomdef.zig");
const doomstat = @import("doomstat.zig");
const d_main = @import("d_main.zig");
const Event = d_main.Event;
const d_strings = @import("d_strings.zig");
const g_game = @import("g_game.zig");
const hu_lib = @import("hu_lib.zig");
const m_menu = @import("m_menu.zig");
const m_swap = @import("m_swap.zig");
const SHORT = m_swap.SHORT;
const s_sound = @import("s_sound.zig");
const S_StartSound = s_sound.S_StartSound_Zig;
const v_video = @import("v_video.zig");
const w_wad = @import("w_wad.zig");
const W_CacheLumpNameFmt = w_wad.W_CacheLumpNameFmt;

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

fn HU_TITLE() []const u8 { return d_strings.text.mapnames[@intCast((g_game.gameepisode-1)*9+g_game.gamemap-1)]; }
fn HU_TITLE2() []const u8 { return d_strings.text.mapnames2[@intCast(g_game.gamemap-1)]; }
fn HU_TITLEP() []const u8 { return d_strings.text.mapnamesp[@intCast(g_game.gamemap-1)]; }
fn HU_TITLET() []const u8 { return d_strings.text.mapnamest[@intCast(g_game.gamemap-1)]; }
const HU_TITLEHEIGHT = 1;
const HU_TITLEX = 0;
fn HU_TITLEY() c_short { return 167 - SHORT(hu_font[0].height); }

const HU_INPUTTOGGLE = 't';
const HU_INPUTX = HU_MSGX;
fn HU_INPUTY() c_short { return HU_MSGY + HU_MSGHEIGHT*(SHORT(hu_font[0].height) + 1); }
const HU_INPUTWIDTH = 64;
const HU_INPUTHEIGHT = 1;

// Initialized by M_LoadDefaults
pub var chat_macros:[10][]const u8 = undefined;


const patch_t = v_video.c.patch_t;

pub var hu_font: [HU_FONTSIZE]*patch_t = undefined;
var plr: *@TypeOf(g_game.players[0]) = undefined;
var w_title: hu_lib.HudTextLine = undefined;
pub var chat_on = false;
var w_chat: hu_lib.HudIText = undefined;
var always_off = false;
var chat_dest: [doomdef.MAXPLAYERS]u8 = @splat(0);
var w_inputbuffer: [doomdef.MAXPLAYERS]hu_lib.HudIText = undefined;

var message_on = false;
pub var message_dontfuckwithme = false;
var message_nottobefuckedwith = false;

var w_message: hu_lib.HudSText = undefined;
var message_counter: c_int = 0;

var headsupactive = false;

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
    for (0..HU_FONTSIZE) |i| {
        hu_font[i] = W_CacheLumpNameFmt(*patch_t,  "STCFN{d:0>3}", .{i + HU_FONTSTART}, .Static);
    }
}

fn HU_Stop() void {
    headsupactive = false;
}

pub fn HU_Start() void {
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
            hu_lib.HUlib_addMessageToSText(&w_message, "", std.mem.span(plr.message.?));
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
                            hu_lib.HUlib_addMessageToSText(&w_message, d_strings.text.player_names[i], w_inputbuffer[i].l.l[0..w_inputbuffer[i].l.len:0]);
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

var chatchars: [QUEUESIZE]u8 = @splat(0);
var head: usize = 0;
var tail: usize = 0;

fn HU_queueChatChar(ch: u8) void {
    if ((head + 1) % QUEUESIZE == tail) {
    //if (((head + 1) & (QUEUESIZE - 1)) == tail) {
        plr.message = d_strings.text.HUSTR_MSGU;
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
                if (ev.data1 == d_strings.text.destination_keys[i]) {
                    if (g_game.playeringame[i] != c.false and i != g_game.consoleplayer) {
                        chat_on = true;
                        eatkey = true;
                        hu_lib.HUlib_resetIText(&w_chat);
                        HU_queueChatChar(@intCast(i+1));
                        break;
                    } else if (i == g_game.consoleplayer) {
                        S.num_nobrainers += 1;

                        plr.message = if (S.num_nobrainers < 3)
                            d_strings.text.HUSTR_TALKTOSELF1
                        else if (S.num_nobrainers < 6)
                            d_strings.text.HUSTR_TALKTOSELF2
                        else if (S.num_nobrainers < 9)
                            d_strings.text.HUSTR_TALKTOSELF3
                        else if (S.num_nobrainers < 32)
                            d_strings.text.HUSTR_TALKTOSELF4
                        else
                            d_strings.text.HUSTR_TALKTOSELF5;
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

            const macromessage = chat_macros[@intCast(ch)];

            // kill last message with a '\n'
            HU_queueChatChar(doomdef.KEY_ENTER); // DEBUG!!!

            // send the macro message
            for (macromessage) |mch| {
                HU_queueChatChar(mch);
            }
            HU_queueChatChar(doomdef.KEY_ENTER);

            // leave chat mode and notify that it was sent
            chat_on = false;
            _ = std.fmt.bufPrintSentinel(&S.lastmessage, "{s}", .{macromessage}, 0) catch unreachable;
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
                    _ = std.fmt.bufPrintSentinel(&S.lastmessage, "{s}", .{msg}, 0) catch unreachable;
                    plr.message = &S.lastmessage;
                }
            } else if (ch == doomdef.KEY_ESCAPE) {
                chat_on = false;
            }
        }
    }

    return eatkey;
}
