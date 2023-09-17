const c = @cImport({
    @cInclude("doomtype.h");
});

const doomdef = @import("doomdef.zig");
const GameMode = doomdef.GameMode;
const Language = doomdef.Language;

// Game Mode - identify IWAD as shareware, retail etc.
pub export var gamemode: GameMode = .Indetermined;

// Language.
pub export var language: Language = .English;

// Set if homebrew PWAD stuff has been added.
pub export var modifiedgame: c.boolean = c.false;

