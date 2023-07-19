const c = @cImport({
    @cInclude("info.h");
    @cInclude("doomdef.h");
});

// TODO: Move ammotype_t definition here?

pub const WeaponInfo = extern struct {
    ammo: c.ammotype_t,
    upstate: c_int,
    downstate: c_int,
    readystate: c_int,
    atkstate: c_int,
    flashstate: c_int,
};

pub export const weaponinfo = [_]WeaponInfo{
    .{
        // fist
        .ammo = c.am_noammo,
        .upstate = c.S_PUNCHUP,
        .downstate = c.S_PUNCHDOWN,
        .readystate = c.S_PUNCH,
        .atkstate = c.S_PUNCH1,
        .flashstate = c.S_NULL,
    },
    .{
        // pistol
        .ammo = c.am_clip,
        .upstate = c.S_PISTOLUP,
        .downstate = c.S_PISTOLDOWN,
        .readystate = c.S_PISTOL,
        .atkstate = c.S_PISTOL1,
        .flashstate = c.S_PISTOLFLASH,
    },
    .{
        // shotgun
        .ammo = c.am_shell,
        .upstate = c.S_SGUNUP,
        .downstate = c.S_SGUNDOWN,
        .readystate = c.S_SGUN,
        .atkstate = c.S_SGUN1,
        .flashstate = c.S_SGUNFLASH1,
    },
    .{
        // chaingun
        .ammo = c.am_clip,
        .upstate = c.S_CHAINUP,
        .downstate = c.S_CHAINDOWN,
        .readystate = c.S_CHAIN,
        .atkstate = c.S_CHAIN1,
        .flashstate = c.S_CHAINFLASH1,
    },
    .{
        // missile launcher
        .ammo = c.am_misl,
        .upstate = c.S_MISSILEUP,
        .downstate = c.S_MISSILEDOWN,
        .readystate = c.S_MISSILE,
        .atkstate = c.S_MISSILE1,
        .flashstate = c.S_MISSILEFLASH1,
    },
    .{
        // plasma rifle
        .ammo = c.am_cell,
        .upstate = c.S_PLASMAUP,
        .downstate = c.S_PLASMADOWN,
        .readystate = c.S_PLASMA,
        .atkstate = c.S_PLASMA1,
        .flashstate = c.S_PLASMAFLASH1,
    },
    .{
        // bfg 9000
        .ammo = c.am_cell,
        .upstate = c.S_BFGUP,
        .downstate = c.S_BFGDOWN,
        .readystate = c.S_BFG,
        .atkstate = c.S_BFG1,
        .flashstate = c.S_BFGFLASH1,
    },
    .{
        // chainsaw
        .ammo = c.am_noammo,
        .upstate = c.S_SAWUP,
        .downstate = c.S_SAWDOWN,
        .readystate = c.S_SAW,
        .atkstate = c.S_SAW1,
        .flashstate = c.S_NULL,
    },
    .{
        // super shotgun
        .ammo = c.am_shell,
        .upstate = c.S_DSGUNUP,
        .downstate = c.S_DSGUNDOWN,
        .readystate = c.S_DSGUN,
        .atkstate = c.S_DSGUN1,
        .flashstate = c.S_DSGUNFLASH1,
    },
};
