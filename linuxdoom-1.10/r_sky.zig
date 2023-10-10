const FRACUNIT = @import("m_fixed.zig").FRACUNIT;

// SKY, store the number for name.
pub const SKYFLATNAME = "F_SKY1";

// The sky map is 256*128*4 maps.
pub const ANGLETOSKYSHIFT = 22;

//
// sky mapping
//
pub export var skyflatnum: c_int = undefined;
pub export var skytexture: c_int = undefined;
pub export var skytexturemid: c_int = undefined;



//
// R_InitSkyMap
// Called whenever the view size changes.
//
pub export fn R_InitSkyMap() void {
    skytexturemid = 100 * FRACUNIT;
}
