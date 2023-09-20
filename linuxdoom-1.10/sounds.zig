const std = @import("std");

//
// SoundFX struct.
//
const SfxInfo = extern struct {
    // up to 6-character name
    name: [*:0]const u8,

    // Sfx singularity (only one at a time)
    singularity: c_int,

    // Sfx priority
    priority: c_int,

    // referenced sound if a link
    //link: ?*SfxInfo,
    // TODO: Would like to use ?*SfxInfo and self link but initialization
    // does not work due to erroneous "error: dependency loop detected".
    // See https://github.com/ziglang/zig/issues/131
    // Instead for now we put in the offset. Could just use the offset
    // once all code using this struct is zig.
    link: usize,

    // pitch if a link
    pitch: c_int,

    // volume if a link
    volume: c_int,

    // sound data
    data: ?[*]const u8,

    // this is checked every second to see if sound
    // can be thrown out (if 0, then decrement, if -1,
    // then throw out, if > 0, then it is in use)
    usefulness: c_int,

    // lump number of sfx
    lumpnum: c_int,
};




//
// MusicInfo struct.
//
const MusicInfo = extern struct {
    // up to 6-character name
    name: [*:0]const u8,

    // lump number of music
    lumpnum: c_int,

    // music data
    data: ?[*]const u8,

    // music handle once registered
    handle: c_int,
};

pub export var S_music: [raw_music.len]MusicInfo = blk: {
    var result: [raw_music.len]MusicInfo = undefined;

    for (raw_music, 0..) |raw, i| {
        result[i] = .{
            .name = raw[0],
            .lumpnum = 0,
            .data = null,
            .handle = 0,
        };
    }

    break :blk result;
};

pub export var S_sfx: [raw_sfx.len]SfxInfo = blk: {
    var result: [raw_sfx.len]SfxInfo = undefined;

    for (raw_sfx, 0..) |raw, i| {
        const link = if (raw[3] != null) for (raw_sfx, 0..) |r, j| {
            if (std.mem.eql(u8, r[0], raw[3].?)) {
                break j;
            }
        } else unreachable else 0; //null;

        result[i] = .{
            .name = raw[0],
            .singularity = @intFromBool(raw[1]),
            .priority = raw[2],
            .link = link,
            .pitch = raw[4],
            .volume = raw[5],
            .data = null,
            .usefulness = 0,
            .lumpnum = 0,
        };
    }

    break :blk result;
};


//
// Identifiers for all music in game.
//

pub const Music = enum {
    None,
    e1m1,
    e1m2,
    e1m3,
    e1m4,
    e1m5,
    e1m6,
    e1m7,
    e1m8,
    e1m9,
    e2m1,
    e2m2,
    e2m3,
    e2m4,
    e2m5,
    e2m6,
    e2m7,
    e2m8,
    e2m9,
    e3m1,
    e3m2,
    e3m3,
    e3m4,
    e3m5,
    e3m6,
    e3m7,
    e3m8,
    e3m9,
    inter,
    intro,
    bunny,
    victor,
    introa,
    runnin,
    stalks,
    countd,
    betwee,
    doom,
    the_da,
    shawn,
    ddtblu,
    in_cit,
    dead,
    stlks2,
    theda2,
    doom2,
    ddtbl2,
    runni2,
    dead2,
    stlks3,
    romero,
    shawn2,
    messag,
    count2,
    ddtbl3,
    ampie,
    theda3,
    adrian,
    messg2,
    romer2,
    tense,
    shawn3,
    openin,
    evil,
    ultima,
    read_m,
    dm2ttl,
    dm2int,
    NUMMUSIC
};

//
// Identifiers for all sfx in game.
//

pub const Sfx = enum {
    None,
    pistol,
    shotgn,
    sgcock,
    dshtgn,
    dbopn,
    dbcls,
    dbload,
    plasma,
    bfg,
    sawup,
    sawidl,
    sawful,
    sawhit,
    rlaunc,
    rxplod,
    firsht,
    firxpl,
    pstart,
    pstop,
    doropn,
    dorcls,
    stnmov,
    swtchn,
    swtchx,
    plpain,
    dmpain,
    popain,
    vipain,
    mnpain,
    pepain,
    slop,
    itemup,
    wpnup,
    oof,
    telept,
    posit1,
    posit2,
    posit3,
    bgsit1,
    bgsit2,
    sgtsit,
    cacsit,
    brssit,
    cybsit,
    spisit,
    bspsit,
    kntsit,
    vilsit,
    mansit,
    pesit,
    sklatk,
    sgtatk,
    skepch,
    vilatk,
    claw,
    skeswg,
    pldeth,
    pdiehi,
    podth1,
    podth2,
    podth3,
    bgdth1,
    bgdth2,
    sgtdth,
    cacdth,
    skldth,
    brsdth,
    cybdth,
    spidth,
    bspdth,
    vildth,
    kntdth,
    pedth,
    skedth,
    posact,
    bgact,
    dmact,
    bspact,
    bspwlk,
    vilact,
    noway,
    barexp,
    punch,
    hoof,
    metal,
    chgun,
    tink,
    bdopn,
    bdcls,
    itmbk,
    flame,
    flamst,
    getpow,
    bospit,
    boscub,
    bossit,
    bospn,
    bosdth,
    manatk,
    mandth,
    sssit,
    ssdth,
    keenpn,
    keendt,
    skeact,
    skesit,
    skeatk,
    radio,
    NUMSFX
};

// NOTE: CONSIDER: Can generate the enums from the raw_music and raw_sfx
// tables. However, the LSP currently cannot figure out the enums when they
// are done this way. So instead the enums are produced manually above. If
// LSP evolves to handle this then switching to the generated enums would
// be preferred.
//
//pub const Music = music_enum: {
//    const EnumField = std.builtin.Type.EnumField;
//    var fields: [raw_music.len]EnumField = undefined;
//    for (raw_music, 0..) |raw, i| {
//        fields[i] = .{
//            .name = raw[0],
//            .value = i,
//        };
//    }
//
//    break :music_enum @Type(.{ .Enum = .{
//        .tag_type = c_uint,
//        .fields = &fields,
//        .decls = &.{},
//        .is_exhaustive = true,
//    }});
//};
//
//pub const Sfx = sfx_enum: {
//    const EnumField = std.builtin.Type.EnumField;
//    var fields: [raw_sfx.len]EnumField = undefined;
//    for (raw_sfx, 0..) |raw, i| {
//        fields[i] = .{
//            .name = raw[0],
//            .value = i,
//        };
//    }
//
//    break :sfx_enum @Type(.{ .Enum = .{
//        .tag_type = c_uint,
//        .fields = &fields,
//        .decls = &.{},
//        .is_exhaustive = true,
//    }});
//};

//
// Information about all the music
//

const RawMusicInfo = struct {
    [:0]const u8,
};

const raw_music = [_]RawMusicInfo{
    .{ "" },
    .{ "e1m1" },
    .{ "e1m2" },
    .{ "e1m3" },
    .{ "e1m4" },
    .{ "e1m5" },
    .{ "e1m6" },
    .{ "e1m7" },
    .{ "e1m8" },
    .{ "e1m9" },
    .{ "e2m1" },
    .{ "e2m2" },
    .{ "e2m3" },
    .{ "e2m4" },
    .{ "e2m5" },
    .{ "e2m6" },
    .{ "e2m7" },
    .{ "e2m8" },
    .{ "e2m9" },
    .{ "e3m1" },
    .{ "e3m2" },
    .{ "e3m3" },
    .{ "e3m4" },
    .{ "e3m5" },
    .{ "e3m6" },
    .{ "e3m7" },
    .{ "e3m8" },
    .{ "e3m9" },
    .{ "inter" },
    .{ "intro" },
    .{ "bunny" },
    .{ "victor" },
    .{ "introa" },
    .{ "runnin" },
    .{ "stalks" },
    .{ "countd" },
    .{ "betwee" },
    .{ "doom" },
    .{ "the_da" },
    .{ "shawn" },
    .{ "ddtblu" },
    .{ "in_cit" },
    .{ "dead" },
    .{ "stlks2" },
    .{ "theda2" },
    .{ "doom2" },
    .{ "ddtbl2" },
    .{ "runni2" },
    .{ "dead2" },
    .{ "stlks3" },
    .{ "romero" },
    .{ "shawn2" },
    .{ "messag" },
    .{ "count2" },
    .{ "ddtbl3" },
    .{ "ampie" },
    .{ "theda3" },
    .{ "adrian" },
    .{ "messg2" },
    .{ "romer2" },
    .{ "tense" },
    .{ "shawn3" },
    .{ "openin" },
    .{ "evil" },
    .{ "ultima" },
    .{ "read_m" },
    .{ "dm2ttl" },
    .{ "dm2int" } 
};

//
// Information about all the sfx
//

const RawSfxInfo = struct {
    [:0]const u8,
    bool,
    i32,
    ?[:0]const u8,
    i32,
    i32,
};

const raw_sfx = [_]RawSfxInfo{
  // S_sfx[0] needs to be a dummy for odd reasons.
  .{ "none", false,  0, null, -1, -1 },

  .{ "pistol", false, 64, null, -1, -1 },
  .{ "shotgn", false, 64, null, -1, -1 },
  .{ "sgcock", false, 64, null, -1, -1 },
  .{ "dshtgn", false, 64, null, -1, -1 },
  .{ "dbopn", false, 64, null, -1, -1 },
  .{ "dbcls", false, 64, null, -1, -1 },
  .{ "dbload", false, 64, null, -1, -1 },
  .{ "plasma", false, 64, null, -1, -1 },
  .{ "bfg", false, 64, null, -1, -1 },
  .{ "sawup", false, 64, null, -1, -1 },
  .{ "sawidl", false, 118, null, -1, -1 },
  .{ "sawful", false, 64, null, -1, -1 },
  .{ "sawhit", false, 64, null, -1, -1 },
  .{ "rlaunc", false, 64, null, -1, -1 },
  .{ "rxplod", false, 70, null, -1, -1 },
  .{ "firsht", false, 70, null, -1, -1 },
  .{ "firxpl", false, 70, null, -1, -1 },
  .{ "pstart", false, 100, null, -1, -1 },
  .{ "pstop", false, 100, null, -1, -1 },
  .{ "doropn", false, 100, null, -1, -1 },
  .{ "dorcls", false, 100, null, -1, -1 },
  .{ "stnmov", false, 119, null, -1, -1 },
  .{ "swtchn", false, 78, null, -1, -1 },
  .{ "swtchx", false, 78, null, -1, -1 },
  .{ "plpain", false, 96, null, -1, -1 },
  .{ "dmpain", false, 96, null, -1, -1 },
  .{ "popain", false, 96, null, -1, -1 },
  .{ "vipain", false, 96, null, -1, -1 },
  .{ "mnpain", false, 96, null, -1, -1 },
  .{ "pepain", false, 96, null, -1, -1 },
  .{ "slop", false, 78, null, -1, -1 },
  .{ "itemup", true, 78, null, -1, -1 },
  .{ "wpnup", true, 78, null, -1, -1 },
  .{ "oof", false, 96, null, -1, -1 },
  .{ "telept", false, 32, null, -1, -1 },
  .{ "posit1", true, 98, null, -1, -1 },
  .{ "posit2", true, 98, null, -1, -1 },
  .{ "posit3", true, 98, null, -1, -1 },
  .{ "bgsit1", true, 98, null, -1, -1 },
  .{ "bgsit2", true, 98, null, -1, -1 },
  .{ "sgtsit", true, 98, null, -1, -1 },
  .{ "cacsit", true, 98, null, -1, -1 },
  .{ "brssit", true, 94, null, -1, -1 },
  .{ "cybsit", true, 92, null, -1, -1 },
  .{ "spisit", true, 90, null, -1, -1 },
  .{ "bspsit", true, 90, null, -1, -1 },
  .{ "kntsit", true, 90, null, -1, -1 },
  .{ "vilsit", true, 90, null, -1, -1 },
  .{ "mansit", true, 90, null, -1, -1 },
  .{ "pesit", true, 90, null, -1, -1 },
  .{ "sklatk", false, 70, null, -1, -1 },
  .{ "sgtatk", false, 70, null, -1, -1 },
  .{ "skepch", false, 70, null, -1, -1 },
  .{ "vilatk", false, 70, null, -1, -1 },
  .{ "claw", false, 70, null, -1, -1 },
  .{ "skeswg", false, 70, null, -1, -1 },
  .{ "pldeth", false, 32, null, -1, -1 },
  .{ "pdiehi", false, 32, null, -1, -1 },
  .{ "podth1", false, 70, null, -1, -1 },
  .{ "podth2", false, 70, null, -1, -1 },
  .{ "podth3", false, 70, null, -1, -1 },
  .{ "bgdth1", false, 70, null, -1, -1 },
  .{ "bgdth2", false, 70, null, -1, -1 },
  .{ "sgtdth", false, 70, null, -1, -1 },
  .{ "cacdth", false, 70, null, -1, -1 },
  .{ "skldth", false, 70, null, -1, -1 },
  .{ "brsdth", false, 32, null, -1, -1 },
  .{ "cybdth", false, 32, null, -1, -1 },
  .{ "spidth", false, 32, null, -1, -1 },
  .{ "bspdth", false, 32, null, -1, -1 },
  .{ "vildth", false, 32, null, -1, -1 },
  .{ "kntdth", false, 32, null, -1, -1 },
  .{ "pedth", false, 32, null, -1, -1 },
  .{ "skedth", false, 32, null, -1, -1 },
  .{ "posact", true, 120, null, -1, -1 },
  .{ "bgact", true, 120, null, -1, -1 },
  .{ "dmact", true, 120, null, -1, -1 },
  .{ "bspact", true, 100, null, -1, -1 },
  .{ "bspwlk", true, 100, null, -1, -1 },
  .{ "vilact", true, 100, null, -1, -1 },
  .{ "noway", false, 78, null, -1, -1 },
  .{ "barexp", false, 60, null, -1, -1 },
  .{ "punch", false, 64, null, -1, -1 },
  .{ "hoof", false, 70, null, -1, -1 },
  .{ "metal", false, 70, null, -1, -1 },
  .{ "chgun", false, 64, "pistol", 150, 0 },
  .{ "tink", false, 60, null, -1, -1 },
  .{ "bdopn", false, 100, null, -1, -1 },
  .{ "bdcls", false, 100, null, -1, -1 },
  .{ "itmbk", false, 100, null, -1, -1 },
  .{ "flame", false, 32, null, -1, -1 },
  .{ "flamst", false, 32, null, -1, -1 },
  .{ "getpow", false, 60, null, -1, -1 },
  .{ "bospit", false, 70, null, -1, -1 },
  .{ "boscub", false, 70, null, -1, -1 },
  .{ "bossit", false, 70, null, -1, -1 },
  .{ "bospn", false, 70, null, -1, -1 },
  .{ "bosdth", false, 70, null, -1, -1 },
  .{ "manatk", false, 70, null, -1, -1 },
  .{ "mandth", false, 70, null, -1, -1 },
  .{ "sssit", false, 70, null, -1, -1 },
  .{ "ssdth", false, 70, null, -1, -1 },
  .{ "keenpn", false, 70, null, -1, -1 },
  .{ "keendt", false, 70, null, -1, -1 },
  .{ "skeact", false, 70, null, -1, -1 },
  .{ "skesit", false, 70, null, -1, -1 },
  .{ "skeatk", false, 70, null, -1, -1 },
  .{ "radio", false, 60, null, -1, -1 },
};
