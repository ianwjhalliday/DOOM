const std = @import("std");

const doomdef = @import("doomdef.zig");
const Language = doomdef.Language;
const d_englsh = @import("d_englsh.zig");
const Strings = d_englsh.Strings;
const d_french = @import("d_french.zig");

pub const english: Strings = .{};

/// Text language. Separate from doomstat.language, which also picks WAD
/// lumps and the keymap that only doom2f.wad provides.
pub var lang: Language = .English;
pub var text: *const Strings = &english;

pub fn setLanguage(language: Language) void {
    lang = language;
    text = switch (language) {
        inline else => |l| table(l),
    };
}

pub fn table(comptime language: Language) *const Strings {
    return switch (language) {
        .French => &d_french.french,
        else => &english,
    };
}

/// Returns a function that reads `field` from the current language's table.
pub fn getter(comptime field: std.meta.FieldEnum(Strings)) *const fn () [:0]const u8 {
    return &struct {
        fn get() [:0]const u8 {
            return @field(text, @tagName(field));
        }
    }.get;
}

pub const SAVEGAMENAME = "doomsav";

pub const NUM_QUITMESSAGES = 15;
pub const endmsg: [NUM_QUITMESSAGES + 1][:0]const u8 = .{
    // DOOM1
    english.QUITMSG,
    "please don't leave, there's more\ndemons to toast!",
    "let's beat it -- this is turning\ninto a bloodbath!",
    "i wouldn't leave if i were you.\ndos is much worse.",
    "you're trying to say you like dos\nbetter than me, right?",
    "don't leave yet -- there's a\ndemon around that corner!",
    "ya know, next time you come in here\ni'm gonna toast ya.",
    "go ahead and leave. see if i care.",

    // QuitDOOM II messages
    "you want to quit?\nthen, thou hast lost an eighth!",
    "don't go now, there's a \ndimensional shambler waiting\nat the dos prompt!",
    "get outta here and go back\nto your boring programs.",
    "if i were your boss, i'd \n deathmatch ya in a minute!",
    "look, bud. you leave now\nand you forfeit your body count!",
    "just leave. when you come\nback, i'll be waiting with a bat.",
    "you're lucky i don't smack\nyou for thinking about leaving.",

    // Internal debug. Different style, too.
    "THIS IS NO MESSAGE!\nPage intentionally left blank.",
};
