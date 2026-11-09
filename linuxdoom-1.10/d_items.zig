const doomdef = @import("doomdef.zig");
const AmmoType = doomdef.AmmoType;
const WeaponType = doomdef.WeaponType;
const d_info = @import("d_info.zig");
const StateNum = d_info.StateNum;

pub const WeaponInfo = extern struct {
    ammo: AmmoType,
    upstate: StateNum,
    downstate: StateNum,
    readystate: StateNum,
    atkstate: StateNum,
    flashstate: StateNum,
};

// TODO: This ought to be a function `info()` on WeaponType so we can write
// `wt.info().ammo` instead of `d_items.weaponInfo(wt).ammo`, etc.
pub fn weaponInfo(w: WeaponType) *const WeaponInfo {
    return &weaponinfo[@backingInt(w)];
}

pub const weaponinfo = [_]WeaponInfo{
    .{
        // fist
        .ammo = .NoAmmo,
        .upstate = .PUNCHUP,
        .downstate = .PUNCHDOWN,
        .readystate = .PUNCH,
        .atkstate = .PUNCH1,
        .flashstate = .NULL,
    },
    .{
        // pistol
        .ammo = .Clip,
        .upstate = .PISTOLUP,
        .downstate = .PISTOLDOWN,
        .readystate = .PISTOL,
        .atkstate = .PISTOL1,
        .flashstate = .PISTOLFLASH,
    },
    .{
        // shotgun
        .ammo = .Shell,
        .upstate = .SGUNUP,
        .downstate = .SGUNDOWN,
        .readystate = .SGUN,
        .atkstate = .SGUN1,
        .flashstate = .SGUNFLASH1,
    },
    .{
        // chaingun
        .ammo = .Clip,
        .upstate = .CHAINUP,
        .downstate = .CHAINDOWN,
        .readystate = .CHAIN,
        .atkstate = .CHAIN1,
        .flashstate = .CHAINFLASH1,
    },
    .{
        // missile launcher
        .ammo = .Missile,
        .upstate = .MISSILEUP,
        .downstate = .MISSILEDOWN,
        .readystate = .MISSILE,
        .atkstate = .MISSILE1,
        .flashstate = .MISSILEFLASH1,
    },
    .{
        // plasma rifle
        .ammo = .Cell,
        .upstate = .PLASMAUP,
        .downstate = .PLASMADOWN,
        .readystate = .PLASMA,
        .atkstate = .PLASMA1,
        .flashstate = .PLASMAFLASH1,
    },
    .{
        // bfg 9000
        .ammo = .Cell,
        .upstate = .BFGUP,
        .downstate = .BFGDOWN,
        .readystate = .BFG,
        .atkstate = .BFG1,
        .flashstate = .BFGFLASH1,
    },
    .{
        // chainsaw
        .ammo = .NoAmmo,
        .upstate = .SAWUP,
        .downstate = .SAWDOWN,
        .readystate = .SAW,
        .atkstate = .SAW1,
        .flashstate = .NULL,
    },
    .{
        // super shotgun
        .ammo = .Shell,
        .upstate = .DSGUNUP,
        .downstate = .DSGUNDOWN,
        .readystate = .DSGUN,
        .atkstate = .DSGUN1,
        .flashstate = .DSGUNFLASH1,
    },
};
